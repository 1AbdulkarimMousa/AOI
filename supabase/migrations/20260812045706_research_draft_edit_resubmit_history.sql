-- Assignment-scoped research draft edits, revision resubmission, and durable review history.

create table public.research_review_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  record_type text not null
    check (record_type in ('respondent', 'session', 'evidence', 'product_event', 'value_exchange', 'observation')),
  record_id uuid not null,
  action text not null check (action in ('approve', 'request_revision', 'archive')),
  from_status text not null,
  to_status text not null,
  notes text,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete restrict
);

create index research_review_history_record_idx
  on public.research_review_history (record_type, record_id, created_at desc);
create index research_review_history_scope_idx
  on public.research_review_history (organization_id, project_id, created_at desc);

alter table public.research_review_history enable row level security;
create policy research_review_history_member_read
  on public.research_review_history for select to authenticated
  using (
    public.is_org_admin(organization_id)
    or (
      public.is_org_member(organization_id)
      and (
        (record_type = 'respondent' and exists (
          select 1 from public.respondents record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
        or (record_type = 'session' and exists (
          select 1 from public.research_sessions record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
        or (record_type = 'evidence' and exists (
          select 1 from public.evidence_records record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
        or (record_type = 'product_event' and exists (
          select 1 from public.product_events record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
        or (record_type = 'value_exchange' and exists (
          select 1 from public.value_exchange_observations record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
        or (record_type = 'observation' and exists (
          select 1 from public.pmf_observations record
          where record.id = record_id
            and record.organization_id = research_review_history.organization_id
            and record.project_id = research_review_history.project_id
            and (record.assigned_to = (select auth.uid()) or record.workflow_status in ('approved', 'archived'))
        ))
      )
    )
  );

create or replace function private.reject_research_review_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'RESEARCH_REVIEW_HISTORY_APPEND_ONLY';
end;
$$;

create trigger reject_research_review_history_mutation
  before update or delete on public.research_review_history
  for each row execute function private.reject_research_review_history_mutation();

revoke all on public.research_review_history from public, anon, authenticated;
grant select on public.research_review_history to authenticated;
revoke all on function private.reject_research_review_history_mutation() from public, anon, authenticated;

create or replace function public.rpc_aoi_update_research_record(
  p_record_type text,
  p_record_id uuid,
  p_payload jsonb,
  p_expected_updated_at timestamptz,
  p_action text default 'save'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table text;
  v_organization_id uuid;
  v_project_id uuid;
  v_assigned_to uuid;
  v_workflow_status text;
  v_updated_at timestamptz;
  v_target_status text;
  v_record jsonb;
  v_segment_id uuid;
  v_respondent_id uuid;
  v_session_id uuid;
  v_definition_id uuid;
  v_value_type text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'RESEARCH_PAYLOAD_INVALID';
  end if;
  if p_action not in ('save', 'submit', 'resubmit') then
    raise exception 'RESEARCH_ACTION_INVALID';
  end if;
  if p_payload ?| array[
    'id', 'organizationId', 'projectId', 'assignedTo', 'createdBy', 'recordedBy',
    'createdAt', 'updatedAt', 'workflowStatus', 'submittedAt', 'reviewedBy',
    'reviewedAt', 'reviewNotes'
  ] then
    raise exception 'RESEARCH_SCOPE_IMMUTABLE';
  end if;

  v_table := case p_record_type
    when 'respondent' then 'respondents'
    when 'session' then 'research_sessions'
    when 'evidence' then 'evidence_records'
    when 'product_event' then 'product_events'
    when 'value_exchange' then 'value_exchange_observations'
    when 'observation' then 'pmf_observations'
  end;
  if v_table is null then raise exception 'RECORD_TYPE_INVALID'; end if;

  execute format(
    'select organization_id, project_id, assigned_to, workflow_status, updated_at from public.%I where id = $1 for update',
    v_table
  ) into v_organization_id, v_project_id, v_assigned_to, v_workflow_status, v_updated_at
  using p_record_id;
  if v_organization_id is null or v_assigned_to is distinct from (select auth.uid()) then
    raise exception 'RESEARCH_RECORD_NOT_ASSIGNED';
  end if;
  if not exists (
    select 1
    from public.projects project
    where project.id = v_project_id
      and project.organization_id = v_organization_id
      and project.status = 'active'
      and public.is_org_member(v_organization_id)
  ) then
    raise exception 'RESEARCH_SCOPE_ACCESS_REQUIRED';
  end if;
  if p_expected_updated_at is null or v_updated_at is distinct from p_expected_updated_at then
    raise exception 'RESEARCH_STALE_WRITE';
  end if;
  if v_workflow_status not in ('draft', 'revision_requested') then
    raise exception 'RESEARCH_RECORD_LOCKED';
  end if;
  if p_action = 'submit' and v_workflow_status <> 'draft' then
    raise exception 'RESEARCH_SUBMISSION_INVALID';
  end if;
  if p_action = 'resubmit' and v_workflow_status <> 'revision_requested' then
    raise exception 'RESEARCH_RESUBMISSION_INVALID';
  end if;
  v_target_status := case when p_action in ('submit', 'resubmit') then 'submitted' else v_workflow_status end;

  if p_record_type = 'respondent' then
    if p_payload ? 'consentStatus'
      and p_payload->>'consentStatus' is distinct from (
        select respondent.consent_status from public.respondents respondent where respondent.id = p_record_id
      ) then
      raise exception 'CONSENT_VERSION_REQUIRED';
    end if;
    if p_payload ? 'segmentCode' then
      select segment.id into v_segment_id
      from public.research_segments segment
      where segment.organization_id = v_organization_id
        and segment.project_id = v_project_id
        and segment.code = p_payload->>'segmentCode'
        and segment.active;
      if v_segment_id is null then raise exception 'SEGMENT_REQUIRED'; end if;
    end if;
    update public.respondents item
    set external_id = case when p_payload ? 'externalId' then trim(p_payload->>'externalId') else item.external_id end,
        segment_id = coalesce(v_segment_id, item.segment_id),
        respondent_type = case when p_payload ? 'respondentType' then p_payload->>'respondentType' else item.respondent_type end,
        specialty_status = case when p_payload ? 'specialtyStatus' then nullif(trim(p_payload->>'specialtyStatus'), '') else item.specialty_status end,
        age_child_age = case when p_payload ? 'ageChildAge' then nullif(trim(p_payload->>'ageChildAge'), '') else item.age_child_age end,
        recruitment_source = case when p_payload ? 'recruitmentSource' then nullif(trim(p_payload->>'recruitmentSource'), '') else item.recruitment_source end,
        stage = case when p_payload ? 'stage' then p_payload->>'stage' else item.stage end,
        status = case when p_payload ? 'status' then p_payload->>'status' else item.status end,
        start_date = case when p_payload ? 'startDate' then nullif(p_payload->>'startDate', '')::date else item.start_date end,
        end_date = case when p_payload ? 'endDate' then nullif(p_payload->>'endDate', '')::date else item.end_date end,
        notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
        retention_review_at = case when p_payload ? 'retentionReviewAt' then nullif(p_payload->>'retentionReviewAt', '')::date else item.retention_review_at end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;

    if p_payload ?| array['contactName', 'email', 'phone', 'contactReference', 'preferredChannel'] then
      insert into public.respondent_contacts (
        respondent_id, organization_id, project_id, contact_name, email, phone,
        contact_reference, preferred_channel, created_by, updated_at
      ) values (
        p_record_id, v_organization_id, v_project_id,
        nullif(trim(p_payload->>'contactName'), ''), nullif(trim(p_payload->>'email'), ''),
        nullif(trim(p_payload->>'phone'), ''), nullif(trim(p_payload->>'contactReference'), ''),
        nullif(trim(p_payload->>'preferredChannel'), ''), (select auth.uid()), clock_timestamp()
      ) on conflict (respondent_id) do update set
        contact_name = case when p_payload ? 'contactName' then excluded.contact_name else public.respondent_contacts.contact_name end,
        email = case when p_payload ? 'email' then excluded.email else public.respondent_contacts.email end,
        phone = case when p_payload ? 'phone' then excluded.phone else public.respondent_contacts.phone end,
        contact_reference = case when p_payload ? 'contactReference' then excluded.contact_reference else public.respondent_contacts.contact_reference end,
        preferred_channel = case when p_payload ? 'preferredChannel' then excluded.preferred_channel else public.respondent_contacts.preferred_channel end,
        updated_at = clock_timestamp();
    end if;

  elsif p_record_type = 'session' then
    update public.research_sessions item
    set pmf_layer = case when p_payload ? 'pmfLayer' then p_payload->>'pmfLayer' else item.pmf_layer end,
        method = case when p_payload ? 'method' then trim(p_payload->>'method') else item.method end,
        session_date = case when p_payload ? 'sessionDate' then nullif(p_payload->>'sessionDate', '')::date else item.session_date end,
        current_behavior = case when p_payload ? 'currentBehavior' then nullif(trim(p_payload->>'currentBehavior'), '') else item.current_behavior end,
        biggest_hassle = case when p_payload ? 'biggestHassle' then nullif(trim(p_payload->>'biggestHassle'), '') else item.biggest_hassle end,
        recent_incident = case when p_payload ? 'recentIncident' then nullif(trim(p_payload->>'recentIncident'), '') else item.recent_incident end,
        current_action = case when p_payload ? 'currentAction' then nullif(trim(p_payload->>'currentAction'), '') else item.current_action end,
        unmet_need = case when p_payload ? 'unmetNeed' then nullif(trim(p_payload->>'unmetNeed'), '') else item.unmet_need end,
        limitations = case when p_payload ? 'limitations' then nullif(trim(p_payload->>'limitations'), '') else item.limitations end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;

  elsif p_record_type = 'evidence' then
    v_respondent_id := case when p_payload ? 'respondentId' then nullif(p_payload->>'respondentId', '')::uuid else null end;
    v_session_id := case when p_payload ? 'sessionId' then nullif(p_payload->>'sessionId', '')::uuid else null end;
    if v_respondent_id is not null and not exists (
      select 1 from public.respondents respondent
      where respondent.id = v_respondent_id
        and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id
        and respondent.assigned_to = (select auth.uid())
    ) then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    if v_session_id is not null and not exists (
      select 1 from public.research_sessions session
      where session.id = v_session_id
        and session.organization_id = v_organization_id and session.project_id = v_project_id
        and session.assigned_to = (select auth.uid())
    ) then raise exception 'SESSION_NOT_ASSIGNED'; end if;
    select respondent.segment_id into v_segment_id
    from public.respondents respondent
    where respondent.id = v_respondent_id and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id;
    if v_segment_id is null and v_session_id is not null then
      select session.segment_id into v_segment_id from public.research_sessions session
      where session.id = v_session_id and session.organization_id = v_organization_id and session.project_id = v_project_id;
    end if;
    update public.evidence_records item
    set respondent_id = case when p_payload ? 'respondentId' then v_respondent_id else item.respondent_id end,
        session_id = case when p_payload ? 'sessionId' then v_session_id else item.session_id end,
        segment_id = coalesce(v_segment_id, item.segment_id),
        pmf_layer = case when p_payload ? 'pmfLayer' then nullif(p_payload->>'pmfLayer', '') else item.pmf_layer end,
        dimension = case when p_payload ? 'dimension' then nullif(trim(p_payload->>'dimension'), '') else item.dimension end,
        topic = case when p_payload ? 'topic' then nullif(trim(p_payload->>'topic'), '') else item.topic end,
        type = case when p_payload ? 'evidenceType' then trim(p_payload->>'evidenceType') else item.type end,
        evidence_type = case when p_payload ? 'evidenceType' then trim(p_payload->>'evidenceType') else item.evidence_type end,
        stance = case when p_payload ? 'stance' then p_payload->>'stance' else item.stance end,
        strength = case when p_payload ? 'strength' then (p_payload->>'strength')::integer else item.strength end,
        title = case when p_payload ? 'title' then trim(p_payload->>'title') else item.title end,
        evidence_text = case when p_payload ? 'evidenceText' then nullif(trim(p_payload->>'evidenceText'), '') else item.evidence_text end,
        source_link = case when p_payload ? 'sourceLink' then nullif(trim(p_payload->>'sourceLink'), '') else item.source_link end,
        decision_relevance = case when p_payload ? 'decisionRelevance' then nullif(trim(p_payload->>'decisionRelevance'), '') else item.decision_relevance end,
        consent_status = case when p_payload ? 'consentStatus' then p_payload->>'consentStatus' else item.consent_status end,
        follow_up_needed = case when p_payload ? 'followUpNeeded' then coalesce((p_payload->>'followUpNeeded')::boolean, false) else item.follow_up_needed end,
        limitations = case when p_payload ? 'limitations' then nullif(trim(p_payload->>'limitations'), '') else item.limitations end,
        notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;

  elsif p_record_type = 'product_event' then
    v_respondent_id := case when p_payload ? 'respondentId' then nullif(p_payload->>'respondentId', '')::uuid else null end;
    if v_respondent_id is not null and not exists (
      select 1 from public.respondents respondent
      where respondent.id = v_respondent_id
        and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id
        and respondent.assigned_to = (select auth.uid())
    ) then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    select respondent.segment_id into v_segment_id from public.respondents respondent
    where respondent.id = v_respondent_id and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id;
    update public.product_events item
    set respondent_id = case when p_payload ? 'respondentId' then v_respondent_id else item.respondent_id end,
        segment_id = coalesce(v_segment_id, item.segment_id),
        event_date = case when p_payload ? 'eventDate' then nullif(p_payload->>'eventDate', '')::date else item.event_date end,
        study_week = case when p_payload ? 'studyWeek' then (p_payload->>'studyWeek')::integer else item.study_week end,
        trigger_type = case when p_payload ? 'triggerType' then nullif(trim(p_payload->>'triggerType'), '') else item.trigger_type end,
        trigger_description = case when p_payload ? 'triggerDescription' then nullif(trim(p_payload->>'triggerDescription'), '') else item.trigger_description end,
        target_user = case when p_payload ? 'targetUser' then nullif(trim(p_payload->>'targetUser'), '') else item.target_user end,
        session_duration_minutes = case when p_payload ? 'sessionDurationMinutes' then nullif(p_payload->>'sessionDurationMinutes', '')::numeric else item.session_duration_minutes end,
        capture_success = case when p_payload ? 'captureSuccess' then nullif(p_payload->>'captureSuccess', '')::boolean else item.capture_success end,
        valid_image = case when p_payload ? 'validImage' then nullif(p_payload->>'validImage', '')::boolean else item.valid_image end,
        compare_used = case when p_payload ? 'compareUsed' then nullif(p_payload->>'compareUsed', '')::boolean else item.compare_used end,
        result_understood = case when p_payload ? 'resultUnderstood' then nullif(p_payload->>'resultUnderstood', '')::boolean else item.result_understood end,
        value_obtained = case when p_payload ? 'valueObtained' then nullif(p_payload->>'valueObtained', '')::boolean else item.value_obtained end,
        action_taken = case when p_payload ? 'actionTaken' then nullif(p_payload->>'actionTaken', '')::boolean else item.action_taken end,
        shared_with_doctor = case when p_payload ? 'sharedWithDoctor' then nullif(p_payload->>'sharedWithDoctor', '')::boolean else item.shared_with_doctor end,
        main_friction = case when p_payload ? 'mainFriction' then nullif(trim(p_payload->>'mainFriction'), '') else item.main_friction end,
        notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;

  elsif p_record_type = 'value_exchange' then
    v_respondent_id := case when p_payload ? 'respondentId' then nullif(p_payload->>'respondentId', '')::uuid else null end;
    if v_respondent_id is not null and not exists (
      select 1 from public.respondents respondent
      where respondent.id = v_respondent_id
        and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id
        and respondent.assigned_to = (select auth.uid())
    ) then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    select respondent.segment_id into v_segment_id from public.respondents respondent
    where respondent.id = v_respondent_id and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id;
    update public.value_exchange_observations item
    set respondent_id = case when p_payload ? 'respondentId' then v_respondent_id else item.respondent_id end,
        segment_id = coalesce(v_segment_id, item.segment_id),
        observed_at = case when p_payload ? 'observedAt' then nullif(p_payload->>'observedAt', '')::date else item.observed_at end,
        hardware_price = case when p_payload ? 'hardwarePrice' then nullif(p_payload->>'hardwarePrice', '')::numeric else item.hardware_price end,
        reasonable_price_min = case when p_payload ? 'reasonablePriceMin' then nullif(p_payload->>'reasonablePriceMin', '')::numeric else item.reasonable_price_min end,
        reasonable_price_max = case when p_payload ? 'reasonablePriceMax' then nullif(p_payload->>'reasonablePriceMax', '')::numeric else item.reasonable_price_max end,
        purchase_intent = case when p_payload ? 'purchaseIntent' then nullif(p_payload->>'purchaseIntent', '')::integer else item.purchase_intent end,
        preferred_offer = case when p_payload ? 'preferredOffer' then nullif(trim(p_payload->>'preferredOffer'), '') else item.preferred_offer end,
        subscription_plan = case when p_payload ? 'subscriptionPlan' then nullif(trim(p_payload->>'subscriptionPlan'), '') else item.subscription_plan end,
        commitment_type = case when p_payload ? 'commitmentType' then nullif(trim(p_payload->>'commitmentType'), '') else item.commitment_type end,
        commitment_amount = case when p_payload ? 'commitmentAmount' then nullif(p_payload->>'commitmentAmount', '')::numeric else item.commitment_amount end,
        main_objection = case when p_payload ? 'mainObjection' then nullif(trim(p_payload->>'mainObjection'), '') else item.main_objection end,
        post_trial_purchase_intent = case when p_payload ? 'postTrialPurchaseIntent' then nullif(p_payload->>'postTrialPurchaseIntent', '')::integer else item.post_trial_purchase_intent end,
        notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;

  elsif p_record_type = 'observation' then
    if p_payload ? 'definitionId' then
      v_definition_id := nullif(p_payload->>'definitionId', '')::uuid;
      select definition.value_type into v_value_type
      from public.pmf_metric_definitions definition
      where definition.id = v_definition_id
        and definition.organization_id = v_organization_id
        and definition.project_id = v_project_id
        and definition.active;
      if v_value_type is null then raise exception 'METRIC_AND_SEGMENT_REQUIRED'; end if;
    end if;
    if p_payload ? 'segmentCode' then
      select segment.id into v_segment_id
      from public.research_segments segment
      where segment.organization_id = v_organization_id
        and segment.project_id = v_project_id
        and segment.code = p_payload->>'segmentCode'
        and segment.active;
      if v_segment_id is null then raise exception 'METRIC_AND_SEGMENT_REQUIRED'; end if;
    end if;
    v_respondent_id := case when p_payload ? 'respondentId' then nullif(p_payload->>'respondentId', '')::uuid else null end;
    v_session_id := case when p_payload ? 'sessionId' then nullif(p_payload->>'sessionId', '')::uuid else null end;
    if v_respondent_id is not null and not exists (
      select 1 from public.respondents respondent
      where respondent.id = v_respondent_id
        and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id
        and respondent.assigned_to = (select auth.uid())
    ) then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    if v_session_id is not null and not exists (
      select 1 from public.research_sessions session
      where session.id = v_session_id
        and session.organization_id = v_organization_id and session.project_id = v_project_id
        and session.assigned_to = (select auth.uid())
    ) then raise exception 'SESSION_NOT_ASSIGNED'; end if;
    if v_respondent_id is not null then
      select respondent.segment_id into v_segment_id from public.respondents respondent
      where respondent.id = v_respondent_id and respondent.organization_id = v_organization_id and respondent.project_id = v_project_id;
    elsif v_session_id is not null then
      select session.segment_id into v_segment_id from public.research_sessions session
      where session.id = v_session_id and session.organization_id = v_organization_id and session.project_id = v_project_id;
    end if;
    update public.pmf_observations item
    set definition_id = case when p_payload ? 'definitionId' then v_definition_id else item.definition_id end,
        respondent_id = case when p_payload ? 'respondentId' then v_respondent_id else item.respondent_id end,
        session_id = case when p_payload ? 'sessionId' then v_session_id else item.session_id end,
        segment_id = coalesce(v_segment_id, item.segment_id),
        numeric_value = case when p_payload ? 'numericValue' then nullif(p_payload->>'numericValue', '')::numeric else item.numeric_value end,
        boolean_value = case when p_payload ? 'booleanValue' then nullif(p_payload->>'booleanValue', '')::boolean else item.boolean_value end,
        text_value = case when p_payload ? 'textValue' then nullif(trim(p_payload->>'textValue'), '') else item.text_value end,
        source_link = case when p_payload ? 'sourceLink' then nullif(trim(p_payload->>'sourceLink'), '') else item.source_link end,
        notes = case when p_payload ? 'notes' then nullif(trim(p_payload->>'notes'), '') else item.notes end,
        workflow_status = v_target_status,
        submitted_at = case when v_target_status = 'submitted' then coalesce(item.submitted_at, clock_timestamp()) else item.submitted_at end,
        updated_at = clock_timestamp()
    where item.id = p_record_id
    returning to_jsonb(item) into v_record;
  end if;

  if v_record is null then raise exception 'RESEARCH_RECORD_NOT_ASSIGNED'; end if;

  if p_action in ('submit', 'resubmit') then
    if p_record_type = 'respondent' and v_record->>'consent_status' <> 'granted' then
      raise exception 'CONSENT_REQUIRED';
    elsif p_record_type = 'session' then
      if length(trim(coalesce(v_record->>'method', ''))) = 0 then raise exception 'RESEARCH_METHOD_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'unmet_need', ''))) = 0 then raise exception 'UNMET_NEED_REQUIRED'; end if;
    elsif p_record_type = 'evidence' then
      if nullif(v_record->>'pmf_layer', '') is null then raise exception 'PMF_LAYER_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'title', ''))) = 0 then raise exception 'EVIDENCE_TITLE_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'evidence_text', ''))) = 0 then raise exception 'EVIDENCE_TEXT_REQUIRED'; end if;
      if nullif(v_record->>'source_link', '') is null and nullif(v_record->>'session_id', '') is null then raise exception 'SOURCE_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'limitations', ''))) = 0 then raise exception 'LIMITATIONS_REQUIRED'; end if;
    elsif p_record_type = 'product_event' and nullif(v_record->>'respondent_id', '') is null then
      raise exception 'RESPONDENT_REQUIRED';
    elsif p_record_type = 'value_exchange' then
      if nullif(v_record->>'respondent_id', '') is null then raise exception 'RESPONDENT_REQUIRED'; end if;
      if nullif(v_record->>'hardware_price', '') is null then raise exception 'HARDWARE_PRICE_REQUIRED'; end if;
    elsif p_record_type = 'observation'
      and nullif(v_record->>'respondent_id', '') is null
      and nullif(v_record->>'session_id', '') is null
      and nullif(v_record->>'source_link', '') is null then
      raise exception 'OBSERVATION_PROVENANCE_REQUIRED';
    end if;
  end if;

  return jsonb_build_object(
    'id', p_record_id,
    'recordType', p_record_type,
    'workflowStatus', v_target_status,
    'updatedAt', v_record->>'updated_at'
  );
end;
$$;

create or replace function public.rpc_aoi_review_research_record(
  p_record_type text,
  p_record_id uuid,
  p_action text,
  p_notes text default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table text;
  v_organization_id uuid;
  v_project_id uuid;
  v_from_status text;
  v_to_status text;
  v_notes text := nullif(trim(p_notes), '');
  v_updated_at timestamptz;
  v_current_updated_at timestamptz;
begin
  v_table := case p_record_type
    when 'respondent' then 'respondents'
    when 'session' then 'research_sessions'
    when 'evidence' then 'evidence_records'
    when 'product_event' then 'product_events'
    when 'value_exchange' then 'value_exchange_observations'
    when 'observation' then 'pmf_observations'
  end;
  if v_table is null then raise exception 'RECORD_TYPE_INVALID'; end if;
  if p_action not in ('approve', 'request_revision', 'archive') then
    raise exception 'REVIEW_ACTION_INVALID';
  end if;
  if p_action = 'request_revision' and v_notes is null then
    raise exception 'REVIEW_REVISION_NOTE_REQUIRED';
  end if;

  execute format(
    'select organization_id, project_id, workflow_status, updated_at from public.%I where id = $1 for update',
    v_table
  ) into v_organization_id, v_project_id, v_from_status, v_current_updated_at
  using p_record_id;
  if v_organization_id is null then raise exception 'RECORD_NOT_FOUND'; end if;
  if not public.is_org_admin(v_organization_id) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_expected_updated_at is null or v_current_updated_at is distinct from p_expected_updated_at then
    raise exception 'RESEARCH_STALE_WRITE';
  end if;

  v_to_status := case p_action
    when 'approve' then 'approved'
    when 'request_revision' then 'revision_requested'
    when 'archive' then 'archived'
  end;
  if (p_action in ('approve', 'request_revision') and v_from_status <> 'submitted')
    or (p_action = 'archive' and v_from_status <> 'approved') then
    raise exception 'REVIEW_TRANSITION_INVALID';
  end if;

  execute format(
    'update public.%I set workflow_status = $1, reviewed_by = $2, reviewed_at = clock_timestamp(), review_notes = $3, updated_at = clock_timestamp() where id = $4 returning updated_at',
    v_table
  ) into v_updated_at
  using v_to_status, (select auth.uid()), v_notes, p_record_id;

  insert into public.research_review_history (
    organization_id, project_id, record_type, record_id, action,
    from_status, to_status, notes, reviewer_id
  ) values (
    v_organization_id, v_project_id, p_record_type, p_record_id, p_action,
    v_from_status, v_to_status, v_notes, (select auth.uid())
  );

  return jsonb_build_object(
    'id', p_record_id,
    'recordType', p_record_type,
    'workflowStatus', v_to_status,
    'updatedAt', v_updated_at
  );
end;
$$;

revoke all on function public.rpc_aoi_update_research_record(text, uuid, jsonb, timestamptz, text)
  from public, anon;
grant execute on function public.rpc_aoi_update_research_record(text, uuid, jsonb, timestamptz, text)
  to authenticated;
revoke all on function public.rpc_aoi_review_research_record(text, uuid, text, text, timestamptz)
  from public, anon;
grant execute on function public.rpc_aoi_review_research_record(text, uuid, text, text, timestamptz)
  to authenticated;

create or replace function private.validate_aoi_research_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record jsonb := to_jsonb(new);
begin
  if (select auth.uid()) is null then return new; end if;
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    join public.organizations organization on organization.id = membership.organization_id
    join public.projects project on project.id = (v_record->>'project_id')::uuid
      and project.organization_id = membership.organization_id
    where membership.user_id = auth.uid()
      and membership.organization_id = (v_record->>'organization_id')::uuid
      and membership.status = 'active'
      and profile.status = 'active' and not profile.must_change_password
      and organization.status = 'active' and project.status = 'active'
  ) then raise exception 'RESEARCH_SCOPE_ACCESS_REQUIRED'; end if;

  if v_record->>'workflow_status' = 'submitted' then
    if tg_table_name = 'respondents' and v_record->>'consent_status' <> 'granted' then
      raise exception 'CONSENT_REQUIRED';
    elsif tg_table_name = 'research_sessions' then
      if length(trim(coalesce(v_record->>'method', ''))) = 0 then raise exception 'RESEARCH_METHOD_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'unmet_need', ''))) = 0 then raise exception 'UNMET_NEED_REQUIRED'; end if;
    elsif tg_table_name = 'evidence_records' then
      if nullif(v_record->>'pmf_layer', '') is null then raise exception 'PMF_LAYER_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'title', ''))) = 0 then raise exception 'EVIDENCE_TITLE_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'evidence_text', ''))) = 0 then raise exception 'EVIDENCE_TEXT_REQUIRED'; end if;
      if nullif(v_record->>'source_link', '') is null and nullif(v_record->>'session_id', '') is null then raise exception 'SOURCE_REQUIRED'; end if;
      if length(trim(coalesce(v_record->>'limitations', ''))) = 0 then raise exception 'LIMITATIONS_REQUIRED'; end if;
    elsif tg_table_name = 'product_events' and nullif(v_record->>'respondent_id', '') is null then
      raise exception 'RESPONDENT_REQUIRED';
    elsif tg_table_name = 'value_exchange_observations' then
      if nullif(v_record->>'respondent_id', '') is null then raise exception 'RESPONDENT_REQUIRED'; end if;
      if nullif(v_record->>'hardware_price', '') is null then raise exception 'HARDWARE_PRICE_REQUIRED'; end if;
    elsif tg_table_name = 'pmf_observations'
      and nullif(v_record->>'respondent_id', '') is null
      and nullif(v_record->>'session_id', '') is null
      and nullif(v_record->>'source_link', '') is null then
      raise exception 'OBSERVATION_PROVENANCE_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

do $triggers$
declare v_table text;
begin
  foreach v_table in array array['respondents','research_sessions','evidence_records','product_events','value_exchange_observations','pmf_observations'] loop
    execute format('drop trigger if exists validate_aoi_research_insert on public.%I', v_table);
    execute format('create trigger validate_aoi_research_insert before insert on public.%I for each row execute function private.validate_aoi_research_insert()', v_table);
  end loop;
end;
$triggers$;
revoke all on function private.validate_aoi_research_insert() from public, anon, authenticated;

-- Keep authenticated research writes behind the validated RPCs. The save RPC
-- was originally an invoker only because direct table grants were still open.
alter function public.rpc_aoi_save_research_record(text, jsonb) security definer;
revoke insert, update on public.respondents, public.research_sessions,
  public.evidence_records, public.product_events,
  public.value_exchange_observations, public.pmf_observations from authenticated;
