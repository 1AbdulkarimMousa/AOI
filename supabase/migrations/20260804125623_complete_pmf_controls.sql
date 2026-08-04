-- Finish consent versioning, observation provenance, private candidate access, and approved-only Gates.
drop policy if exists candidates_assigned_read on public.candidates;
create policy candidates_assigned_read on public.candidates for select to authenticated using (
  public.is_org_admin(organization_id)
  or (assigned_to = (select auth.uid()) and public.is_org_member(organization_id))
);

create or replace function public.validate_aoi_observation_value()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_value_type text;
begin
  select definition.value_type into v_value_type
  from public.pmf_metric_definitions definition
  where definition.id = new.definition_id
    and definition.organization_id = new.organization_id
    and definition.project_id = new.project_id;
  if v_value_type is null
    or (v_value_type = 'numeric' and new.numeric_value is null)
    or (v_value_type = 'boolean' and new.boolean_value is null)
    or (v_value_type = 'text' and nullif(new.text_value, '') is null) then
    raise exception 'OBSERVATION_VALUE_TYPE_MISMATCH';
  end if;
  if new.workflow_status in ('submitted', 'approved', 'archived')
    and new.respondent_id is null and new.session_id is null and nullif(new.source_link, '') is null then
    raise exception 'OBSERVATION_PROVENANCE_REQUIRED';
  end if;
  return new;
end; $$;
revoke all on function public.validate_aoi_observation_value() from public, anon, authenticated;

create or replace function private.assign_aoi_consent_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.respondents respondent where respondent.id = new.respondent_id for update;
  select coalesce(max(consent.version), 0) + 1 into new.version
  from public.consent_records consent where consent.respondent_id = new.respondent_id;
  return new;
end; $$;
revoke all on function private.assign_aoi_consent_version() from public, anon, authenticated;
drop trigger if exists assign_aoi_consent_version on public.consent_records;
create trigger assign_aoi_consent_version before insert on public.consent_records
  for each row execute function private.assign_aoi_consent_version();

create or replace function public.rpc_aoi_append_consent_version(p_respondent_id uuid, p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_respondent public.respondents%rowtype;
  v_status text;
  v_version integer;
  v_id uuid;
begin
  select respondent.* into v_respondent from public.respondents respondent
  where respondent.id = p_respondent_id
    and (public.is_org_admin(respondent.organization_id) or respondent.assigned_to = auth.uid());
  if v_respondent.id is null then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
  v_status := nullif(p_payload->>'status', '');
  if v_status not in ('pending', 'granted', 'declined', 'withdrawn', 'expired') then
    raise exception 'CONSENT_STATUS_INVALID';
  end if;
  select coalesce(max(consent.version), 0) + 1 into v_version
  from public.consent_records consent where consent.respondent_id = p_respondent_id;
  insert into public.consent_records (
    organization_id, project_id, respondent_id, version, status,
    interview_allowed, recording_allowed, images_allowed, quotation_allowed, recontact_allowed,
    granted_at, withdrawn_at, withdrawal_reason, recorded_by
  ) values (
    v_respondent.organization_id, v_respondent.project_id, v_respondent.id, v_version, v_status,
    coalesce((p_payload->>'interviewAllowed')::boolean, false),
    coalesce((p_payload->>'recordingAllowed')::boolean, false),
    coalesce((p_payload->>'imagesAllowed')::boolean, false),
    coalesce((p_payload->>'quotationAllowed')::boolean, false),
    coalesce((p_payload->>'recontactAllowed')::boolean, false),
    case when v_status = 'granted' then now() end,
    case when v_status = 'withdrawn' then now() end,
    nullif(p_payload->>'withdrawalReason', ''), auth.uid()
  ) returning id, version into v_id, v_version;
  return jsonb_build_object('id', v_id, 'respondentId', p_respondent_id, 'version', v_version, 'status', v_status);
end; $$;

create or replace function private.create_aoi_gate_snapshot(p_pmf_layer text, p_decision text, p_rationale text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_snapshot jsonb; v_id uuid;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active' and membership.role = 'admin'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if p_pmf_layer not in ('H1','H2','H3','H4','H5')
    or p_decision not in ('go','revise','stop','insufficient')
    or length(trim(coalesce(p_rationale, ''))) < 10 then
    raise exception 'GATE_INPUT_INVALID';
  end if;

  v_snapshot := jsonb_build_object(
    'generatedAt', now(),
    'pmfLayer', p_pmf_layer,
    'hypothesis', (select jsonb_build_object(
      'id', hypothesis.id, 'code', hypothesis.code, 'statement', hypothesis.statement,
      'successCriteria', hypothesis.success_criteria, 'decisionStatus', hypothesis.decision_status
    ) from public.hypotheses hypothesis
      where hypothesis.project_id = v_project_id and hypothesis.pmf_layer = p_pmf_layer limit 1),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object(
      'id', evidence.id, 'respondentId', evidence.respondent_id, 'sessionId', evidence.session_id,
      'segmentId', evidence.segment_id, 'dimension', evidence.dimension, 'title', evidence.title,
      'evidenceText', evidence.evidence_text, 'stance', evidence.stance, 'strength', evidence.strength,
      'sourceLink', evidence.source_link, 'limitations', evidence.limitations
    ) order by evidence.created_at)
      from public.evidence_records evidence where evidence.project_id = v_project_id
        and evidence.pmf_layer = p_pmf_layer and evidence.workflow_status = 'approved'), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object(
      'id', observation.id, 'definitionId', observation.definition_id, 'respondentId', observation.respondent_id,
      'sessionId', observation.session_id, 'segmentId', observation.segment_id,
      'numericValue', observation.numeric_value, 'booleanValue', observation.boolean_value,
      'textValue', observation.text_value, 'sourceLink', observation.source_link
    ) order by observation.created_at)
      from public.pmf_observations observation
      join public.pmf_metric_definitions definition on definition.id = observation.definition_id
      where observation.project_id = v_project_id and definition.pmf_layer = p_pmf_layer
        and observation.workflow_status = 'approved'), '[]'::jsonb)
  );
  insert into public.gate_snapshots (organization_id, project_id, pmf_layer, decision, rationale, snapshot, created_by)
  values (v_org_id, v_project_id, p_pmf_layer, p_decision, trim(p_rationale), v_snapshot, auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'pmfLayer', p_pmf_layer, 'decision', p_decision);
end; $$;

revoke insert on public.gate_snapshots from authenticated;
grant usage on schema private to authenticated;
revoke all on function private.create_aoi_gate_snapshot(text,text,text) from public, anon, authenticated;
grant execute on function private.create_aoi_gate_snapshot(text,text,text) to authenticated;

create or replace function public.rpc_aoi_create_gate_snapshot(p_pmf_layer text, p_decision text, p_rationale text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.create_aoi_gate_snapshot(p_pmf_layer, p_decision, p_rationale);
$$;

revoke all on function public.rpc_aoi_append_consent_version(uuid,jsonb) from public, anon;
revoke all on function public.rpc_aoi_create_gate_snapshot(text,text,text) from public, anon;
grant execute on function public.rpc_aoi_append_consent_version(uuid,jsonb) to authenticated;
grant execute on function public.rpc_aoi_create_gate_snapshot(text,text,text) to authenticated;
