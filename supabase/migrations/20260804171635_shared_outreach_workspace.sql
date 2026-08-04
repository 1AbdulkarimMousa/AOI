-- Shared Ambiloop Outreach workspace and August 2026 operational seed.
-- Candidate collaboration is organization-wide; campaign controls remain administrator-only.

alter table public.candidates
  add column if not exists source_label text,
  add column if not exists content_fit text,
  add column if not exists follow_up_1 date,
  add column if not exists follow_up_2 date,
  add column if not exists response_date date,
  add column if not exists source_updated_on date;

alter table public.candidates drop constraint if exists candidates_created_by_fkey;
alter table public.candidates add constraint candidates_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_candidate_id_fkey;
alter table public.evidence_records add constraint evidence_records_candidate_id_fkey
  foreign key (candidate_id) references public.candidates(id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_candidate_scope_fk;
alter table public.evidence_records add constraint evidence_records_candidate_scope_fk
  foreign key (organization_id, project_id, candidate_id)
  references public.candidates(organization_id, project_id, id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_recorded_by_fkey;
alter table public.evidence_records add constraint evidence_records_recorded_by_fkey
  foreign key (recorded_by) references public.profiles(id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_respondent_id_fkey;
alter table public.evidence_records add constraint evidence_records_respondent_id_fkey
  foreign key (respondent_id) references public.respondents(id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_respondent_scope_fk;
alter table public.evidence_records add constraint evidence_records_respondent_scope_fk
  foreign key (organization_id, project_id, respondent_id)
  references public.respondents(organization_id, project_id, id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_session_id_fkey;
alter table public.evidence_records add constraint evidence_records_session_id_fkey
  foreign key (session_id) references public.research_sessions(id) on delete restrict;
alter table public.evidence_records drop constraint if exists evidence_records_session_scope_fk;
alter table public.evidence_records add constraint evidence_records_session_scope_fk
  foreign key (organization_id, project_id, session_id)
  references public.research_sessions(organization_id, project_id, id) on delete restrict;

create table public.outreach_campaigns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  name text not null,
  preliminary_interest_deadline date,
  preliminary_interest_target integer not null default 0 check (preliminary_interest_target >= 0),
  confirmation_deadline date,
  confirmed_target_low integer not null default 0 check (confirmed_target_low >= 0),
  confirmed_target_high integer not null default 0 check (confirmed_target_high >= confirmed_target_low),
  planning_target integer not null default 0 check (planning_target >= 0),
  conversion_rate numeric(5,4) not null default 0 check (conversion_rate between 0 and 1),
  recommended_active_pool integer not null default 0 check (recommended_active_pool >= 0),
  safety_notice text,
  first_touch_guidance text,
  scoring_rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table public.outreach_plan_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  campaign_id uuid not null,
  plan_date date not null,
  focus text not null,
  planned_first_touches integer not null default 0 check (planned_first_touches >= 0),
  actual_first_touches integer not null default 0 check (actual_first_touches >= 0),
  planned_follow_ups integer not null default 0 check (planned_follow_ups >= 0),
  actual_follow_ups integer not null default 0 check (actual_follow_ups >= 0),
  expected_outcome text,
  owner_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, plan_date),
  foreign key (organization_id, project_id, campaign_id)
    references public.outreach_campaigns (organization_id, project_id, id) on delete cascade
);
create index outreach_plan_project_date_idx
  on public.outreach_plan_items (organization_id, project_id, plan_date);

alter table public.outreach_campaigns enable row level security;
alter table public.outreach_plan_items enable row level security;

drop policy if exists candidates_member_read on public.candidates;
drop policy if exists candidates_member_write on public.candidates;
drop policy if exists candidates_member_update on public.candidates;
drop policy if exists candidates_assigned_read on public.candidates;
drop policy if exists candidates_assigned_insert on public.candidates;
drop policy if exists candidates_assigned_update on public.candidates;
create policy candidates_workspace_read on public.candidates for select to authenticated
  using (public.is_org_member(organization_id));
create policy candidates_workspace_insert on public.candidates for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and created_by = (select auth.uid())
    and (public.is_org_admin(organization_id) or (
      assigned_to = (select auth.uid()) and workflow_status = 'draft'
    ))
    and exists (
      select 1 from public.organization_memberships membership
      where membership.organization_id = candidates.organization_id
        and membership.user_id = candidates.assigned_to
        and membership.status = 'active'
    )
  );
create policy candidates_workspace_update on public.candidates for update to authenticated
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

create or replace function public.enforce_aoi_candidate_assignee_membership()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.assigned_to is null then
    new.owner_id := null;
    return new;
  end if;
  if not exists (
    select 1 from public.organization_memberships membership
    where membership.organization_id = new.organization_id
      and membership.user_id = new.assigned_to
      and membership.status = 'active'
  ) then
    raise exception 'ASSIGNEE_MEMBERSHIP_REQUIRED';
  end if;
  new.owner_id := new.assigned_to;
  return new;
end; $$;
revoke all on function public.enforce_aoi_candidate_assignee_membership() from public, anon, authenticated;
drop trigger if exists enforce_aoi_assignee_membership on public.candidates;
create trigger enforce_aoi_assignee_membership
  before insert or update of assigned_to, owner_id, organization_id on public.candidates
  for each row execute function public.enforce_aoi_candidate_assignee_membership();

create or replace function public.enforce_aoi_candidate_workflow()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.organization_id is distinct from new.organization_id
    or old.project_id is distinct from new.project_id
    or old.external_id is distinct from new.external_id
    or old.created_by is distinct from new.created_by
    or old.created_at is distinct from new.created_at then
    raise exception 'CANDIDATE_SCOPE_IMMUTABLE';
  end if;
  if public.is_org_admin(old.organization_id) then return new; end if;
  if old.assigned_to is distinct from new.assigned_to
    or old.owner_id is distinct from new.owner_id then
    raise exception 'CANDIDATE_OWNER_IMMUTABLE';
  end if;
  if old.workflow_status is distinct from new.workflow_status then
    raise exception 'CANDIDATE_WORKFLOW_IMMUTABLE';
  end if;
  return new;
end; $$;
revoke all on function public.enforce_aoi_candidate_workflow() from public, anon, authenticated;

drop policy if exists outreach_member_read on public.outreach_events;
drop policy if exists outreach_member_write on public.outreach_events;
drop policy if exists outreach_assigned_read on public.outreach_events;
drop policy if exists outreach_assigned_insert on public.outreach_events;
create policy outreach_workspace_read on public.outreach_events for select to authenticated
  using (public.is_org_member(organization_id));
create policy outreach_workspace_insert on public.outreach_events for insert to authenticated
  with check (
    actor_id = (select auth.uid()) and public.is_org_member(organization_id)
    and exists (
      select 1 from public.candidates candidate
      where candidate.id = outreach_events.candidate_id
        and candidate.organization_id = outreach_events.organization_id
        and candidate.project_id = outreach_events.project_id
    )
  );

drop policy if exists evidence_member_read on public.evidence_records;
drop policy if exists evidence_member_write on public.evidence_records;
drop policy if exists evidence_assigned_read on public.evidence_records;
drop policy if exists evidence_assigned_insert on public.evidence_records;
drop policy if exists evidence_assigned_update on public.evidence_records;
create policy evidence_workspace_read on public.evidence_records for select to authenticated
  using (public.is_org_member(organization_id));
create policy evidence_workspace_insert on public.evidence_records for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and recorded_by = (select auth.uid())
    and assigned_to = (select auth.uid())
    and (public.is_org_admin(organization_id) or workflow_status = 'draft')
    and exists (
      select 1 from public.candidates candidate
      where candidate.id = evidence_records.candidate_id
        and candidate.organization_id = evidence_records.organization_id
        and candidate.project_id = evidence_records.project_id
    )
  );
create policy evidence_workspace_update on public.evidence_records for update to authenticated
  using (
    public.is_org_admin(organization_id)
    or (public.is_org_member(organization_id) and assigned_to = (select auth.uid()) and workflow_status not in ('submitted', 'approved', 'archived'))
  )
  with check (
    public.is_org_admin(organization_id)
    or (public.is_org_member(organization_id) and assigned_to = (select auth.uid()) and workflow_status in ('draft', 'submitted', 'revision_requested'))
  );

create or replace function public.enforce_aoi_evidence_provenance()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.organization_id is distinct from new.organization_id
    or old.project_id is distinct from new.project_id
    or old.candidate_id is distinct from new.candidate_id
    or old.respondent_id is distinct from new.respondent_id
    or old.session_id is distinct from new.session_id
    or old.recorded_by is distinct from new.recorded_by
    or old.recorded_at is distinct from new.recorded_at
    or old.created_at is distinct from new.created_at then
    raise exception 'EVIDENCE_PROVENANCE_IMMUTABLE';
  end if;
  return new;
end; $$;
revoke all on function public.enforce_aoi_evidence_provenance() from public, anon, authenticated;
drop trigger if exists enforce_aoi_evidence_provenance on public.evidence_records;
create trigger enforce_aoi_evidence_provenance
  before update on public.evidence_records
  for each row execute function public.enforce_aoi_evidence_provenance();

create policy outreach_campaign_member_read on public.outreach_campaigns for select to authenticated
  using (public.is_org_member(organization_id));
create policy outreach_campaign_admin_write on public.outreach_campaigns for all to authenticated
  using (public.is_org_admin(organization_id))
  with check (public.is_org_admin(organization_id));
create policy outreach_plan_member_read on public.outreach_plan_items for select to authenticated
  using (public.is_org_member(organization_id));
create policy outreach_plan_admin_write on public.outreach_plan_items for all to authenticated
  using (public.is_org_admin(organization_id))
  with check (public.is_org_admin(organization_id));

revoke all on public.outreach_campaigns, public.outreach_plan_items from anon, authenticated;
grant select, insert, update on public.outreach_campaigns, public.outreach_plan_items to authenticated;

drop function if exists public.rpc_aoi_operations_snapshot();
create function public.rpc_aoi_operations_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'campaign', coalesce((select jsonb_build_object(
      'id', campaign.id, 'name', campaign.name,
      'preliminaryInterestDeadline', campaign.preliminary_interest_deadline,
      'preliminaryInterestTarget', campaign.preliminary_interest_target,
      'deadline', campaign.confirmation_deadline,
      'targetLow', campaign.confirmed_target_low,
      'targetHigh', campaign.confirmed_target_high,
      'planningTarget', campaign.planning_target,
      'conversionRate', campaign.conversion_rate,
      'recommendedActivePool', campaign.recommended_active_pool,
      'safetyNotice', campaign.safety_notice,
      'firstTouchGuidance', campaign.first_touch_guidance
    ) from public.outreach_campaigns campaign where campaign.project_id = v_project_id), '{}'::jsonb),
    'scoringRules', coalesce((select campaign.scoring_rules from public.outreach_campaigns campaign where campaign.project_id = v_project_id), '{}'::jsonb),
    'outreachSummary', jsonb_build_object(
      'totalCandidates', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id),
      'contactReady', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.contact_readiness <> 'Research needed'),
      'contacted', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status not in ('Not Contacted', 'Ready to Send', 'Unreachable')),
      'responses', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and (candidate.response_date is not null or candidate.outreach_status in ('Replied', 'Interested', 'Confirmed', 'Declined'))),
      'interested', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status in ('Interested', 'Confirmed')),
      'confirmed', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.outreach_status = 'Confirmed'),
      'pmfCandidates', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.pmf_candidate),
      'researchNeeded', (select count(*) from public.candidates candidate where candidate.project_id = v_project_id and candidate.contact_readiness = 'Research needed')
    ),
    'categories', coalesce((select jsonb_agg(jsonb_build_object(
      'name', grouped.category, 'candidates', grouped.candidates,
      'contactReady', grouped.contact_ready, 'confirmed', grouped.confirmed
    ) order by grouped.category) from (
      select candidate.category,
        count(*) as candidates,
        count(*) filter (where candidate.contact_readiness <> 'Research needed') as contact_ready,
        count(*) filter (where candidate.outreach_status = 'Confirmed') as confirmed
      from public.candidates candidate where candidate.project_id = v_project_id
      group by candidate.category
    ) grouped), '[]'::jsonb),
    'executionPlan', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.id, 'date', item.plan_date, 'focus', item.focus,
      'plannedFirstTouches', item.planned_first_touches, 'actualFirstTouches', item.actual_first_touches,
      'plannedFollowUps', item.planned_follow_ups, 'actualFollowUps', item.actual_follow_ups,
      'expectedOutcome', item.expected_outcome, 'owner', item.owner_label
    ) order by item.plan_date) from public.outreach_plan_items item where item.project_id = v_project_id), '[]'::jsonb),
    'emailTemplates', case when v_role = 'admin' then coalesce((select jsonb_agg(jsonb_build_object(
      'id', template.id, 'name', template.name, 'audience', template.audience,
      'subject', template.subject, 'body', template.body, 'status', template.status
    ) order by template.name) from public.email_templates template where template.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'candidates', coalesce((select jsonb_agg(jsonb_build_object(
      'id', candidate.id, 'externalId', candidate.external_id, 'source', candidate.source_label,
      'name', candidate.name, 'category', candidate.category, 'platforms', candidate.platforms,
      'reach', candidate.reach, 'tier', candidate.tier, 'creatorType', candidate.creator_type,
      'contentFit', candidate.content_fit, 'fitLevel', candidate.fit_level, 'contactReadiness', candidate.contact_readiness,
      'contactChannel', candidate.contact_channel, 'contactDetail', candidate.contact_detail,
      'sourceUrl', candidate.source_url, 'pmfCandidate', candidate.pmf_candidate,
      'pmfRationale', candidate.pmf_rationale, 'priorityScore', candidate.priority_score,
      'priorityBand', candidate.priority_band, 'ownerId', candidate.assigned_to,
      'ownerName', profile.display_name, 'outreachStatus', candidate.outreach_status,
      'interestLevel', candidate.interest_level, 'preferredCollaboration', candidate.preferred_collaboration,
      'deckIntroduced', candidate.deck_introduced, 'pmfAsked', candidate.pmf_asked,
      'firstOutreach', candidate.first_outreach, 'followUp1', candidate.follow_up_1,
      'followUp2', candidate.follow_up_2, 'responseDate', candidate.response_date,
      'nextStep', candidate.next_step, 'nextStepDue', candidate.next_step_due,
      'notes', candidate.notes, 'workflowStatus', candidate.workflow_status,
      'sourceUpdatedOn', candidate.source_updated_on, 'lastUpdated', candidate.updated_at::date
    ) order by candidate.priority_score desc, candidate.next_step_due nulls last)
      from public.candidates candidate left join public.profiles profile on profile.id = candidate.assigned_to
      where candidate.project_id = v_project_id), '[]'::jsonb),
    'outreachEvents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', event.id, 'candidateId', event.candidate_id, 'channel', event.channel,
      'kind', event.kind, 'status', event.status, 'occurredAt', event.occurred_at,
      'actorName', coalesce(profile.display_name, 'AOI'), 'summary', event.summary
    ) order by event.occurred_at desc) from public.outreach_events event
      left join public.profiles profile on profile.id = event.actor_id where event.project_id = v_project_id), '[]'::jsonb),
    'evidenceRecords', coalesce((select jsonb_agg(jsonb_build_object(
      'id', evidence.id, 'candidateId', evidence.candidate_id, 'type', evidence.type,
      'stance', evidence.stance, 'strength', evidence.strength, 'title', evidence.title,
      'notes', evidence.notes, 'consentStatus', evidence.consent_status,
      'recordedBy', coalesce(profile.display_name, 'AOI'), 'recordedAt', evidence.recorded_at,
      'workflowStatus', evidence.workflow_status
    ) order by evidence.recorded_at desc) from public.evidence_records evidence
      left join public.profiles profile on profile.id = evidence.recorded_by where evidence.project_id = v_project_id), '[]'::jsonb)
  );
end; $$;

drop function if exists public.rpc_aoi_upsert_candidate(jsonb);
create function public.rpc_aoi_upsert_candidate(p_candidate jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_org_id uuid; v_project_id uuid; v_role text; v_owner_id uuid;
  v_candidate_id uuid; v_owner_requested boolean := false; v_result public.candidates%rowtype;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(p_candidate->>'name', ''))) < 2 then raise exception 'CANDIDATE_NAME_REQUIRED'; end if;
  if coalesce(p_candidate->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_candidate_id := (p_candidate->>'id')::uuid;
  elsif nullif(p_candidate->>'externalId', '') is not null then
    select candidate.id into v_candidate_id from public.candidates candidate
    where candidate.project_id = v_project_id and candidate.external_id = p_candidate->>'externalId';
  end if;
  if v_candidate_id is not null then
    select candidate.assigned_to into v_owner_id from public.candidates candidate
    where candidate.id = v_candidate_id and candidate.organization_id = v_org_id and candidate.project_id = v_project_id;
    if not found then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  else v_owner_id := auth.uid(); end if;
  if v_role = 'admin' and nullif(p_candidate->>'ownerId', '') is not null then
    v_owner_requested := true;
    select membership.user_id into v_owner_id from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.user_id = (p_candidate->>'ownerId')::uuid and membership.status = 'active';
  elsif v_role = 'admin' and nullif(p_candidate->>'ownerName', '') is not null then
    v_owner_requested := true;
    select membership.user_id into v_owner_id
    from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.status = 'active'
      and lower(profile.display_name) = lower(trim(p_candidate->>'ownerName'))
    order by membership.joined_at limit 1;
  end if;
  if v_owner_requested and v_owner_id is null then raise exception 'CANDIDATE_OWNER_INVALID'; end if;

  if v_candidate_id is not null then
    update public.candidates candidate set
      source_label = case when p_candidate ? 'source' then p_candidate->>'source' else candidate.source_label end,
      name = trim(p_candidate->>'name'),
      category = case when nullif(p_candidate->>'category','') is not null then p_candidate->>'category' else candidate.category end,
      platforms = case when p_candidate ? 'platforms' then p_candidate->>'platforms' else candidate.platforms end,
      reach = case when p_candidate ? 'reach' then p_candidate->>'reach' else candidate.reach end,
      tier = case when p_candidate ? 'tier' then p_candidate->>'tier' else candidate.tier end,
      creator_type = case when p_candidate ? 'creatorType' then p_candidate->>'creatorType' else candidate.creator_type end,
      content_fit = case when p_candidate ? 'contentFit' then p_candidate->>'contentFit' else candidate.content_fit end,
      fit_level = case when p_candidate ? 'fitLevel' then p_candidate->>'fitLevel' else candidate.fit_level end,
      contact_readiness = case when nullif(p_candidate->>'contactReadiness','') is not null then p_candidate->>'contactReadiness' else candidate.contact_readiness end,
      contact_channel = case when p_candidate ? 'contactChannel' then p_candidate->>'contactChannel' else candidate.contact_channel end,
      contact_detail = case when p_candidate ? 'contactDetail' then p_candidate->>'contactDetail' else candidate.contact_detail end,
      source_url = case when p_candidate ? 'sourceUrl' then p_candidate->>'sourceUrl' else candidate.source_url end,
      pmf_candidate = case when p_candidate ? 'pmfCandidate' then (p_candidate->>'pmfCandidate')::boolean else candidate.pmf_candidate end,
      pmf_rationale = case when p_candidate ? 'pmfRationale' then p_candidate->>'pmfRationale' else candidate.pmf_rationale end,
      priority_score = case when nullif(p_candidate->>'priorityScore','') is not null then greatest(0, least(100, (p_candidate->>'priorityScore')::integer)) else candidate.priority_score end,
      priority_band = case when p_candidate ? 'priorityBand' then p_candidate->>'priorityBand' else candidate.priority_band end,
      owner_id = v_owner_id, assigned_to = v_owner_id,
      outreach_status = case when nullif(p_candidate->>'outreachStatus','') is not null then p_candidate->>'outreachStatus' else candidate.outreach_status end,
      interest_level = case when nullif(p_candidate->>'interestLevel','') is not null then p_candidate->>'interestLevel' else candidate.interest_level end,
      preferred_collaboration = case when p_candidate ? 'preferredCollaboration' then p_candidate->>'preferredCollaboration' else candidate.preferred_collaboration end,
      deck_introduced = case when p_candidate ? 'deckIntroduced' then (p_candidate->>'deckIntroduced')::boolean else candidate.deck_introduced end,
      pmf_asked = case when p_candidate ? 'pmfAsked' then (p_candidate->>'pmfAsked')::boolean else candidate.pmf_asked end,
      first_outreach = case when p_candidate ? 'firstOutreach' then nullif(p_candidate->>'firstOutreach','')::date else candidate.first_outreach end,
      follow_up_1 = case when p_candidate ? 'followUp1' then nullif(p_candidate->>'followUp1','')::date else candidate.follow_up_1 end,
      follow_up_2 = case when p_candidate ? 'followUp2' then nullif(p_candidate->>'followUp2','')::date else candidate.follow_up_2 end,
      response_date = case when p_candidate ? 'responseDate' then nullif(p_candidate->>'responseDate','')::date else candidate.response_date end,
      next_step = case when p_candidate ? 'nextStep' then p_candidate->>'nextStep' else candidate.next_step end,
      next_step_due = case when p_candidate ? 'nextStepDue' then nullif(p_candidate->>'nextStepDue','')::date else candidate.next_step_due end,
      notes = case when p_candidate ? 'notes' then p_candidate->>'notes' else candidate.notes end,
      source_updated_on = case when p_candidate ? 'sourceUpdatedOn' then nullif(p_candidate->>'sourceUpdatedOn','')::date else candidate.source_updated_on end,
      updated_at = now()
    where candidate.id = v_candidate_id and candidate.organization_id = v_org_id and candidate.project_id = v_project_id
    returning candidate.* into v_result;
  else
    insert into public.candidates (
      organization_id, project_id, external_id, source_label, name, category, platforms, reach, tier,
      creator_type, content_fit, fit_level, contact_readiness, contact_channel, contact_detail, source_url,
      pmf_candidate, pmf_rationale, priority_score, priority_band, owner_id, assigned_to,
      outreach_status, interest_level, preferred_collaboration, deck_introduced, pmf_asked,
      first_outreach, follow_up_1, follow_up_2, response_date, next_step, next_step_due, notes,
      source_updated_on, created_by
    ) values (
      v_org_id, v_project_id, case when coalesce(p_candidate->>'externalId','') like 'local-%' then null else nullif(p_candidate->>'externalId','') end,
      p_candidate->>'source', trim(p_candidate->>'name'), coalesce(nullif(p_candidate->>'category',''), 'Other / Discovery'),
      p_candidate->>'platforms', p_candidate->>'reach', p_candidate->>'tier', p_candidate->>'creatorType', p_candidate->>'contentFit', p_candidate->>'fitLevel',
      coalesce(nullif(p_candidate->>'contactReadiness',''), 'Research needed'), p_candidate->>'contactChannel',
      p_candidate->>'contactDetail', p_candidate->>'sourceUrl', coalesce((p_candidate->>'pmfCandidate')::boolean, false),
      p_candidate->>'pmfRationale', greatest(0, least(100, coalesce((p_candidate->>'priorityScore')::integer, 0))),
      p_candidate->>'priorityBand', v_owner_id, v_owner_id,
      coalesce(nullif(p_candidate->>'outreachStatus',''), 'Not Contacted'), coalesce(nullif(p_candidate->>'interestLevel',''), 'Unknown'),
      p_candidate->>'preferredCollaboration', coalesce((p_candidate->>'deckIntroduced')::boolean, false),
      coalesce((p_candidate->>'pmfAsked')::boolean, false), nullif(p_candidate->>'firstOutreach','')::date,
      nullif(p_candidate->>'followUp1','')::date, nullif(p_candidate->>'followUp2','')::date,
      nullif(p_candidate->>'responseDate','')::date, p_candidate->>'nextStep', nullif(p_candidate->>'nextStepDue','')::date,
      p_candidate->>'notes', nullif(p_candidate->>'sourceUpdatedOn','')::date, auth.uid()
    ) returning * into v_result;
  end if;
  if v_result.id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'candidate', v_result.id, 'upsert', jsonb_build_object('name', v_result.name));
  return jsonb_build_object('id', v_result.id, 'externalId', v_result.external_id, 'name', v_result.name,
    'category', v_result.category, 'ownerId', v_result.assigned_to,
    'outreachStatus', v_result.outreach_status, 'workflowStatus', v_result.workflow_status);
end; $$;

drop function if exists public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text);
create function public.rpc_aoi_add_evidence(p_candidate_id uuid, p_evidence_type text, p_evidence_stance text, p_evidence_strength integer, p_evidence_title text, p_evidence_notes text, p_evidence_consent text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_result public.evidence_records%rowtype;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select candidate.project_id into v_project_id from public.candidates candidate
  where candidate.id = p_candidate_id and candidate.organization_id = v_org_id;
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if trim(coalesce(p_evidence_title, '')) = '' then raise exception 'EVIDENCE_TITLE_REQUIRED'; end if;
  insert into public.evidence_records (
    organization_id, project_id, candidate_id, type, evidence_type, stance, strength,
    title, notes, consent_status, workflow_status, assigned_to, recorded_by
  ) values (
    v_org_id, v_project_id, p_candidate_id,
    coalesce(nullif(p_evidence_type, ''), 'PMF interview'), coalesce(nullif(p_evidence_type, ''), 'PMF interview'),
    p_evidence_stance, greatest(1, least(4, coalesce(p_evidence_strength, 1))), trim(p_evidence_title),
    p_evidence_notes, coalesce(nullif(p_evidence_consent, ''), 'pending'), 'draft', auth.uid(), auth.uid()
  ) returning * into v_result;
  return jsonb_build_object('id', v_result.id, 'candidateId', v_result.candidate_id);
end; $$;

create or replace function public.rpc_aoi_import_candidates(p_rows jsonb, p_file_name text, p_file_format text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_row jsonb; v_count integer := 0; v_job_id uuid;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'IMPORT_ROWS_REQUIRED'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'IMPORT_TOO_LARGE'; end if;
  insert into public.import_jobs (organization_id, project_id, file_name, file_format, row_count, status, created_by)
  values (v_org_id, v_project_id, p_file_name, p_file_format, jsonb_array_length(p_rows), 'previewed', auth.uid())
  returning id into v_job_id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    perform public.rpc_aoi_upsert_candidate(v_row);
    v_count := v_count + 1;
  end loop;
  update public.import_jobs set status = 'committed' where id = v_job_id;
  return jsonb_build_object('jobId', v_job_id, 'imported', v_count);
end; $$;

revoke all on function public.rpc_aoi_operations_snapshot() from public, anon;
revoke all on function public.rpc_aoi_upsert_candidate(jsonb) from public, anon;
revoke all on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) from public, anon;
revoke all on function public.rpc_aoi_import_candidates(jsonb,text,text) from public, anon;
grant execute on function public.rpc_aoi_operations_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated;
grant execute on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) to authenticated;
grant execute on function public.rpc_aoi_import_candidates(jsonb,text,text) to authenticated;

do $seed$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_owner_id uuid;
  v_campaign_id uuid;
  v_row jsonb;
begin
  select organization.id into v_org_id from public.organizations organization
  where organization.slug = 'aoi-technologics' order by organization.created_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.code = 'AOI-PMF-01' order by project.created_at limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'OUTREACH_SEED_PROJECT_REQUIRED'; end if;

  select membership.user_id into v_owner_id
  from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
  where membership.organization_id = v_org_id and membership.status = 'active'
    and lower(profile.display_name) in ('mike', 'mike revou moses')
  order by case when lower(profile.display_name) = 'mike' then 1 else 2 end, membership.joined_at limit 1;
  if v_owner_id is null then
    select membership.user_id into v_owner_id from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.status = 'active' and membership.role = 'admin'
    order by membership.joined_at limit 1;
  end if;
  if v_owner_id is null then
    select membership.user_id into v_owner_id from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.status = 'active'
    order by membership.joined_at limit 1;
  end if;

  insert into public.outreach_campaigns (
    organization_id, project_id, name, preliminary_interest_deadline, preliminary_interest_target,
    confirmation_deadline, confirmed_target_low, confirmed_target_high, planning_target,
    conversion_rate, recommended_active_pool, safety_notice, first_touch_guidance, scoring_rules
  ) values (
    v_org_id, v_project_id, 'August KOL Outreach', '2026-08-10', 10, '2026-08-20', 40, 50, 45,
    0.4, 113,
    'Discovery conversation or demo-only self-evaluation; no patient use; not a clinical study; no public name, quote, photo, or endorsement without separate written consent.',
    'Use the deck as a PDF attachment in email. For social DMs, introduce the collaboration and ask for the best business email before sending an attachment. Every first touch must name a specific piece of the creator''s work and clearly say Ambiloop wants to explore a potential collaboration.',
    '{"category":{"Dental Professional":30,"Mom & Family":25,"Technology Reviewer":25,"Other / Discovery":10},"fitLevel":{"High":20,"Medium":12,"Low":4},"contactReadiness":{"Email ready":25,"Form ready":18,"Social DM ready":12,"Research needed":0},"tier":{"Micro":15,"Macro":12,"Nano":10,"Mega":5,"Publisher":8,"UGC":12,"Professional KOL":14,"Unknown":6},"pmfCandidate":{"Yes":15,"No":0},"statusOptions":["Not Contacted","Ready to Send","Contacted","Sent","Follow-up 1","Follow-up 2","Replied","Interested","Meeting Booked","Negotiating","Confirmed","Declined","No Response","Unreachable"],"interestOptions":["Unknown","None","Low","Medium","High"],"collaborationOptions":["Not Known","Product Trial / Review","Sponsored Content","UGC","Affiliate","Giveaway","Professional Feedback","Interview / Product Testing","Advisory / PMF","Other"]}'::jsonb
  ) on conflict (project_id) do update set
    name = excluded.name,
    preliminary_interest_deadline = coalesce(public.outreach_campaigns.preliminary_interest_deadline, excluded.preliminary_interest_deadline),
    preliminary_interest_target = case when public.outreach_campaigns.preliminary_interest_target = 0 then excluded.preliminary_interest_target else public.outreach_campaigns.preliminary_interest_target end,
    confirmation_deadline = coalesce(public.outreach_campaigns.confirmation_deadline, excluded.confirmation_deadline),
    confirmed_target_low = case when public.outreach_campaigns.confirmed_target_low = 0 then excluded.confirmed_target_low else public.outreach_campaigns.confirmed_target_low end,
    confirmed_target_high = case when public.outreach_campaigns.confirmed_target_high = 0 then excluded.confirmed_target_high else public.outreach_campaigns.confirmed_target_high end,
    planning_target = case when public.outreach_campaigns.planning_target = 0 then excluded.planning_target else public.outreach_campaigns.planning_target end,
    conversion_rate = case when public.outreach_campaigns.conversion_rate = 0 then excluded.conversion_rate else public.outreach_campaigns.conversion_rate end,
    recommended_active_pool = case when public.outreach_campaigns.recommended_active_pool = 0 then excluded.recommended_active_pool else public.outreach_campaigns.recommended_active_pool end,
    safety_notice = coalesce(public.outreach_campaigns.safety_notice, excluded.safety_notice),
    first_touch_guidance = coalesce(public.outreach_campaigns.first_touch_guidance, excluded.first_touch_guidance),
    scoring_rules = case when public.outreach_campaigns.scoring_rules = '{}'::jsonb then excluded.scoring_rules else public.outreach_campaigns.scoring_rules end
  returning id into v_campaign_id;

  for v_row in select value from jsonb_array_elements($candidates$[
    {"externalId":"1","source":"Original list","category":"Dental Professional","name":"@thebentist","platforms":"TikTok","reach":"15.9M","tier":"Mega","creatorType":"Orthodontist","fit":"Dental education + entertainment, owns oral care product line","fitLevel":"High","contactChannel":"Email + TikTok DM","contactDetail":"https://www.tiktok.com/@thebentist","sourceUrl":"https://www.tiktok.com/@thebentist","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":82,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"pmfAsked":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If they reply, request rate card, available TikTok collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email and TikTok DM on 2026-08-03. Asked for collaboration pricing, cooperation formats, contact information, online meeting availability, and PMF validation interest.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"2","source":"Original list","category":"Dental Professional","name":"@avalene.r","platforms":"TikTok","reach":"2.1M","tier":"Mega","creatorType":"Dental Hygienist","fit":"Oral care + NYC urban lifestyle","fitLevel":"Medium","contactChannel":"Email + TikTok + Instagram + Facebook + Threads","contactDetail":"https://www.tiktok.com/@avalene.r","sourceUrl":"https://www.tiktok.com/@avalene.r","contactReadiness":"Social DM ready","priorityScore":59,"priorityBand":"Low","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If they reply, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, TikTok, Instagram, Facebook, and Threads on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"3","source":"Original list","category":"Dental Professional","name":"@jasminerdh","platforms":"TikTok / YouTube","reach":"1.1M","tier":"Mega","creatorType":"Registered Dental Hygienist","fit":"Dental hygiene education + product reviews, brand collab experienced","fitLevel":"High","contactChannel":"Email + TikTok + Instagram","contactDetail":"contact@jasminerdh.com","contactReadiness":"Email ready","priorityScore":80,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If she replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, TikTok, and Instagram on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"4","source":"Original list","category":"Dental Professional","name":"@corina_907","platforms":"TikTok / Instagram","reach":"TK 2.5M / IG 226K","tier":"Mega","creatorType":"Registered Dental Hygienist","fit":"Tooth Fairy, humorous dental education","fitLevel":"Medium","contactChannel":"Email + TikTok","contactDetail":"corinalaytonpr@gmail.com","contactReadiness":"Email ready","priorityScore":72,"priorityBand":"Medium","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If she replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email and TikTok on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"5","source":"Original list","category":"Dental Professional","name":"@kishengodhia","platforms":"TikTok","reach":"770.4K","tier":"Macro","creatorType":"Restorative & Cosmetic Dentist","fit":"Smile design + oral health education","fitLevel":"Medium","contactChannel":"Email + TikTok + Instagram","contactDetail":"https://www.tiktok.com/@kishengodhia","sourceUrl":"https://www.tiktok.com/@kishengodhia","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If he replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, TikTok, and Instagram on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"6","source":"Original list","category":"Dental Professional","name":"@joycethedentist","platforms":"TikTok","reach":"537.2K","tier":"Macro","creatorType":"Cosmetic Dentist","fit":"Veneers + minimally invasive restoration","fitLevel":"Medium","contactChannel":"Email + TikTok + Website","contactDetail":"https://www.tiktok.com/@joycethedentist","sourceUrl":"https://www.tiktok.com/@joycethedentist","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If she replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, TikTok, and website on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"7","source":"Original list","category":"Dental Professional","name":"@drjordanbrown","platforms":"TikTok","reach":"295K","tier":"Macro","creatorType":"General Dentist","fit":"Dental knowledge + daily life, Tampa FL","fitLevel":"Medium","contactChannel":"Email + Instagram + TikTok","contactDetail":"https://www.tiktok.com/@drjordanbrown","sourceUrl":"https://www.tiktok.com/@drjordanbrown","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If he replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, Instagram, and TikTok on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"8","source":"Original list","category":"Dental Professional","name":"@askthedentist","platforms":"TikTok / YouTube","reach":"TK 235K / YT 150K","tier":"Macro","creatorType":"Functional Dentist","fit":"Oral microbiome + evidence-based dentistry","fitLevel":"Medium","contactChannel":"Email + Instagram","contactDetail":"catharine@askthedentist.com","contactReadiness":"Email ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":94,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If they reply, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email and Instagram on 2026-08-03. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"9","source":"Original list","category":"Dental Professional","name":"@teethtalkgirl","platforms":"TikTok / YouTube / Instagram","reach":"TK 160K / YT 825K","tier":"Macro","creatorType":"Registered Dental Hygienist","fit":"Cross-platform oral health education, real-product testing","fitLevel":"Medium","contactChannel":"Website + Email + Facebook + Instagram","contactDetail":"hello@teethtalkgirl.com; alex@teethtalkgirl.com","contactReadiness":"Email ready","priorityScore":79,"priorityBand":"Medium","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If they reply, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by website, email, Facebook, and Instagram on 2026-08-03. Email contacts: hello@teethtalkgirl.com; alex@teethtalkgirl.com. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"10","source":"Original list","category":"Dental Professional","name":"@drbilldorfmanofficial","platforms":"TikTok","reach":"122.6K","tier":"Macro","creatorType":"Cosmetic Dentist","fit":"Celebrity dentist (ABC Extreme Makeover)","fitLevel":"Medium","contactChannel":"Email + TikTok Comment + Instagram Message","contactDetail":"customerservice@pooof.com","sourceUrl":"https://www.tiktok.com/@drbilldorfmanofficial","contactReadiness":"Email ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":94,"priorityBand":"High","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07. If he or his team replies, request rate card, available collaboration formats, best partnership contact, and online meeting availability.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by email, TikTok post comment, and Instagram message on 2026-08-03. Email used: customerservice@pooof.com. Asked for collaboration options/pricing and online meeting availability.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"11","source":"Original list","category":"Dental Professional","name":"@dr_plolo","platforms":"TikTok","reach":"106.3K","tier":"Macro","creatorType":"Pediatric Dentist","fit":"Making dentistry fun for kids","fitLevel":"High","contactChannel":"Instagram Message + TikTok Comment","contactDetail":"https://www.tiktok.com/@dr_plolo","sourceUrl":"https://www.tiktok.com/@dr_plolo","contactReadiness":"Social DM ready; no email/phone found","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":77,"priorityBand":"Medium","outreachStatus":"Sent","interestLevel":"Unknown","preferredCollaboration":"Not Known","deckIntroduced":true,"firstOutreach":"2026-08-03","followUp1":"2026-08-07","nextStep":"Follow up if no response by 2026-08-07 via Instagram/TikTok. Continue looking for email or phone contact if needed.","nextStepDue":"2026-08-07","notes":"Initial outreach sent by Instagram message and TikTok post comment on 2026-08-03. No email or phone number found.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"12","source":"Original list","category":"Dental Professional","name":"@dentist_emi","platforms":"TikTok / Instagram / YouTube","reach":"93K","tier":"Micro","creatorType":"General Dentist","fit":"Cross-platform dental daily life + product reviews","fitLevel":"High","contactChannel":"Instagram Message + TikTok","contactDetail":"https://www.tiktok.com/@dentist_emi","sourceUrl":"https://www.tiktok.com/@dentist_emi","contactReadiness":"Unreachable via current social routes; Instagram messages blocked; TikTok comment/message unavailable","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":80,"priorityBand":"High","outreachStatus":"Unreachable","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find alternate email, website/contact form, agency contact, or other verified contact route before reattempting outreach.","nextStepDue":"2026-08-04","notes":"Attempted contact on 2026-08-03. Instagram messages are blocked, and TikTok cannot be messaged or commented on. No successful outreach completed through those channels.","sourceUpdatedOn":"2026-08-03"},
    {"externalId":"13","source":"Original list","category":"Dental Professional","name":"@dryazdan","platforms":"TikTok / Instagram","reach":"82.9K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"Veneers + smile design, California","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@dryazdan","sourceUrl":"https://www.tiktok.com/@dryazdan","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"14","source":"Original list","category":"Dental Professional","name":"@fitlittlehygienist","platforms":"TikTok","reach":"55.9K","tier":"Micro","creatorType":"Dental Hygienist","fit":"Dental hygiene + fitness lifestyle","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@fitlittlehygienist","sourceUrl":"https://www.tiktok.com/@fitlittlehygienist","contactReadiness":"Social DM ready","priorityScore":69,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"15","source":"Original list","category":"Dental Professional","name":"@justflossit","platforms":"TikTok / Instagram","reach":"34.3K","tier":"Micro","creatorType":"Registered Dental Hygienist","fit":"Flossing + oral product recommendations","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@justflossit","sourceUrl":"https://www.tiktok.com/@justflossit","contactReadiness":"Social DM ready","priorityScore":69,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"16","source":"Original list","category":"Dental Professional","name":"@drashleyizadi","platforms":"TikTok","reach":"27.9K","tier":"Micro","creatorType":"General Dentist","fit":"Oral health education + fun content","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@drashleyizadi","sourceUrl":"https://www.tiktok.com/@drashleyizadi","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"17","source":"Original list","category":"Dental Professional","name":"@smilewithcallie","platforms":"TikTok","reach":"24K","tier":"Micro","creatorType":"RDH + Mom","fit":"Dental hygienist + toddler mom","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@smilewithcallie","sourceUrl":"https://www.tiktok.com/@smilewithcallie","contactReadiness":"Social DM ready","priorityScore":77,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"18","source":"Original list","category":"Dental Professional","name":"@iamdr_a","platforms":"TikTok / Instagram","reach":"TK 17.2K / IG 27K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"NYC street-style dentist content","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@iamdr_a","sourceUrl":"https://www.tiktok.com/@iamdr_a","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"19","source":"Original list","category":"Dental Professional","name":"@jerry_rdh","platforms":"Instagram","reach":"89K","tier":"Macro","creatorType":"Registered Dental Hygienist","fit":"Dental humor + education","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/jerry_rdh","sourceUrl":"https://www.instagram.com/jerry_rdh","contactReadiness":"Social DM ready","priorityScore":66,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"20","source":"Original list","category":"Dental Professional","name":"@pediatric.dentist.mom","platforms":"Instagram","reach":"228K","tier":"Macro","creatorType":"Pediatric Dentist + Mom","fit":"Kids' teeth + family prevention","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/pediatric.dentist.mom","sourceUrl":"https://www.instagram.com/pediatric.dentist.mom","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":89,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"21","source":"Original list","category":"Dental Professional","name":"@dr.norazaghi","platforms":"Instagram / YouTube","reach":"108K","tier":"Macro","creatorType":"Functional Pediatric Dentist + Mom","fit":"Whole-body health + airway-focused dentistry","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/dr.norazaghi","sourceUrl":"https://www.instagram.com/dr.norazaghi","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":89,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"22","source":"Original list","category":"Dental Professional","name":"@baby_dds","platforms":"Instagram","reach":"30K","tier":"Micro","creatorType":"Pediatric Dentist + 3 Kids Mom","fit":"Pediatric + mom dual identity","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/baby_dds","sourceUrl":"https://www.instagram.com/baby_dds","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":92,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"23","source":"Original list","category":"Dental Professional","name":"@thelatinardh","platforms":"Instagram","reach":"30K","tier":"Micro","creatorType":"Latina Public Health RDH","fit":"Multicultural oral health","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/thelatinardh","sourceUrl":"https://www.instagram.com/thelatinardh","contactReadiness":"Social DM ready","priorityScore":69,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"24","source":"Original list","category":"Dental Professional","name":"@amberaugerrdh","platforms":"Instagram","reach":"20K","tier":"Micro","creatorType":"Registered Dental Hygienist","fit":"RDH career + oral education","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/amberaugerrdh","sourceUrl":"https://www.instagram.com/amberaugerrdh","contactReadiness":"Social DM ready","priorityScore":69,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"25","source":"Original list","category":"Dental Professional","name":"@drteethboutique","platforms":"TikTok / Instagram","reach":"TK 30K / IG 24K","tier":"Micro","creatorType":"General Dentist","fit":"LA female dentist, high engagement 8.8%","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.tiktok.com/@drteethboutique","sourceUrl":"https://www.tiktok.com/@drteethboutique","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"26","source":"Original list","category":"Dental Professional","name":"@DentalDigest","platforms":"YouTube","reach":"21.2M","tier":"Mega","creatorType":"Dental Student / Creator","fit":"Satisfying dental content + product reviews","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@DentalDigest","sourceUrl":"https://www.youtube.com/@DentalDigest","contactReadiness":"Social DM ready","priorityScore":67,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"27","source":"Original list","category":"Dental Professional","name":"@DrJohnYoo","platforms":"YouTube","reach":"1.2M","tier":"Mega","creatorType":"Pediatric Dentist","fit":"KPop dentist, fun dental education","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@DrJohnYoo","sourceUrl":"https://www.youtube.com/@DrJohnYoo","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":82,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"28","source":"Original list","category":"Dental Professional","name":"@InnovativeDentalofSpringfield","platforms":"YouTube","reach":"133K","tier":"Macro","creatorType":"Dental Clinic","fit":"Latest dental tech + smile transformations","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@InnovativeDentalofSpringfield","sourceUrl":"https://www.youtube.com/@InnovativeDentalofSpringfield","contactReadiness":"Social DM ready","priorityScore":74,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"29","source":"Original list","category":"Dental Professional","name":"@MichaeltheDentist","platforms":"YouTube","reach":"130K","tier":"Macro","creatorType":"General Dentist","fit":"Real surgery + oral health science","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@MichaeltheDentist","sourceUrl":"https://www.youtube.com/@MichaeltheDentist","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"30","source":"Original list","category":"Dental Professional","name":"@VeryNiceSmile","platforms":"YouTube","reach":"144K","tier":"Macro","creatorType":"General Dentist","fit":"Dental education + DIY oral care","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@VeryNiceSmile","sourceUrl":"https://www.youtube.com/@VeryNiceSmile","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"31","source":"Original list","category":"Dental Professional","name":"@HygieneEdge","platforms":"YouTube","reach":"91.1K","tier":"Macro","creatorType":"Dental Hygienist Team","fit":"New tech + product reviews","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@hygieneedge","sourceUrl":"https://www.youtube.com/@hygieneedge","contactReadiness":"Social DM ready","priorityScore":74,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"32","source":"Original list","category":"Dental Professional","name":"@ToothTimeFamilyDentistry","platforms":"YouTube","reach":"486K","tier":"Macro","creatorType":"Dental Clinic","fit":"Dental daily life + kids + braces","fitLevel":"High","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@ToothTimeFamilyDentistry","sourceUrl":"https://www.youtube.com/@ToothTimeFamilyDentistry","contactReadiness":"Social DM ready","priorityScore":74,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"33","source":"Original list","category":"Dental Professional","name":"@dynamicsmilesbydrp","platforms":"Instagram","reach":"254K","tier":"Macro","creatorType":"Cosmetic Dentist","fit":"Cosmetic dentistry + lifestyle","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/dynamicsmilesbydrp","sourceUrl":"https://www.instagram.com/dynamicsmilesbydrp","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"34","source":"Original list","category":"Other / Discovery","name":"@drjoshuaghiam","platforms":"Instagram","reach":"155K","tier":"Macro","creatorType":"Porcelain Veneer Specialist","fit":"High-end cosmetic dentistry","fitLevel":"Low","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/drjoshuaghiam","sourceUrl":"https://www.instagram.com/drjoshuaghiam","contactReadiness":"Social DM ready","priorityScore":38,"priorityBand":"Low","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"35","source":"Original list","category":"Dental Professional","name":"@drjordandavis_","platforms":"Instagram","reach":"100K","tier":"Macro","creatorType":"Cosmetic Dentist","fit":"Non-invasive veneers, +325% follower growth in 6 months","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/drjordandavis_","sourceUrl":"https://www.instagram.com/drjordandavis_","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":81,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"36","source":"Original list","category":"Dental Professional","name":"@dr.jaysmile","platforms":"Instagram","reach":"59K","tier":"Micro","creatorType":"General Dentist","fit":"Highest engagement 12.4%","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/dr.jaysmile","sourceUrl":"https://www.instagram.com/dr.jaysmile","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"37","source":"Original list","category":"Dental Professional","name":"@marshallhansondentistry","platforms":"Instagram","reach":"47K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"Non-invasive veneer international educator","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/marshallhansondentistry","sourceUrl":"https://www.instagram.com/marshallhansondentistry","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"38","source":"Original list","category":"Dental Professional","name":"@dentalclarafication","platforms":"Instagram","reach":"45K","tier":"Micro","creatorType":"Dental Student Influencer","fit":"Dental school + oral health education","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/dentalclarafication","sourceUrl":"https://www.instagram.com/dentalclarafication","contactReadiness":"Social DM ready","priorityScore":69,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"39","source":"Original list","category":"Dental Professional","name":"@thesmilediva","platforms":"Instagram","reach":"33K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"Smile makeover artist","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/thesmilediva","sourceUrl":"https://www.instagram.com/thesmilediva","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"40","source":"Original list","category":"Dental Professional","name":"@drrobertomacedo","platforms":"Instagram","reach":"35K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"Tampa top dentist, 3.9% engagement","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/drrobertomacedo","sourceUrl":"https://www.instagram.com/drrobertomacedo","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"41","source":"Original list","category":"Dental Professional","name":"@officialdrmoe_","platforms":"Instagram","reach":"31K","tier":"Micro","creatorType":"Cosmetic Dentist","fit":"Houston veneer specialist","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/officialdrmoe_","sourceUrl":"https://www.instagram.com/officialdrmoe_","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"42","source":"Original list","category":"Dental Professional","name":"@adamoelvis","platforms":"Instagram","reach":"22K","tier":"Micro","creatorType":"AACD Accredited Dentist","fit":"Authoritative cosmetic dentistry","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.instagram.com/adamoelvis","sourceUrl":"https://www.instagram.com/adamoelvis","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"43","source":"Original list","category":"Dental Professional","name":"@Dr.Rana.DDS","platforms":"YouTube / Instagram","reach":"Mid-size","tier":"Micro","creatorType":"General Dentist","fit":"Dentist daily life + consumer education","fitLevel":"Medium","contactChannel":"Social DM","contactDetail":"https://www.youtube.com/@Dr.Rana.DDS","sourceUrl":"https://www.youtube.com/@Dr.Rana.DDS","contactReadiness":"Social DM ready","pmfCandidate":true,"pmfRationale":"Influential dentist; evaluate for interview, demo-only testing, professional feedback, or future consented endorsement","priorityScore":84,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"44","source":"Original list","category":"Dental Professional","name":"@Nano Pool A","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"RDH / Dental Student","fit":"UGC real usage scenario","fitLevel":"Medium","contactChannel":"Contact research","contactDetail":"Search via hashtag #dentalhygienist","contactReadiness":"Research needed","priorityScore":52,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"45","source":"Original list","category":"Mom & Family","name":"@Nano Pool B","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"Mom / Family Creator","fit":"Kids' oral self-check scenario","fitLevel":"High","contactChannel":"Contact research","contactDetail":"Search via hashtag #momtok","contactReadiness":"Research needed","priorityScore":55,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"46","source":"Original list","category":"Mom & Family","name":"@Nano Pool C","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"Wellness / Health","fit":"Daily oral care routine","fitLevel":"Low","contactChannel":"Contact research","contactDetail":"Search via hashtag #wellnesstok","contactReadiness":"Research needed","priorityScore":39,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"47","source":"Original list","category":"Technology Reviewer","name":"@Nano Pool D","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"3C / Tech Enthusiast","fit":"Oral health tech gadgets","fitLevel":"High","contactChannel":"Contact research","contactDetail":"Search via hashtag #techreview","contactReadiness":"Research needed","priorityScore":55,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"48","source":"Original list","category":"Mom & Family","name":"@Nano Pool E","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"Lifestyle","fit":"Beauty/whitening + oral tools","fitLevel":"Low","contactChannel":"Contact research","contactDetail":"Search via hashtag #beautytok","contactReadiness":"Research needed","priorityScore":39,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"49","source":"Original list","category":"Other / Discovery","name":"@Nano Pool F","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"Student / Young User","fit":"Affordable oral gadgets","fitLevel":"Low","contactChannel":"Contact research","contactDetail":"Search via hashtag #college","contactReadiness":"Research needed","priorityScore":24,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"50","source":"Original list","category":"Other / Discovery","name":"@Nano Pool G","platforms":"TikTok / Instagram","reach":"1K-10K","tier":"Nano","creatorType":"Diverse / Young User","fit":"Daily oral self-check","fitLevel":"Low","contactChannel":"Contact research","contactDetail":"Search via hashtag #dentalcare","contactReadiness":"Research needed","priorityScore":24,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"51","source":"Added research","category":"Dental Professional","name":"@bracesbybritt / Dr. Britteny Zito","platforms":"Instagram / TikTok / YouTube","reach":"1M+ community (official site)","tier":"Macro","creatorType":"Board-certified orthodontist","fit":"Braces and aligner education; parents, patients, and documented oral-care brand collaborations","fitLevel":"High","contactChannel":"Business email + official collaboration form","contactDetail":"bracesbybritt@gmail.com","sourceUrl":"https://www.bracesbybritt.com/","contactReadiness":"Email ready","pmfCandidate":true,"pmfRationale":"High-value orthodontic creator; strong Segment A and hands-on feedback fit","priorityScore":95,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"52","source":"Added research","category":"Dental Professional","name":"@thebracesguy / Dr. Grant Collins","platforms":"TikTok / Instagram / YouTube / Facebook","reach":"5M+ cross-platform (official site)","tier":"Mega","creatorType":"Orthodontist / creator","fit":"How-to braces content and private-practice credibility","fitLevel":"High","contactChannel":"Business email","contactDetail":"TheBracesGuyOfficial@gmail.com","sourceUrl":"https://www.thebracesguy.com/","contactReadiness":"Email ready","pmfCandidate":true,"pmfRationale":"Influential orthodontist with private-practice and family-facing reach","priorityScore":95,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"53","source":"Added research","category":"Dental Professional","name":"The Peds Dentist / Dr. Ivy Fua","platforms":"Website / social","reach":"Not verified","tier":"Professional KOL","creatorType":"Pediatric dentist + mother","fit":"Pediatric oral-health education from a dentist and parent perspective","fitLevel":"High","contactChannel":"Business email + official collaboration form","contactDetail":"drivydds@gmail.com","sourceUrl":"https://www.thepedsdentist.com/contact","contactReadiness":"Email ready","pmfCandidate":true,"pmfRationale":"Pediatric and parent crossover; strong PMF interview candidate","priorityScore":97,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"54","source":"Added research","category":"Dental Professional","name":"Melissa K. Turner / The Tooth Girl","platforms":"Multi-platform / dental media","reach":"150K+ audience reach (official site)","tier":"Macro","creatorType":"Dental hygienist / dental AI thought leader","fit":"Dental technology, education, social campaigns, and strategic product partnerships","fitLevel":"High","contactChannel":"Official inquiry form","contactDetail":"https://www.melissakturner.com/","sourceUrl":"https://www.melissakturner.com/","contactReadiness":"Form ready","pmfRationale":"Strong dental-tech collaboration fit; use for KOL content rather than dentist-only PMF sample","priorityScore":80,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"55","source":"Added research","category":"Dental Professional","name":"Brad Hughes DDS","platforms":"Website / podcast / social","reach":"Not verified","tier":"Professional KOL","creatorType":"Dentist / educator / creator","fit":"Dental content collaboration, speaking, and practice leadership","fitLevel":"High","contactChannel":"Official work-with-me form","contactDetail":"https://bradhughesdds.com/work-with-me/","sourceUrl":"https://bradhughesdds.com/work-with-me/","contactReadiness":"Form ready","pmfCandidate":true,"pmfRationale":"Dentist and educator with explicit content-collaboration channel","priorityScore":97,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"56","source":"Added research","category":"Dental Professional","name":"Dr. Amanda Wilson / StraightSmile Solutions","platforms":"YouTube / Instagram / TikTok / LinkedIn","reach":"Not verified","tier":"Professional KOL","creatorType":"Orthodontist / consultant","fit":"Doctor-to-doctor orthodontic consulting and technology adoption","fitLevel":"High","contactChannel":"Official website contact","contactDetail":"https://www.straightsmilesolutions.com/about/find-us-online/","sourceUrl":"https://www.straightsmilesolutions.com/about/find-us-online/","contactReadiness":"Form ready","pmfCandidate":true,"pmfRationale":"Orthodontic workflow and professional adoption perspective","priorityScore":97,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"57","source":"Added research","category":"Mom & Family","name":"Graceful Mommy / Kari Ogg","platforms":"TikTok / YouTube / Instagram / Pinterest","reach":"168K+ TikTok; 144K+ YouTube (official site)","tier":"Macro","creatorType":"Mom / family creator","fit":"Product-led family and motherhood content; explicit brand collaboration packages","fitLevel":"High","contactChannel":"Official collaboration form","contactDetail":"https://gracefulmommy.com/","sourceUrl":"https://gracefulmommy.com/","contactReadiness":"Form ready","pmfRationale":"Strong family-routine and product-demonstration fit","priorityScore":75,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"58","source":"Added research","category":"Mom & Family","name":"One Messy Mama / Ashton","platforms":"Blog / Instagram / Facebook / Pinterest","reach":"Not verified","tier":"Micro","creatorType":"Parenting / family lifestyle creator","fit":"Family lifestyle, product reviews, giveaways, and sponsored posts","fitLevel":"High","contactChannel":"Business email","contactDetail":"onemessymama4@gmail.com","sourceUrl":"https://onemessymama.com/contact-me/","contactReadiness":"Email ready","pmfRationale":"Explicitly open to authentic family brand collaborations","priorityScore":85,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"59","source":"Added research","category":"Mom & Family","name":"The Modern Latina Mama / Carla Gomez","platforms":"TikTok / YouTube / Instagram / blog","reach":"1.1M+ monthly reach (official site)","tier":"Macro","creatorType":"Motherhood / family creator","fit":"Motherhood, family, wellness, and UGC with U.S.-based parent audience","fitLevel":"High","contactChannel":"Business email + official collaboration form","contactDetail":"themodernlatinamama@gmail.com","sourceUrl":"https://www.themodernlatinamama.com/collaborate","contactReadiness":"Email ready","pmfRationale":"Family wellness and culturally relevant parent reach","priorityScore":75,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"60","source":"Added research","category":"Mom & Family","name":"Brittany Allen & Family","platforms":"UGC / social","reach":"Not verified","tier":"UGC","creatorType":"Mom-life / family / tech UGC creator","fit":"Unboxing, how-to, testimonials, educational content, and family participation","fitLevel":"High","contactChannel":"Business email","contactDetail":"britt@keycreativemarketing.com","sourceUrl":"https://brittugc.com/","contactReadiness":"Email ready","pmfRationale":"Flexible family UGC and tech-product demonstration","priorityScore":82,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"61","source":"Added research","category":"Mom & Family","name":"Hamnah Saqlain / @startswithasmilehum","platforms":"Instagram / TikTok","reach":"11K+ Instagram (official site)","tier":"Micro","creatorType":"Motherhood / lifestyle / tech UGC creator","fit":"Family routines, wellness, product demos, and bilingual-capable content","fitLevel":"High","contactChannel":"Business email","contactDetail":"hamnah@growwithhamnah.com","sourceUrl":"https://growwithhamnah.com/","contactReadiness":"Email ready","pmfRationale":"Practical family-routine storytelling and product demonstration","priorityScore":85,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"62","source":"Added research","category":"Mom & Family","name":"Lauren Bodnar","platforms":"UGC / Instagram","reach":"Not verified","tier":"UGC","creatorType":"Homeschool mom / family / tech creator","fit":"Authentic family, homeschool, budget living, and beta-tech usage","fitLevel":"High","contactChannel":"Business email","contactDetail":"laurenbodnar.ugc@gmail.com","sourceUrl":"https://www.laurenbodnar.com/","contactReadiness":"Email ready","pmfRationale":"Family routines plus comfort testing new technology","priorityScore":82,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"63","source":"Added research","category":"Mom & Family","name":"Teresa / @createwithteresa_","platforms":"TikTok / Instagram / UGC","reach":"30.5M+ content views (official site)","tier":"UGC","creatorType":"Mom of four / performance UGC creator","fit":"Paid and organic family product videos; strong demonstration focus","fitLevel":"High","contactChannel":"Business email + official brand inquiry form","contactDetail":"hello@createwithteresa.com","sourceUrl":"https://createwithteresa.com/","contactReadiness":"Email ready","pmfRationale":"Experienced parent creator for clear product demonstrations","priorityScore":75,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"64","source":"Added research","category":"Technology Reviewer","name":"Well Connected Mom / Lori","platforms":"Blog / social","reach":"Not verified","tier":"Publisher","creatorType":"Family technology reviewer","fit":"Lives with products to assess relevance for families; accepts review pitches","fitLevel":"High","contactChannel":"Review email","contactDetail":"Lori@wellconnectedmom.com; info@wellconnectedmom.com; media@wellconnctedmom.com; lori@wellconnctedmom.com","sourceUrl":"https://wellconnectedmom.com/blog/contact-us/","contactReadiness":"Email ready","pmfRationale":"Best bridge between family use and technology review","priorityScore":78,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"65","source":"Added research","category":"Technology Reviewer","name":"NYC Tech Mommy","platforms":"Blog / social","reach":"Not verified","tier":"Micro","creatorType":"Family technology creator","fit":"Family lifestyle, technology, product reviews, and collaborations","fitLevel":"High","contactChannel":"Business email + official contact page","contactDetail":"monica@nyctechmommy.com","sourceUrl":"https://www.nyctechmommy.com/contact-us/","contactReadiness":"Email ready","pmfRationale":"Parent-and-tech crossover relevant to at-home oral visibility","priorityScore":78,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"66","source":"Added research","category":"Technology Reviewer","name":"The Gadgeteer","platforms":"Website / newsletter","reach":"Not verified","tier":"Publisher","creatorType":"Independent gadget review publication","fit":"Long-form product reviews; explicitly accepts product-review pitches","fitLevel":"High","contactChannel":"Official review pitch form","contactDetail":"https://the-gadgeteer.com/well-review-it/","sourceUrl":"https://the-gadgeteer.com/well-review-it/","contactReadiness":"Form ready","pmfRationale":"Hands-on gadget testing and clear review submission process","priorityScore":71,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"67","source":"Added research","category":"Technology Reviewer","name":"Modern Castle","platforms":"Website / video","reach":"Not verified","tier":"Publisher","creatorType":"Consumer product testing publisher","fit":"Detailed home and consumer product reviews","fitLevel":"Medium","contactChannel":"Official contact page","contactDetail":"https://moderncastle.com/contact/","sourceUrl":"https://moderncastle.com/contact/","contactReadiness":"Form ready","pmfRationale":"Structured testing capability; confirm oral-health category interest","priorityScore":63,"priorityBand":"Medium","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"},
    {"externalId":"68","source":"Added research","category":"Technology Reviewer","name":"TechGearLab","platforms":"Website","reach":"Not verified","tier":"Publisher","creatorType":"Consumer technology testing publisher","fit":"Objective side-by-side consumer product testing","fitLevel":"Medium","contactChannel":"Editorial contact research","contactDetail":"https://www.techgearlab.com/","sourceUrl":"https://www.techgearlab.com/","contactReadiness":"Research needed","pmfRationale":"Strong testing methodology; route to correct health/fitness editor","priorityScore":45,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"69","source":"Added research","category":"Technology Reviewer","name":"TechRadar Health & Fitness","platforms":"Website / YouTube / social","reach":"Not verified","tier":"Publisher","creatorType":"Technology review media","fit":"Maintains current electric-toothbrush testing and buying guides","fitLevel":"High","contactChannel":"Editorial contact research","contactDetail":"matt.evans@futurenet.com","sourceUrl":"https://www.techradar.com/health-fitness/oral-health/best-electric-toothbrush","contactReadiness":"Research needed","pmfRationale":"Direct oral-care technology review relevance","priorityScore":53,"priorityBand":"Low","outreachStatus":"Not Contacted","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Find a verified business contact"},
    {"externalId":"70","source":"Added research","category":"Technology Reviewer","name":"Well-Caffeinated Mom","platforms":"Blog / social","reach":"Not verified","tier":"Micro","creatorType":"Family tech and product reviewer","fit":"Family-friendly technology, gadgets, and product reviews","fitLevel":"High","contactChannel":"Partnership email","contactDetail":"partnerships@wellcaffeinatedmom.com; pr@wellcaffeinatedmom.com; rondab@wellcaffeinatedmom.com; contribute@wellcaffeinatedmom.com; ronda@wellcaffeinatedmom.com","sourceUrl":"https://www.wellcaffeinatedmom.com/sample-and-review-policy/","contactReadiness":"Email ready","pmfRationale":"Family-tech crossover with explicit product review policy","priorityScore":85,"priorityBand":"High","outreachStatus":"Ready to Send","interestLevel":"Unknown","preferredCollaboration":"Not Known","nextStep":"Personalize and send first touch"}
  ]$candidates$::jsonb) loop
    if exists (
      select 1 from public.candidates candidate
      where candidate.project_id = v_project_id and candidate.external_id = v_row->>'externalId'
        and lower(candidate.name) <> lower(v_row->>'name')
    ) then
      raise exception 'OUTREACH_SEED_IDENTITY_CONFLICT: %', v_row->>'externalId';
    end if;
    insert into public.candidates (
      organization_id, project_id, external_id, source_label, name, category, platforms, reach, tier,
      creator_type, content_fit, fit_level, contact_readiness, contact_channel, contact_detail, source_url,
      pmf_candidate, pmf_rationale, priority_score, priority_band, owner_id, assigned_to,
      outreach_status, interest_level, preferred_collaboration, deck_introduced, pmf_asked,
      first_outreach, follow_up_1, follow_up_2, response_date, next_step, next_step_due, notes,
      source_updated_on, created_by
    ) values (
      v_org_id, v_project_id, v_row->>'externalId', v_row->>'source', v_row->>'name', v_row->>'category',
      v_row->>'platforms', v_row->>'reach', v_row->>'tier', v_row->>'creatorType', v_row->>'fit', v_row->>'fitLevel',
      v_row->>'contactReadiness', v_row->>'contactChannel', v_row->>'contactDetail', v_row->>'sourceUrl',
      coalesce((v_row->>'pmfCandidate')::boolean, false), v_row->>'pmfRationale',
      coalesce((v_row->>'priorityScore')::integer, 0), v_row->>'priorityBand', v_owner_id, v_owner_id,
      coalesce(v_row->>'outreachStatus', 'Not Contacted'), coalesce(v_row->>'interestLevel', 'Unknown'),
      v_row->>'preferredCollaboration', coalesce((v_row->>'deckIntroduced')::boolean, false),
      coalesce((v_row->>'pmfAsked')::boolean, false), nullif(v_row->>'firstOutreach','')::date,
      nullif(v_row->>'followUp1','')::date, nullif(v_row->>'followUp2','')::date,
      nullif(v_row->>'responseDate','')::date, v_row->>'nextStep', nullif(v_row->>'nextStepDue','')::date,
      v_row->>'notes', nullif(v_row->>'sourceUpdatedOn','')::date, v_owner_id
    ) on conflict (project_id, external_id) where external_id is not null do update set
      source_label = coalesce(public.candidates.source_label, excluded.source_label),
      category = coalesce(nullif(public.candidates.category, ''), excluded.category),
      platforms = coalesce(nullif(public.candidates.platforms, ''), excluded.platforms),
      reach = coalesce(nullif(public.candidates.reach, ''), excluded.reach),
      tier = coalesce(nullif(public.candidates.tier, ''), excluded.tier),
      creator_type = coalesce(nullif(public.candidates.creator_type, ''), excluded.creator_type),
      content_fit = coalesce(nullif(public.candidates.content_fit, ''), excluded.content_fit),
      fit_level = coalesce(nullif(public.candidates.fit_level, ''), excluded.fit_level),
      contact_readiness = case
        when public.candidates.contact_readiness in ('', 'Research needed') and excluded.contact_detail like '%@%' then excluded.contact_readiness
        else public.candidates.contact_readiness end,
      contact_channel = coalesce(nullif(public.candidates.contact_channel, ''), excluded.contact_channel),
      contact_detail = case
        when excluded.contact_detail like '%@%' and coalesce(public.candidates.contact_detail, '') not like '%@%' then excluded.contact_detail
        else coalesce(nullif(public.candidates.contact_detail, ''), excluded.contact_detail) end,
      source_url = coalesce(nullif(public.candidates.source_url, ''), excluded.source_url),
      pmf_candidate = public.candidates.pmf_candidate or excluded.pmf_candidate,
      pmf_rationale = coalesce(nullif(public.candidates.pmf_rationale, ''), excluded.pmf_rationale),
      priority_score = case when public.candidates.priority_score = 0 then excluded.priority_score else public.candidates.priority_score end,
      priority_band = coalesce(nullif(public.candidates.priority_band, ''), excluded.priority_band),
      outreach_status = public.candidates.outreach_status,
      interest_level = public.candidates.interest_level,
      preferred_collaboration = coalesce(nullif(public.candidates.preferred_collaboration, ''), excluded.preferred_collaboration),
      deck_introduced = public.candidates.deck_introduced or excluded.deck_introduced,
      pmf_asked = public.candidates.pmf_asked or excluded.pmf_asked,
      first_outreach = coalesce(public.candidates.first_outreach, excluded.first_outreach),
      follow_up_1 = coalesce(public.candidates.follow_up_1, excluded.follow_up_1),
      follow_up_2 = coalesce(public.candidates.follow_up_2, excluded.follow_up_2),
      response_date = coalesce(public.candidates.response_date, excluded.response_date),
      next_step = coalesce(nullif(public.candidates.next_step, ''), excluded.next_step),
      next_step_due = coalesce(public.candidates.next_step_due, excluded.next_step_due),
      notes = coalesce(public.candidates.notes, excluded.notes),
      source_updated_on = coalesce(public.candidates.source_updated_on, excluded.source_updated_on);
  end loop;

  for v_row in select value from jsonb_array_elements($execution_plan$[
    {"date":"2026-08-03","focus":"Approve product readiness, external deck PDF, claims, sender signature, and offer boundaries","plannedFirstTouches":0,"actualFirstTouches":11,"plannedFollowUps":0,"actualFollowUps":0,"expectedOutcome":"Internal","owner":"Mike"},
    {"date":"2026-08-04","focus":"Contact research + Wave 1: highest-score dental KOLs","plannedFirstTouches":15,"actualFirstTouches":0,"plannedFollowUps":0,"actualFollowUps":0,"expectedOutcome":"15 personalized first touches","owner":"Mike"},
    {"date":"2026-08-05","focus":"Wave 2: orthodontic, pediatric, and PMF candidates","plannedFirstTouches":15,"actualFirstTouches":0,"plannedFollowUps":0,"actualFollowUps":0,"expectedOutcome":"PMF conversations begin booking","owner":"Mike"},
    {"date":"2026-08-06","focus":"Wave 3: mom/family creators","plannedFirstTouches":15,"actualFirstTouches":0,"plannedFollowUps":0,"actualFollowUps":0,"expectedOutcome":"Family collaboration interest","owner":"Mike"},
    {"date":"2026-08-07","focus":"Wave 4: technology reviewers + family-tech crossovers","plannedFirstTouches":15,"actualFirstTouches":0,"plannedFollowUps":0,"actualFollowUps":11,"expectedOutcome":"Review pipeline opens","owner":"Mike"},
    {"date":"2026-08-08","focus":"Wave 5 + first follow-ups for earliest sends","plannedFirstTouches":10,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"All 70 rows actioned or assigned","owner":"Mike"},
    {"date":"2026-08-09","focus":"Fast response handling and call scheduling","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":15,"actualFollowUps":0,"expectedOutcome":"Turn replies into meetings","owner":"Mike"},
    {"date":"2026-08-10","focus":"Preliminary-interest checkpoint","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":15,"actualFollowUps":0,"expectedOutcome":"Initial interested group documented","owner":"Mike"},
    {"date":"2026-08-11","focus":"Calls, product-fit questions, rates, formats, and PMF interviews","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Qualified active opportunities","owner":"Mike"},
    {"date":"2026-08-12","focus":"Calls and demo-only PMF scheduling","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"PMF and commercial tracks separated","owner":"Mike"},
    {"date":"2026-08-13","focus":"Second-wave sourcing to close pipeline gap","plannedFirstTouches":15,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Prospect pool expanded","owner":"Mike"},
    {"date":"2026-08-14","focus":"Terms, deliverables, rights, lead times, and sample logistics","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Verbal alignment converted to written next steps","owner":"Mike"},
    {"date":"2026-08-15","focus":"Final follow-up for nonresponders","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":20,"actualFollowUps":0,"expectedOutcome":"Close or reclassify cold leads","owner":"Mike"},
    {"date":"2026-08-16","focus":"Weekend response handling / no new cold send unless appropriate","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":5,"actualFollowUps":0,"expectedOutcome":"Maintain momentum","owner":"Mike"},
    {"date":"2026-08-17","focus":"Confirmation push: scope, timing, compensation, shipping","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Confirmed collaboration records","owner":"Mike"},
    {"date":"2026-08-18","focus":"Escalate blockers and replace stalled prospects","plannedFirstTouches":10,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Recovery pipeline","owner":"Mike"},
    {"date":"2026-08-19","focus":"Final confirmation audit","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":10,"actualFollowUps":0,"expectedOutcome":"Every active KOL has a dated next step","owner":"Mike"},
    {"date":"2026-08-20","focus":"Final target checkpoint and boss report","plannedFirstTouches":0,"actualFirstTouches":0,"plannedFollowUps":5,"actualFollowUps":0,"expectedOutcome":"40-50 confirmed or quantified gap/recovery plan","owner":"Mike"}
  ]$execution_plan$::jsonb) loop
    insert into public.outreach_plan_items (
      organization_id, project_id, campaign_id, plan_date, focus,
      planned_first_touches, actual_first_touches, planned_follow_ups, actual_follow_ups,
      expected_outcome, owner_label
    ) values (
      v_org_id, v_project_id, v_campaign_id, (v_row->>'date')::date, v_row->>'focus',
      (v_row->>'plannedFirstTouches')::integer, (v_row->>'actualFirstTouches')::integer,
      (v_row->>'plannedFollowUps')::integer, (v_row->>'actualFollowUps')::integer,
      v_row->>'expectedOutcome', v_row->>'owner'
    ) on conflict (campaign_id, plan_date) do nothing;
  end loop;

  for v_row in select value from jsonb_array_elements($email_templates$[
    {"name":"Initial - dental KOL + PMF","audience":"Dentists / orthodontists / pediatric dentists","subject":"Exploring an Ambiloop collaboration + professional feedback","body":"Hi Dr. [Last Name],\n\nI've been following your work on [specific topic], especially [specific post or video]. I'm reaching out from Ambiloop, a new home oral-visibility system designed to help people capture hard-to-see areas, build a visual timeline, and organize records they can choose to share with a dental professional.\n\nWe'd like to explore a potential collaboration with you, and I've attached our short collaboration deck. Depending on fit, this could include a product trial, educational content, an interview, or professional feedback.\n\nBecause your perspective on [orthodontic / pediatric / preventive] care is especially relevant, would you also be open to a 20-minute PMF validation conversation? A smaller group may be invited to a 30-60 minute, demo-only hands-on feedback session. This is not a clinical study, involves no patient use, and we would never use your name, quote, or image publicly without separate written permission.\n\nWould you be open to a brief call next week? If so, which collaboration format interests you most?\n\nBest,\nMike\nAmbiloop"},
    {"name":"Initial - mom / family","audience":"Mom and family creators","subject":"Could Ambiloop fit your family's oral-care routine?","body":"Hi [First Name],\n\nI enjoyed your [specific post or series] about [family routine / parenting topic]. I'm reaching out from Ambiloop, a new home oral-visibility system that helps families see hard-to-check areas, keep a visual timeline, and make oral care feel more understandable and engaging.\n\nWe'd love to explore a potential collaboration with you and have attached our short collaboration deck. Possible formats include an honest family product trial, routine-based content, UGC, or a sponsored educational story - always with age-appropriate use and parent control.\n\nWould you be interested in learning more? If so, I'd love to hear which format feels most natural for your audience, your timing, and your usual partnership requirements.\n\nBest,\nMike\nAmbiloop"},
    {"name":"Initial - tech reviewer","audience":"Technology reviewers / tech creators","subject":"Review opportunity: a new oral-visibility technology category","body":"Hi [First Name],\n\nYour review of [specific product or video] stood out for [specific reason]. I'm reaching out from Ambiloop, a new home oral-visibility system built around guided image capture, visual timelines, and user-controlled sharing.\n\nWe're interested in exploring a potential collaboration with you and have attached our short collaboration deck. We can support an independent hands-on review, first-look demonstration, product-testing feedback, or an interview with the team.\n\nWould this fit your coverage? If so, please share the review format, lead time, sample policy, and any commercial terms you require.\n\nBest,\nMike\nAmbiloop"},
    {"name":"First follow-up","audience":"No response after 3 business days","subject":"Quick follow-up - Ambiloop collaboration","body":"Hi [First Name],\n\nFollowing up on my note about exploring a potential Ambiloop collaboration. I thought the product could be relevant to your work on [specific topic], especially because it helps make hard-to-see oral-care routines more visible over time.\n\nWould you be open to a short conversation, or is there someone else who handles partnerships? I'm happy to resend the deck or provide a one-paragraph summary.\n\nBest,\nMike"},
    {"name":"Final follow-up","audience":"No response 5-7 days later","subject":"Closing the loop - Ambiloop","body":"Hi [First Name],\n\nI'll close the loop after this note. We'd still be glad to explore a potential Ambiloop collaboration if the timing is right. Possible formats include [best-fit format].\n\nIf now isn't a fit, no reply is needed. If you'd prefer that we do not contact you again, just let me know and I'll update our records immediately.\n\nBest,\nMike"},
    {"name":"Interested response","audience":"Creator expressed interest","subject":"Next steps for Ambiloop x [Creator]","body":"Hi [First Name],\n\nThank you - we're excited to explore this with you. To shape the right next step, could you share: (1) your preferred collaboration format, (2) timing and availability, (3) rates or media kit if applicable, (4) shipping location after terms are agreed, and (5) any product-testing or editorial requirements?\n\nFor professional participants, please also confirm whether you're open to a separate PMF feedback conversation or demo-only product session. Public use of any name, quote, photo, or endorsement would require separate written approval.\n\nBest,\nMike"},
    {"name":"Social DM opener","audience":"Instagram / TikTok / LinkedIn","subject":"N/A","body":"Hi [First Name] - I work with Ambiloop, a new home oral-visibility product. Your [specific content] looks like a strong fit, and we'd love to explore a potential collaboration. Could you share the best business email? I'll send a short deck and the relevant options. - Mike"}
  ]$email_templates$::jsonb) loop
    if not exists (
      select 1 from public.email_templates template
      where template.organization_id = v_org_id and template.name = v_row->>'name'
    ) then
      insert into public.email_templates (organization_id, name, audience, subject, body, status, created_by)
      values (v_org_id, v_row->>'name', v_row->>'audience', v_row->>'subject', v_row->>'body', 'approved', v_owner_id);
    end if;
  end loop;

  insert into public.outreach_events (organization_id, project_id, candidate_id, channel, kind, status, occurred_at, actor_id, summary)
  select v_org_id, v_project_id, candidate.id, candidate.contact_channel, 'Initial', 'Sent',
    candidate.first_outreach::timestamptz + interval '12 hours', v_owner_id,
    coalesce(candidate.notes, 'Initial outreach sent on ' || candidate.first_outreach::text)
  from public.candidates candidate
  where candidate.project_id = v_project_id
    and candidate.external_id in ('1','2','3','4','5','6','7','8','9','10','11')
    and candidate.first_outreach is not null
    and not exists (
      select 1 from public.outreach_events event
      where event.candidate_id = candidate.id and event.kind = 'Initial' and event.status = 'Sent'
        and event.occurred_at::date = candidate.first_outreach
    );

  insert into public.outreach_events (organization_id, project_id, candidate_id, channel, kind, status, occurred_at, actor_id, summary)
  select v_org_id, v_project_id, candidate.id, candidate.contact_channel, 'Attempt', 'Blocked',
    '2026-08-03 12:00:00+00'::timestamptz, v_owner_id, candidate.notes
  from public.candidates candidate
  where candidate.project_id = v_project_id and candidate.external_id = '12'
    and not exists (
      select 1 from public.outreach_events event
      where event.candidate_id = candidate.id and event.kind = 'Attempt' and event.status = 'Blocked'
        and event.occurred_at::date = '2026-08-03'
    );
end;
$seed$;
