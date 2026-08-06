-- Extend the effective survey validator without discarding version-integrity checks.

alter function private.validate_aoi_survey_definition(jsonb)
  rename to validate_aoi_survey_definition_base;

create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_errors jsonb := private.validate_aoi_survey_definition_base(p_definition);
  v_section jsonb;
  v_question jsonb;
  v_option_ids text[];
  v_exclusive_id text;
  v_minimum integer;
  v_maximum integer;
  v_require_zh boolean := coalesce(p_definition->'locales','[]'::jsonb) ? 'zh-CN';
begin
  if jsonb_typeof(p_definition) <> 'object' then return v_errors; end if;
  for v_section in select value from jsonb_array_elements(coalesce(p_definition->'blocks','[]'::jsonb)) loop
    for v_question in select value from jsonb_array_elements(coalesce(v_section->'blocks','[]'::jsonb)) loop
      if v_question->>'type' = 'content' then continue; end if;

      if nullif(v_question#>>'{privacy,classification}','') is not null
        and v_question#>>'{privacy,classification}' <> 'direct_identifier' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_PRIVACY_INVALID','path',v_question->>'id'));
      end if;

      if v_question->>'type' in ('single_choice','multiple_choice','dropdown','yes_no','ranking') then
        select coalesce(array_agg(option->>'id'), '{}') into v_option_ids
        from jsonb_array_elements(coalesce(v_question->'options','[]'::jsonb)) option;

        if nullif(v_question#>>'{other,optionId}','') is not null then
          if v_question->>'type'='ranking' then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','OTHER_OPTION_UNSUPPORTED','path',v_question->>'id'));
          end if;
          if not (v_question#>>'{other,optionId}' = any(v_option_ids))
            or nullif(trim(v_question#>>'{other,label,en}'),'') is null
            or v_require_zh and nullif(trim(v_question#>>'{other,label,zh}'),'') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','OTHER_OPTION_INVALID','path',v_question->>'id'));
          end if;
        end if;

        if jsonb_typeof(coalesce(v_question#>'{validation,exclusiveOptionIds}','[]'::jsonb)) <> 'array' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','EXCLUSIVE_OPTION_INVALID','path',v_question->>'id'));
        else
          for v_exclusive_id in select value from jsonb_array_elements_text(coalesce(v_question#>'{validation,exclusiveOptionIds}','[]'::jsonb)) loop
            if not (v_exclusive_id = any(v_option_ids)) then
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','EXCLUSIVE_OPTION_INVALID','path',v_question->>'id'));
            end if;
          end loop;
        end if;
      end if;

      if v_question->>'type' = 'multiple_choice' then
        if nullif(v_question#>>'{validation,minSelections}','') is not null
          and v_question#>>'{validation,minSelections}' !~ '^\d+$'
          or nullif(v_question#>>'{validation,maxSelections}','') is not null
          and v_question#>>'{validation,maxSelections}' !~ '^\d+$' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SELECTION_RANGE_INVALID','path',v_question->>'id'));
        else
          v_minimum := nullif(v_question#>>'{validation,minSelections}','')::integer;
          v_maximum := nullif(v_question#>>'{validation,maxSelections}','')::integer;
          if coalesce(v_minimum,0) < 0
            or v_maximum is not null and v_maximum < 1
            or v_minimum is not null and v_maximum is not null and v_minimum > v_maximum
            or v_maximum is not null and v_maximum > coalesce(array_length(v_option_ids,1),0) then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SELECTION_RANGE_INVALID','path',v_question->>'id'));
          end if;
        end if;
      end if;
    end loop;
  end loop;
  return v_errors;
exception when others then
  return v_errors || jsonb_build_array(jsonb_build_object('code','DEFINITION_INVALID','path','definition'));
end;
$$;

revoke all on function private.validate_aoi_survey_definition_base(jsonb),
  private.validate_aoi_survey_definition(jsonb) from public, anon, authenticated;

drop policy if exists survey_response_identifiers_assignee_read on public.survey_response_identifiers;
create policy survey_response_identifiers_assignee_read
  on public.survey_response_identifiers for select to authenticated
  using (exists (
    select 1
    from public.survey_submissions submission
    join public.survey_assets asset on asset.id=submission.asset_id
    where submission.id=survey_response_identifiers.submission_id
      and (public.is_org_admin(submission.organization_id) or asset.assigned_to=(select auth.uid()))
  ));

insert into public.survey_response_identifiers(
  organization_id,project_id,submission_id,question_id,answer_value,answer_revision,is_active,created_at,updated_at
)
select answer.organization_id,answer.project_id,answer.submission_id,answer.question_id,answer.answer_value,answer.answer_revision,answer.is_active,answer.created_at,answer.updated_at
from public.survey_answers answer
join public.survey_submissions submission on submission.id=answer.submission_id
join public.survey_versions version on version.id=submission.version_id
cross join lateral jsonb_array_elements(version.definition->'blocks') section
cross join lateral jsonb_array_elements(coalesce(section->'blocks','[]'::jsonb)) question
where question->>'id'=answer.question_id and question#>>'{privacy,classification}'='direct_identifier'
on conflict(submission_id,question_id) do update
set answer_value=excluded.answer_value,
    answer_revision=greatest(public.survey_response_identifiers.answer_revision,excluded.answer_revision),
    is_active=excluded.is_active,
    updated_at=greatest(public.survey_response_identifiers.updated_at,excluded.updated_at);

-- Retain the original row as an inactive audit tombstone. Deleting it would
-- cascade answer revisions and text codes and would sever PMF provenance.
update public.survey_answers answer
set is_active=false,updated_at=now()
where answer.id in (
  select candidate.id
  from public.survey_answers candidate
  join public.survey_submissions submission on submission.id=candidate.submission_id
  join public.survey_versions version on version.id=submission.version_id
  cross join lateral jsonb_array_elements(version.definition->'blocks') section
  cross join lateral jsonb_array_elements(coalesce(section->'blocks','[]'::jsonb)) question
  where question->>'id'=candidate.question_id
    and question#>>'{privacy,classification}'='direct_identifier'
    and candidate.is_active
);

create or replace function public.rpc_aoi_survey_workspace(p_asset_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid()<>v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  return jsonb_build_object(
    'asset',jsonb_build_object('id',v_asset.id,'assetType',v_asset.asset_type,'title',v_asset.title,'description',v_asset.description,'status',v_asset.lifecycle_status,'ownerId',v_asset.owner_id,'assignedTo',v_asset.assigned_to,'tags',v_asset.tags,'updatedAt',v_asset.updated_at),
    'draft',(select jsonb_build_object('revision',draft.revision,'definition',draft.definition,'validationErrors',draft.validation_errors,'updatedAt',draft.updated_at) from public.survey_drafts draft where draft.asset_id=p_asset_id),
    'versions',coalesce((select jsonb_agg(jsonb_build_object('id',version.id,'versionNumber',version.version_number,'status',version.version_status,'definition',version.definition,'definitionHash',encode(version.definition_hash,'hex'),'submittedAt',version.submitted_at,'reviewedAt',version.reviewed_at,'publishedAt',version.published_at,'reviewNotes',version.review_notes) order by version.version_number desc) from public.survey_versions version where version.asset_id=p_asset_id),'[]'::jsonb),
    'links',coalesce((select jsonb_agg(jsonb_build_object('id',link.id,'versionId',link.version_id,'label',link.label,'mode',link.link_mode,'identityMode',link.identity_mode,'status',link.link_status,'responseCount',link.response_count,'maxResponses',link.max_responses,'opensAt',link.opens_at,'closesAt',link.closes_at,'allowedOrigins',link.allowed_origins,'settings',link.settings) order by link.created_at desc) from public.survey_links link where link.asset_id=p_asset_id),'[]'::jsonb),
    'submissions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',response.id,'versionId',response.version_id,'versionNumber',version.version_number,'versionDefinition',version.definition,
      'linkId',response.link_id,'status',response.response_status,'locale',response.locale,'score',response.score_result,
      'qualityFlags',response.quality_flags,'assignedTo',response.assigned_to,'startedAt',response.started_at,
      'submittedAt',response.submitted_at,'approvedAt',response.approved_at,
      'answers',coalesce((select jsonb_object_agg(answer.question_id,answer.answer_value) from public.survey_answers answer where answer.submission_id=response.id and answer.is_active),'{}'::jsonb),
      'identifiers',case when public.is_org_admin(v_asset.organization_id) or auth.uid() is not distinct from v_asset.assigned_to
        then coalesce((select jsonb_object_agg(identifier.question_id,identifier.answer_value) from public.survey_response_identifiers identifier where identifier.submission_id=response.id and identifier.is_active),'{}'::jsonb)
        else '{}'::jsonb end
    ) order by response.started_at desc)
    from public.survey_submissions response
    join public.survey_versions version on version.id=response.version_id
    where response.asset_id=p_asset_id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_survey_analysis(p_asset_id uuid,p_population text default 'approved')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets; v_allowed text[]; v_started integer; v_completed integer; v_population_count integer;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if p_population not in ('approved','operational') then raise exception 'SURVEY_POPULATION_INVALID'; end if;
  v_allowed:=case when p_population='approved' then array['approved'] else array['submitted','in_review','approved','revision_requested','rejected','excluded'] end;
  select count(*),count(*) filter(where submitted_at is not null) into v_started,v_completed from public.survey_submissions where asset_id=p_asset_id;
  select count(*) into v_population_count from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed);
  return jsonb_build_object(
    'population',p_population,'populationCount',v_population_count,'starts',v_started,'completed',v_completed,
    'completionRate',case when v_started=0 then 0 else round(v_completed::numeric/v_started*100) end,
    'statusCounts',coalesce((select jsonb_object_agg(response_status,total) from(select response_status,count(*) total from public.survey_submissions where asset_id=p_asset_id group by response_status) status),'{}'::jsonb),
    'questions',coalesce((select jsonb_agg(summary) from (
      select jsonb_build_object('versionId',response.version_id,'questionId',answer.question_id,'questionType',question#>>'{type}','definition',question,'count',count(*),'denominator',v_population_count,'values',jsonb_agg(answer.answer_value)) summary
      from public.survey_answers answer
      join public.survey_submissions response on response.id=answer.submission_id
      join public.survey_versions version on version.id=response.version_id
      cross join lateral jsonb_array_elements(version.definition->'blocks') section
      cross join lateral jsonb_array_elements(coalesce(section->'blocks','[]'::jsonb)) question
      where response.asset_id=p_asset_id and response.response_status=any(v_allowed) and answer.is_active
        and question->>'id'=answer.question_id
        and question#>>'{privacy,classification}' is distinct from 'direct_identifier'
      group by response.version_id,answer.question_id,question
    ) typed),'[]'::jsonb),
    'qualityFlags',coalesce((select jsonb_agg(jsonb_build_object('submissionId',id,'flags',quality_flags)) from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed) and jsonb_array_length(quality_flags)>0),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_survey_workspace(uuid),public.rpc_aoi_survey_analysis(uuid,text) from public,anon;
grant execute on function public.rpc_aoi_survey_workspace(uuid),public.rpc_aoi_survey_analysis(uuid,text) to authenticated;
