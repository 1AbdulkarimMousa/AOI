-- Close public collection integrity gaps found in the pre-release review.

alter table public.survey_answers add column is_active boolean not null default true;
alter table public.survey_links add constraint survey_identified_links_are_invited check(identity_mode<>'identified' or link_mode='invited') not valid;
alter table public.survey_links validate constraint survey_identified_links_are_invited;
create unique index survey_promotions_answer_unique on public.survey_promotions (submission_id,answer_id,target_type) where answer_id is not null;
create unique index survey_submissions_invitation_unique on public.survey_submissions (invitation_id) where invitation_id is not null;
create unique index survey_versions_asset_identity_unique on public.survey_versions (organization_id,project_id,asset_id,id);
create unique index survey_versions_one_submitted on public.survey_versions(asset_id) where version_status='submitted';
create unique index survey_versions_one_approved on public.survey_versions(asset_id) where version_status='approved';
create unique index survey_links_full_identity_unique on public.survey_links (organization_id,project_id,asset_id,version_id,id);

alter table public.survey_links add constraint survey_links_version_asset_fk
  foreign key (organization_id,project_id,asset_id,version_id)
  references public.survey_versions(organization_id,project_id,asset_id,id) on delete restrict not valid;
alter table public.survey_links validate constraint survey_links_version_asset_fk;
alter table public.survey_submissions add constraint survey_submissions_link_identity_fk
  foreign key (organization_id,project_id,asset_id,version_id,link_id)
  references public.survey_links(organization_id,project_id,asset_id,version_id,id) on delete restrict not valid;
alter table public.survey_submissions validate constraint survey_submissions_link_identity_fk;

create or replace function private.enforce_aoi_survey_source_scope()
returns trigger language plpgsql set search_path = '' as $$
declare v_source public.survey_assets;
begin
  if new.source_asset_id is null then return new; end if;
  select * into v_source from public.survey_assets where id=new.source_asset_id;
  if v_source.id is null or v_source.organization_id<>new.organization_id or v_source.project_id<>new.project_id then raise exception 'SURVEY_SOURCE_SCOPE_INVALID'; end if;
  return new;
end;
$$;
drop trigger if exists survey_source_scope_guard on public.survey_assets;
create trigger survey_source_scope_guard before insert or update of source_asset_id,organization_id,project_id on public.survey_assets for each row execute function private.enforce_aoi_survey_source_scope();
revoke all on function private.enforce_aoi_survey_source_scope() from public,anon,authenticated;

create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare v_errors jsonb := '[]'::jsonb; v_section jsonb; v_question jsonb; v_option jsonb; v_ids text[] := '{}'; v_type text;
begin
  if jsonb_typeof(p_definition)<>'object' then return jsonb_build_array(jsonb_build_object('code','DEFINITION_OBJECT_REQUIRED','path','definition')); end if;
  if coalesce((p_definition->>'schemaVersion')::integer,0)<>1 then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SCHEMA_VERSION_UNSUPPORTED','path','schemaVersion')); end if;
  if nullif(trim(p_definition#>>'{title,en}'),'') is null or nullif(trim(p_definition#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_TRANSLATIONS_REQUIRED','path','title')); end if;
  if jsonb_typeof(p_definition->'blocks')<>'array' or jsonb_array_length(p_definition->'blocks')=0 then return v_errors||jsonb_build_array(jsonb_build_object('code','SURVEY_BLOCK_REQUIRED','path','blocks')); end if;
  for v_section in select value from jsonb_array_elements(p_definition->'blocks') loop
    if v_section->>'type'<>'section' or nullif(v_section->>'id','') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SECTION_INVALID','path','blocks')); end if;
    if nullif(trim(v_section#>>'{title,en}'),'') is null or nullif(trim(v_section#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','SECTION_TRANSLATIONS_REQUIRED','path',coalesce(v_section->>'id','section'))); end if;
    for v_question in select value from jsonb_array_elements(coalesce(v_section->'blocks','[]'::jsonb)) loop
      v_type:=v_question->>'type';
      if coalesce(v_question->>'id','') !~ '^[A-Za-z][A-Za-z0-9_-]{0,79}$' or (v_question->>'id')=any(v_ids) then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_ID_INVALID','path',coalesce(v_question->>'id','question'))); else v_ids:=array_append(v_ids,v_question->>'id'); end if;
      if v_type not in ('short_text','long_text','number','email','phone','url','date','time','single_choice','multiple_choice','dropdown','yes_no','rating','nps','likert','matrix_single','matrix_multiple','ranking','upload','signature','consent','calculated','hidden') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_TYPE_INVALID','path',coalesce(v_question->>'id','question'))); end if;
      if nullif(trim(v_question#>>'{title,en}'),'') is null or nullif(trim(v_question#>>'{title,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_TRANSLATIONS_REQUIRED','path',coalesce(v_question->>'id','question'))); end if;
      if v_type in ('single_choice','multiple_choice','dropdown','yes_no','ranking') then
        if jsonb_typeof(v_question->'options')<>'array' or jsonb_array_length(v_question->'options')<2 then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','QUESTION_OPTIONS_REQUIRED','path',v_question->>'id')); end if;
        for v_option in select value from jsonb_array_elements(coalesce(v_question->'options','[]'::jsonb)) loop
          if coalesce(v_option->>'id','') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' or nullif(trim(v_option#>>'{label,en}'),'') is null or nullif(trim(v_option#>>'{label,zh}'),'') is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','OPTION_INVALID','path',v_question->>'id')); end if;
        end loop;
      end if;
      if v_type='calculated' and coalesce(v_question#>>'{calculation,operator}','') not in ('sum','average','minimum','maximum','product','difference') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CALCULATION_INVALID','path',v_question->>'id')); end if;
    end loop;
  end loop;
  return v_errors;
exception when others then return jsonb_build_array(jsonb_build_object('code','DEFINITION_INVALID','path','definition'));
end;
$$;

create or replace function public.rpc_aoi_create_survey_invitation(p_link_id uuid,p_recipient_name text,p_recipient_email text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_link public.survey_links; v_asset public.survey_assets; v_invitation public.survey_invitations; v_token text;
begin
  select * into v_link from public.survey_links where id=p_link_id and link_mode='invited' and link_status='active';
  if v_link.id is null then raise exception 'SURVEY_INVITED_LINK_REQUIRED'; end if;
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  if not public.is_org_admin(v_link.organization_id) and auth.uid()<>v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  if nullif(trim(p_recipient_email),'') is null then raise exception 'SURVEY_INVITATION_EMAIL_REQUIRED'; end if;
  v_token:=encode(gen_random_bytes(24),'hex');
  insert into public.survey_invitations(organization_id,project_id,link_id,token_hash,recipient_name,recipient_email,created_by)
  values(v_link.organization_id,v_link.project_id,v_link.id,digest(v_token,'sha256'),nullif(trim(p_recipient_name),''),lower(trim(p_recipient_email)),auth.uid()) returning * into v_invitation;
  insert into public.audit_events(organization_id,actor_id,entity_type,entity_id,action,metadata) values(v_link.organization_id,auth.uid(),'survey_invitation',v_invitation.id,'created',jsonb_build_object('link_id',v_link.id));
  return jsonb_build_object('id',v_invitation.id,'token',v_token,'status',v_invitation.invitation_status);
end;
$$;

create or replace function public.rpc_aoi_public_survey_load(p_token text,p_invitation_token text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_link public.survey_links; v_version public.survey_versions; v_asset public.survey_assets; v_invitation public.survey_invitations;
begin
  if nullif(p_invitation_token,'') is not null then
    select * into v_invitation from public.survey_invitations invitation where invitation.token_hash=digest(p_invitation_token,'sha256') and invitation.invitation_status not in ('completed','revoked','bounced');
    if v_invitation.id is not null then select * into v_link from public.survey_links where id=v_invitation.link_id; end if;
  else
    select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256');
  end if;
  if v_link.id is null or v_link.link_status<>'active' or (v_link.opens_at is not null and v_link.opens_at>now()) or (v_link.closes_at is not null and v_link.closes_at<=now()) or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses) then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  select * into v_version from public.survey_versions where id=v_link.version_id and version_status='published';
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  if v_version.id is null then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' then
    if v_invitation.id is null then select * into v_invitation from public.survey_invitations invitation where invitation.link_id=v_link.id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256') and invitation.invitation_status not in ('completed','revoked','bounced'); end if;
    if v_invitation.id is null then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  elsif v_link.identity_mode='identified' then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  return jsonb_build_object('linkId',v_link.id,'versionId',v_version.id,'identityMode',v_link.identity_mode,'mode',v_link.link_mode,'definition',v_version.definition,'title',v_asset.title,'settings',v_link.settings,'allowedOrigins',v_link.allowed_origins,'invitationId',v_invitation.id);
end;
$$;

create or replace function public.rpc_aoi_public_survey_start(p_token text,p_invitation_token text,p_locale text,p_consent jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_link public.survey_links; v_submission public.survey_submissions; v_invitation public.survey_invitations; v_resume text;
begin
  if nullif(p_invitation_token,'') is not null then
    select * into v_invitation from public.survey_invitations invitation where invitation.token_hash=digest(p_invitation_token,'sha256') and invitation.invitation_status not in ('completed','revoked','bounced') for update;
    if v_invitation.id is not null then select * into v_link from public.survey_links where id=v_invitation.link_id for update; end if;
  else
    select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256') for update;
  end if;
  if v_link.id is null or v_link.link_status<>'active' or (v_link.opens_at is not null and v_link.opens_at>now()) or (v_link.closes_at is not null and v_link.closes_at<=now()) or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses) then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' then
    if v_invitation.id is null then select * into v_invitation from public.survey_invitations invitation where invitation.link_id=v_link.id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256') and invitation.invitation_status not in ('completed','revoked','bounced') for update; end if;
    if v_invitation.id is null then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  elsif v_link.identity_mode='identified' then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  v_resume:=encode(gen_random_bytes(24),'hex');
  insert into public.survey_submissions(organization_id,project_id,asset_id,version_id,link_id,invitation_id,resume_token_hash,locale,consent_receipt,retention_review_at)
  values(v_link.organization_id,v_link.project_id,v_link.asset_id,v_link.version_id,v_link.id,v_invitation.id,digest(v_resume,'sha256'),case when p_locale='zh-CN' then 'zh-CN' else 'en' end,p_consent,current_date+interval '1 year') returning * into v_submission;
  if v_invitation.id is not null then update public.survey_invitations set invitation_status='started' where id=v_invitation.id; end if;
  return jsonb_build_object('submissionId',v_submission.id,'resumeToken',v_resume,'status','in_progress');
exception when unique_violation then raise exception 'SURVEY_INVITATION_ALREADY_USED';
end;
$$;

create or replace function public.rpc_aoi_public_survey_save(p_token text,p_invitation_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions; v_answer record; v_existing public.survey_answers;
begin
  select response.* into v_submission from public.survey_submissions response join public.survey_links link on link.id=response.link_id
  left join public.survey_invitations invitation on invitation.id=response.invitation_id
  where response.id=p_submission_id and response.response_status in ('in_progress','revision_requested') and response.resume_token_hash=digest(p_resume_token,'sha256')
    and (link.token_hash=digest(p_token,'sha256') or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) and link.link_status='active' and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now())
    and (link.link_mode<>'invited' or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) for update of response;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if jsonb_typeof(p_answers)<>'object' then raise exception 'SURVEY_ANSWERS_INVALID'; end if;
  for v_existing in select * from public.survey_answers where submission_id=v_submission.id and is_active and not (p_answers ? question_id) for update loop
    insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
    values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,'null'::jsonb,'Answer hidden by current branch path');
    update public.survey_answers set is_active=false,answer_revision=answer_revision+1,updated_at=now() where id=v_existing.id;
  end loop;
  for v_answer in select key,value from jsonb_each(p_answers) loop
    select * into v_existing from public.survey_answers where submission_id=v_submission.id and question_id=v_answer.key for update;
    if v_existing.id is null then
      insert into public.survey_answers(organization_id,project_id,submission_id,question_id,answer_value,validated,is_active) values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value,true,true);
    elsif v_existing.answer_value is distinct from v_answer.value or not v_existing.is_active then
      insert into public.survey_answer_revisions(organization_id,project_id,answer_id,revision,previous_value,new_value,change_reason)
      values(v_existing.organization_id,v_existing.project_id,v_existing.id,v_existing.answer_revision+1,v_existing.answer_value,v_answer.value,'Respondent autosave revision');
      update public.survey_answers set answer_value=v_answer.value,answer_revision=answer_revision+1,validated=true,is_active=true,updated_at=now() where id=v_existing.id;
    end if;
  end loop;
  update public.survey_submissions set last_saved_at=now(),response_status='in_progress' where id=v_submission.id;
  return jsonb_build_object('submissionId',v_submission.id,'savedAt',now());
end;
$$;

create or replace function public.rpc_aoi_public_survey_submit(p_token text,p_invitation_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb,p_idempotency_key text,p_score jsonb,p_consent jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions; v_link public.survey_links; v_first_submission boolean;
begin
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'SURVEY_IDEMPOTENCY_REQUIRED'; end if;
  select response.* into v_submission from public.survey_submissions response where response.id=p_submission_id and response.resume_token_hash=digest(p_resume_token,'sha256') for update;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if v_submission.idempotency_key=p_idempotency_key then return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at); end if;
  if v_submission.response_status not in ('in_progress','revision_requested') then raise exception 'SURVEY_RESPONSE_LOCKED'; end if;
  select * into v_link from public.survey_links link where link.id=v_submission.link_id and (link.token_hash=digest(p_token,'sha256') or exists(select 1 from public.survey_invitations invitation where invitation.id=v_submission.invitation_id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'))) and link.link_status='active'
    and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now()) for update;
  if v_link.id is null then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' and not exists(select 1 from public.survey_invitations invitation where invitation.id=v_submission.invitation_id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  v_first_submission:=v_submission.submitted_at is null;
  if v_first_submission and v_link.max_responses is not null and v_link.response_count>=v_link.max_responses then raise exception 'SURVEY_RESPONSE_CAPACITY_REACHED'; end if;
  perform public.rpc_aoi_public_survey_save(p_token,p_invitation_token,p_submission_id,p_resume_token,p_answers);
  update public.survey_submissions set response_status='submitted',submitted_at=coalesce(submitted_at,now()),last_saved_at=now(),idempotency_key=p_idempotency_key,score_result=p_score,consent_receipt=p_consent where id=v_submission.id returning * into v_submission;
  if v_first_submission then update public.survey_links set response_count=response_count+1,link_status=case when max_responses is not null and response_count+1>=max_responses then 'exhausted' else link_status end where id=v_submission.link_id; end if;
  if v_submission.invitation_id is not null then update public.survey_invitations set invitation_status='completed',completed_at=now() where id=v_submission.invitation_id; end if;
  return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at);
end;
$$;

create or replace function public.rpc_aoi_public_survey_upload_authorize(p_token text,p_invitation_token text,p_submission_id uuid,p_resume_token text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions;
begin
  select response.* into v_submission from public.survey_submissions response join public.survey_links link on link.id=response.link_id
  left join public.survey_invitations invitation on invitation.id=response.invitation_id
  where response.id=p_submission_id and response.response_status in ('in_progress','revision_requested') and response.resume_token_hash=digest(p_resume_token,'sha256')
    and (link.token_hash=digest(p_token,'sha256') or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256')) and link.link_status='active'
    and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now())
    and (link.link_mode<>'invited' or invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'));
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  return jsonb_build_object('submissionId',v_submission.id);
end;
$$;

create or replace function public.rpc_aoi_review_survey_submission(p_submission_id uuid,p_action text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_status text;
begin
  select * into v_submission from public.survey_submissions response where response.id=p_submission_id and public.is_org_member(response.organization_id) for update;
  if v_submission.id is null then raise exception 'SURVEY_SUBMISSION_NOT_FOUND'; end if;
  if not public.is_org_admin(v_submission.organization_id) and auth.uid() is distinct from v_submission.assigned_to then raise exception 'SURVEY_REVIEW_ASSIGNMENT_REQUIRED'; end if;
  if p_action='start_review' and v_submission.response_status<>'submitted' then raise exception 'SURVEY_REVIEW_TRANSITION_INVALID'; end if;
  if p_action in ('recommend_approve','recommend_reject') and v_submission.response_status<>'in_review' then raise exception 'SURVEY_REVIEW_TRANSITION_INVALID'; end if;
  if p_action in ('approve','reject','exclude','request_revision') and v_submission.response_status not in ('submitted','in_review') then raise exception 'SURVEY_REVIEW_TRANSITION_INVALID'; end if;
  if p_action in ('approve','reject','exclude','request_revision') and not public.is_org_admin(v_submission.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  if p_action='request_revision' and v_submission.invitation_id is null then raise exception 'SURVEY_REVISION_CONTACT_REQUIRED'; end if;
  v_status:=case p_action when 'start_review' then 'in_review' when 'approve' then 'approved' when 'request_revision' then 'revision_requested' when 'reject' then 'rejected' when 'exclude' then 'excluded' else null end;
  if v_status is not null then update public.survey_submissions set response_status=v_status,reviewed_by=case when p_action in ('approve','reject','exclude','request_revision') then auth.uid() else reviewed_by end,reviewed_at=case when p_action in ('approve','reject','exclude','request_revision') then now() else reviewed_at end,approved_at=case when p_action='approve' then now() else approved_at end where id=p_submission_id returning * into v_submission; end if;
  insert into public.survey_reviews(organization_id,project_id,submission_id,action,notes,reviewer_id) values(v_submission.organization_id,v_submission.project_id,v_submission.id,case when p_action='start_review' then 'in_review' else p_action end,nullif(trim(p_notes),''),auth.uid());
  return jsonb_build_object('id',v_submission.id,'status',v_submission.response_status,'action',p_action);
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
  update public.survey_versions set version_status='published',published_at=now() where id=p_version_id returning * into v_version;
  update public.survey_assets set lifecycle_status='published',updated_at=now() where id=v_version.asset_id;
  insert into public.audit_events(organization_id,actor_id,entity_type,entity_id,action,metadata) values(v_version.organization_id,auth.uid(),'survey_version',v_version.id,'published',jsonb_build_object('version',v_version.version_number));
  return jsonb_build_object('id',v_version.id,'assetId',v_version.asset_id,'status','published','publishedAt',v_version.published_at);
end;
$$;

create or replace function public.rpc_aoi_survey_analysis(p_asset_id uuid,p_population text default 'approved')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets; v_allowed text[]; v_started integer; v_completed integer;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if p_population not in ('approved','operational') then raise exception 'SURVEY_POPULATION_INVALID'; end if;
  v_allowed:=case when p_population='approved' then array['approved'] else array['submitted','in_review','approved','revision_requested','rejected','excluded'] end;
  select count(*),count(*) filter(where submitted_at is not null) into v_started,v_completed from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed);
  return jsonb_build_object('population',p_population,'starts',v_started,'completed',v_completed,'completionRate',case when v_started=0 then 0 else round(v_completed::numeric/v_started*100) end,
    'statusCounts',coalesce((select jsonb_object_agg(response_status,total) from(select response_status,count(*) total from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed) group by response_status) status),'{}'::jsonb),
    'questions',coalesce((select jsonb_agg(jsonb_build_object('questionId',answer.question_id,'count',count(*),'values',jsonb_agg(answer.answer_value))) from public.survey_answers answer join public.survey_submissions response on response.id=answer.submission_id where response.asset_id=p_asset_id and response.response_status=any(v_allowed) and answer.is_active group by answer.question_id),'[]'::jsonb),
    'qualityFlags',coalesce((select jsonb_agg(jsonb_build_object('submissionId',id,'flags',quality_flags)) from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed) and jsonb_array_length(quality_flags)>0),'[]'::jsonb));
end;
$$;

create or replace function public.rpc_aoi_promote_survey_answer(p_submission_id uuid,p_question_id text,p_metric_code text,p_segment_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_answer public.survey_answers; v_definition public.pmf_metric_definitions; v_segment public.research_segments; v_observation public.pmf_observations; v_version public.survey_versions; v_question jsonb;
begin
  select * into v_submission from public.survey_submissions where id=p_submission_id for update;
  if v_submission.id is null or v_submission.response_status<>'approved' then raise exception 'SURVEY_APPROVED_RESPONSE_REQUIRED'; end if;
  if not public.is_org_admin(v_submission.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  if exists(select 1 from public.survey_promotions where submission_id=p_submission_id and answer_id=(select id from public.survey_answers where submission_id=p_submission_id and question_id=p_question_id) and target_type='pmf_observation') then raise exception 'SURVEY_ANSWER_ALREADY_PROMOTED'; end if;
  select * into v_answer from public.survey_answers where submission_id=p_submission_id and question_id=p_question_id and is_active;
  select * into v_version from public.survey_versions where id=v_submission.version_id;
  select jsonb_path_query_first(v_version.definition,'$.blocks[*].blocks[*] ? (@.id == $questionId)',jsonb_build_object('questionId',to_jsonb(p_question_id))) into v_question;
  if v_question is null or v_question#>>'{pmfMapping,metricCode}'<>p_metric_code then raise exception 'SURVEY_PMF_MAPPING_INVALID'; end if;
  select * into v_definition from public.pmf_metric_definitions where organization_id=v_submission.organization_id and project_id=v_submission.project_id and code=p_metric_code and active;
  select * into v_segment from public.research_segments where organization_id=v_submission.organization_id and project_id=v_submission.project_id and code=p_segment_code and active;
  if v_answer.id is null or v_definition.id is null or v_segment.id is null then raise exception 'SURVEY_PROMOTION_TARGET_INVALID'; end if;
  insert into public.pmf_observations(organization_id,project_id,definition_id,respondent_id,segment_id,numeric_value,boolean_value,text_value,source_link,notes,workflow_status,assigned_to,created_by,submitted_at,reviewed_by,reviewed_at,review_notes)
  values(v_submission.organization_id,v_submission.project_id,v_definition.id,v_submission.respondent_id,v_segment.id,case when v_definition.value_type='numeric' then(v_answer.answer_value#>>'{}')::numeric end,case when v_definition.value_type='boolean' then(v_answer.answer_value#>>'{}')::boolean end,case when v_definition.value_type='text' then coalesce(v_answer.answer_value#>>'{}',v_answer.answer_value::text) end,'https://1abdulkarimmousa.github.io/AOI/workspace.html?view=surveys&response='||v_submission.id::text,'Survey '||v_submission.asset_id::text||', version '||v_submission.version_id::text||', question '||p_question_id,'approved',auth.uid(),auth.uid(),v_submission.submitted_at,auth.uid(),now(),'Approved survey promotion') returning * into v_observation;
  insert into public.survey_promotions(organization_id,project_id,submission_id,answer_id,target_type,target_id,promoted_by) values(v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.id,'pmf_observation',v_observation.id,auth.uid());
  return jsonb_build_object('promotionType','pmf_observation','targetId',v_observation.id,'questionId',p_question_id,'metricCode',p_metric_code);
end;
$$;

drop policy if exists survey_text_codes_member_read on public.survey_text_codes;
create policy survey_text_codes_assignee_read on public.survey_text_codes for select to authenticated using(exists(select 1 from public.survey_answers answer join public.survey_submissions response on response.id=answer.submission_id join public.survey_assets asset on asset.id=response.asset_id where answer.id=public.survey_text_codes.answer_id and (public.is_org_admin(answer.organization_id) or response.assigned_to=(select auth.uid()) or asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));

revoke all on function public.rpc_aoi_create_survey_invitation(uuid,text,text) from public,anon;
grant execute on function public.rpc_aoi_create_survey_invitation(uuid,text,text) to authenticated;
revoke all on function public.rpc_aoi_public_survey_load(text,text),public.rpc_aoi_public_survey_start(text,text,text,jsonb),public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb),public.rpc_aoi_public_survey_submit(text,text,uuid,text,jsonb,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_load(text,text),public.rpc_aoi_public_survey_start(text,text,text,jsonb),public.rpc_aoi_public_survey_save(text,text,uuid,text,jsonb),public.rpc_aoi_public_survey_submit(text,text,uuid,text,jsonb,text,jsonb,jsonb) to service_role;
revoke all on function public.rpc_aoi_public_survey_upload_authorize(text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_upload_authorize(text,text,uuid,text) to service_role;
revoke all on function public.rpc_aoi_public_survey_load(text),public.rpc_aoi_public_survey_start(text,text,jsonb),public.rpc_aoi_public_survey_save(text,uuid,text,jsonb),public.rpc_aoi_public_survey_submit(text,uuid,text,jsonb,text,jsonb,jsonb) from service_role;
