-- Phase 3 security and data-integrity hardening.

-- Allow the service-role edge function to reconcile a successful Auth password
-- update when the follow-up profile/audit transaction failed.
create or replace function private.admin_reconcile_self_password_change(
  p_organization_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id
      and membership.user_id = p_actor_id
      and membership.role = 'admin'
      and membership.status = 'active'
      and profile.status in ('active', 'password_change_required')
  ) then raise exception 'ADMIN_REQUIRED'; end if;

  update public.profiles
  set must_change_password = false,
      status = 'active',
      password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = p_actor_id;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (p_organization_id, p_actor_id, 'profile', p_actor_id, 'password_changed_self_reconciled', jsonb_build_object('source', 'administration'));
end;
$$;

create or replace function public.rpc_admin_reconcile_self_password_change(p_organization_id uuid, p_actor_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.admin_reconcile_self_password_change(p_organization_id, p_actor_id);
$$;

revoke all on function private.admin_reconcile_self_password_change(uuid, uuid), public.rpc_admin_reconcile_self_password_change(uuid, uuid) from public, anon, authenticated;
grant execute on function private.admin_reconcile_self_password_change(uuid, uuid), public.rpc_admin_reconcile_self_password_change(uuid, uuid) to service_role;

-- Make survey analysis assignment-aware even though the function is a definer.
create or replace function public.rpc_aoi_survey_analysis(p_asset_id uuid, p_population text default 'approved')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_asset public.survey_assets;
  v_allowed text[];
  v_started integer;
  v_completed integer;
  v_population_count integer;
begin
  select * into v_asset
  from public.survey_assets asset
  where asset.id = p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id)
    and auth.uid() is distinct from v_asset.owner_id
    and auth.uid() is distinct from v_asset.assigned_to then
    raise exception 'SURVEY_ASSIGNMENT_REQUIRED';
  end if;
  if p_population not in ('approved', 'operational') then raise exception 'SURVEY_POPULATION_INVALID'; end if;
  v_allowed := case when p_population = 'approved' then array['approved'] else array['submitted', 'in_review', 'approved', 'revision_requested', 'rejected', 'excluded'] end;
  select count(*), count(*) filter (where submitted_at is not null)
  into v_started, v_completed
  from public.survey_submissions
  where asset_id = p_asset_id;
  select count(*) into v_population_count
  from public.survey_submissions
  where asset_id = p_asset_id and response_status = any(v_allowed);
  return jsonb_build_object(
    'population', p_population,
    'populationCount', v_population_count,
    'starts', v_started,
    'completed', v_completed,
    'completionRate', case when v_started = 0 then 0 else round(v_completed::numeric / v_started * 100) end,
    'statusCounts', coalesce((select jsonb_object_agg(response_status, total) from (select response_status, count(*) total from public.survey_submissions where asset_id = p_asset_id group by response_status) status), '{}'::jsonb),
    'questions', coalesce((select jsonb_agg(summary) from (
      select jsonb_build_object('versionId', response.version_id, 'questionId', answer.question_id, 'questionType', question#>>'{type}', 'definition', question, 'count', count(*), 'denominator', v_population_count, 'values', jsonb_agg(answer.answer_value)) summary
      from public.survey_answers answer
      join public.survey_submissions response on response.id = answer.submission_id
      join public.survey_versions version on version.id = response.version_id
      cross join lateral jsonb_array_elements(version.definition->'blocks') section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
      where response.asset_id = p_asset_id
        and response.response_status = any(v_allowed)
        and answer.is_active
        and question->>'id' = answer.question_id
        and question#>>'{privacy,classification}' is distinct from 'direct_identifier'
      group by response.version_id, answer.question_id, question
    ) typed), '[]'::jsonb),
    'qualityFlags', coalesce((select jsonb_agg(jsonb_build_object('submissionId', id, 'flags', quality_flags)) from public.survey_submissions where asset_id = p_asset_id and response_status = any(v_allowed) and jsonb_array_length(quality_flags) > 0), '[]'::jsonb)
  );
end;
$$;

-- Require identity-bearing question types to use restricted identifier storage.
create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_errors jsonb := private.validate_aoi_survey_definition_base(p_definition);
  v_section jsonb;
  v_question jsonb;
  v_value jsonb;
  v_option_ids text[];
  v_exclusive_id text;
  v_minimum integer;
  v_maximum integer;
  v_require_zh boolean := coalesce(p_definition->'locales', '[]'::jsonb) ? 'zh-CN';
  v_question_ids text[];
  v_question_id text;
begin
  if jsonb_typeof(p_definition) <> 'object' then return v_errors; end if;
  select coalesce(array_agg(question->>'id'), '{}'::text[]) into v_question_ids
  from jsonb_array_elements(coalesce(p_definition->'blocks', '[]'::jsonb)) section
  cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
  where question->>'type' <> 'content';

  for v_section in select value from jsonb_array_elements(coalesce(p_definition->'blocks', '[]'::jsonb)) loop
    for v_question in select value from jsonb_array_elements(coalesce(v_section->'blocks', '[]'::jsonb)) loop
      if v_question->>'type' = 'content' then continue; end if;

      if v_question->>'type' in ('email', 'phone')
        and coalesce(v_question#>>'{privacy,classification}', '') <> 'direct_identifier' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'DIRECT_IDENTIFIER_CLASSIFICATION_REQUIRED', 'path', v_question->>'id'));
      end if;
      if nullif(v_question#>>'{privacy,classification}', '') is not null
        and v_question#>>'{privacy,classification}' <> 'direct_identifier' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'QUESTION_PRIVACY_INVALID', 'path', v_question->>'id'));
      end if;

      for v_value in select value from jsonb_array_elements(coalesce(v_question#>'{visibility,all}', '[]'::jsonb) || coalesce(v_question#>'{visibility,any}', '[]'::jsonb)) loop
        if not (v_value->>'questionId' = any(v_question_ids)) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'BRANCH_TARGET_MISSING', 'path', v_question->>'id'));
        end if;
        if v_value->>'questionId' = v_question->>'id' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'BRANCH_SELF_REFERENCE', 'path', v_question->>'id'));
        end if;
      end loop;

      if v_question->>'type' in ('single_choice', 'multiple_choice', 'dropdown', 'yes_no', 'ranking') then
        select coalesce(array_agg(option->>'id'), '{}') into v_option_ids
        from jsonb_array_elements(coalesce(v_question->'options', '[]'::jsonb)) option;
        if nullif(v_question#>>'{other,optionId}', '') is not null then
          if v_question->>'type' = 'ranking' then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'OTHER_OPTION_UNSUPPORTED', 'path', v_question->>'id'));
          end if;
          if not (v_question#>>'{other,optionId}' = any(v_option_ids))
            or nullif(trim(v_question#>>'{other,label,en}'), '') is null
            or v_require_zh and nullif(trim(v_question#>>'{other,label,zh}'), '') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'OTHER_OPTION_INVALID', 'path', v_question->>'id'));
          end if;
        end if;
        if jsonb_typeof(coalesce(v_question#>'{validation,exclusiveOptionIds}', '[]'::jsonb)) <> 'array' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'EXCLUSIVE_OPTION_INVALID', 'path', v_question->>'id'));
        else
          for v_exclusive_id in select value from jsonb_array_elements_text(coalesce(v_question#>'{validation,exclusiveOptionIds}', '[]'::jsonb)) loop
            if not (v_exclusive_id = any(v_option_ids)) then
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'EXCLUSIVE_OPTION_INVALID', 'path', v_question->>'id'));
            end if;
          end loop;
        end if;
      end if;

      if v_question->>'type' = 'multiple_choice' then
        if nullif(v_question#>>'{validation,minSelections}', '') is not null and v_question#>>'{validation,minSelections}' !~ '^\d+$'
          or nullif(v_question#>>'{validation,maxSelections}', '') is not null and v_question#>>'{validation,maxSelections}' !~ '^\d+$' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'SELECTION_RANGE_INVALID', 'path', v_question->>'id'));
        else
          v_minimum := nullif(v_question#>>'{validation,minSelections}', '')::integer;
          v_maximum := nullif(v_question#>>'{validation,maxSelections}', '')::integer;
          if coalesce(v_minimum, 0) < 0 or v_maximum is not null and v_maximum < 1 or v_minimum is not null and v_maximum is not null and v_minimum > v_maximum or v_maximum is not null and v_maximum > coalesce(array_length(v_option_ids, 1), 0) then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'SELECTION_RANGE_INVALID', 'path', v_question->>'id'));
          end if;
        end if;
      end if;

      if v_question->>'type' = 'calculated' then
        if coalesce(v_question#>>'{calculation,operator}', '') not in ('sum', 'average', 'minimum', 'maximum', 'product', 'difference') then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'CALCULATION_INVALID', 'path', v_question->>'id'));
        end if;
        for v_question_id in select value from jsonb_array_elements_text(coalesce(v_question#>'{calculation,questionIds}', '[]'::jsonb)) loop
          if not (v_question_id = any(v_question_ids)) or v_question_id = v_question->>'id' then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'CALCULATION_REFERENCE_INVALID', 'path', v_question->>'id'));
          end if;
        end loop;
      end if;
    end loop;
  end loop;

  if exists (
    with recursive edges as (
      select question->>'id' source_id, condition->>'questionId' target_id
      from jsonb_array_elements(coalesce(p_definition->'blocks', '[]'::jsonb)) section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
      cross join lateral jsonb_array_elements(coalesce(question#>'{visibility,all}', '[]'::jsonb) || coalesce(question#>'{visibility,any}', '[]'::jsonb)) condition
      where question->>'id' is not null and condition->>'questionId' is not null
    ), walk(source_id, target_id, path) as (
      select source_id, target_id, array[source_id, target_id] from edges
      union all
      select walk.source_id, edge.target_id, array_append(walk.path, edge.target_id)
      from walk join edges edge on edge.source_id = walk.target_id
      where walk.target_id <> walk.source_id
        and (edge.target_id = walk.source_id or not (edge.target_id = any(walk.path)))
    ) select 1 from walk where source_id = target_id
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'BRANCH_CYCLE', 'path', 'definition'));
  end if;

  if exists (
    with recursive edges as (
      select question->>'id' source_id, dependency.value #>> '{}' target_id
      from jsonb_array_elements(coalesce(p_definition->'blocks', '[]'::jsonb)) section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks', '[]'::jsonb)) question
      cross join lateral jsonb_array_elements(coalesce(question#>'{calculation,questionIds}', '[]'::jsonb)) dependency
      where question->>'type' = 'calculated'
    ), walk(source_id, target_id, path) as (
      select source_id, target_id, array[source_id, target_id] from edges
      union all
      select walk.source_id, edge.target_id, array_append(walk.path, edge.target_id)
      from walk join edges edge on edge.source_id = walk.target_id
      where walk.target_id <> walk.source_id
        and (edge.target_id = walk.source_id or not (edge.target_id = any(walk.path)))
    ) select 1 from walk where source_id = target_id
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'CALCULATION_CYCLE', 'path', 'definition'));
  end if;
  return v_errors;
exception when others then
  return v_errors || jsonb_build_array(jsonb_build_object('code', 'DEFINITION_INVALID', 'path', 'definition'));
end;
$$;

-- Replays are valid only while the original link and invitation remain valid.
drop function if exists public.rpc_aoi_public_survey_replay(uuid, text, text);
create or replace function public.rpc_aoi_public_survey_replay(
  p_submission_id uuid,
  p_resume_token text,
  p_idempotency_key text,
  p_token text,
  p_invitation_token text
)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions;
begin
  select response.* into v_submission
  from public.survey_submissions response
  join public.survey_links link on link.id = response.link_id
  join public.survey_assets asset on asset.id = response.asset_id
  join public.survey_versions version on version.id = response.version_id
  left join public.survey_invitations invitation on invitation.id = response.invitation_id
  where response.id = p_submission_id
    and response.resume_token_hash = digest(p_resume_token, 'sha256')
    and response.idempotency_key = p_idempotency_key
    and response.submitted_at is not null
    and (link.token_hash = digest(p_token, 'sha256') or invitation.token_hash = digest(coalesce(p_invitation_token, ''), 'sha256'))
    and link.link_status = 'active'
    and asset.lifecycle_status = 'published'
    and version.version_status in ('published', 'retired')
    and (link.opens_at is null or link.opens_at <= now())
    and (link.closes_at is null or link.closes_at > now())
    and (link.link_mode <> 'invited' or invitation.token_hash = digest(coalesce(p_invitation_token, ''), 'sha256'));
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  return jsonb_build_object('replayed', true, 'submissionId', v_submission.id, 'status', 'submitted', 'submittedAt', v_submission.submitted_at);
end;
$$;

revoke all on function public.rpc_aoi_public_survey_replay(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.rpc_aoi_public_survey_replay(uuid, text, text, text, text) to service_role;

-- Preserve approved observation provenance instead of silently nulling it.
alter table public.pmf_observations drop constraint if exists pmf_observations_organization_id_project_id_respondent_id_fkey;
alter table public.pmf_observations drop constraint if exists pmf_observations_organization_id_project_id_session_id_fkey;
alter table public.pmf_observations add constraint pmf_observations_respondent_restrict_fk
  foreign key (organization_id, project_id, respondent_id) references public.respondents(organization_id, project_id, id) on delete restrict;
alter table public.pmf_observations add constraint pmf_observations_session_restrict_fk
  foreign key (organization_id, project_id, session_id) references public.research_sessions(organization_id, project_id, id) on delete restrict;

-- Normalize legacy malformed URLs before validating stricter constraints.
update public.evidence_records set source_link = null where source_link is not null and source_link !~* '^https?://[^[:space:]/?#]+([/?#].*)?$';
update public.pmf_observations set source_link = null where source_link is not null and source_link !~* '^https?://[^[:space:]/?#]+([/?#].*)?$';
update public.crm_contacts set source_url = null where source_url is not null and source_url !~* '^https?://[^[:space:]/?#]+([/?#].*)?$';
update public.candidates set source_url = null where source_url is not null and source_url !~* '^https?://[^[:space:]/?#]+([/?#].*)?$';

alter table public.evidence_records drop constraint if exists evidence_records_source_link_http;
alter table public.evidence_records add constraint evidence_records_source_link_http check (source_link is null or source_link ~* '^https?://[^[:space:]/?#]+([/?#].*)?$');
alter table public.pmf_observations drop constraint if exists pmf_observations_source_link_http;
alter table public.pmf_observations add constraint pmf_observations_source_link_http check (source_link is null or source_link ~* '^https?://[^[:space:]/?#]+([/?#].*)?$');
alter table public.crm_contacts drop constraint if exists crm_contacts_source_url_http;
alter table public.crm_contacts add constraint crm_contacts_source_url_http check (source_url is null or source_url ~* '^https?://[^[:space:]/?#]+([/?#].*)?$');
alter table public.candidates drop constraint if exists candidates_source_url_http;
alter table public.candidates add constraint candidates_source_url_http check (source_url is null or source_url ~* '^https?://[^[:space:]/?#]+([/?#].*)?$');
