-- Questionnaire-ready survey primitives and direct-identifier separation.

create table public.survey_response_identifiers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  submission_id uuid not null,
  question_id text not null,
  answer_value jsonb not null default 'null'::jsonb,
  answer_revision integer not null default 1 check (answer_revision > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (submission_id, question_id),
  foreign key (organization_id, project_id, submission_id)
    references public.survey_submissions(organization_id, project_id, id) on delete cascade
);

create index survey_response_identifiers_submission_idx
  on public.survey_response_identifiers (submission_id, is_active);

alter table public.survey_response_identifiers enable row level security;

create policy survey_response_identifiers_assignee_read
  on public.survey_response_identifiers for select to authenticated
  using (exists (
    select 1
    from public.survey_submissions submission
    join public.survey_assets asset on asset.id = submission.asset_id
    where submission.id = survey_response_identifiers.submission_id
      and (
        public.is_org_admin(submission.organization_id)
        or asset.owner_id = (select auth.uid())
        or asset.assigned_to = (select auth.uid())
      )
  ));

revoke all on public.survey_response_identifiers from public, anon, authenticated;
grant select on public.survey_response_identifiers to authenticated;
grant all on public.survey_response_identifiers to service_role;

create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_section jsonb;
  v_question jsonb;
  v_option jsonb;
  v_row jsonb;
  v_column jsonb;
  v_ids text[] := '{}';
  v_option_ids text[];
  v_locales text[];
  v_type text;
  v_require_zh boolean;
begin
  if jsonb_typeof(p_definition) <> 'object' then
    return jsonb_build_array(jsonb_build_object('code','DEFINITION_OBJECT_REQUIRED','path','definition'));
  end if;
  if coalesce((p_definition->>'schemaVersion')::integer, 0) <> 1 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SCHEMA_VERSION_UNSUPPORTED','path','schemaVersion'));
  end if;
  select coalesce(array_agg(locale), '{}') into v_locales
  from jsonb_array_elements_text(coalesce(p_definition->'locales', '["en","zh-CN"]'::jsonb)) as configured(locale);
  if cardinality(v_locales) = 0
    or not ('en' = any(v_locales))
    or exists (select 1 from unnest(v_locales) locale where locale not in ('en','zh-CN')) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SURVEY_LOCALES_INVALID','path','locales'));
  end if;
  v_require_zh := 'zh-CN' = any(v_locales);
  if nullif(trim(p_definition#>>'{title,en}'),'') is null
    or v_require_zh and nullif(trim(p_definition#>>'{title,zh}'),'') is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SURVEY_TRANSLATIONS_REQUIRED','path','title'));
  end if;
  if jsonb_typeof(p_definition->'blocks') <> 'array' or jsonb_array_length(p_definition->'blocks') = 0 then
    return v_errors || jsonb_build_array(jsonb_build_object('code','SURVEY_BLOCK_REQUIRED','path','blocks'));
  end if;
  for v_section in select value from jsonb_array_elements(p_definition->'blocks') loop
    if v_section->>'type' <> 'section' or nullif(v_section->>'id','') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_INVALID','path','blocks'));
    end if;
    if nullif(trim(v_section#>>'{title,en}'),'') is null
      or v_require_zh and nullif(trim(v_section#>>'{title,zh}'),'') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_TRANSLATIONS_REQUIRED','path',coalesce(v_section->>'id','section')));
    end if;
    for v_question in select value from jsonb_array_elements(coalesce(v_section->'blocks','[]'::jsonb)) loop
      v_type := v_question->>'type';
      if v_type = 'content' then
        if coalesce(v_question->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$'
          or nullif(trim(v_question#>>'{title,en}'),'') is null
          or v_require_zh and nullif(trim(v_question#>>'{title,zh}'),'') is null then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','CONTENT_BLOCK_INVALID','path',coalesce(v_question->>'id','content')));
        end if;
        continue;
      end if;
      if coalesce(v_question->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$' or (v_question->>'id') = any(v_ids) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_ID_INVALID','path',coalesce(v_question->>'id','question')));
      else
        v_ids := array_append(v_ids, v_question->>'id');
      end if;
      if v_type not in ('short_text','long_text','number','email','phone','url','date','time','single_choice','multiple_choice','dropdown','yes_no','rating','nps','likert','matrix_single','matrix_multiple','ranking','upload','signature','consent','calculated','hidden') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_TYPE_INVALID','path',coalesce(v_question->>'id','question')));
      end if;
      if nullif(trim(v_question#>>'{title,en}'),'') is null
        or v_require_zh and nullif(trim(v_question#>>'{title,zh}'),'') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_TRANSLATIONS_REQUIRED','path',coalesce(v_question->>'id','question')));
      end if;
      if nullif(v_question#>>'{privacy,classification}','') is not null
        and v_question#>>'{privacy,classification}' <> 'direct_identifier' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_PRIVACY_INVALID','path',v_question->>'id'));
      end if;
      if v_type in ('single_choice','multiple_choice','dropdown','yes_no','ranking') then
        v_option_ids := '{}';
        if jsonb_typeof(v_question->'options') <> 'array' or jsonb_array_length(v_question->'options') < 2 then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','QUESTION_OPTIONS_REQUIRED','path',v_question->>'id'));
        end if;
        for v_option in select value from jsonb_array_elements(coalesce(v_question->'options','[]'::jsonb)) loop
          if coalesce(v_option->>'id','') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'
            or (v_option->>'id') = any(v_option_ids)
            or nullif(trim(v_option#>>'{label,en}'),'') is null
            or v_require_zh and nullif(trim(v_option#>>'{label,zh}'),'') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','OPTION_INVALID','path',v_question->>'id'));
          else
            v_option_ids := array_append(v_option_ids, v_option->>'id');
          end if;
        end loop;
        if nullif(v_question#>>'{other,optionId}','') is not null
          and not (v_question#>>'{other,optionId}' = any(v_option_ids)) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','OTHER_OPTION_INVALID','path',v_question->>'id'));
        end if;
      end if;
      if v_type in ('matrix_single','matrix_multiple') then
        if jsonb_array_length(coalesce(v_question->'rows','[]'::jsonb)) = 0
          or jsonb_array_length(coalesce(v_question->'columns','[]'::jsonb)) = 0 then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MATRIX_DIMENSIONS_REQUIRED','path',v_question->>'id'));
        end if;
        for v_row in select value from jsonb_array_elements(coalesce(v_question->'rows','[]'::jsonb)) loop
          if nullif(v_row->>'id','') is null or nullif(trim(v_row#>>'{label,en}'),'') is null
            or v_require_zh and nullif(trim(v_row#>>'{label,zh}'),'') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MATRIX_ROW_INVALID','path',v_question->>'id'));
          end if;
        end loop;
        for v_column in select value from jsonb_array_elements(coalesce(v_question->'columns','[]'::jsonb)) loop
          if nullif(v_column->>'id','') is null or nullif(trim(v_column#>>'{label,en}'),'') is null
            or v_require_zh and nullif(trim(v_column#>>'{label,zh}'),'') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MATRIX_COLUMN_INVALID','path',v_question->>'id'));
          end if;
        end loop;
      end if;
      if v_type = 'calculated' and coalesce(v_question#>>'{calculation,operator}','') not in ('sum','average','minimum','maximum','product','difference') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','CALCULATION_INVALID','path',v_question->>'id'));
      end if;
    end loop;
  end loop;
  return v_errors;
exception when others then
  return jsonb_build_array(jsonb_build_object('code','DEFINITION_INVALID','path','definition'));
end;
$$;

create or replace function public.rpc_aoi_create_survey(
  p_title jsonb,
  p_asset_type text default 'survey',
  p_definition jsonb default null,
  p_source_asset_id uuid default null
) returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_org uuid; v_project uuid; v_asset public.survey_assets; v_definition jsonb;
begin
  select context.organization_id, context.project_id into v_org, v_project from private.aoi_survey_context() context;
  if v_org is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if p_asset_type not in ('template','survey') then raise exception 'SURVEY_ASSET_TYPE_INVALID'; end if;
  v_definition := coalesce(p_definition, jsonb_build_object(
    'schemaVersion',1,'locales',jsonb_build_array('en','zh-CN'),'defaultLocale','en','title',p_title,
    'description',jsonb_build_object('en','','zh',''),'settings',jsonb_build_object('presentation','sections','showProgress',true,'allowReview',true,'randomizeSections',false),
    'theme',jsonb_build_object('accent','orange','density','comfortable'),
    'blocks',jsonb_build_array(jsonb_build_object('id','section-'||gen_random_uuid()::text,'type','section','title',jsonb_build_object('en','Section 1','zh','第一部分'),'description',jsonb_build_object('en','','zh',''),'blocks',jsonb_build_array())),
    'quotas',jsonb_build_array(),'scoring',jsonb_build_object('enabled',false,'bands',jsonb_build_array()),
    'completion',jsonb_build_object('message',jsonb_build_object('en','Thank you for your response.','zh','感谢您的参与。'),'redirectUrl','')
  ));
  if jsonb_array_length(private.validate_aoi_survey_definition(v_definition)) > 0 then raise exception 'SURVEY_DEFINITION_INVALID'; end if;
  insert into public.survey_assets (organization_id,project_id,asset_type,source_asset_id,title,description,owner_id,assigned_to,created_by)
  values (v_org,v_project,p_asset_type,p_source_asset_id,v_definition->'title',coalesce(v_definition->'description','{}'::jsonb),auth.uid(),auth.uid(),auth.uid()) returning * into v_asset;
  insert into public.survey_drafts (asset_id,organization_id,project_id,definition,updated_by)
  values (v_asset.id,v_org,v_project,v_definition,auth.uid());
  insert into public.audit_events (organization_id,actor_id,entity_type,entity_id,action,metadata)
  values (v_org,auth.uid(),'survey_asset',v_asset.id,'created',jsonb_build_object('asset_type',p_asset_type));
  return jsonb_build_object('id',v_asset.id,'revision',1,'definition',v_definition);
end;
$$;

create or replace function public.rpc_aoi_survey_workspace(p_asset_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid() <> v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  return jsonb_build_object(
    'asset',jsonb_build_object('id',v_asset.id,'assetType',v_asset.asset_type,'title',v_asset.title,'description',v_asset.description,'status',v_asset.lifecycle_status,'ownerId',v_asset.owner_id,'assignedTo',v_asset.assigned_to,'tags',v_asset.tags,'updatedAt',v_asset.updated_at),
    'draft',(select jsonb_build_object('revision',draft.revision,'definition',draft.definition,'validationErrors',draft.validation_errors,'updatedAt',draft.updated_at) from public.survey_drafts draft where draft.asset_id=p_asset_id),
    'versions',coalesce((select jsonb_agg(jsonb_build_object('id',version.id,'versionNumber',version.version_number,'status',version.version_status,'submittedAt',version.submitted_at,'reviewedAt',version.reviewed_at,'publishedAt',version.published_at,'reviewNotes',version.review_notes) order by version.version_number desc) from public.survey_versions version where version.asset_id=p_asset_id),'[]'::jsonb),
    'links',coalesce((select jsonb_agg(jsonb_build_object('id',link.id,'versionId',link.version_id,'label',link.label,'mode',link.link_mode,'identityMode',link.identity_mode,'status',link.link_status,'responseCount',link.response_count,'maxResponses',link.max_responses,'opensAt',link.opens_at,'closesAt',link.closes_at,'settings',link.settings) order by link.created_at desc) from public.survey_links link where link.asset_id=p_asset_id),'[]'::jsonb),
    'submissions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',response.id,'versionId',response.version_id,'linkId',response.link_id,'status',response.response_status,'locale',response.locale,'score',response.score_result,'qualityFlags',response.quality_flags,'assignedTo',response.assigned_to,'startedAt',response.started_at,'submittedAt',response.submitted_at,'approvedAt',response.approved_at,
      'answers',coalesce((select jsonb_object_agg(answer.question_id,answer.answer_value) from public.survey_answers answer where answer.submission_id=response.id and answer.is_active),'{}'::jsonb),
      'identifiers',coalesce((select jsonb_object_agg(identifier.question_id,identifier.answer_value) from public.survey_response_identifiers identifier where identifier.submission_id=response.id and identifier.is_active),'{}'::jsonb)
    ) order by response.started_at desc) from public.survey_submissions response where response.asset_id=p_asset_id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_public_survey_save(p_token text,p_invitation_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare
  v_submission public.survey_submissions;
  v_answer record;
  v_existing public.survey_answers;
  v_identifier public.survey_response_identifiers;
  v_definition jsonb;
  v_identifier_ids text[] := '{}';
begin
  select response.* into v_submission from public.survey_submissions response join public.survey_links link on link.id=response.link_id
  left join public.survey_invitations invitation on invitation.id=response.invitation_id
  where response.id=p_submission_id and response.response_status in ('in_progress','revision_requested') and response.resume_token_hash=digest(p_resume_token,'sha256')
    and (link.token_hash=digest(p_token,'sha256') or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) and link.link_status='active' and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now())
    and (link.link_mode<>'invited' or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) for update of response;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if jsonb_typeof(p_answers)<>'object' then raise exception 'SURVEY_ANSWERS_INVALID'; end if;

  select version.definition into v_definition from public.survey_versions version where version.id=v_submission.version_id;
  select coalesce(array_agg(question->>'id'), '{}') into v_identifier_ids
  from jsonb_array_elements(v_definition->'blocks') section
  cross join lateral jsonb_array_elements(coalesce(section->'blocks','[]'::jsonb)) question
  where question#>>'{privacy,classification}'='direct_identifier';

  for v_existing in select * from public.survey_answers where submission_id=v_submission.id and is_active and (not (p_answers ? question_id) or question_id=any(v_identifier_ids)) for update loop
    insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
    values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,'null'::jsonb,
      case when v_existing.question_id=any(v_identifier_ids) then 'Answer moved to restricted identifier storage' else 'Answer hidden by current branch path' end);
    update public.survey_answers set is_active=false,answer_revision=answer_revision+1,updated_at=now() where id=v_existing.id;
  end loop;

  update public.survey_response_identifiers set is_active=false,answer_revision=answer_revision+1,updated_at=now()
  where submission_id=v_submission.id and is_active and (not (p_answers ? question_id) or not (question_id=any(v_identifier_ids)));

  for v_answer in select key,value from jsonb_each(p_answers) loop
    if v_answer.key=any(v_identifier_ids) then
      select * into v_identifier from public.survey_response_identifiers where submission_id=v_submission.id and question_id=v_answer.key for update;
      if v_identifier.id is null then
        insert into public.survey_response_identifiers(organization_id,project_id,submission_id,question_id,answer_value)
        values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value);
      elsif v_identifier.answer_value is distinct from v_answer.value or not v_identifier.is_active then
        update public.survey_response_identifiers set answer_value=v_answer.value,answer_revision=answer_revision+1,is_active=true,updated_at=now() where id=v_identifier.id;
      end if;
    else
      select * into v_existing from public.survey_answers where submission_id=v_submission.id and question_id=v_answer.key for update;
      if v_existing.id is null then
        insert into public.survey_answers(organization_id,project_id,submission_id,question_id,answer_value,validated,is_active)
        values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value,true,true);
      elsif v_existing.answer_value is distinct from v_answer.value or not v_existing.is_active then
        insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
        values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,v_answer.value,'Respondent autosave revision');
        update public.survey_answers set answer_value=v_answer.value,answer_revision=answer_revision+1,validated=true,is_active=true,updated_at=now() where id=v_existing.id;
      end if;
    end if;
  end loop;
  update public.survey_submissions set last_saved_at=now(),response_status='in_progress' where id=v_submission.id;
  return jsonb_build_object('submissionId',v_submission.id,'savedAt',now());
end;
$$;

revoke all on function public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb) to service_role;
