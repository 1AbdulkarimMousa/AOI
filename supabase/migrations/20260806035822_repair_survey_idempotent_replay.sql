create or replace function public.rpc_aoi_public_survey_replay(p_submission_id uuid,p_resume_token text,p_idempotency_key text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, extensions as $$
declare v_submission public.survey_submissions;
begin
  select * into v_submission from public.survey_submissions where id=p_submission_id and resume_token_hash=digest(p_resume_token,'sha256');
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if v_submission.idempotency_key=p_idempotency_key and v_submission.submitted_at is not null then
    return jsonb_build_object('replayed',true,'submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at);
  end if;
  return jsonb_build_object('replayed',false);
end;
$$;

revoke all on function public.rpc_aoi_public_survey_replay(uuid,text,text) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_replay(uuid,text,text) to service_role;
