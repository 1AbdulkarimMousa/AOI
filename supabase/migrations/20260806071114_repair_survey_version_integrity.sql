-- Keep direct identifiers out of analytical answers and bind every response to
-- the immutable definition that collected it.

create or replace function public.rpc_aoi_public_survey_save(
  p_token text,
  p_invitation_token text,
  p_submission_id uuid,
  p_resume_token text,
  p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare
  v_submission public.survey_submissions;
  v_version public.survey_versions;
  v_answer record;
  v_question jsonb;
  v_existing public.survey_answers;
  v_identifier public.survey_response_identifiers;
begin
  select response.* into v_submission
  from public.survey_submissions response
  join public.survey_links link on link.id=response.link_id
  join public.survey_assets asset on asset.id=response.asset_id
  join public.survey_versions version on version.id=response.version_id
  left join public.survey_invitations invitation on invitation.id=response.invitation_id
  where response.id=p_submission_id
    and response.response_status in ('in_progress','revision_requested')
    and response.resume_token_hash=digest(p_resume_token,'sha256')
    and (link.token_hash=digest(p_token,'sha256') or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'))
    and link.link_status='active'
    and asset.lifecycle_status='published'
    and version.version_status in ('published','retired')
    and (link.opens_at is null or link.opens_at<=now())
    and (link.closes_at is null or link.closes_at>now())
    and (link.link_mode<>'invited' or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'))
  for update of response;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if jsonb_typeof(p_answers)<>'object' then raise exception 'SURVEY_ANSWERS_INVALID'; end if;

  select * into v_version from public.survey_versions where id=v_submission.version_id;
  if v_version.id is null then raise exception 'SURVEY_VERSION_NOT_FOUND'; end if;

  for v_existing in
    select * from public.survey_answers
    where submission_id=v_submission.id and is_active and not (p_answers ? question_id)
    for update
  loop
    insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
    values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,'null'::jsonb,'Answer hidden by current branch path');
    update public.survey_answers set is_active=false,answer_revision=answer_revision+1,updated_at=now() where id=v_existing.id;
  end loop;
  update public.survey_response_identifiers
  set is_active=false,answer_revision=answer_revision+1,updated_at=now()
  where submission_id=v_submission.id and is_active and not (p_answers ? question_id);

  for v_answer in select key,value from jsonb_each(p_answers) loop
    select jsonb_path_query_first(
      v_version.definition,
      '$.blocks[*].blocks[*] ? (@.id == $questionId)',
      jsonb_build_object('questionId',to_jsonb(v_answer.key))
    ) into v_question;
    if v_question is null then raise exception 'SURVEY_QUESTION_NOT_FOUND'; end if;

    if v_question#>>'{privacy,classification}'='direct_identifier' then
      select * into v_existing from public.survey_answers where submission_id=v_submission.id and question_id=v_answer.key for update;
      if v_existing.id is not null and v_existing.is_active then
        insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
        values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,'null'::jsonb,'Moved to direct identifier storage');
        update public.survey_answers set is_active=false,answer_revision=answer_revision+1,updated_at=now() where id=v_existing.id;
      end if;
      insert into public.survey_response_identifiers(organization_id,project_id,submission_id,question_id,answer_value,is_active)
      values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value,true)
      on conflict(submission_id,question_id) do update
      set answer_value=excluded.answer_value,
          answer_revision=public.survey_response_identifiers.answer_revision+1,
          is_active=true,
          updated_at=now();
    else
      update public.survey_response_identifiers
      set is_active=false,answer_revision=answer_revision+1,updated_at=now()
      where submission_id=v_submission.id and question_id=v_answer.key and is_active;
      select * into v_existing from public.survey_answers where submission_id=v_submission.id and question_id=v_answer.key for update;
      if v_existing.id is null then
        insert into public.survey_answers(organization_id,project_id,submission_id,question_id,answer_value,validated,is_active)
        values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value,true,true);
      elsif v_existing.answer_value is distinct from v_answer.value or not v_existing.is_active then
        insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
        values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,v_answer.value,'Respondent autosave revision');
        update public.survey_answers
        set answer_value=v_answer.value,answer_revision=answer_revision+1,validated=true,is_active=true,updated_at=now()
        where id=v_existing.id;
      end if;
    end if;
  end loop;

  update public.survey_submissions set last_saved_at=now(),response_status='in_progress' where id=v_submission.id;
  return jsonb_build_object('submissionId',v_submission.id,'savedAt',now());
end;
$$;

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
      'identifiers',coalesce((select jsonb_object_agg(identifier.question_id,identifier.answer_value) from public.survey_response_identifiers identifier where identifier.submission_id=response.id and identifier.is_active),'{}'::jsonb)
    ) order by response.started_at desc)
    from public.survey_submissions response
    join public.survey_versions version on version.id=response.version_id
    where response.asset_id=p_asset_id),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb) to service_role;
revoke all on function public.rpc_aoi_survey_workspace(uuid) from public,anon;
grant execute on function public.rpc_aoi_survey_workspace(uuid) to authenticated;

create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_section jsonb;
  v_question jsonb;
  v_value jsonb;
  v_ids text[] := '{}';
  v_dimension_ids text[];
  v_locales text[];
  v_require_zh boolean;
  v_type text;
begin
  if jsonb_typeof(p_definition)<>'object' then return jsonb_build_array(jsonb_build_object('code','DEFINITION_OBJECT_REQUIRED','path','definition')); end if;
  if coalesce((p_definition->>'schemaVersion')::integer,0)<>1 then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SCHEMA_VERSION_UNSUPPORTED','path','schemaVersion')); end if;
  select coalesce(array_agg(locale),'{}') into v_locales from jsonb_array_elements_text(coalesce(p_definition->'locales','[]'::jsonb)) configured(locale);
  if cardinality(v_locales)=0 or exists(select 1 from unnest(v_locales) locale where locale not in ('en','zh-CN')) then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_LOCALES_INVALID','path','locales')); end if;
  if not coalesce(p_definition->>'defaultLocale','')=any(v_locales) then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','DEFAULT_LOCALE_INVALID','path','defaultLocale')); end if;
  if jsonb_typeof(p_definition#>'{settings,showProgress}')<>'boolean'
    or jsonb_typeof(p_definition#>'{settings,allowReview}')<>'boolean'
    or jsonb_typeof(p_definition#>'{settings,randomizeSections}')<>'boolean' then
    v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_SETTING_INVALID','path','settings'));
  end if;
  if nullif(p_definition#>>'{completion,redirectUrl}','') is not null and p_definition#>>'{completion,redirectUrl}' !~ '^https?://' then
    v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','COMPLETION_REDIRECT_INVALID','path','completion.redirectUrl'));
  end if;
  v_require_zh:='zh-CN'=any(v_locales);
  if nullif(trim(p_definition#>>'{title,en}'),'') is null or v_require_zh and nullif(trim(p_definition#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_TRANSLATIONS_REQUIRED','path','title')); end if;
  if jsonb_typeof(p_definition->'blocks')<>'array' or jsonb_array_length(p_definition->'blocks')=0 then return v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_BLOCK_REQUIRED','path','blocks')); end if;
  for v_section in select value from jsonb_array_elements(p_definition->'blocks') loop
    if v_section->>'type'<>'section' or coalesce(v_section->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$' then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SECTION_INVALID','path','blocks')); end if;
    if nullif(trim(v_section#>>'{title,en}'),'') is null or v_require_zh and nullif(trim(v_section#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SECTION_TRANSLATIONS_REQUIRED','path',coalesce(v_section->>'id','section'))); end if;
    for v_question in select value from jsonb_array_elements(coalesce(v_section->'blocks','[]'::jsonb)) loop
      v_type:=v_question->>'type';
      if v_type='content' then
        if coalesce(v_question->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$' or nullif(trim(v_question#>>'{title,en}'),'') is null or v_require_zh and nullif(trim(v_question#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CONTENT_BLOCK_INVALID','path',coalesce(v_question->>'id','content'))); end if;
        continue;
      end if;
      if coalesce(v_question->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$' or (v_question->>'id')=any(v_ids) then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_ID_INVALID','path',coalesce(v_question->>'id','question'))); else v_ids:=array_append(v_ids,v_question->>'id'); end if;
      if v_type not in ('short_text','long_text','number','email','phone','url','date','time','single_choice','multiple_choice','dropdown','yes_no','rating','nps','likert','matrix_single','matrix_multiple','ranking','upload','signature','consent','calculated','hidden') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_TYPE_INVALID','path',coalesce(v_question->>'id','question'))); end if;
      if nullif(trim(v_question#>>'{title,en}'),'') is null or v_require_zh and nullif(trim(v_question#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_TRANSLATIONS_REQUIRED','path',coalesce(v_question->>'id','question'))); end if;
      if v_type in ('single_choice','multiple_choice','dropdown','yes_no','ranking') then
        v_dimension_ids:='{}';
        if jsonb_typeof(v_question->'options')<>'array' or jsonb_array_length(v_question->'options')<2 then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_OPTIONS_REQUIRED','path',v_question->>'id')); end if;
        for v_value in select value from jsonb_array_elements(coalesce(v_question->'options','[]'::jsonb)) loop
          if coalesce(v_value->>'id','') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' or (v_value->>'id')=any(v_dimension_ids) or nullif(trim(v_value#>>'{label,en}'),'') is null or v_require_zh and nullif(trim(v_value#>>'{label,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','OPTION_INVALID','path',v_question->>'id')); else v_dimension_ids:=array_append(v_dimension_ids,v_value->>'id'); end if;
        end loop;
      end if;
      if v_type in ('matrix_single','matrix_multiple') then
        if jsonb_array_length(coalesce(v_question->'rows','[]'::jsonb))=0 or jsonb_array_length(coalesce(v_question->'columns','[]'::jsonb))=0 then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','MATRIX_DIMENSIONS_REQUIRED','path',v_question->>'id')); end if;
        v_dimension_ids:='{}';
        for v_value in select value from jsonb_array_elements(coalesce(v_question->'rows','[]'::jsonb)) loop
          if coalesce(v_value->>'id','') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' or (v_value->>'id')=any(v_dimension_ids) or nullif(trim(v_value#>>'{label,en}'),'') is null or v_require_zh and nullif(trim(v_value#>>'{label,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','MATRIX_ROW_INVALID','path',v_question->>'id')); else v_dimension_ids:=array_append(v_dimension_ids,v_value->>'id'); end if;
        end loop;
        v_dimension_ids:='{}';
        for v_value in select value from jsonb_array_elements(coalesce(v_question->'columns','[]'::jsonb)) loop
          if coalesce(v_value->>'id','') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' or (v_value->>'id')=any(v_dimension_ids) or nullif(trim(v_value#>>'{label,en}'),'') is null or v_require_zh and nullif(trim(v_value#>>'{label,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','MATRIX_COLUMN_INVALID','path',v_question->>'id')); else v_dimension_ids:=array_append(v_dimension_ids,v_value->>'id'); end if;
        end loop;
      end if;
      if v_type='calculated' and coalesce(v_question#>>'{calculation,operator}','') not in ('sum','average','minimum','maximum','product','difference') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CALCULATION_INVALID','path',v_question->>'id')); end if;
    end loop;
  end loop;
  return v_errors;
exception when others then return jsonb_build_array(jsonb_build_object('code','DEFINITION_INVALID','path','definition'));
end;
$$;

create or replace function public.rpc_aoi_publish_survey(p_version_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_version public.survey_versions;
begin
  select * into v_version from public.survey_versions version where version.id=p_version_id for update;
  if v_version.id is null then raise exception 'SURVEY_VERSION_NOT_FOUND'; end if;
  if not public.is_org_admin(v_version.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  if v_version.version_status<>'approved' then raise exception 'SURVEY_VERSION_APPROVAL_REQUIRED'; end if;
  update public.survey_versions set version_status='retired' where asset_id=v_version.asset_id and version_status='published';
  update public.survey_versions set version_status='published',published_at=now() where id=p_version_id returning * into v_version;
  update public.survey_assets set lifecycle_status='published',updated_at=now() where id=v_version.asset_id;
  insert into public.audit_events(organization_id,actor_id,entity_type,entity_id,action,metadata)
  values(v_version.organization_id,auth.uid(),'survey_version',v_version.id,'published',jsonb_build_object('version',v_version.version_number));
  return jsonb_build_object('id',v_version.id,'assetId',v_version.asset_id,'status','published','publishedAt',v_version.published_at);
end;
$$;

create or replace function public.rpc_aoi_public_survey_load(p_token text,p_invitation_token text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_link public.survey_links; v_version public.survey_versions; v_asset public.survey_assets; v_invitation public.survey_invitations;
begin
  if nullif(p_invitation_token,'') is not null then
    select * into v_invitation from public.survey_invitations invitation where invitation.token_hash=digest(p_invitation_token,'sha256') and invitation.invitation_status not in ('completed','revoked','bounced');
    if v_invitation.id is not null then select * into v_link from public.survey_links where id=v_invitation.link_id; end if;
  else select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256'); end if;
  if v_link.id is null or v_link.link_status<>'active' or (v_link.opens_at is not null and v_link.opens_at>now()) or (v_link.closes_at is not null and v_link.closes_at<=now()) or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses) then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  select * into v_version from public.survey_versions where id=v_link.version_id and version_status in ('published','retired');
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  if v_version.id is null or v_asset.lifecycle_status<>'published' then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' then
    if v_invitation.id is null then select * into v_invitation from public.survey_invitations invitation where invitation.link_id=v_link.id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256') and invitation.invitation_status not in ('completed','revoked','bounced'); end if;
    if v_invitation.id is null then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  elsif v_link.identity_mode='identified' then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  return jsonb_build_object('linkId',v_link.id,'versionId',v_version.id,'identityMode',v_link.identity_mode,'mode',v_link.link_mode,'definition',v_version.definition,'title',v_asset.title,'settings',v_link.settings,'allowedOrigins',v_link.allowed_origins,'invitationId',v_invitation.id);
end;
$$;

create or replace function public.rpc_aoi_public_survey_start(p_token text,p_invitation_token text,p_locale text,p_consent jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_loaded jsonb; v_link public.survey_links; v_asset public.survey_assets; v_version public.survey_versions; v_submission public.survey_submissions; v_invitation public.survey_invitations; v_resume text; v_locale text;
begin
  if coalesce((p_consent->>'accepted')::boolean,false) is not true then raise exception 'SURVEY_CONSENT_REQUIRED'; end if;
  v_loaded:=public.rpc_aoi_public_survey_load(p_token,p_invitation_token);
  select * into v_link from public.survey_links where id=(v_loaded->>'linkId')::uuid for update;
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  select * into v_version from public.survey_versions where id=v_link.version_id;
  if v_link.link_status<>'active'
    or (v_link.opens_at is not null and v_link.opens_at>now())
    or (v_link.closes_at is not null and v_link.closes_at<=now())
    or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses)
    or v_asset.lifecycle_status<>'published'
    or v_version.version_status not in ('published','retired') then
    raise exception 'SURVEY_LINK_UNAVAILABLE';
  end if;
  if nullif(v_loaded->>'invitationId','') is not null then select * into v_invitation from public.survey_invitations where id=(v_loaded->>'invitationId')::uuid for update; end if;
  v_resume:=encode(gen_random_bytes(24),'hex'); v_locale:=case when p_locale='zh-CN' then 'zh-CN' else 'en' end;
  if v_invitation.id is not null then
    select * into v_submission from public.survey_submissions where invitation_id=v_invitation.id and response_status='revision_requested' for update;
    if v_submission.id is not null then
      update public.survey_submissions set resume_token_hash=digest(v_resume,'sha256'),locale=v_locale,last_saved_at=now() where id=v_submission.id;
      update public.survey_invitations set invitation_status='started',completed_at=null where id=v_invitation.id;
      return jsonb_build_object('submissionId',v_submission.id,'resumeToken',v_resume,'status','revision_requested','event','SURVEY_REVISION_RESUMED');
    end if;
  end if;
  insert into public.survey_submissions(organization_id,project_id,asset_id,version_id,link_id,invitation_id,resume_token_hash,locale,consent_receipt,retention_review_at)
  values(v_link.organization_id,v_link.project_id,v_link.asset_id,v_link.version_id,v_link.id,v_invitation.id,digest(v_resume,'sha256'),v_locale,jsonb_build_object('accepted',true,'locale',v_locale,'versionId',v_link.version_id,'shownAt',now()),current_date+interval '1 year') returning * into v_submission;
  if v_invitation.id is not null then update public.survey_invitations set invitation_status='started' where id=v_invitation.id; end if;
  return jsonb_build_object('submissionId',v_submission.id,'resumeToken',v_resume,'status','in_progress');
exception when unique_violation then raise exception 'SURVEY_INVITATION_ALREADY_USED';
end;
$$;

create or replace function public.rpc_aoi_public_survey_submit(p_token text,p_invitation_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb,p_idempotency_key text,p_score jsonb,p_consent jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions; v_link public.survey_links; v_version public.survey_versions; v_asset public.survey_assets; v_first_submission boolean;
begin
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'SURVEY_IDEMPOTENCY_REQUIRED'; end if;
  select * into v_submission from public.survey_submissions where id=p_submission_id and resume_token_hash=digest(p_resume_token,'sha256') for update;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if v_submission.idempotency_key=p_idempotency_key then return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at); end if;
  if v_submission.response_status not in ('in_progress','revision_requested') then raise exception 'SURVEY_RESPONSE_LOCKED'; end if;
  select * into v_link from public.survey_links link where link.id=v_submission.link_id and (link.token_hash=digest(p_token,'sha256') or exists(select 1 from public.survey_invitations invitation where invitation.id=v_submission.invitation_id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'))) and link.link_status='active' and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now()) for update;
  select * into v_version from public.survey_versions where id=v_submission.version_id and version_status in ('published','retired');
  select * into v_asset from public.survey_assets where id=v_submission.asset_id;
  if v_link.id is null or v_version.id is null or v_asset.lifecycle_status<>'published' then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' and not exists(select 1 from public.survey_invitations invitation where invitation.id=v_submission.invitation_id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  v_first_submission:=v_submission.submitted_at is null;
  if v_first_submission and v_link.max_responses is not null and v_link.response_count>=v_link.max_responses then raise exception 'SURVEY_RESPONSE_CAPACITY_REACHED'; end if;
  perform public.rpc_aoi_public_survey_save(p_token,p_invitation_token,p_submission_id,p_resume_token,p_answers);
  update public.survey_submissions set response_status='submitted',submitted_at=coalesce(submitted_at,now()),last_saved_at=now(),idempotency_key=p_idempotency_key,score_result=p_score,consent_receipt=jsonb_build_object('accepted',true,'locale',v_submission.locale,'versionId',v_submission.version_id,'submittedAt',now()) where id=v_submission.id returning * into v_submission;
  if v_first_submission then update public.survey_links set response_count=response_count+1,link_status=case when max_responses is not null and response_count+1>=max_responses then 'exhausted' else link_status end where id=v_submission.link_id; end if;
  if v_submission.invitation_id is not null then update public.survey_invitations set invitation_status='completed',completed_at=now() where id=v_submission.invitation_id; end if;
  return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at);
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
      where response.asset_id=p_asset_id and response.response_status=any(v_allowed) and answer.is_active and question->>'id'=answer.question_id
      group by response.version_id,answer.question_id,question
    ) typed),'[]'::jsonb),
    'qualityFlags',coalesce((select jsonb_agg(jsonb_build_object('submissionId',id,'flags',quality_flags)) from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed) and jsonb_array_length(quality_flags)>0),'[]'::jsonb)
  );
end;
$$;

revoke all on function private.validate_aoi_survey_definition(jsonb) from public,anon,authenticated;
revoke all on function public.rpc_aoi_public_survey_load(text,text),public.rpc_aoi_public_survey_start(text,text,text,jsonb),public.rpc_aoi_public_survey_submit(text,text,uuid,text,jsonb,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_load(text,text),public.rpc_aoi_public_survey_start(text,text,text,jsonb),public.rpc_aoi_public_survey_submit(text,text,uuid,text,jsonb,text,jsonb,jsonb) to service_role;
