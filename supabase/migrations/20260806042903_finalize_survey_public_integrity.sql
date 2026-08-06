create or replace function public.rpc_aoi_public_survey_load(p_token text,p_invitation_token text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_link public.survey_links; v_version public.survey_versions; v_asset public.survey_assets; v_invitation public.survey_invitations;
begin
  if nullif(p_invitation_token,'') is not null then
    select * into v_invitation from public.survey_invitations invitation where invitation.token_hash=digest(p_invitation_token,'sha256') and invitation.invitation_status not in ('completed','revoked','bounced');
    if v_invitation.id is not null then select * into v_link from public.survey_links where id=v_invitation.link_id; end if;
  else select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256'); end if;
  if v_link.id is null or v_link.link_status<>'active' or (v_link.opens_at is not null and v_link.opens_at>now()) or (v_link.closes_at is not null and v_link.closes_at<=now()) or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses) then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  select * into v_version from public.survey_versions where id=v_link.version_id and version_status='published';
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
declare v_link public.survey_links; v_asset public.survey_assets; v_submission public.survey_submissions; v_invitation public.survey_invitations; v_resume text; v_locale text;
begin
  if coalesce((p_consent->>'accepted')::boolean,false) is not true then raise exception 'SURVEY_CONSENT_REQUIRED'; end if;
  if nullif(p_invitation_token,'') is not null then
    select * into v_invitation from public.survey_invitations invitation where invitation.token_hash=digest(p_invitation_token,'sha256') and invitation.invitation_status not in ('completed','revoked','bounced') for update;
    if v_invitation.id is not null then select * into v_link from public.survey_links where id=v_invitation.link_id for update; end if;
  else select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256') for update; end if;
  if v_link.id is null or v_link.link_status<>'active' or (v_link.opens_at is not null and v_link.opens_at>now()) or (v_link.closes_at is not null and v_link.closes_at<=now()) or (v_link.max_responses is not null and v_link.response_count>=v_link.max_responses) then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  if v_asset.lifecycle_status<>'published' then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  if v_link.link_mode='invited' then
    if v_invitation.id is null then select * into v_invitation from public.survey_invitations invitation where invitation.link_id=v_link.id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256') and invitation.invitation_status not in ('completed','revoked','bounced') for update; end if;
    if v_invitation.id is null then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
  elsif v_link.identity_mode='identified' then raise exception 'SURVEY_INVITATION_REQUIRED'; end if;
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
declare v_submission public.survey_submissions; v_link public.survey_links; v_asset public.survey_assets; v_first_submission boolean;
begin
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'SURVEY_IDEMPOTENCY_REQUIRED'; end if;
  select * into v_submission from public.survey_submissions where id=p_submission_id and resume_token_hash=digest(p_resume_token,'sha256') for update;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if v_submission.idempotency_key=p_idempotency_key then return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at); end if;
  if v_submission.response_status not in ('in_progress','revision_requested') then raise exception 'SURVEY_RESPONSE_LOCKED'; end if;
  select * into v_link from public.survey_links link where link.id=v_submission.link_id and (link.token_hash=digest(p_token,'sha256') or exists(select 1 from public.survey_invitations invitation where invitation.id=v_submission.invitation_id and invitation.token_hash=digest(coalesce(p_invitation_token,''),'sha256'))) and link.link_status='active' and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now()) for update;
  select * into v_asset from public.survey_assets where id=v_submission.asset_id;
  if v_link.id is null or v_asset.lifecycle_status<>'published' then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
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
  if p_action='request_revision' then update public.survey_invitations set invitation_status='started',completed_at=null where id=v_submission.invitation_id; end if;
  insert into public.survey_reviews(organization_id,project_id,submission_id,action,notes,reviewer_id) values(v_submission.organization_id,v_submission.project_id,v_submission.id,case when p_action='start_review' then 'in_review' else p_action end,nullif(trim(p_notes),''),auth.uid());
  return jsonb_build_object('id',v_submission.id,'status',v_submission.response_status,'action',p_action);
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
  return jsonb_build_object('population',p_population,'populationCount',v_population_count,'starts',v_started,'completed',v_completed,'completionRate',case when v_started=0 then 0 else round(v_completed::numeric/v_started*100) end,
    'statusCounts',coalesce((select jsonb_object_agg(response_status,total) from(select response_status,count(*) total from public.survey_submissions where asset_id=p_asset_id group by response_status) status),'{}'::jsonb),
    'questions',coalesce((select jsonb_agg(jsonb_build_object('questionId',answer.question_id,'count',count(*),'denominator',v_population_count,'values',jsonb_agg(answer.answer_value))) from public.survey_answers answer join public.survey_submissions response on response.id=answer.submission_id where response.asset_id=p_asset_id and response.response_status=any(v_allowed) and answer.is_active group by answer.question_id),'[]'::jsonb),
    'qualityFlags',coalesce((select jsonb_agg(jsonb_build_object('submissionId',id,'flags',quality_flags)) from public.survey_submissions where asset_id=p_asset_id and response_status=any(v_allowed) and jsonb_array_length(quality_flags)>0),'[]'::jsonb));
end;
$$;
