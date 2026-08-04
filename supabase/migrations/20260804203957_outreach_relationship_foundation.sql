-- Outreach Release 1: canonical relationship, campaign, and activity foundation.

-- Restore PMF evidence privacy after the shared Outreach workspace broadened it.
drop policy if exists evidence_workspace_read on public.evidence_records;
drop policy if exists evidence_workspace_insert on public.evidence_records;
drop policy if exists evidence_assignment_or_approved_read on public.evidence_records;
drop policy if exists evidence_assignment_scoped_insert on public.evidence_records;

create policy evidence_assignment_or_approved_read on public.evidence_records
for select to authenticated using (
  public.is_org_admin(organization_id)
  or (
    public.is_org_member(organization_id)
    and assigned_to = (select auth.uid())
  )
  or (
    public.is_org_member(organization_id)
    and workflow_status = 'approved'
  )
);

create policy evidence_assignment_scoped_insert on public.evidence_records
for insert to authenticated with check (
  public.is_org_member(organization_id)
  and recorded_by = (select auth.uid())
  and (assigned_to = (select auth.uid()) or public.is_org_admin(organization_id))
  and (workflow_status = 'draft' or public.is_org_admin(organization_id))
  and (
    (
      candidate_id is not null
      and exists (
        select 1
        from public.candidates candidate
        where candidate.id = evidence_records.candidate_id
          and candidate.organization_id = evidence_records.organization_id
          and candidate.project_id = evidence_records.project_id
      )
    )
    or (
      candidate_id is null
      and respondent_id is not null
      and exists (
        select 1
        from public.respondents respondent
        where respondent.id = evidence_records.respondent_id
          and respondent.organization_id = evidence_records.organization_id
          and respondent.project_id = evidence_records.project_id
      )
    )
  )
);

create table public.crm_contact_methods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  method_type text not null check (method_type in ('email','phone','form','website','social','other')),
  value text not null check (length(trim(value)) > 0),
  label text,
  is_primary boolean not null default false,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','verified','invalid')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (contact_id, method_type, value),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade
);
alter table public.crm_contact_methods enable row level security;
create index crm_contact_methods_scope_idx
  on public.crm_contact_methods (organization_id, project_id, contact_id, method_type);
create unique index crm_contact_methods_one_primary_idx
  on public.crm_contact_methods (contact_id, method_type) where is_primary;

create table public.crm_communication_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  channel text not null check (channel in ('email','phone','form','website','social','other')),
  consent_state text not null default 'unknown'
    check (consent_state in ('unknown','allowed','denied','withdrawn')),
  allowed boolean,
  source text,
  evidence text,
  effective_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_communication_preferences_state_check check (
    (consent_state = 'unknown' and allowed is null)
    or (consent_state = 'allowed' and allowed is true)
    or (consent_state in ('denied','withdrawn') and allowed is false)
  ),
  unique (contact_id, channel),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade
);
alter table public.crm_communication_preferences enable row level security;
create index crm_communication_preferences_scope_idx
  on public.crm_communication_preferences (organization_id, project_id, contact_id);

create table public.outreach_stage_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  campaign_id uuid not null,
  stage_key text not null check (stage_key ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (length(trim(label)) > 0),
  semantic_family text not null check (semantic_family in (
    'research','ready','contacted','engaged','qualified','committed','closed'
  )),
  position integer not null check (position > 0),
  active boolean not null default true,
  sla_days integer check (sla_days is null or sla_days >= 0),
  transition_requirements jsonb not null default '{}'::jsonb
    check (jsonb_typeof(transition_requirements) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, stage_key),
  unique (campaign_id, position),
  unique (organization_id, project_id, campaign_id, id),
  foreign key (organization_id, project_id, campaign_id)
    references public.outreach_campaigns (organization_id, project_id, id) on delete cascade
);
alter table public.outreach_stage_definitions enable row level security;
create index outreach_stage_definitions_scope_idx
  on public.outreach_stage_definitions (organization_id, project_id, campaign_id, active, position);

create table public.outreach_campaign_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  campaign_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid not null,
  stage_id uuid not null,
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  membership_status text not null default 'active'
    check (membership_status in ('active','closed')),
  entered_stage_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, contact_id),
  unique (campaign_id, candidate_id),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, campaign_id)
    references public.outreach_campaigns (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, campaign_id, stage_id)
    references public.outreach_stage_definitions (organization_id, project_id, campaign_id, id) on delete restrict
);
alter table public.outreach_campaign_memberships enable row level security;
create index outreach_campaign_memberships_queue_idx
  on public.outreach_campaign_memberships
  (organization_id, project_id, campaign_id, stage_id, assigned_to, membership_status);

create table public.outreach_research (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid not null,
  summary text not null check (length(trim(summary)) > 0),
  source_url text,
  research_status text not null default 'draft'
    check (research_status in ('draft','ready','archived')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete cascade
);
alter table public.outreach_research enable row level security;
create index outreach_research_contact_idx
  on public.outreach_research (organization_id, project_id, contact_id, updated_at desc);

create table public.relationship_activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid,
  actor_id uuid references public.profiles(id) on delete set null,
  activity_type text not null check (length(trim(activity_type)) > 0),
  summary text not null check (length(trim(summary)) > 0),
  channel text,
  status text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz not null default now(),
  legacy_source text,
  legacy_id uuid,
  created_at timestamptz not null default now(),
  check ((legacy_source is null) = (legacy_id is null)),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete set null (candidate_id)
);
alter table public.relationship_activities enable row level security;
create index relationship_activities_timeline_idx
  on public.relationship_activities (organization_id, project_id, contact_id, occurred_at desc, id);
create unique index relationship_activities_legacy_unique
  on public.relationship_activities (legacy_source, legacy_id) where legacy_source is not null;

create table public.outreach_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid not null,
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'completed') = (completed_at is not null)),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete cascade
);
alter table public.outreach_tasks enable row level security;
create index outreach_tasks_queue_idx
  on public.outreach_tasks (organization_id, project_id, assigned_to, status, due_at);

create table public.outreach_meetings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid not null,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  scheduled_at timestamptz not null,
  status text not null default 'planned'
    check (status in ('planned','completed','cancelled','no_show')),
  outcome text,
  next_action text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete cascade
);
alter table public.outreach_meetings enable row level security;
create index outreach_meetings_schedule_idx
  on public.outreach_meetings (organization_id, project_id, owner_id, status, scheduled_at);

create table public.outreach_offers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  candidate_id uuid not null,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  offer_type text not null check (length(trim(offer_type)) > 0),
  title text not null check (length(trim(title)) > 0),
  status text not null default 'draft'
    check (status in ('draft','proposed','accepted','declined','withdrawn','fulfilled')),
  value_exchange text,
  fulfillment_notes text,
  proposed_at timestamptz,
  decided_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete cascade
);
alter table public.outreach_offers enable row level security;
create index outreach_offers_contact_idx
  on public.outreach_offers (organization_id, project_id, contact_id, status, updated_at desc);

create table public.outreach_audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null,
  actor_id uuid references public.profiles(id) on delete set null,
  contact_id uuid,
  candidate_id uuid,
  action text not null check (length(trim(action)) > 0),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade,
  foreign key (organization_id, project_id, contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete set null (contact_id),
  foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete set null (candidate_id)
);
alter table public.outreach_audit_events enable row level security;
create index outreach_audit_events_scope_idx
  on public.outreach_audit_events (organization_id, project_id, created_at desc, id);

-- New normalized records are read-only through the Data API. RPCs own all writes.
revoke all on public.crm_contact_methods from anon, authenticated;
revoke all on public.crm_communication_preferences from anon, authenticated;
revoke all on public.outreach_stage_definitions from anon, authenticated;
revoke all on public.outreach_campaign_memberships from anon, authenticated;
revoke all on public.outreach_research from anon, authenticated;
revoke all on public.relationship_activities from anon, authenticated;
revoke all on public.outreach_tasks from anon, authenticated;
revoke all on public.outreach_meetings from anon, authenticated;
revoke all on public.outreach_offers from anon, authenticated;
revoke all on public.outreach_audit_events from anon, authenticated;
revoke insert, update on public.candidates from authenticated;
revoke insert on public.outreach_events from authenticated;
revoke insert on public.email_deliveries from authenticated;

grant select on public.crm_contact_methods to authenticated;
grant select on public.crm_communication_preferences to authenticated;
grant select on public.outreach_stage_definitions to authenticated;
grant select on public.outreach_campaign_memberships to authenticated;
grant select on public.outreach_research to authenticated;
grant select on public.relationship_activities to authenticated;
grant select on public.outreach_tasks to authenticated;
grant select on public.outreach_meetings to authenticated;
grant select on public.outreach_offers to authenticated;
grant select on public.outreach_audit_events to authenticated;

create or replace function private.can_read_aoi_relationship(
  p_organization_id uuid,
  p_project_id uuid,
  p_contact_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles caller
      on caller.id = membership.user_id and caller.status = 'active'
    join public.crm_contacts contact
      on contact.id = p_contact_id
      and contact.organization_id = p_organization_id
      and contact.project_id = p_project_id
    where membership.organization_id = p_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and (
        membership.role = 'admin'
        or contact.owner_id = auth.uid()
        or exists (
          select 1 from public.candidates candidate
          where candidate.crm_contact_id = contact.id
            and candidate.organization_id = contact.organization_id
            and candidate.project_id = contact.project_id
        )
      )
  );
$$;
grant usage on schema private to authenticated;
revoke all on function private.can_read_aoi_relationship(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function private.can_read_aoi_relationship(uuid,uuid,uuid) to authenticated;

-- Linked relationships and their normalized details are shared. Unlinked CRM stays private.
drop policy if exists crm_contacts_member_read on public.crm_contacts;
drop policy if exists crm_contacts_assigned_read on public.crm_contacts;
drop policy if exists crm_contacts_relationship_read on public.crm_contacts;
create policy crm_contacts_relationship_read on public.crm_contacts
for select to authenticated using (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and owner_id = (select auth.uid()))
  or (
    public.is_org_member(organization_id)
    and exists (
      select 1
      from public.candidates candidate
      where candidate.crm_contact_id = crm_contacts.id
        and candidate.organization_id = crm_contacts.organization_id
        and candidate.project_id = crm_contacts.project_id
    )
  )
);

create policy crm_contact_methods_relationship_read on public.crm_contact_methods
for select to authenticated using (
  private.can_read_aoi_relationship(organization_id, project_id, contact_id)
);

create policy crm_communication_preferences_relationship_read on public.crm_communication_preferences
for select to authenticated using (
  private.can_read_aoi_relationship(organization_id, project_id, contact_id)
);

create policy outreach_stage_definitions_member_read on public.outreach_stage_definitions
for select to authenticated using (public.is_org_member(organization_id));
create policy outreach_campaign_memberships_member_read on public.outreach_campaign_memberships
for select to authenticated using (public.is_org_member(organization_id));
create policy outreach_research_member_read on public.outreach_research
for select to authenticated using (public.is_org_member(organization_id));
create policy relationship_activities_relationship_read on public.relationship_activities
for select to authenticated using (
  private.can_read_aoi_relationship(organization_id, project_id, contact_id)
);
create policy outreach_tasks_member_read on public.outreach_tasks
for select to authenticated using (public.is_org_member(organization_id));
create policy outreach_meetings_member_read on public.outreach_meetings
for select to authenticated using (public.is_org_member(organization_id));
create policy outreach_offers_member_read on public.outreach_offers
for select to authenticated using (public.is_org_member(organization_id));
create policy outreach_audit_events_admin_read on public.outreach_audit_events
for select to authenticated using (public.is_org_admin(organization_id));

-- Build a one-to-one contact mapping without name-based merging.
drop trigger if exists enforce_aoi_assignee_membership on public.candidates;
drop trigger if exists enforce_aoi_candidate_workflow on public.candidates;
drop trigger if exists validate_crm_candidate_link on public.candidates;

create temporary table outreach_crm_backfill (
  candidate_id uuid primary key,
  crm_id uuid,
  assigned_to uuid
);

insert into outreach_crm_backfill (candidate_id, crm_id, assigned_to)
select candidate.id, candidate.crm_contact_id, chosen.user_id
from public.candidates candidate
left join public.crm_contacts contact
  on contact.id = candidate.crm_contact_id
  and contact.organization_id = candidate.organization_id
  and contact.project_id = candidate.project_id
left join lateral (
  select membership.user_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.organization_id = candidate.organization_id
    and membership.status = 'active'
  order by case
    when membership.user_id = candidate.assigned_to then 1
    when membership.user_id = candidate.owner_id then 2
    when membership.user_id = contact.owner_id then 3
    when membership.role = 'admin' then 4
    else 5
  end, membership.joined_at, membership.user_id
  limit 1
) chosen on true;

do $$
declare v_candidate_id uuid;
begin
  select mapping.candidate_id into v_candidate_id
  from outreach_crm_backfill mapping
  where mapping.assigned_to is null
  order by mapping.candidate_id
  limit 1;
  if v_candidate_id is not null then
    raise exception 'OUTREACH_CANDIDATE_ASSIGNEE_REQUIRED: %', v_candidate_id;
  end if;
end;
$$;

update outreach_crm_backfill mapping
set crm_id = gen_random_uuid()
where mapping.crm_id is null;

insert into public.crm_contacts (
  id, organization_id, project_id, contact_type, name, primary_channel, source_url,
  owner_id, lifecycle, next_action, next_action_due, priority_score, notes, created_by,
  created_at, updated_at
)
select mapping.crm_id, candidate.organization_id, candidate.project_id,
  coalesce(nullif(candidate.category, ''), 'KOL'), candidate.name,
  coalesce(nullif(candidate.contact_channel, ''), 'Email'), candidate.source_url,
  mapping.assigned_to,
  case
    when candidate.outreach_status = 'Confirmed' then 'qualified'
    when candidate.outreach_status in ('Interested','Replied','Meeting Booked','Negotiating') then 'engaged'
    when candidate.outreach_status in ('Sent','Contacted','Drafted','Follow-up 1','Follow-up 2','No Response') then 'contacted'
    when candidate.outreach_status = 'Ready to Send'
      or candidate.contact_readiness in ('Email ready','Form ready','Social DM ready') then 'ready'
    else 'researching'
  end,
  candidate.next_step, candidate.next_step_due, candidate.priority_score,
  candidate.notes, coalesce(candidate.created_by, mapping.assigned_to),
  candidate.created_at, candidate.updated_at
from outreach_crm_backfill mapping
join public.candidates candidate on candidate.id = mapping.candidate_id
where candidate.crm_contact_id is null;

update public.crm_contacts contact
set owner_id = mapping.assigned_to,
    updated_at = case when contact.owner_id is distinct from mapping.assigned_to then clock_timestamp() else contact.updated_at end
from outreach_crm_backfill mapping
where contact.id = mapping.crm_id
  and contact.owner_id is distinct from mapping.assigned_to;

update public.candidates candidate
set crm_contact_id = mapping.crm_id,
    assigned_to = mapping.assigned_to,
    owner_id = mapping.assigned_to,
    updated_at = case
      when candidate.crm_contact_id is distinct from mapping.crm_id
        or candidate.assigned_to is distinct from mapping.assigned_to
        or candidate.owner_id is distinct from mapping.assigned_to
      then clock_timestamp()
      else candidate.updated_at
    end
from outreach_crm_backfill mapping
where candidate.id = mapping.candidate_id;

do $$
begin
  if exists (select 1 from public.candidates where crm_contact_id is null) then
    raise exception 'OUTREACH_CRM_BACKFILL_INCOMPLETE';
  end if;
end;
$$;

alter table public.candidates alter column crm_contact_id set not null;
alter table public.candidates drop constraint if exists candidates_crm_contact_id_fkey;
alter table public.candidates drop constraint if exists candidates_crm_contact_scope_fk;
alter table public.candidates add constraint candidates_crm_contact_id_fkey
  foreign key (crm_contact_id) references public.crm_contacts(id) on delete restrict;
alter table public.candidates add constraint candidates_crm_contact_scope_fk
  foreign key (organization_id, project_id, crm_contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete restrict not valid;
alter table public.candidates validate constraint candidates_crm_contact_scope_fk;

create unique index candidates_relationship_scope_unique
  on public.candidates (organization_id, project_id, crm_contact_id, id);

alter table public.outreach_campaign_memberships
  add constraint outreach_campaign_memberships_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete cascade not valid;
alter table public.outreach_campaign_memberships
  validate constraint outreach_campaign_memberships_relationship_pair_fk;
alter table public.outreach_research
  add constraint outreach_research_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete cascade not valid;
alter table public.outreach_research
  validate constraint outreach_research_relationship_pair_fk;
alter table public.relationship_activities
  add constraint relationship_activities_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete set null (candidate_id) not valid;
alter table public.relationship_activities
  validate constraint relationship_activities_relationship_pair_fk;
alter table public.outreach_tasks
  add constraint outreach_tasks_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete cascade not valid;
alter table public.outreach_tasks
  validate constraint outreach_tasks_relationship_pair_fk;
alter table public.outreach_meetings
  add constraint outreach_meetings_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete cascade not valid;
alter table public.outreach_meetings
  validate constraint outreach_meetings_relationship_pair_fk;
alter table public.outreach_offers
  add constraint outreach_offers_relationship_pair_fk
  foreign key (organization_id, project_id, contact_id, candidate_id)
  references public.candidates (organization_id, project_id, crm_contact_id, id)
  on delete cascade not valid;
alter table public.outreach_offers
  validate constraint outreach_offers_relationship_pair_fk;

create trigger enforce_aoi_assignee_membership
before insert or update of assigned_to, owner_id, organization_id on public.candidates
for each row execute function public.enforce_aoi_candidate_assignee_membership();
create trigger enforce_aoi_candidate_workflow
before update on public.candidates
for each row execute function public.enforce_aoi_candidate_workflow();
create trigger validate_crm_candidate_link
before insert or update of crm_contact_id, assigned_to on public.candidates
for each row execute function public.validate_crm_candidate_link();

-- Preserve canonical values and raw source details without splitting ambiguous strings.
insert into public.crm_contact_methods (
  organization_id, project_id, contact_id, method_type, value, label, is_primary
)
select contact.organization_id, contact.project_id, contact.id, 'email', trim(contact.email), 'Canonical email',
  lower(contact.primary_channel) = 'email'
from public.crm_contacts contact
where nullif(trim(contact.email), '') is not null
on conflict (contact_id, method_type, value) do update
set is_primary = excluded.is_primary, updated_at = clock_timestamp();

insert into public.crm_contact_methods (
  organization_id, project_id, contact_id, method_type, value, label, is_primary
)
select contact.organization_id, contact.project_id, contact.id, 'phone', trim(contact.phone), 'Canonical phone',
  lower(contact.primary_channel) = 'phone'
from public.crm_contacts contact
where nullif(trim(contact.phone), '') is not null
on conflict (contact_id, method_type, value) do update
set is_primary = excluded.is_primary, updated_at = clock_timestamp();

insert into public.crm_contact_methods (
  organization_id, project_id, contact_id, method_type, value, label, is_primary
)
select candidate.organization_id, candidate.project_id, candidate.crm_contact_id,
  case
    when trim(candidate.contact_detail) ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then 'email'
    when trim(candidate.contact_detail) ~ '^\+?[0-9][0-9 ()-]{5,}[0-9]$' then 'phone'
    when lower(trim(candidate.contact_channel)) = 'form'
      and trim(candidate.contact_detail) ~* '^https?://[^[:space:]]+$' then 'form'
    when lower(trim(candidate.contact_channel)) = 'website'
      and trim(candidate.contact_detail) ~* '^https?://[^[:space:]]+$' then 'website'
    when lower(trim(candidate.contact_channel)) in ('social','social dm','tiktok','instagram','facebook','linkedin','youtube','threads') then 'social'
    else 'other'
  end,
  trim(candidate.contact_detail), nullif(trim(candidate.contact_channel), ''), false
from public.candidates candidate
where nullif(trim(candidate.contact_detail), '') is not null
on conflict (contact_id, method_type, value) do nothing;

insert into public.crm_communication_preferences (
  organization_id, project_id, contact_id, channel, consent_state, allowed,
  source, evidence, effective_at, created_at, updated_at
)
select preference.organization_id, candidate.project_id, candidate.crm_contact_id, 'email',
  case when preference.email_opt_out then 'denied' else 'unknown' end,
  case when preference.email_opt_out then false else null end,
  'legacy_contact_preferences', preference.reason, preference.recorded_at,
  preference.recorded_at, preference.recorded_at
from public.contact_preferences preference
join public.candidates candidate
  on candidate.id = preference.candidate_id
  and candidate.organization_id = preference.organization_id
on conflict (contact_id, channel) do update set
  consent_state = excluded.consent_state,
  allowed = excluded.allowed,
  source = excluded.source,
  evidence = excluded.evidence,
  effective_at = excluded.effective_at,
  updated_at = excluded.updated_at;

-- Ensure each project has a campaign before seeding stages and linked memberships.
insert into public.outreach_campaigns (organization_id, project_id, name)
select project.organization_id, project.id, project.name || ' Outreach'
from public.projects project
where not exists (
  select 1 from public.outreach_campaigns campaign where campaign.project_id = project.id
);

-- Release 1 supports only these current legacy status mappings; custom stage configuration is Release 3.
-- Every campaign receives stable semantic stages, and every candidate receives membership.
insert into public.outreach_stage_definitions (
  organization_id, project_id, campaign_id, stage_key, label, semantic_family, position, sla_days
)
select campaign.organization_id, campaign.project_id, campaign.id,
  seed.stage_key, seed.label, seed.semantic_family, seed.position, seed.sla_days
from public.outreach_campaigns campaign
cross join (values
  ('research_needed','Research Needed','research',1,3),
  ('ready_to_send','Ready to Send','ready',2,2),
  ('sent','Sent','contacted',3,4),
  ('follow_up_due','Follow-up Due','contacted',4,3),
  ('responded','Responded','engaged',5,2),
  ('interested','Interested','qualified',6,3),
  ('confirmed','Confirmed','committed',7,null::integer),
  ('declined','Declined','closed',8,null::integer),
  ('unreachable','Unreachable','closed',9,null::integer)
) as seed(stage_key, label, semantic_family, position, sla_days)
on conflict (campaign_id, stage_key) do update set
  label = excluded.label,
  semantic_family = excluded.semantic_family,
  position = excluded.position,
  sla_days = excluded.sla_days,
  updated_at = clock_timestamp();

insert into public.outreach_campaign_memberships (
  organization_id, project_id, campaign_id, contact_id, candidate_id, stage_id,
  assigned_to, membership_status, entered_stage_at
)
select candidate.organization_id, candidate.project_id, campaign.id,
  candidate.crm_contact_id, candidate.id, stage.id, candidate.assigned_to,
  case when stage.semantic_family = 'closed' then 'closed' else 'active' end,
  candidate.updated_at
from public.candidates candidate
join public.outreach_campaigns campaign
  on campaign.organization_id = candidate.organization_id and campaign.project_id = candidate.project_id
join public.outreach_stage_definitions stage
  on stage.campaign_id = campaign.id
  and stage.stage_key = case
    when candidate.outreach_status = 'Ready to Send' then 'ready_to_send'
    when candidate.outreach_status in ('Sent','Contacted','Drafted') then 'sent'
    when candidate.outreach_status in ('Follow-up 1','Follow-up 2','No Response') then 'follow_up_due'
    when candidate.outreach_status in ('Replied','Meeting Booked') then 'responded'
    when candidate.outreach_status in ('Interested','Negotiating') then 'interested'
    when candidate.outreach_status = 'Confirmed' then 'confirmed'
    when candidate.outreach_status = 'Declined' then 'declined'
    when candidate.outreach_status = 'Unreachable' then 'unreachable'
    else 'research_needed'
  end
on conflict (campaign_id, contact_id) do update set
  candidate_id = excluded.candidate_id,
  stage_id = excluded.stage_id,
  assigned_to = excluded.assigned_to,
  membership_status = excluded.membership_status,
  updated_at = clock_timestamp();

-- Keep the singular legacy timelines intact while projecting them into one append-only stream.
insert into public.relationship_activities (
  organization_id, project_id, contact_id, candidate_id, actor_id, activity_type,
  summary, metadata, occurred_at, legacy_source, legacy_id, created_at
)
select activity.organization_id, activity.project_id, activity.contact_id, candidate.id,
  activity.actor_id, activity.activity_type, activity.summary, '{}'::jsonb,
  activity.created_at, 'crm_activity', activity.id, activity.created_at
from public.crm_activity activity
left join public.candidates candidate
  on candidate.crm_contact_id = activity.contact_id
  and candidate.organization_id = activity.organization_id
  and candidate.project_id = activity.project_id
on conflict (legacy_source, legacy_id) where legacy_source is not null do nothing;

drop function if exists public.rpc_aoi_outreach_foundation_snapshot();
create function public.rpc_aoi_outreach_foundation_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_visible_contact_ids uuid[];
begin
  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller
    on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid()
    and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id
  limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  select coalesce(array_agg(contact.id order by contact.id), '{}'::uuid[])
  into v_visible_contact_ids
  from public.crm_contacts contact
  where contact.organization_id = v_org_id
    and contact.project_id = v_project_id
    and (
      v_role = 'admin'
      or contact.owner_id = auth.uid()
      or exists (
        select 1
        from public.candidates candidate
        where candidate.crm_contact_id = contact.id
          and candidate.organization_id = contact.organization_id
          and candidate.project_id = contact.project_id
      )
    );

  return jsonb_build_object(
    'projectId', v_project_id,
    'semanticStages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', stage.id, 'campaignId', stage.campaign_id, 'key', stage.stage_key,
        'label', stage.label, 'semanticFamily', stage.semantic_family,
        'position', stage.position, 'active', stage.active, 'slaDays', stage.sla_days,
        'transitionRequirements', stage.transition_requirements
      ) order by stage.campaign_id, stage.position)
      from public.outreach_stage_definitions stage
      where stage.organization_id = v_org_id and stage.project_id = v_project_id
    ), '[]'::jsonb),
    'relationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'contactId', contact.id, 'candidateId', candidate.id,
        'name', contact.name, 'organization', contact.organization_name,
        'contactType', contact.contact_type, 'email', contact.email, 'phone', contact.phone,
        'primaryChannel', contact.primary_channel, 'sourceUrl', contact.source_url,
        'tags', contact.tags, 'ownerId', contact.owner_id, 'ownerName', owner.display_name,
        'lifecycle', contact.lifecycle, 'nextAction', contact.next_action,
        'nextActionDue', contact.next_action_due, 'priorityScore', contact.priority_score,
        'notes', contact.notes, 'updatedAt', contact.updated_at,
        'outreachStatus', candidate.outreach_status, 'contactReadiness', candidate.contact_readiness,
        'category', candidate.category, 'pmfCandidate', candidate.pmf_candidate,
        'tier', candidate.tier, 'reach', candidate.reach,
        'interestLevel', candidate.interest_level, 'workflowStatus', candidate.workflow_status
      ) order by contact.priority_score desc, contact.name)
      from public.crm_contacts contact
      left join public.candidates candidate
        on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id
        and candidate.project_id = contact.project_id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'methods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', method.id, 'contactId', method.contact_id, 'type', method.method_type,
        'value', method.value, 'label', method.label, 'isPrimary', method.is_primary,
        'verificationStatus', method.verification_status, 'verifiedAt', method.verified_at
      ) order by method.contact_id, method.is_primary desc, method.created_at)
      from public.crm_contact_methods method
      where method.project_id = v_project_id and method.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'preferences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', preference.id, 'contactId', preference.contact_id, 'channel', preference.channel,
        'consentState', preference.consent_state, 'allowed', preference.allowed,
        'source', preference.source, 'evidence', preference.evidence,
        'effectiveAt', preference.effective_at, 'updatedAt', preference.updated_at
      ) order by preference.contact_id, preference.channel)
      from public.crm_communication_preferences preference
      where preference.project_id = v_project_id and preference.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', membership.id, 'campaignId', membership.campaign_id,
        'contactId', membership.contact_id, 'candidateId', membership.candidate_id,
        'stageId', membership.stage_id, 'assignedTo', membership.assigned_to,
        'status', membership.membership_status, 'enteredStageAt', membership.entered_stage_at,
        'updatedAt', membership.updated_at
      ) order by membership.created_at)
      from public.outreach_campaign_memberships membership
      where membership.project_id = v_project_id and membership.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', activity.id, 'contactId', activity.contact_id,
        'candidateId', activity.candidate_id, 'actorId', activity.actor_id,
        'actorName', coalesce(actor.display_name, 'AOI'),
        'activityType', activity.activity_type, 'summary', activity.summary,
        'channel', activity.channel, 'status', activity.status,
        'metadata', activity.metadata, 'occurredAt', activity.occurred_at
      ) order by activity.occurred_at desc, activity.id desc)
      from public.relationship_activities activity
      left join public.profiles actor on actor.id = activity.actor_id
      where activity.project_id = v_project_id and activity.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'research', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', research.id, 'contactId', research.contact_id,
        'candidateId', research.candidate_id, 'summary', research.summary,
        'sourceUrl', research.source_url, 'status', research.research_status,
        'createdBy', research.created_by, 'updatedBy', research.updated_by,
        'updatedAt', research.updated_at
      ) order by research.updated_at desc)
      from public.outreach_research research
      where research.project_id = v_project_id and research.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', task.id, 'contactId', task.contact_id, 'candidateId', task.candidate_id,
        'assignedTo', task.assigned_to, 'title', task.title, 'dueAt', task.due_at,
        'status', task.status, 'completedAt', task.completed_at,
        'completedBy', task.completed_by, 'updatedAt', task.updated_at
      ) order by task.due_at nulls last, task.created_at)
      from public.outreach_tasks task
      where task.project_id = v_project_id and task.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', meeting.id, 'contactId', meeting.contact_id,
        'candidateId', meeting.candidate_id, 'ownerId', meeting.owner_id,
        'scheduledAt', meeting.scheduled_at, 'status', meeting.status,
        'outcome', meeting.outcome, 'nextAction', meeting.next_action,
        'updatedAt', meeting.updated_at
      ) order by meeting.scheduled_at desc)
      from public.outreach_meetings meeting
      where meeting.project_id = v_project_id and meeting.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', offer.id, 'contactId', offer.contact_id, 'candidateId', offer.candidate_id,
        'ownerId', offer.owner_id, 'offerType', offer.offer_type, 'title', offer.title,
        'status', offer.status, 'valueExchange', offer.value_exchange,
        'fulfillmentNotes', offer.fulfillment_notes,
        'proposedAt', offer.proposed_at, 'decidedAt', offer.decided_at,
        'updatedAt', offer.updated_at
      ) order by offer.updated_at desc)
      from public.outreach_offers offer
      where offer.project_id = v_project_id and offer.contact_id = any(v_visible_contact_ids)
    ), '[]'::jsonb)
  );
end;
$$;

drop function if exists public.rpc_aoi_save_relationship(jsonb,jsonb,timestamptz);
create function public.rpc_aoi_save_relationship(
  p_contact jsonb,
  p_outreach jsonb,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_contact_id uuid;
  v_candidate_id uuid;
  v_campaign_id uuid;
  v_stage_id uuid;
  v_owner_id uuid;
  v_assigned_to uuid;
  v_requested_owner_id uuid;
  v_create_outreach boolean;
  v_name text;
  v_outreach_status text;
  v_before_contact public.crm_contacts%rowtype;
  v_saved_contact public.crm_contacts%rowtype;
  v_before_candidate public.candidates%rowtype;
  v_saved_candidate public.candidates%rowtype;
  v_before jsonb;
begin
  p_contact := coalesce(p_contact, '{}'::jsonb);
  p_outreach := coalesce(p_outreach, '{}'::jsonb);
  if jsonb_typeof(p_contact) <> 'object' or jsonb_typeof(p_outreach) <> 'object' then
    raise exception 'OUTREACH_PAYLOAD_INVALID';
  end if;

  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller
    on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  v_contact_id := nullif(p_contact->>'id', '')::uuid;
  v_candidate_id := nullif(p_outreach->>'candidateId', '')::uuid;
  v_create_outreach := coalesce(
    nullif(p_contact->>'createOutreach', '')::boolean,
    nullif(p_outreach->>'createOutreach', '')::boolean,
    true
  );
  v_requested_owner_id := coalesce(
    nullif(p_contact->>'ownerId', '')::uuid,
    nullif(p_outreach->>'ownerId', '')::uuid
  );

  if v_contact_id is not null then
    select contact.* into v_before_contact
    from public.crm_contacts contact
    where contact.id = v_contact_id
      and contact.organization_id = v_org_id
      and contact.project_id = v_project_id
    for update;
    if v_before_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
    select membership.assigned_to into v_assigned_to
    from public.outreach_campaign_memberships membership
    where membership.organization_id = v_org_id
      and membership.project_id = v_project_id
      and membership.contact_id = v_contact_id
    order by membership.updated_at desc, membership.id
    limit 1;
    if not (
      v_role = 'admin'
      or v_before_contact.owner_id = auth.uid()
      or coalesce(v_assigned_to = auth.uid(), false)
    ) then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
    if p_expected_updated_at is null or v_before_contact.updated_at <> p_expected_updated_at then
      raise exception 'OUTREACH_STALE_WRITE';
    end if;
    v_owner_id := v_before_contact.owner_id;
    if v_requested_owner_id is not null and v_requested_owner_id is distinct from v_owner_id then
      if v_role <> 'admin' then raise exception 'OUTREACH_REASSIGN_ADMIN_REQUIRED'; end if;
      v_owner_id := v_requested_owner_id;
      v_assigned_to := v_requested_owner_id;
    end if;
  else
    if p_expected_updated_at is not null then raise exception 'OUTREACH_STALE_WRITE'; end if;
    v_owner_id := coalesce(v_requested_owner_id, auth.uid());
    if v_role <> 'admin' and v_owner_id is distinct from auth.uid() then
      raise exception 'OUTREACH_REASSIGN_ADMIN_REQUIRED';
    end if;
    v_assigned_to := v_owner_id;
  end if;

  if not exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id
      and membership.user_id = v_owner_id
      and membership.status = 'active'
      and profile.status = 'active'
  ) then raise exception 'OUTREACH_OWNER_INVALID'; end if;
  v_assigned_to := coalesce(v_assigned_to, v_owner_id);
  if not exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id
      and membership.user_id = v_assigned_to
      and membership.status = 'active'
      and profile.status = 'active'
  ) then raise exception 'OUTREACH_OWNER_INVALID'; end if;

  v_name := trim(coalesce(p_contact->>'name', v_before_contact.name, ''));
  if length(v_name) < 2 then raise exception 'CRM_CONTACT_NAME_REQUIRED'; end if;
  if nullif(p_contact->>'lifecycle', '') is not null
    and p_contact->>'lifecycle' not in ('new','researching','ready','contacted','engaged','qualified','paused') then
    raise exception 'CRM_LIFECYCLE_INVALID';
  end if;

  if v_contact_id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, organization_name, email, phone,
      primary_channel, source_url, tags, owner_id, lifecycle, next_action,
      next_action_due, priority_score, notes, created_by
    ) values (
      v_org_id, v_project_id, coalesce(nullif(p_contact->>'contactType', ''), 'KOL'), v_name,
      nullif(p_contact->>'organization', ''), nullif(p_contact->>'email', ''),
      nullif(p_contact->>'phone', ''), coalesce(nullif(p_contact->>'primaryChannel', ''), 'Email'),
      nullif(p_contact->>'sourceUrl', ''), nullif(p_contact->>'tags', ''), v_owner_id,
      coalesce(nullif(p_contact->>'lifecycle', ''), 'new'), nullif(p_contact->>'nextAction', ''),
      nullif(p_contact->>'nextActionDue', '')::date,
      greatest(0, least(100, coalesce(nullif(p_contact->>'priorityScore', '')::integer, 50))),
      nullif(p_contact->>'notes', ''), auth.uid()
    ) returning * into v_saved_contact;
    v_contact_id := v_saved_contact.id;
  else
    update public.crm_contacts contact set
      contact_type = case when p_contact ? 'contactType' then coalesce(nullif(p_contact->>'contactType', ''), contact.contact_type) else contact.contact_type end,
      name = v_name,
      organization_name = case when p_contact ? 'organization' then nullif(p_contact->>'organization', '') else contact.organization_name end,
      email = case when p_contact ? 'email' then nullif(p_contact->>'email', '') else contact.email end,
      phone = case when p_contact ? 'phone' then nullif(p_contact->>'phone', '') else contact.phone end,
      primary_channel = case when p_contact ? 'primaryChannel' then coalesce(nullif(p_contact->>'primaryChannel', ''), contact.primary_channel) else contact.primary_channel end,
      source_url = case when p_contact ? 'sourceUrl' then nullif(p_contact->>'sourceUrl', '') else contact.source_url end,
      tags = case when p_contact ? 'tags' then nullif(p_contact->>'tags', '') else contact.tags end,
      owner_id = v_owner_id,
      lifecycle = case when p_contact ? 'lifecycle' then coalesce(nullif(p_contact->>'lifecycle', ''), contact.lifecycle) else contact.lifecycle end,
      next_action = case when p_contact ? 'nextAction' then nullif(p_contact->>'nextAction', '') else contact.next_action end,
      next_action_due = case when p_contact ? 'nextActionDue' then nullif(p_contact->>'nextActionDue', '')::date else contact.next_action_due end,
      priority_score = case when nullif(p_contact->>'priorityScore', '') is not null then greatest(0, least(100, (p_contact->>'priorityScore')::integer)) else contact.priority_score end,
      notes = case when p_contact ? 'notes' then nullif(p_contact->>'notes', '') else contact.notes end,
      updated_at = clock_timestamp()
    where contact.id = v_contact_id
    returning contact.* into v_saved_contact;
  end if;

  if v_saved_contact.email is not null then
    if lower(v_saved_contact.primary_channel) = 'email' then
      update public.crm_contact_methods method set is_primary = false, updated_at = clock_timestamp()
      where method.contact_id = v_saved_contact.id and method.method_type = 'email' and method.value <> v_saved_contact.email and method.is_primary;
    end if;
    insert into public.crm_contact_methods (
      organization_id, project_id, contact_id, method_type, value, label, is_primary
    ) values (
      v_org_id, v_project_id, v_saved_contact.id, 'email', v_saved_contact.email,
      'Canonical email', lower(v_saved_contact.primary_channel) = 'email'
    ) on conflict (contact_id, method_type, value) do update set
      is_primary = excluded.is_primary, updated_at = clock_timestamp();
  end if;
  if v_saved_contact.phone is not null then
    if lower(v_saved_contact.primary_channel) = 'phone' then
      update public.crm_contact_methods method set is_primary = false, updated_at = clock_timestamp()
      where method.contact_id = v_saved_contact.id and method.method_type = 'phone' and method.value <> v_saved_contact.phone and method.is_primary;
    end if;
    insert into public.crm_contact_methods (
      organization_id, project_id, contact_id, method_type, value, label, is_primary
    ) values (
      v_org_id, v_project_id, v_saved_contact.id, 'phone', v_saved_contact.phone,
      'Canonical phone', lower(v_saved_contact.primary_channel) = 'phone'
    ) on conflict (contact_id, method_type, value) do update set
      is_primary = excluded.is_primary, updated_at = clock_timestamp();
  end if;

  if v_candidate_id is not null then
    select candidate.* into v_before_candidate
    from public.candidates candidate
    where candidate.id = v_candidate_id
      and candidate.organization_id = v_org_id
      and candidate.project_id = v_project_id
      and candidate.crm_contact_id = v_contact_id
    for update;
    if v_before_candidate.id is null then raise exception 'OUTREACH_CANDIDATE_SCOPE_INVALID'; end if;
  else
    select candidate.* into v_before_candidate
    from public.candidates candidate
    where candidate.organization_id = v_org_id
      and candidate.project_id = v_project_id
      and candidate.crm_contact_id = v_contact_id
    for update;
    v_candidate_id := v_before_candidate.id;
  end if;

  v_before := jsonb_build_object(
    'contact', case when v_before_contact.id is null then null else to_jsonb(v_before_contact) end,
    'candidate', case when v_before_candidate.id is null then null else to_jsonb(v_before_candidate) end
  );

  if not v_create_outreach and v_candidate_id is null then
    insert into public.outreach_audit_events (
      organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
    ) values (
      v_org_id, v_project_id, auth.uid(), v_saved_contact.id, null,
      case when v_before_contact.id is null then 'crm_contact_created' else 'crm_contact_updated' end,
      jsonb_build_object(
        'before', v_before,
        'after', jsonb_build_object('contact', to_jsonb(v_saved_contact), 'candidate', null),
        'createOutreach', false
      )
    );
    select contact.* into v_saved_contact
    from public.crm_contacts contact where contact.id = v_saved_contact.id;
    return jsonb_build_object(
      'contactId', v_saved_contact.id,
      'candidateId', null,
      'campaignId', null,
      'stageId', null,
      'ownerId', v_saved_contact.owner_id,
      'updatedAt', v_saved_contact.updated_at
    );
  end if;

  if v_candidate_id is null then
    insert into public.candidates (
      organization_id, project_id, crm_contact_id, external_id, source_label,
      name, category, platforms, reach, tier, creator_type, content_fit, fit_level,
      contact_readiness, contact_channel, contact_detail, source_url,
      pmf_candidate, pmf_rationale, priority_score, priority_band,
      owner_id, assigned_to, outreach_status, interest_level, preferred_collaboration,
      deck_introduced, pmf_asked, first_outreach, follow_up_1, follow_up_2,
      response_date, next_step, next_step_due, notes, source_updated_on, created_by
    ) values (
      v_org_id, v_project_id, v_saved_contact.id, nullif(p_outreach->>'externalId', ''),
      nullif(p_outreach->>'source', ''), v_saved_contact.name, v_saved_contact.contact_type,
      nullif(p_outreach->>'platforms', ''), nullif(p_outreach->>'reach', ''), nullif(p_outreach->>'tier', ''),
      nullif(p_outreach->>'creatorType', ''), nullif(p_outreach->>'contentFit', ''), nullif(p_outreach->>'fitLevel', ''),
      coalesce(nullif(p_outreach->>'contactReadiness', ''), 'Research needed'),
      v_saved_contact.primary_channel,
      coalesce(nullif(p_outreach->>'contactDetail', ''),
        case when lower(v_saved_contact.primary_channel) = 'email' then v_saved_contact.email
             when lower(v_saved_contact.primary_channel) = 'phone' then v_saved_contact.phone end),
      v_saved_contact.source_url, coalesce(nullif(p_outreach->>'pmfCandidate', '')::boolean, false),
      nullif(p_outreach->>'pmfRationale', ''), v_saved_contact.priority_score,
      nullif(p_outreach->>'priorityBand', ''), v_assigned_to, v_assigned_to,
      coalesce(nullif(p_outreach->>'outreachStatus', ''), 'Not Contacted'),
      coalesce(nullif(p_outreach->>'interestLevel', ''), 'Unknown'),
      nullif(p_outreach->>'preferredCollaboration', ''),
      coalesce(nullif(p_outreach->>'deckIntroduced', '')::boolean, false),
      coalesce(nullif(p_outreach->>'pmfAsked', '')::boolean, false),
      nullif(p_outreach->>'firstOutreach', '')::date,
      nullif(p_outreach->>'followUp1', '')::date, nullif(p_outreach->>'followUp2', '')::date,
      nullif(p_outreach->>'responseDate', '')::date,
      v_saved_contact.next_action, v_saved_contact.next_action_due,
      v_saved_contact.notes, nullif(p_outreach->>'sourceUpdatedOn', '')::date, auth.uid()
    ) returning * into v_saved_candidate;
    v_candidate_id := v_saved_candidate.id;
  else
    update public.candidates candidate set
      name = v_saved_contact.name,
      category = v_saved_contact.contact_type,
      source_label = case when p_outreach ? 'source' then nullif(p_outreach->>'source', '') else candidate.source_label end,
      platforms = case when p_outreach ? 'platforms' then nullif(p_outreach->>'platforms', '') else candidate.platforms end,
      reach = case when p_outreach ? 'reach' then nullif(p_outreach->>'reach', '') else candidate.reach end,
      tier = case when p_outreach ? 'tier' then nullif(p_outreach->>'tier', '') else candidate.tier end,
      creator_type = case when p_outreach ? 'creatorType' then nullif(p_outreach->>'creatorType', '') else candidate.creator_type end,
      content_fit = case when p_outreach ? 'contentFit' then nullif(p_outreach->>'contentFit', '') else candidate.content_fit end,
      fit_level = case when p_outreach ? 'fitLevel' then nullif(p_outreach->>'fitLevel', '') else candidate.fit_level end,
      contact_readiness = case when p_outreach ? 'contactReadiness' then coalesce(nullif(p_outreach->>'contactReadiness', ''), candidate.contact_readiness) else candidate.contact_readiness end,
      contact_channel = v_saved_contact.primary_channel,
      contact_detail = case
        when p_outreach ? 'contactDetail' then nullif(p_outreach->>'contactDetail', '')
        when lower(v_saved_contact.primary_channel) = 'email' then v_saved_contact.email
        when lower(v_saved_contact.primary_channel) = 'phone' then v_saved_contact.phone
        else candidate.contact_detail
      end,
      source_url = v_saved_contact.source_url,
      pmf_candidate = case when nullif(p_outreach->>'pmfCandidate', '') is not null then (p_outreach->>'pmfCandidate')::boolean else candidate.pmf_candidate end,
      pmf_rationale = case when p_outreach ? 'pmfRationale' then nullif(p_outreach->>'pmfRationale', '') else candidate.pmf_rationale end,
      priority_score = v_saved_contact.priority_score,
      priority_band = case when p_outreach ? 'priorityBand' then nullif(p_outreach->>'priorityBand', '') else candidate.priority_band end,
      owner_id = v_assigned_to,
      assigned_to = v_assigned_to,
      outreach_status = case when p_outreach ? 'outreachStatus' then coalesce(nullif(p_outreach->>'outreachStatus', ''), candidate.outreach_status) else candidate.outreach_status end,
      interest_level = case when p_outreach ? 'interestLevel' then coalesce(nullif(p_outreach->>'interestLevel', ''), candidate.interest_level) else candidate.interest_level end,
      preferred_collaboration = case when p_outreach ? 'preferredCollaboration' then nullif(p_outreach->>'preferredCollaboration', '') else candidate.preferred_collaboration end,
      deck_introduced = case when nullif(p_outreach->>'deckIntroduced', '') is not null then (p_outreach->>'deckIntroduced')::boolean else candidate.deck_introduced end,
      pmf_asked = case when nullif(p_outreach->>'pmfAsked', '') is not null then (p_outreach->>'pmfAsked')::boolean else candidate.pmf_asked end,
      first_outreach = case when p_outreach ? 'firstOutreach' then nullif(p_outreach->>'firstOutreach', '')::date else candidate.first_outreach end,
      follow_up_1 = case when p_outreach ? 'followUp1' then nullif(p_outreach->>'followUp1', '')::date else candidate.follow_up_1 end,
      follow_up_2 = case when p_outreach ? 'followUp2' then nullif(p_outreach->>'followUp2', '')::date else candidate.follow_up_2 end,
      response_date = case when p_outreach ? 'responseDate' then nullif(p_outreach->>'responseDate', '')::date else candidate.response_date end,
      next_step = v_saved_contact.next_action,
      next_step_due = v_saved_contact.next_action_due,
      notes = v_saved_contact.notes,
      source_updated_on = case when p_outreach ? 'sourceUpdatedOn' then nullif(p_outreach->>'sourceUpdatedOn', '')::date else candidate.source_updated_on end,
      updated_at = clock_timestamp()
    where candidate.id = v_candidate_id
    returning candidate.* into v_saved_candidate;
  end if;

  select campaign.id into v_campaign_id
  from public.outreach_campaigns campaign
  where campaign.organization_id = v_org_id and campaign.project_id = v_project_id
  order by campaign.created_at, campaign.id limit 1;
  if v_campaign_id is null then raise exception 'OUTREACH_CAMPAIGN_REQUIRED'; end if;

  if nullif(p_outreach->>'stageId', '') is not null then
    select stage.id into v_stage_id
    from public.outreach_stage_definitions stage
    where stage.id = (p_outreach->>'stageId')::uuid
      and stage.organization_id = v_org_id and stage.project_id = v_project_id
      and stage.campaign_id = v_campaign_id and stage.active;
  else
    v_outreach_status := v_saved_candidate.outreach_status;
    select stage.id into v_stage_id
    from public.outreach_stage_definitions stage
    where stage.campaign_id = v_campaign_id
      and stage.stage_key = case
        when v_outreach_status = 'Ready to Send' then 'ready_to_send'
        when v_outreach_status in ('Sent','Contacted','Drafted') then 'sent'
        when v_outreach_status in ('Follow-up 1','Follow-up 2','No Response') then 'follow_up_due'
        when v_outreach_status in ('Replied','Meeting Booked') then 'responded'
        when v_outreach_status in ('Interested','Negotiating') then 'interested'
        when v_outreach_status = 'Confirmed' then 'confirmed'
        when v_outreach_status = 'Declined' then 'declined'
        when v_outreach_status = 'Unreachable' then 'unreachable'
        else 'research_needed'
      end;
  end if;
  if v_stage_id is null then raise exception 'OUTREACH_STAGE_INVALID'; end if;

  insert into public.outreach_campaign_memberships (
    organization_id, project_id, campaign_id, contact_id, candidate_id,
    stage_id, assigned_to, membership_status, entered_stage_at
  ) values (
    v_org_id, v_project_id, v_campaign_id, v_saved_contact.id, v_saved_candidate.id,
    v_stage_id, v_assigned_to,
    case when exists (
      select 1 from public.outreach_stage_definitions stage
      where stage.id = v_stage_id and stage.semantic_family = 'closed'
    ) then 'closed' else 'active' end,
    clock_timestamp()
  ) on conflict (campaign_id, contact_id) do update set
    candidate_id = excluded.candidate_id,
    stage_id = excluded.stage_id,
    assigned_to = excluded.assigned_to,
    membership_status = excluded.membership_status,
    entered_stage_at = case
      when public.outreach_campaign_memberships.stage_id is distinct from excluded.stage_id
      then excluded.entered_stage_at
      else public.outreach_campaign_memberships.entered_stage_at
    end,
    updated_at = clock_timestamp();

  insert into public.outreach_audit_events (
    organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
  ) values (
    v_org_id, v_project_id, auth.uid(), v_saved_contact.id, v_saved_candidate.id,
    case when v_before_contact.id is null then 'relationship_created' else 'relationship_updated' end,
    jsonb_build_object(
      'before', v_before,
      'after', jsonb_build_object('contact', to_jsonb(v_saved_contact), 'candidate', to_jsonb(v_saved_candidate)),
      'stageId', v_stage_id
    )
  );

  select contact.* into v_saved_contact
  from public.crm_contacts contact where contact.id = v_saved_contact.id;

  return jsonb_build_object(
    'contactId', v_saved_contact.id,
    'candidateId', v_saved_candidate.id,
    'campaignId', v_campaign_id,
    'stageId', v_stage_id,
    'ownerId', v_saved_contact.owner_id,
    'updatedAt', v_saved_contact.updated_at
  );
end;
$$;

drop function if exists public.rpc_aoi_log_relationship_activity(uuid,text,text,text,text,jsonb);
create function public.rpc_aoi_log_relationship_activity(
  p_contact_id uuid,
  p_activity_type text,
  p_summary text,
  p_channel text default null,
  p_status text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_candidate_id uuid;
  v_activity_id uuid;
  v_contact public.crm_contacts%rowtype;
begin
  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller
    on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(p_activity_type, ''))) < 2 then raise exception 'OUTREACH_ACTIVITY_TYPE_REQUIRED'; end if;
  if length(trim(coalesce(p_summary, ''))) < 3 then raise exception 'OUTREACH_ACTIVITY_SUMMARY_REQUIRED'; end if;
  if coalesce(jsonb_typeof(p_metadata), 'null') <> 'object' then raise exception 'OUTREACH_ACTIVITY_METADATA_INVALID'; end if;

  select contact.* into v_contact
  from public.crm_contacts contact
  where contact.id = p_contact_id
    and contact.organization_id = v_org_id
    and contact.project_id = v_project_id;
  if v_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  if not (
    v_role = 'admin'
    or v_contact.owner_id = auth.uid()
    or exists (
      select 1 from public.outreach_campaign_memberships membership
      where membership.organization_id = v_org_id
        and membership.project_id = v_project_id
        and membership.contact_id = p_contact_id
        and membership.assigned_to = auth.uid()
    )
  ) then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
  select candidate.id into v_candidate_id
  from public.candidates candidate
  where candidate.crm_contact_id = p_contact_id
    and candidate.organization_id = v_org_id
    and candidate.project_id = v_project_id;

  insert into public.relationship_activities (
    organization_id, project_id, contact_id, candidate_id, actor_id,
    activity_type, summary, channel, status, metadata
  ) values (
    v_org_id, v_project_id, p_contact_id, v_candidate_id, auth.uid(),
    trim(p_activity_type), trim(p_summary), nullif(trim(p_channel), ''),
    nullif(trim(p_status), ''), coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_activity_id;

  insert into public.outreach_audit_events (
    organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
  ) values (
    v_org_id, v_project_id, auth.uid(), p_contact_id, v_candidate_id,
    'activity_logged', jsonb_build_object(
      'activityId', v_activity_id, 'activityType', trim(p_activity_type),
      'channel', nullif(trim(p_channel), ''), 'status', nullif(trim(p_status), '')
    )
  );

  return jsonb_build_object(
    'id', v_activity_id, 'contactId', p_contact_id,
    'candidateId', v_candidate_id, 'occurredAt', clock_timestamp()
  );
end;
$$;

-- Preserve the CRM payload contract while sharing linked relationships and unified activity.
create or replace function public.rpc_aoi_crm_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
begin
  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller
    on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  select project.id into v_project_id
  from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'crmContacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', contact.id, 'candidateId', candidate.id, 'contactType', contact.contact_type,
        'name', contact.name, 'organization', contact.organization_name, 'email', contact.email,
        'phone', contact.phone, 'primaryChannel', contact.primary_channel,
        'sourceUrl', contact.source_url, 'tags', contact.tags,
        'ownerId', contact.owner_id, 'ownerName', owner.display_name,
        'lifecycle', contact.lifecycle, 'nextAction', contact.next_action,
        'nextActionDue', contact.next_action_due, 'priorityScore', contact.priority_score,
        'notes', contact.notes, 'updatedAt', contact.updated_at,
        'outreachStatus', candidate.outreach_status,
        'category', candidate.category, 'pmfCandidate', candidate.pmf_candidate,
        'activityCount', (
          select count(*) from public.relationship_activities activity
          where activity.contact_id = contact.id
            and activity.organization_id = contact.organization_id
            and activity.project_id = contact.project_id
        )
      ) order by contact.next_action_due nulls last, contact.priority_score desc)
      from public.crm_contacts contact
      left join public.candidates candidate
        on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id
        and candidate.project_id = contact.project_id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.organization_id = v_org_id and contact.project_id = v_project_id
        and (v_role = 'admin' or contact.owner_id = auth.uid() or candidate.id is not null)
    ), '[]'::jsonb),
    'crmActivity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', activity.id, 'contactId', activity.contact_id,
        'activityType', activity.activity_type, 'summary', activity.summary,
        'actorName', coalesce(actor.display_name, 'AOI'), 'createdAt', activity.occurred_at
      ) order by activity.occurred_at desc, activity.id desc)
      from public.relationship_activities activity
      join public.crm_contacts contact
        on contact.id = activity.contact_id
        and contact.organization_id = activity.organization_id
        and contact.project_id = activity.project_id
      left join public.candidates candidate
        on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id
        and candidate.project_id = contact.project_id
      left join public.profiles actor on actor.id = activity.actor_id
      where activity.organization_id = v_org_id and activity.project_id = v_project_id
        and (v_role = 'admin' or contact.owner_id = auth.uid() or candidate.id is not null)
    ), '[]'::jsonb),
    'crmProgress', jsonb_build_object(
      'xp', coalesce((select sum(reward.points) from public.crm_reward_events reward
        where reward.project_id = v_project_id and reward.actor_id = auth.uid()), 0),
      'completedToday', coalesce((select count(*) from public.crm_reward_events reward
        where reward.project_id = v_project_id and reward.actor_id = auth.uid()
          and reward.reward_date = current_date), 0),
      'streakDays', coalesce((select count(distinct reward.reward_date)
        from public.crm_reward_events reward
        where reward.project_id = v_project_id and reward.actor_id = auth.uid()
          and reward.reward_date >= current_date - 6), 0)
    )
  );
end;
$$;

revoke all on function public.rpc_aoi_outreach_foundation_snapshot() from public, anon;
revoke all on function public.rpc_aoi_save_relationship(jsonb,jsonb,timestamptz) from public, anon;
revoke all on function public.rpc_aoi_log_relationship_activity(uuid,text,text,text,text,jsonb) from public, anon;
revoke all on function public.rpc_aoi_crm_snapshot() from public, anon;
grant execute on function public.rpc_aoi_outreach_foundation_snapshot() to authenticated;
grant execute on function public.rpc_aoi_save_relationship(jsonb,jsonb,timestamptz) to authenticated;
grant execute on function public.rpc_aoi_log_relationship_activity(uuid,text,text,text,text,jsonb) to authenticated;
grant execute on function public.rpc_aoi_crm_snapshot() to authenticated;

-- Add aggregate versions to the existing Operations payload without duplicating its projection.
alter function public.rpc_aoi_operations_snapshot()
  rename to rpc_aoi_operations_snapshot_unversioned;
revoke all on function public.rpc_aoi_operations_snapshot_unversioned() from public, anon;
grant execute on function public.rpc_aoi_operations_snapshot_unversioned() to authenticated;

create function public.rpc_aoi_operations_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_candidates jsonb;
begin
  v_snapshot := public.rpc_aoi_operations_snapshot_unversioned();
  select coalesce(jsonb_agg(
    item || jsonb_build_object('updatedAt', contact.updated_at)
    order by ordinal
  ), '[]'::jsonb)
  into v_candidates
  from jsonb_array_elements(coalesce(v_snapshot->'candidates', '[]'::jsonb))
    with ordinality as candidate_item(item, ordinal)
  join public.candidates candidate on candidate.id = (item->>'id')::uuid
  join public.crm_contacts contact on contact.id = candidate.crm_contact_id
    and contact.organization_id = candidate.organization_id
    and contact.project_id = candidate.project_id;
  return jsonb_set(v_snapshot, '{candidates}', v_candidates, true);
end;
$$;
revoke all on function public.rpc_aoi_operations_snapshot() from public, anon;
grant execute on function public.rpc_aoi_operations_snapshot() to authenticated;

insert into public.relationship_activities (
  organization_id, project_id, contact_id, candidate_id, actor_id, activity_type,
  summary, channel, status, metadata, occurred_at, legacy_source, legacy_id, created_at
)
select event.organization_id, event.project_id, candidate.crm_contact_id, candidate.id,
  event.actor_id, 'outreach', event.summary, event.channel, event.status,
  jsonb_build_object('kind', event.kind, 'providerMessageId', event.provider_message_id),
  event.occurred_at, 'outreach_events', event.id, event.created_at
from public.outreach_events event
join public.candidates candidate
  on candidate.id = event.candidate_id
  and candidate.organization_id = event.organization_id
  and candidate.project_id = event.project_id
on conflict (legacy_source, legacy_id) where legacy_source is not null do nothing;

-- Keep current browser RPCs functional until the Outreach page adopts the new contracts.
create or replace function public.rpc_aoi_upsert_candidate(p_candidate jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_candidate public.candidates%rowtype;
  v_contact public.crm_contacts%rowtype;
  v_contact_payload jsonb;
  v_outreach_payload jsonb;
  v_saved jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  if coalesce(p_candidate->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select candidate.* into v_candidate from public.candidates candidate
    where candidate.id = (p_candidate->>'id')::uuid
      and candidate.organization_id = v_org_id and candidate.project_id = v_project_id;
  elsif nullif(p_candidate->>'externalId', '') is not null then
    select candidate.* into v_candidate from public.candidates candidate
    where candidate.project_id = v_project_id and candidate.external_id = p_candidate->>'externalId';
  end if;
  if nullif(p_candidate->>'id', '') is not null and v_candidate.id is null
    and coalesce(p_candidate->>'id', '') not like 'local-%' then
    raise exception 'CANDIDATE_NOT_FOUND';
  end if;
  if v_candidate.id is not null then
    select contact.* into v_contact from public.crm_contacts contact
    where contact.id = v_candidate.crm_contact_id
      and contact.organization_id = v_org_id and contact.project_id = v_project_id;
  end if;

  v_contact_payload := jsonb_strip_nulls(jsonb_build_object(
    'id', v_contact.id,
    'name', coalesce(nullif(p_candidate->>'name', ''), v_contact.name),
    'contactType', coalesce(nullif(p_candidate->>'category', ''), v_contact.contact_type),
    'primaryChannel', coalesce(nullif(p_candidate->>'contactChannel', ''), v_contact.primary_channel),
    'sourceUrl', case when p_candidate ? 'sourceUrl' then nullif(p_candidate->>'sourceUrl', '') else v_contact.source_url end,
    'nextAction', case when p_candidate ? 'nextStep' then nullif(p_candidate->>'nextStep', '') else v_contact.next_action end,
    'nextActionDue', case when p_candidate ? 'nextStepDue' then nullif(p_candidate->>'nextStepDue', '') else v_contact.next_action_due::text end,
    'priorityScore', coalesce(nullif(p_candidate->>'priorityScore', '')::integer, v_contact.priority_score, 50),
    'notes', case when p_candidate ? 'notes' then nullif(p_candidate->>'notes', '') else v_contact.notes end,
    'ownerId', nullif(p_candidate->>'ownerId', '')::uuid
  ));
  if trim(coalesce(p_candidate->>'contactDetail', ''))
    ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    v_contact_payload := v_contact_payload || jsonb_build_object('email', trim(p_candidate->>'contactDetail'));
  elsif trim(coalesce(p_candidate->>'contactDetail', ''))
    ~ '^\+?[0-9][0-9 ()-]{5,}[0-9]$' then
    v_contact_payload := v_contact_payload || jsonb_build_object('phone', trim(p_candidate->>'contactDetail'));
  end if;
  v_outreach_payload := p_candidate || case
    when v_candidate.id is null then '{}'::jsonb
    else jsonb_build_object('candidateId', v_candidate.id)
  end;

  v_saved := public.rpc_aoi_save_relationship(
    v_contact_payload,
    v_outreach_payload,
    case
      when v_contact.id is null then null
      else nullif(p_candidate->>'updatedAt', '')::timestamptz
    end
  );
  select candidate.* into v_candidate from public.candidates candidate
  where candidate.id = (v_saved->>'candidateId')::uuid;
  return jsonb_build_object(
    'id', v_candidate.id, 'externalId', v_candidate.external_id,
    'name', v_candidate.name, 'category', v_candidate.category,
    'ownerId', v_candidate.assigned_to, 'outreachStatus', v_candidate.outreach_status,
    'workflowStatus', v_candidate.workflow_status, 'updatedAt', v_saved->>'updatedAt'
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_crm_contact(contact jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_contact public.crm_contacts%rowtype;
  v_candidate_id uuid;
  v_saved jsonb;
  v_points integer := 35;
  v_awarded integer := 0;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  if nullif(contact->>'id', '') is not null then
    select existing.* into v_contact from public.crm_contacts existing
    where existing.id = (contact->>'id')::uuid
      and existing.organization_id = v_org_id and existing.project_id = v_project_id;
    if v_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  end if;
  v_candidate_id := nullif(contact->>'candidateId', '')::uuid;
  if v_candidate_id is null and v_contact.id is not null then
    select candidate.id into v_candidate_id from public.candidates candidate
    where candidate.crm_contact_id = v_contact.id
      and candidate.organization_id = v_org_id and candidate.project_id = v_project_id;
  end if;

  v_saved := public.rpc_aoi_save_relationship(
    contact,
    jsonb_strip_nulls(jsonb_build_object(
      'candidateId', v_candidate_id,
      'createOutreach', coalesce(
        nullif(contact->>'createOutreach', '')::boolean,
        v_candidate_id is not null
      ),
      'outreachStatus', nullif(contact->>'outreachStatus', ''),
      'pmfCandidate', nullif(contact->>'pmfCandidate', '')::boolean
    )),
    case
      when v_contact.id is null then null
      else nullif(contact->>'updatedAt', '')::timestamptz
    end
  );
  perform public.rpc_aoi_log_relationship_activity(
    (v_saved->>'contactId')::uuid, 'enrich', 'Contact record saved'
  );
  select existing.* into v_contact from public.crm_contacts existing
  where existing.id = (v_saved->>'contactId')::uuid;
  if v_contact.source_url is not null and v_contact.next_action is not null and v_contact.next_action_due is not null then
    v_points := v_points + 10;
  end if;
  insert into public.crm_reward_events (
    organization_id, project_id, contact_id, actor_id, action, points
  ) values (
    v_org_id, v_project_id, v_contact.id, auth.uid(), 'enrich', v_points
  ) on conflict do nothing returning points into v_awarded;
  return jsonb_build_object(
    'id', v_contact.id, 'candidateId', (v_saved->>'candidateId')::uuid,
    'ownerId', v_contact.owner_id, 'name', v_contact.name,
    'rewardPoints', coalesce(v_awarded, 0), 'updatedAt', v_contact.updated_at
  );
end;
$$;

-- Mirror future calls to legacy activity RPCs into the append-only relationship stream.
create or replace function private.mirror_legacy_relationship_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_activity_id uuid;
  v_candidate_id uuid;
begin
  if tg_table_name = 'crm_activity' then
    insert into public.relationship_activities (
      organization_id, project_id, contact_id, candidate_id, actor_id,
      activity_type, summary, metadata, occurred_at, legacy_source, legacy_id, created_at
    )
    select new.organization_id, new.project_id, new.contact_id, candidate.id,
      new.actor_id, new.activity_type, new.summary, '{}'::jsonb,
      new.created_at, 'crm_activity', new.id, new.created_at
    from (select 1) source
    left join public.candidates candidate
      on candidate.crm_contact_id = new.contact_id
      and candidate.organization_id = new.organization_id
      and candidate.project_id = new.project_id
    on conflict (legacy_source, legacy_id) where legacy_source is not null do nothing
    returning id, candidate_id into v_activity_id, v_candidate_id;
    if v_activity_id is not null then
      insert into public.outreach_audit_events (
        organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
      ) values (
        new.organization_id, new.project_id, new.actor_id, new.contact_id, v_candidate_id,
        'legacy_crm_activity_logged',
        jsonb_build_object('activityId', v_activity_id, 'legacyId', new.id)
      );
    end if;
  elsif tg_table_name = 'outreach_events' then
    insert into public.relationship_activities (
      organization_id, project_id, contact_id, candidate_id, actor_id,
      activity_type, summary, channel, status, metadata, occurred_at,
      legacy_source, legacy_id, created_at
    )
    select new.organization_id, new.project_id, candidate.crm_contact_id, candidate.id,
      new.actor_id, 'outreach', new.summary, new.channel, new.status,
      jsonb_build_object('kind', new.kind, 'providerMessageId', new.provider_message_id),
      new.occurred_at, 'outreach_events', new.id, new.created_at
    from public.candidates candidate
    where candidate.id = new.candidate_id
      and candidate.organization_id = new.organization_id
      and candidate.project_id = new.project_id
    on conflict (legacy_source, legacy_id) where legacy_source is not null do nothing
    returning id, candidate_id into v_activity_id, v_candidate_id;
    if v_activity_id is not null then
      insert into public.outreach_audit_events (
        organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
      ) values (
        new.organization_id, new.project_id, new.actor_id,
        (select candidate.crm_contact_id from public.candidates candidate where candidate.id = new.candidate_id),
        v_candidate_id, 'legacy_outreach_logged',
        jsonb_build_object('activityId', v_activity_id, 'legacyId', new.id)
      );
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.mirror_legacy_relationship_activity() from public, anon, authenticated;

drop trigger if exists mirror_legacy_relationship_activity on public.crm_activity;
create trigger mirror_legacy_relationship_activity
after insert on public.crm_activity
for each row execute function private.mirror_legacy_relationship_activity();
drop trigger if exists mirror_legacy_relationship_activity on public.outreach_events;
create trigger mirror_legacy_relationship_activity
after insert on public.outreach_events
for each row execute function private.mirror_legacy_relationship_activity();

create or replace function private.sync_candidate_campaign_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_id uuid;
  v_stage_id uuid;
  v_semantic_family text;
begin
  select campaign.id into v_campaign_id
  from public.outreach_campaigns campaign
  where campaign.organization_id = new.organization_id and campaign.project_id = new.project_id
  order by campaign.created_at, campaign.id limit 1;
  if v_campaign_id is null or new.crm_contact_id is null or new.assigned_to is null then return new; end if;

  select stage.id, stage.semantic_family into v_stage_id, v_semantic_family
  from public.outreach_stage_definitions stage
  where stage.campaign_id = v_campaign_id
    and stage.stage_key = case
      when new.outreach_status = 'Ready to Send' then 'ready_to_send'
      when new.outreach_status in ('Sent','Contacted','Drafted') then 'sent'
      when new.outreach_status in ('Follow-up 1','Follow-up 2','No Response') then 'follow_up_due'
      when new.outreach_status in ('Replied','Meeting Booked') then 'responded'
      when new.outreach_status in ('Interested','Negotiating') then 'interested'
      when new.outreach_status = 'Confirmed' then 'confirmed'
      when new.outreach_status = 'Declined' then 'declined'
      when new.outreach_status = 'Unreachable' then 'unreachable'
      else 'research_needed'
    end;
  if v_stage_id is null then return new; end if;

  insert into public.outreach_campaign_memberships (
    organization_id, project_id, campaign_id, contact_id, candidate_id,
    stage_id, assigned_to, membership_status, entered_stage_at
  ) values (
    new.organization_id, new.project_id, v_campaign_id, new.crm_contact_id, new.id,
    v_stage_id, new.assigned_to,
    case when v_semantic_family = 'closed' then 'closed' else 'active' end,
    clock_timestamp()
  ) on conflict (campaign_id, contact_id) do update set
    candidate_id = excluded.candidate_id,
    stage_id = excluded.stage_id,
    assigned_to = excluded.assigned_to,
    membership_status = excluded.membership_status,
    entered_stage_at = case
      when public.outreach_campaign_memberships.stage_id is distinct from excluded.stage_id
      then excluded.entered_stage_at
      else public.outreach_campaign_memberships.entered_stage_at
    end,
    updated_at = clock_timestamp();
  return new;
end;
$$;
revoke all on function private.sync_candidate_campaign_membership() from public, anon, authenticated;
drop trigger if exists sync_candidate_campaign_membership on public.candidates;
create trigger sync_candidate_campaign_membership
after insert or update of crm_contact_id, assigned_to, outreach_status on public.candidates
for each row execute function private.sync_candidate_campaign_membership();

create or replace function private.touch_relationship_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact_id uuid;
begin
  if tg_table_name = 'candidates' then
    v_contact_id := case when tg_op = 'DELETE' then old.crm_contact_id else new.crm_contact_id end;
  else
    v_contact_id := case when tg_op = 'DELETE' then old.contact_id else new.contact_id end;
  end if;
  if v_contact_id is not null then
    update public.crm_contacts contact
    set updated_at = clock_timestamp()
    where contact.id = v_contact_id;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function private.touch_relationship_version() from public, anon, authenticated;

create trigger touch_relationship_version
after insert or update or delete on public.candidates
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.outreach_campaign_memberships
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.crm_contact_methods
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.crm_communication_preferences
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.relationship_activities
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.outreach_research
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.outreach_tasks
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.outreach_meetings
for each row execute function private.touch_relationship_version();
create trigger touch_relationship_version
after insert or update or delete on public.outreach_offers
for each row execute function private.touch_relationship_version();

create or replace function public.rpc_aoi_log_outreach(
  p_candidate_id uuid,
  p_event_channel text,
  p_event_kind text,
  p_event_status text,
  p_event_summary text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_contact_id uuid;
  v_event public.outreach_events%rowtype;
begin
  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id limit 1;
  select candidate.project_id, candidate.crm_contact_id
  into v_project_id, v_contact_id
  from public.candidates candidate
  where candidate.id = p_candidate_id and candidate.organization_id = v_org_id;
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if not (
    v_role = 'admin'
    or exists (
      select 1 from public.outreach_campaign_memberships membership
      where membership.organization_id = v_org_id
        and membership.project_id = v_project_id
        and membership.contact_id = v_contact_id
        and membership.candidate_id = p_candidate_id
        and membership.assigned_to = auth.uid()
    )
  ) then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
  if length(trim(coalesce(p_event_summary, ''))) < 3 then
    raise exception 'OUTREACH_ACTIVITY_SUMMARY_REQUIRED';
  end if;

  insert into public.outreach_events (
    organization_id, project_id, candidate_id, channel, kind, status, actor_id, summary
  ) values (
    v_org_id, v_project_id, p_candidate_id, p_event_channel,
    coalesce(nullif(p_event_kind, ''), 'Initial'),
    coalesce(nullif(p_event_status, ''), 'Drafted'), auth.uid(), trim(p_event_summary)
  ) returning * into v_event;
  update public.candidates candidate set
    outreach_status = case
      when p_event_status in ('Sent','Replied','Interested','Confirmed') then p_event_status
      else candidate.outreach_status
    end,
    updated_at = clock_timestamp()
  where candidate.id = p_candidate_id;
  return jsonb_build_object('id', v_event.id, 'candidateId', v_event.candidate_id);
end;
$$;

drop function if exists public.rpc_aoi_set_communication_preference(uuid,jsonb,timestamptz);
create function public.rpc_aoi_set_communication_preference(
  p_contact_id uuid,
  p_preference jsonb,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_channel text;
  v_state text;
  v_allowed boolean;
  v_contact public.crm_contacts%rowtype;
  v_before public.crm_communication_preferences%rowtype;
  v_saved public.crm_communication_preferences%rowtype;
begin
  select membership.organization_id, membership.role
  into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select contact.* into v_contact from public.crm_contacts contact
  where contact.id = p_contact_id
    and contact.organization_id = v_org_id and contact.project_id = v_project_id
  for update;
  if v_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  if not (
    v_role = 'admin'
    or v_contact.owner_id = auth.uid()
    or exists (
      select 1 from public.outreach_campaign_memberships membership
      where membership.organization_id = v_org_id
        and membership.project_id = v_project_id
        and membership.contact_id = p_contact_id
        and membership.assigned_to = auth.uid()
    )
  ) then raise exception 'OUTREACH_WRITE_NOT_ASSIGNED'; end if;
  if p_expected_updated_at is null or v_contact.updated_at <> p_expected_updated_at then
    raise exception 'OUTREACH_STALE_WRITE';
  end if;

  v_channel := lower(trim(coalesce(p_preference->>'channel', '')));
  v_state := lower(trim(coalesce(p_preference->>'consentState', '')));
  if v_channel not in ('email','phone','form','website','social','other') then
    raise exception 'OUTREACH_PREFERENCE_CHANNEL_INVALID';
  end if;
  if v_state not in ('unknown','allowed','denied','withdrawn') then
    raise exception 'OUTREACH_PREFERENCE_STATE_INVALID';
  end if;
  v_allowed := case when v_state = 'allowed' then true when v_state = 'unknown' then null else false end;
  select preference.* into v_before
  from public.crm_communication_preferences preference
  where preference.contact_id = p_contact_id and preference.channel = v_channel;

  insert into public.crm_communication_preferences (
    organization_id, project_id, contact_id, channel, consent_state, allowed,
    source, evidence, effective_at
  ) values (
    v_org_id, v_project_id, p_contact_id, v_channel, v_state, v_allowed,
    nullif(trim(p_preference->>'source'), ''), nullif(trim(p_preference->>'evidence'), ''),
    coalesce(nullif(p_preference->>'effectiveAt', '')::timestamptz, clock_timestamp())
  ) on conflict (contact_id, channel) do update set
    consent_state = excluded.consent_state,
    allowed = excluded.allowed,
    source = excluded.source,
    evidence = excluded.evidence,
    effective_at = excluded.effective_at,
    updated_at = clock_timestamp()
  returning * into v_saved;
  insert into public.outreach_audit_events (
    organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
  ) values (
    v_org_id, v_project_id, auth.uid(), p_contact_id,
    (select candidate.id from public.candidates candidate where candidate.crm_contact_id = p_contact_id),
    'communication_preference_set',
    jsonb_build_object('before', case when v_before.id is null then null else to_jsonb(v_before) end, 'after', to_jsonb(v_saved))
  );
  select contact.* into v_contact from public.crm_contacts contact where contact.id = p_contact_id;
  return jsonb_build_object(
    'id', v_saved.id, 'contactId', p_contact_id, 'channel', v_saved.channel,
    'consentState', v_saved.consent_state, 'allowed', v_saved.allowed,
    'updatedAt', v_contact.updated_at
  );
end;
$$;

create or replace function public.rpc_aoi_queue_email(
  p_candidate_id uuid,
  p_recipient text,
  p_email_subject text,
  p_email_body text,
  p_send_at timestamptz default now(),
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_contact_id uuid;
  v_delivery public.email_deliveries%rowtype;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid()
    and membership.status = 'active' and membership.role = 'admin'
  order by membership.joined_at, membership.organization_id limit 1;
  if v_org_id is null then raise exception 'ADMIN_APPROVAL_REQUIRED'; end if;
  select candidate.project_id, candidate.crm_contact_id into v_project_id, v_contact_id
  from public.candidates candidate
  where candidate.id = p_candidate_id and candidate.organization_id = v_org_id;
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if exists (
    select 1 from public.crm_communication_preferences preference
    where preference.organization_id = v_org_id
      and preference.project_id = v_project_id
      and preference.contact_id = v_contact_id
      and preference.channel = 'email'
      and preference.consent_state in ('denied','withdrawn')
  ) or (
    not exists (
      select 1 from public.crm_communication_preferences preference
      where preference.organization_id = v_org_id
        and preference.project_id = v_project_id
        and preference.contact_id = v_contact_id
        and preference.channel = 'email'
    ) and exists (
      select 1 from public.contact_preferences preference
      where preference.candidate_id = p_candidate_id and preference.email_opt_out
    )
  ) then raise exception 'EMAIL_OPTED_OUT'; end if;
  if not exists (
    select 1 from public.crm_contact_methods method
    where method.organization_id = v_org_id
      and method.project_id = v_project_id
      and method.contact_id = v_contact_id
      and method.method_type = 'email'
      and method.verification_status <> 'invalid'
      and lower(method.value) = lower(trim(p_recipient))
  ) then raise exception 'EMAIL_RECIPIENT_NOT_REGISTERED'; end if;

  insert into public.email_deliveries (
    organization_id, project_id, candidate_id, template_id,
    recipient, subject, body, scheduled_for, created_by
  ) values (
    v_org_id, v_project_id, p_candidate_id, p_template_id,
    trim(p_recipient), trim(p_email_subject), p_email_body,
    coalesce(p_send_at, now()), auth.uid()
  ) returning * into v_delivery;
  insert into public.outreach_audit_events (
    organization_id, project_id, actor_id, contact_id, candidate_id, action, metadata
  ) values (
    v_org_id, v_project_id, auth.uid(), v_contact_id, p_candidate_id,
    'email_queued', jsonb_build_object('deliveryId', v_delivery.id, 'scheduledFor', v_delivery.scheduled_for)
  );
  return jsonb_build_object('id', v_delivery.id, 'status', v_delivery.status, 'scheduledFor', v_delivery.scheduled_for);
end;
$$;

create or replace function public.rpc_aoi_import_candidates(
  p_rows jsonb,
  p_file_name text,
  p_file_format text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_row jsonb;
  v_owner_id uuid;
  v_owner_count integer;
  v_count integer := 0;
  v_job_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id and caller.status = 'active'
  where membership.user_id = auth.uid()
    and membership.status = 'active' and membership.role = 'admin'
  order by membership.joined_at, membership.organization_id limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'IMPORT_ROWS_REQUIRED'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'IMPORT_TOO_LARGE'; end if;

  insert into public.import_jobs (
    organization_id, project_id, file_name, file_format, row_count, status, created_by
  ) values (
    v_org_id, v_project_id, p_file_name, p_file_format,
    jsonb_array_length(p_rows), 'previewed', auth.uid()
  ) returning id into v_job_id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_owner_id := null;
    if nullif(trim(v_row->>'ownerName'), '') is not null then
      select count(*), (array_agg(membership.user_id order by membership.user_id))[1]
      into v_owner_count, v_owner_id
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id
        and membership.status = 'active' and profile.status = 'active'
        and lower(trim(profile.display_name)) = lower(trim(v_row->>'ownerName'));
      if v_owner_count = 0 then raise exception 'OUTREACH_OWNER_INVALID'; end if;
      if v_owner_count > 1 then raise exception 'OUTREACH_OWNER_AMBIGUOUS'; end if;
      v_row := v_row || jsonb_build_object('ownerId', v_owner_id);
    elsif nullif(v_row->>'ownerId', '') is not null then
      select membership.user_id into v_owner_id
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id
        and membership.user_id = (v_row->>'ownerId')::uuid
        and membership.status = 'active' and profile.status = 'active';
      if v_owner_id is null then raise exception 'OUTREACH_OWNER_INVALID'; end if;
    end if;
    perform public.rpc_aoi_upsert_candidate(v_row);
    v_count := v_count + 1;
  end loop;
  update public.import_jobs set status = 'committed' where id = v_job_id;
  return jsonb_build_object('jobId', v_job_id, 'imported', v_count);
end;
$$;

revoke all on function public.rpc_aoi_upsert_candidate(jsonb) from public, anon;
revoke all on function public.rpc_aoi_upsert_crm_contact(jsonb) from public, anon;
revoke all on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) from public, anon;
revoke all on function public.rpc_aoi_set_communication_preference(uuid,jsonb,timestamptz) from public, anon;
revoke all on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) from public, anon;
revoke all on function public.rpc_aoi_import_candidates(jsonb,text,text) from public, anon;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated;
grant execute on function public.rpc_aoi_upsert_crm_contact(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) to authenticated;
grant execute on function public.rpc_aoi_set_communication_preference(uuid,jsonb,timestamptz) to authenticated;
grant execute on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) to authenticated;
grant execute on function public.rpc_aoi_import_candidates(jsonb,text,text) to authenticated;
