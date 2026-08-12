-- Native project operating records, explicit project context, and collaboration integration.

alter table public.projects
  add column if not exists objective text,
  add column if not exists sponsor_name text,
  add column if not exists manager_id uuid references public.profiles(id) on delete set null,
  add column if not exists planned_start date,
  add column if not exists planned_finish date,
  add column if not exists actual_start date,
  add column if not exists actual_finish date,
  add column if not exists health text not null default 'on_track'
    check (health in ('on_track', 'at_risk', 'off_track')),
  add column if not exists lifecycle_status text not null default 'active'
    check (lifecycle_status in ('planning', 'active', 'on_hold', 'completed', 'archived')),
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id) on delete set null,
  add column if not exists archive_reason text;

update public.projects
set lifecycle_status = case status
  when 'planning' then 'planning'
  when 'paused' then 'on_hold'
  when 'complete' then 'completed'
  when 'archived' then 'archived'
  else 'active'
end
where lifecycle_status = 'active' and status <> 'active';

create table public.project_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  selected_organization_id uuid not null references public.organizations(id) on delete cascade,
  selected_project_id uuid not null references public.projects(id) on delete cascade,
  selected_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (selected_organization_id, selected_project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_members (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  responsibility text,
  active boolean not null default true,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default clock_timestamp(),
  archived_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (project_id, user_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_milestones (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  title text not null check (length(trim(title)) > 0),
  intended_outcome text,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  planned_start date,
  planned_finish date,
  actual_start date,
  actual_finish date,
  progress_percent integer not null default 0 check (progress_percent between 0 and 100),
  acceptance_criteria text,
  next_action text,
  next_action_due date,
  status text not null default 'draft' check (status in (
    'draft', 'active', 'blocked', 'submitted', 'revision_requested', 'approved', 'completed', 'cancelled'
  )),
  progress_note text,
  review_note text,
  submitted_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_blockers (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  title text not null check (length(trim(title)) > 0),
  description text,
  source_type text,
  source_id uuid,
  blocked_since timestamptz not null default clock_timestamp(),
  reported_by uuid not null references public.profiles(id) on delete restrict,
  blocking_party text,
  resolution_owner_id uuid not null references public.profiles(id) on delete restrict,
  expected_resolution_date date,
  impact text not null default 'medium' check (impact in ('low', 'medium', 'high', 'critical')),
  next_action text,
  next_action_due date,
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolving', 'resolved')),
  escalated boolean not null default false,
  escalation_reason text,
  escalated_by uuid references public.profiles(id) on delete set null,
  escalated_at timestamptz,
  resolution_note text,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_risks (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  statement text not null check (length(trim(statement)) > 0),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  probability integer not null check (probability between 1 and 5),
  impact integer not null check (impact between 1 and 5),
  score integer generated always as (probability * impact) stored,
  trigger_condition text,
  mitigation text,
  next_action text,
  next_action_due date,
  review_date date,
  status text not null default 'identified' check (status in (
    'identified', 'assessing', 'mitigating', 'monitoring', 'accepted', 'closed'
  )),
  acceptance_rationale text,
  closure_note text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_decisions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  title text not null check (length(trim(title)) > 0),
  statement text,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  decision_maker_id uuid references public.profiles(id) on delete set null,
  alternatives jsonb not null default '[]'::jsonb check (jsonb_typeof(alternatives) = 'array'),
  rationale text,
  expected_impact text,
  status text not null default 'draft' check (status in (
    'draft', 'submitted', 'revision_requested', 'resubmitted', 'approved', 'rejected', 'superseded'
  )),
  review_guidance text,
  submitted_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  superseded_by_decision_id uuid references public.project_decisions(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_decision_evidence (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  decision_id uuid not null,
  evidence_id uuid not null references public.evidence_records(id) on delete restrict,
  stance text not null check (stance in ('supporting', 'contradicting')),
  relevance_note text,
  linked_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (decision_id, evidence_id),
  foreign key (organization_id, project_id, decision_id)
    references public.project_decisions(organization_id, project_id, id) on delete cascade
);

create table public.project_decision_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  decision_id uuid not null,
  version integer not null check (version > 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  approved_by uuid not null references public.profiles(id) on delete restrict,
  approved_at timestamptz not null default clock_timestamp(),
  supersedes_snapshot_id uuid references public.project_decision_snapshots(id) on delete restrict,
  unique (decision_id, version),
  foreign key (organization_id, project_id, decision_id)
    references public.project_decisions(organization_id, project_id, id) on delete restrict
);

create table public.project_record_history (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  record_type text not null check (record_type in ('milestone', 'blocker', 'risk', 'decision')),
  record_id uuid not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null,
  from_status text,
  to_status text not null,
  note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_history (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null,
  from_status text,
  to_status text not null,
  note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.project_decision_supersessions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  predecessor_decision_id uuid not null,
  successor_decision_id uuid not null,
  predecessor_snapshot_id uuid not null references public.project_decision_snapshots(id) on delete restrict,
  successor_snapshot_id uuid not null references public.project_decision_snapshots(id) on delete restrict,
  superseded_by uuid not null references public.profiles(id) on delete restrict,
  superseded_at timestamptz not null default clock_timestamp(),
  unique (predecessor_decision_id),
  check (predecessor_decision_id <> successor_decision_id),
  foreign key (organization_id, project_id, predecessor_decision_id)
    references public.project_decisions(organization_id, project_id, id) on delete restrict,
  foreign key (organization_id, project_id, successor_decision_id)
    references public.project_decisions(organization_id, project_id, id) on delete restrict
);

create table public.project_mutation_operations (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  client_nonce uuid not null,
  operation_key text not null,
  request_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (actor_id, client_nonce),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create index project_members_access_idx on public.project_members (user_id, active, project_id);
create index project_milestones_register_idx on public.project_milestones (project_id, status, planned_finish, owner_id);
create index project_blockers_register_idx on public.project_blockers (project_id, status, impact, next_action_due);
create index project_risks_register_idx on public.project_risks (project_id, status, score desc, review_date);
create index project_decisions_register_idx on public.project_decisions (project_id, status, updated_at desc);
create index project_history_source_idx on public.project_record_history (project_id, record_type, record_id, created_at desc);
create index project_lifecycle_history_idx on public.project_history (project_id, created_at, id);
create index project_supersession_successor_idx on public.project_decision_supersessions (successor_decision_id);
create index project_mutation_operations_scope_idx on public.project_mutation_operations (project_id, actor_id, created_at desc);

alter table public.project_preferences enable row level security;
alter table public.project_members enable row level security;
alter table public.project_milestones enable row level security;
alter table public.project_blockers enable row level security;
alter table public.project_risks enable row level security;
alter table public.project_decisions enable row level security;
alter table public.project_decision_evidence enable row level security;
alter table public.project_decision_snapshots enable row level security;
alter table public.project_record_history enable row level security;
alter table public.project_history enable row level security;
alter table public.project_decision_supersessions enable row level security;
alter table public.project_mutation_operations enable row level security;

-- Administrators retain their historical organization-wide access. Interns are
-- backfilled only from explicit source assignment, or an unambiguous sole project.
insert into public.project_members (
  organization_id, project_id, user_id, responsibility, assigned_by
)
select distinct project.organization_id, project.id, membership.user_id,
  case membership.role when 'admin' then 'Project administrator' else 'Existing assigned work' end,
  coalesce((select owner.user_id from public.organization_memberships owner
    where owner.organization_id = project.organization_id and owner.is_owner limit 1), membership.user_id)
from public.organization_memberships membership
join public.projects project on project.organization_id = membership.organization_id
  and project.status = 'active' and project.lifecycle_status <> 'archived'
where membership.status = 'active' and (
  membership.role = 'admin'
  or exists (select 1 from public.tasks source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.respondents source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.research_sessions source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.evidence_records source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.product_events source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.value_exchange_observations source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or exists (select 1 from public.pmf_observations source where source.project_id = project.id and source.assigned_to = membership.user_id)
  or 1 = (select count(*) from public.projects sole
    where sole.organization_id = membership.organization_id
      and sole.status = 'active' and sole.lifecycle_status <> 'archived')
)
on conflict (project_id, user_id) do nothing;

create or replace function private.aoi_actor_can_access_project(
  p_actor_id uuid,
  p_organization_id uuid,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.projects project
    join public.organizations organization on organization.id = project.organization_id
      and organization.status = 'active'
    join public.organization_memberships membership
      on membership.organization_id = project.organization_id
      and membership.user_id = p_actor_id and membership.status = 'active'
    join public.profiles profile on profile.id = membership.user_id
      and profile.status = 'active' and not profile.must_change_password
    join auth.users auth_user on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
    where project.id = p_project_id and project.organization_id = p_organization_id
      and (membership.role = 'admin' or exists (
        select 1 from public.project_members project_member
        where project_member.organization_id = project.organization_id
          and project_member.project_id = project.id
          and project_member.user_id = p_actor_id and project_member.active
      ))
  );
$$;

create or replace function public.aoi_can_access_project(p_organization_id uuid, p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.aoi_actor_can_access_project((select auth.uid()), p_organization_id, p_project_id);
$$;

create or replace function private.aoi_resolve_project(p_actor_id uuid, p_requested_project_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project_id uuid;
  v_count integer;
begin
  if p_requested_project_id is not null then
    select project.id into v_project_id from public.projects project
    where project.id = p_requested_project_id
      and private.aoi_actor_can_access_project(p_actor_id, project.organization_id, project.id);
    if v_project_id is null then raise exception 'PROJECT_NOT_FOUND'; end if;
    return v_project_id;
  end if;

  select preference.selected_project_id into v_project_id
  from public.project_preferences preference
  join public.projects project on project.id = preference.selected_project_id
    and project.organization_id = preference.selected_organization_id
  where preference.user_id = p_actor_id
    and private.aoi_actor_can_access_project(p_actor_id, project.organization_id, project.id);
  if v_project_id is not null then return v_project_id; end if;

  select count(*) into v_count
  from public.projects project
  where private.aoi_actor_can_access_project(p_actor_id, project.organization_id, project.id);
  if v_count = 0 then raise exception 'PROJECT_NOT_FOUND'; end if;
  if v_count > 1 then raise exception 'PROJECT_SELECTION_REQUIRED'; end if;
  select project.id into v_project_id
  from public.projects project
  where private.aoi_actor_can_access_project(p_actor_id, project.organization_id, project.id)
  order by project.created_at, project.id limit 1;
  return v_project_id;
end;
$$;

create or replace function public.aoi_apply_project_context(p_requested_project_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_id uuid := private.aoi_resolve_project((select auth.uid()), p_requested_project_id);
  v_organization_id uuid;
begin
  -- Access resolution requires profile.status = 'active', not profile.must_change_password,
  -- and organization.status = 'active' through private.aoi_actor_can_access_project.
  select project.organization_id into v_organization_id from public.projects project where project.id = v_project_id;
  perform set_config('aoi.selected_project_id', v_project_id::text, true);
  perform set_config('aoi.selected_organization_id', v_organization_id::text, true);
  return v_project_id;
end;
$$;

revoke all on function private.aoi_actor_can_access_project(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.aoi_resolve_project(uuid, uuid) from public, anon, authenticated;
revoke all on function public.aoi_apply_project_context(uuid) from public, anon, authenticated;
revoke all on function public.aoi_can_access_project(uuid, uuid) from public, anon;
grant execute on function public.aoi_can_access_project(uuid, uuid) to authenticated, service_role;
grant execute on function public.aoi_apply_project_context(uuid) to authenticated, service_role;

create policy organizations_canonical_context on public.organizations as restrictive for select to authenticated
using (nullif(current_setting('aoi.selected_organization_id', true), '') is null
  or id = current_setting('aoi.selected_organization_id', true)::uuid);
create policy memberships_canonical_context on public.organization_memberships as restrictive for select to authenticated
using (nullif(current_setting('aoi.selected_organization_id', true), '') is null
  or organization_id = current_setting('aoi.selected_organization_id', true)::uuid);
create policy projects_canonical_context on public.projects as restrictive for select to authenticated
using (nullif(current_setting('aoi.selected_project_id', true), '') is null
  or id = current_setting('aoi.selected_project_id', true)::uuid);

drop policy if exists projects_member_read on public.projects;
create policy projects_authorized_read on public.projects for select to authenticated
using (public.aoi_can_access_project(organization_id, id));

create policy project_preferences_self_read on public.project_preferences for select to authenticated
using (user_id = (select auth.uid()));
create policy project_members_authorized_read on public.project_members for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_milestones_authorized_read on public.project_milestones for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_blockers_authorized_read on public.project_blockers for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_risks_authorized_read on public.project_risks for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_decisions_authorized_read on public.project_decisions for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_decision_evidence_authorized_read on public.project_decision_evidence for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_decision_snapshots_authorized_read on public.project_decision_snapshots for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_record_history_authorized_read on public.project_record_history for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_history_authorized_read on public.project_history for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_decision_supersessions_authorized_read on public.project_decision_supersessions for select to authenticated
using (public.aoi_can_access_project(organization_id, project_id));
create policy project_mutation_operations_self_read on public.project_mutation_operations for select to authenticated
using (actor_id = (select auth.uid()) and public.aoi_can_access_project(organization_id, project_id));

create or replace function private.prevent_project_append_only_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'project_decision_snapshots' then
    raise exception 'PROJECT_DECISION_SNAPSHOT_IMMUTABLE';
  end if;
  if tg_table_name = 'project_decision_supersessions' then
    raise exception 'PROJECT_DECISION_SUPERSESSION_IMMUTABLE';
  end if;
  if tg_table_name = 'project_mutation_operations' then
    raise exception 'PROJECT_MUTATION_OPERATION_IMMUTABLE';
  end if;
  if tg_table_name = 'project_history' then
    raise exception 'PROJECT_HISTORY_APPEND_ONLY';
  end if;
  raise exception 'PROJECT_RECORD_HISTORY_APPEND_ONLY';
end;
$$;

create trigger project_decision_snapshots_immutable
before update or delete on public.project_decision_snapshots
for each row execute function private.prevent_project_append_only_mutation();
create trigger project_record_history_append_only
before update or delete on public.project_record_history
for each row execute function private.prevent_project_append_only_mutation();
create trigger project_history_append_only
before update or delete on public.project_history
for each row execute function private.prevent_project_append_only_mutation();
create trigger project_decision_supersessions_immutable
before update or delete on public.project_decision_supersessions
for each row execute function private.prevent_project_append_only_mutation();
create trigger project_mutation_operations_immutable
before update or delete on public.project_mutation_operations
for each row execute function private.prevent_project_append_only_mutation();
revoke all on function private.prevent_project_append_only_mutation() from public, anon, authenticated;

create or replace function public.rpc_aoi_project_context()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_selected_project_id uuid;
  v_selected_organization_id uuid;
  v_project_count integer;
begin
  select preference.selected_project_id, preference.selected_organization_id
  into v_selected_project_id, v_selected_organization_id
  from public.project_preferences preference
  join public.projects project on project.id = preference.selected_project_id
    and project.organization_id = preference.selected_organization_id
  where preference.user_id = v_actor_id
    and private.aoi_actor_can_access_project(v_actor_id, project.organization_id, project.id);

  select count(*) into v_project_count from public.projects project
  where private.aoi_actor_can_access_project(v_actor_id, project.organization_id, project.id);
  if v_project_count = 0 then raise exception 'PROJECT_NOT_FOUND'; end if;
  if v_selected_project_id is null and v_project_count = 1 then
    select project.id, project.organization_id into v_selected_project_id, v_selected_organization_id
    from public.projects project
    where private.aoi_actor_can_access_project(v_actor_id, project.organization_id, project.id);
  end if;

  return jsonb_build_object(
    'selectedOrganizationId', v_selected_organization_id,
    'selectedProjectId', v_selected_project_id,
    'selectionRequired', v_selected_project_id is null,
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', organization.id, 'name', organization.name, 'slug', organization.slug,
        'role', membership.role, 'isOwner', membership.is_owner,
        'projects', coalesce((select jsonb_agg(jsonb_build_object(
          'id', project.id, 'code', project.code, 'name', project.name,
          'health', project.health, 'status', project.lifecycle_status
        ) order by project.created_at, project.id)
          from public.projects project
          where project.organization_id = organization.id
            and private.aoi_actor_can_access_project(v_actor_id, organization.id, project.id)), '[]'::jsonb)
      ) order by membership.joined_at, organization.id)
      from public.organization_memberships membership
      join public.organizations organization on organization.id = membership.organization_id
      where membership.user_id = v_actor_id and membership.status = 'active'
        and exists (select 1 from public.projects project where project.organization_id = organization.id
          and private.aoi_actor_can_access_project(v_actor_id, organization.id, project.id))
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_select_project(p_project_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project public.projects%rowtype;
begin
  select project.* into v_project from public.projects project
  where project.id = p_project_id
    and private.aoi_actor_can_access_project(v_actor_id, project.organization_id, project.id);
  if v_project.id is null then raise exception 'PROJECT_NOT_FOUND'; end if;

  insert into public.project_preferences (user_id, selected_organization_id, selected_project_id)
  values (v_actor_id, v_project.organization_id, v_project.id)
  on conflict (user_id) do update set
    selected_organization_id = excluded.selected_organization_id,
    selected_project_id = excluded.selected_project_id,
    selected_at = clock_timestamp(), updated_at = clock_timestamp();
  return jsonb_build_object('selectedOrganizationId', v_project.organization_id, 'selectedProjectId', v_project.id);
end;
$$;

create or replace function public.rpc_aoi_admin_save_project(
  p_payload jsonb,
  p_project_id uuid default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_organization_id uuid;
  v_project public.projects%rowtype;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'PROJECT_PAYLOAD_INVALID'; end if;
  if p_project_id is null then
    v_organization_id := nullif(p_payload->>'organizationId', '')::uuid;
    if v_organization_id is null then
      select preference.selected_organization_id into v_organization_id
      from public.project_preferences preference where preference.user_id = v_actor_id;
    end if;
    if v_organization_id is null and 1 = (select count(*) from public.organization_memberships membership
      where membership.user_id = v_actor_id and membership.role = 'admin' and membership.status = 'active'
        and public.is_org_admin(membership.organization_id)) then
      select membership.organization_id into v_organization_id
      from public.organization_memberships membership
      where membership.user_id = v_actor_id and membership.role = 'admin' and membership.status = 'active'
        and public.is_org_admin(membership.organization_id);
    end if;
    if v_organization_id is null then raise exception 'PROJECT_ORGANIZATION_REQUIRED'; end if;
    select membership.organization_id into v_organization_id
    from public.organization_memberships membership
    where membership.organization_id = v_organization_id and membership.user_id = v_actor_id
      and membership.role = 'admin' and membership.status = 'active'
      and public.is_org_admin(membership.organization_id)
    limit 1;
    if v_organization_id is null then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
    insert into public.projects (
      organization_id, code, name, description, objective, sponsor_name, manager_id,
      planned_start, planned_finish, health, lifecycle_status, status
    ) values (
      v_organization_id, trim(coalesce(p_payload->>'code', '')), trim(coalesce(p_payload->>'name', '')),
      nullif(trim(p_payload->>'description'), ''), nullif(trim(p_payload->>'objective'), ''),
      nullif(trim(p_payload->>'sponsorName'), ''), nullif(p_payload->>'managerId', '')::uuid,
      nullif(p_payload->>'plannedStart', '')::date, nullif(p_payload->>'plannedFinish', '')::date,
      coalesce(nullif(p_payload->>'health', ''), 'on_track'), 'planning', 'planning'
    ) returning * into v_project;
    insert into public.project_members (organization_id, project_id, user_id, responsibility, assigned_by)
    values (v_organization_id, v_project.id, v_actor_id, 'Project administrator', v_actor_id)
    on conflict (project_id, user_id) do update set active = true, archived_at = null, updated_at = clock_timestamp();
  else
    select project.* into v_project from public.projects project where project.id = p_project_id for update;
    if v_project.id is null or not public.is_org_admin(v_project.organization_id) then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
    if p_expected_updated_at is null then raise exception 'PROJECT_EXPECTED_UPDATED_AT_REQUIRED'; end if;
    if v_project.lifecycle_status = 'archived' then raise exception 'PROJECT_READ_ONLY'; end if;
    update public.projects project set
      code = case when p_payload ? 'code' then trim(p_payload->>'code') else project.code end,
      name = case when p_payload ? 'name' then trim(p_payload->>'name') else project.name end,
      description = case when p_payload ? 'description' then nullif(trim(p_payload->>'description'), '') else project.description end,
      objective = case when p_payload ? 'objective' then nullif(trim(p_payload->>'objective'), '') else project.objective end,
      sponsor_name = case when p_payload ? 'sponsorName' then nullif(trim(p_payload->>'sponsorName'), '') else project.sponsor_name end,
      manager_id = case when p_payload ? 'managerId' then nullif(p_payload->>'managerId', '')::uuid else project.manager_id end,
      planned_start = case when p_payload ? 'plannedStart' then nullif(p_payload->>'plannedStart', '')::date else project.planned_start end,
      planned_finish = case when p_payload ? 'plannedFinish' then nullif(p_payload->>'plannedFinish', '')::date else project.planned_finish end,
      actual_start = case when p_payload ? 'actualStart' then nullif(p_payload->>'actualStart', '')::date else project.actual_start end,
      actual_finish = case when p_payload ? 'actualFinish' then nullif(p_payload->>'actualFinish', '')::date else project.actual_finish end,
      health = case when p_payload ? 'health' then p_payload->>'health' else project.health end,
      updated_at = clock_timestamp()
    where project.id = p_project_id and project.updated_at = p_expected_updated_at returning project.* into v_project;
    if v_project.id is null then raise exception 'PROJECT_STALE_WRITE'; end if;
  end if;
  if length(trim(v_project.code)) = 0 or length(trim(v_project.name)) = 0 then raise exception 'PROJECT_VALIDATION_FAILED'; end if;
  if v_project.manager_id is not null and not private.aoi_actor_can_access_project(v_project.manager_id, v_project.organization_id, v_project.id) then
    raise exception 'PROJECT_MANAGER_INVALID';
  end if;
  return to_jsonb(v_project);
exception when unique_violation or check_violation or invalid_text_representation then
  raise exception 'PROJECT_VALIDATION_FAILED: %', sqlerrm;
end;
$$;

create or replace function public.rpc_aoi_admin_set_project_member(
  p_project_id uuid,
  p_user_id uuid,
  p_active boolean,
  p_responsibility text,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project public.projects%rowtype;
  v_member public.project_members%rowtype;
begin
  select project.* into v_project from public.projects project where project.id = p_project_id for update;
  if v_project.id is null or not public.is_org_admin(v_project.organization_id) then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
  if v_project.lifecycle_status = 'archived' then raise exception 'PROJECT_READ_ONLY'; end if;
  if not exists (select 1 from public.organization_memberships membership where membership.organization_id = v_project.organization_id
    and membership.user_id = p_user_id and membership.status = 'active') then raise exception 'PROJECT_MEMBER_ORGANIZATION_REQUIRED'; end if;
  select member.* into v_member from public.project_members member where member.project_id = p_project_id and member.user_id = p_user_id for update;
  if v_member.id is not null and p_expected_updated_at is not null and v_member.updated_at <> p_expected_updated_at then raise exception 'PROJECT_MEMBER_STALE_WRITE'; end if;
  if not p_active and exists (select 1 from public.organization_memberships membership where membership.organization_id = v_project.organization_id
    and membership.user_id = p_user_id and membership.is_owner) then raise exception 'PROJECT_OWNER_REMOVAL_FORBIDDEN'; end if;
  if not p_active and (
    exists (select 1 from public.project_milestones where project_id = p_project_id and owner_id = p_user_id and status not in ('completed','cancelled'))
    or exists (select 1 from public.project_blockers where project_id = p_project_id and resolution_owner_id = p_user_id and status <> 'resolved')
    or exists (select 1 from public.project_risks where project_id = p_project_id and owner_id = p_user_id and status not in ('accepted','closed'))
    or exists (select 1 from public.project_decisions where project_id = p_project_id and owner_id = p_user_id and status not in ('approved','rejected','superseded'))
  ) then raise exception 'PROJECT_MEMBER_HAS_OPEN_ASSIGNMENTS'; end if;
  insert into public.project_members (organization_id, project_id, user_id, responsibility, active, assigned_by, archived_at)
  values (v_project.organization_id, p_project_id, p_user_id, nullif(trim(p_responsibility), ''), p_active, v_actor_id,
    case when p_active then null else clock_timestamp() end)
  on conflict (project_id, user_id) do update set responsibility = excluded.responsibility, active = excluded.active,
    assigned_by = excluded.assigned_by, assigned_at = case when excluded.active and not project_members.active then clock_timestamp() else project_members.assigned_at end,
    archived_at = excluded.archived_at, updated_at = clock_timestamp()
  returning * into v_member;
  return to_jsonb(v_member);
end;
$$;

create or replace function public.rpc_aoi_transition_project(
  p_project_id uuid,
  p_action text,
  p_note text,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project public.projects%rowtype;
  v_from_status text;
  v_to_status text;
begin
  if p_expected_updated_at is null then raise exception 'PROJECT_EXPECTED_UPDATED_AT_REQUIRED'; end if;
  select project.* into v_project from public.projects project where project.id = p_project_id for update;
  if v_project.id is null or not public.is_org_admin(v_project.organization_id) then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
  if v_project.updated_at <> p_expected_updated_at then raise exception 'PROJECT_STALE_WRITE'; end if;
  v_from_status := v_project.lifecycle_status;
  if p_action = 'activate' and v_from_status = 'planning' then v_to_status := 'active';
  elsif p_action = 'hold' and v_from_status = 'active' then
    if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
    v_to_status := 'on_hold';
  elsif p_action = 'resume' and v_from_status = 'on_hold' then v_to_status := 'active';
  elsif p_action = 'complete' and v_from_status = 'active' then
    if exists (select 1 from public.project_blockers where project_id = p_project_id and impact = 'critical' and status <> 'resolved') then
      raise exception 'PROJECT_COMPLETION_BLOCKED';
    end if;
    v_to_status := 'completed';
  elsif p_action = 'archive' and v_from_status = 'completed' then v_to_status := 'archived';
  elsif p_action = 'archive' and v_from_status <> 'archived' then
    if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_ARCHIVE_OVERRIDE_NOTE_REQUIRED'; end if;
    v_to_status := 'archived';
  elsif p_action = 'restore' and v_from_status = 'archived' then
    if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
    v_to_status := 'completed';
  else raise exception 'PROJECT_TRANSITION_INVALID'; end if;
  update public.projects set lifecycle_status = v_to_status,
    status = case v_to_status when 'planning' then 'planning' when 'on_hold' then 'paused' when 'completed' then 'complete' when 'archived' then 'archived' else 'active' end,
    actual_start = case when p_action = 'activate' then coalesce(actual_start, current_date) else actual_start end,
    actual_finish = case when p_action = 'complete' then coalesce(actual_finish, current_date) when p_action = 'restore' then actual_finish else actual_finish end,
    archived_at = case when p_action = 'archive' then clock_timestamp() when p_action = 'restore' then null else archived_at end,
    archived_by = case when p_action = 'archive' then v_actor_id when p_action = 'restore' then null else archived_by end,
    archive_reason = case when p_action = 'archive' then nullif(trim(p_note), '') when p_action = 'restore' then null else archive_reason end,
    updated_at = clock_timestamp()
  where id = p_project_id returning * into v_project;
  insert into public.project_history (organization_id, project_id, actor_id, action, from_status, to_status, note)
  values (v_project.organization_id, v_project.id, v_actor_id, p_action, v_from_status, v_to_status, nullif(trim(p_note), ''));
  return to_jsonb(v_project);
end;
$$;

create or replace function public.rpc_aoi_project_snapshot(p_project_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, p_project_id);
begin
  return jsonb_build_object(
    'project', (select jsonb_build_object(
      'id', project.id, 'organizationId', project.organization_id, 'code', project.code,
      'name', project.name, 'description', project.description, 'objective', project.objective,
      'sponsorName', project.sponsor_name, 'managerId', project.manager_id,
      'plannedStart', project.planned_start, 'plannedFinish', project.planned_finish,
      'actualStart', project.actual_start, 'actualFinish', project.actual_finish,
      'health', project.health, 'status', project.lifecycle_status, 'updatedAt', project.updated_at
    ) from public.projects project where project.id = v_project_id),
    'members', coalesce((select jsonb_agg(jsonb_build_object(
      'id', member.id, 'userId', member.user_id, 'displayName', profile.display_name,
      'responsibility', member.responsibility, 'active', member.active
    ) order by profile.display_name, member.user_id)
      from public.project_members member join public.profiles profile on profile.id = member.user_id
      where member.project_id = v_project_id and member.active), '[]'::jsonb),
    'milestones', coalesce((select jsonb_agg(to_jsonb(record) order by record.planned_finish nulls last, record.created_at)
      from public.project_milestones record where record.project_id = v_project_id), '[]'::jsonb),
    'blockers', coalesce((select jsonb_agg(to_jsonb(record) order by record.resolved_at nulls first, record.created_at desc)
      from public.project_blockers record where record.project_id = v_project_id), '[]'::jsonb),
    'risks', coalesce((select jsonb_agg(to_jsonb(record) order by record.score desc, record.review_date nulls last)
      from public.project_risks record where record.project_id = v_project_id), '[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(to_jsonb(record) order by record.updated_at desc)
      from public.project_decisions record where record.project_id = v_project_id), '[]'::jsonb),
    'summary', jsonb_build_object(
      'openMilestones', (select count(*) from public.project_milestones where project_id = v_project_id and status not in ('completed', 'cancelled')),
      'openBlockers', (select count(*) from public.project_blockers where project_id = v_project_id and status <> 'resolved'),
      'highRisks', (select count(*) from public.project_risks where project_id = v_project_id and score >= 10 and status not in ('accepted', 'closed')),
      'pendingDecisions', (select count(*) from public.project_decisions where project_id = v_project_id and status in ('submitted', 'resubmitted'))
    ),
    'activity', coalesce((select jsonb_agg(to_jsonb(history) order by history.created_at desc, history.id desc)
      from (select * from public.project_record_history where project_id = v_project_id order by created_at desc, id desc limit 100) history), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_project_record_detail(p_record_type text, p_record_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_organization_id uuid;
  v_project_id uuid;
  v_record jsonb;
begin
  case p_record_type
    when 'milestone' then select organization_id, project_id, to_jsonb(record) into v_organization_id, v_project_id, v_record from public.project_milestones record where id = p_record_id;
    when 'blocker' then select organization_id, project_id, to_jsonb(record) into v_organization_id, v_project_id, v_record from public.project_blockers record where id = p_record_id;
    when 'risk' then select organization_id, project_id, to_jsonb(record) into v_organization_id, v_project_id, v_record from public.project_risks record where id = p_record_id;
    when 'decision' then select organization_id, project_id, to_jsonb(record) into v_organization_id, v_project_id, v_record from public.project_decisions record where id = p_record_id;
    else raise exception 'PROJECT_RECORD_TYPE_INVALID';
  end case;
  if v_record is null or not private.aoi_actor_can_access_project(v_actor_id, v_organization_id, v_project_id) then
    raise exception 'PROJECT_RECORD_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'recordType', p_record_type, 'record', v_record,
    'history', coalesce((select jsonb_agg(to_jsonb(history) order by history.created_at, history.id)
      from public.project_record_history history where history.record_type = p_record_type and history.record_id = p_record_id), '[]'::jsonb),
    'comments', coalesce((select jsonb_agg(to_jsonb(comment) order by comment.created_at, comment.id)
      from public.work_comments comment where comment.source_type = p_record_type and comment.source_id = p_record_id), '[]'::jsonb),
    'evidence', case when p_record_type = 'decision' then coalesce((select jsonb_agg(jsonb_build_object(
      'id', link.id, 'evidenceId', link.evidence_id, 'title', evidence.title,
      'evidenceText', evidence.evidence_text, 'sourceLink', evidence.source_link,
      'stance', link.stance, 'relevanceNote', link.relevance_note,
      'limitations', evidence.limitations, 'workflowStatus', evidence.workflow_status,
      'provenance', jsonb_build_object('recordedBy', evidence.recorded_by,
        'recordedAt', evidence.recorded_at, 'respondentId', evidence.respondent_id,
        'sessionId', evidence.session_id, 'evidenceType', coalesce(evidence.evidence_type, evidence.type))
    ) order by link.created_at, link.id)
      from public.project_decision_evidence link join public.evidence_records evidence on evidence.id = link.evidence_id
      where link.decision_id = p_record_id), '[]'::jsonb) else '[]'::jsonb end,
    'snapshots', case when p_record_type = 'decision' then coalesce((select jsonb_agg(to_jsonb(snapshot) order by snapshot.version)
      from public.project_decision_snapshots snapshot where snapshot.decision_id = p_record_id), '[]'::jsonb) else '[]'::jsonb end,
    'supersessions', case when p_record_type = 'decision' then coalesce((select jsonb_agg(to_jsonb(link) order by link.superseded_at, link.id)
      from public.project_decision_supersessions link
      where link.predecessor_decision_id = p_record_id or link.successor_decision_id = p_record_id), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create function public.rpc_aoi_save_project_record(
  p_record_type text,
  p_payload jsonb,
  p_record_id uuid default null,
  p_expected_updated_at timestamptz default null,
  p_client_nonce uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid;
  v_organization_id uuid;
  v_is_admin boolean;
  v_result jsonb;
  v_owner_id uuid;
  v_status text;
  v_evidence jsonb;
  v_request_hash text;
  v_operation public.project_mutation_operations%rowtype;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'PROJECT_PAYLOAD_INVALID'; end if;
  if p_record_type not in ('milestone', 'blocker', 'risk', 'decision') then raise exception 'PROJECT_RECORD_TYPE_INVALID'; end if;
  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'recordType', p_record_type, 'payload', p_payload, 'recordId', p_record_id,
    'expectedUpdatedAt', p_expected_updated_at
  )::text, 'sha256'), 'hex');
  if p_client_nonce is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor_id::text || ':' || p_client_nonce::text, 0));
    select operation.* into v_operation from public.project_mutation_operations operation
    where operation.actor_id = v_actor_id and operation.client_nonce = p_client_nonce;
    if v_operation.id is not null then
      if v_operation.operation_key <> 'save_record' or v_operation.request_hash <> v_request_hash then
        raise exception 'PROJECT_IDEMPOTENCY_MISMATCH';
      end if;
      return v_operation.result;
    end if;
  end if;

  if p_record_id is null then
    v_project_id := private.aoi_resolve_project(v_actor_id, nullif(p_payload->>'projectId', '')::uuid);
    select project.organization_id into v_organization_id from public.projects project where project.id = v_project_id;
  else
    case p_record_type
      when 'milestone' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_status from public.project_milestones where id = p_record_id;
      when 'blocker' then select organization_id, project_id, resolution_owner_id, status into v_organization_id, v_project_id, v_owner_id, v_status from public.project_blockers where id = p_record_id;
      when 'risk' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_status from public.project_risks where id = p_record_id;
      when 'decision' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_status from public.project_decisions where id = p_record_id;
    end case;
    if v_project_id is null or not private.aoi_actor_can_access_project(v_actor_id, v_organization_id, v_project_id) then raise exception 'PROJECT_RECORD_NOT_FOUND'; end if;
    if p_expected_updated_at is null then raise exception 'PROJECT_EXPECTED_UPDATED_AT_REQUIRED'; end if;
    if nullif(p_payload->>'projectId', '') is not null and (p_payload->>'projectId')::uuid <> v_project_id then raise exception 'PROJECT_RECORD_SCOPE_IMMUTABLE'; end if;
  end if;
  v_is_admin := public.is_org_admin(v_organization_id);
  if exists (select 1 from public.projects project where project.id = v_project_id and project.lifecycle_status = 'archived') then
    raise exception 'PROJECT_READ_ONLY';
  end if;

  v_owner_id := case p_record_type
    when 'blocker' then coalesce(nullif(p_payload->>'resolutionOwnerId', '')::uuid, v_owner_id, v_actor_id)
    else coalesce(nullif(p_payload->>'ownerId', '')::uuid, v_owner_id, v_actor_id)
  end;
  if not private.aoi_actor_can_access_project(v_owner_id, v_organization_id, v_project_id) then
    raise exception 'PROJECT_RECORD_OWNER_REQUIRED';
  end if;
  if p_record_type = 'decision' and nullif(p_payload->>'decisionMakerId', '') is not null
    and not private.aoi_actor_can_access_project((p_payload->>'decisionMakerId')::uuid, v_organization_id, v_project_id) then
    raise exception 'PROJECT_RECORD_OWNER_REQUIRED';
  end if;

  if p_record_type = 'milestone' then
    if p_record_id is null then
      if not v_is_admin then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
      insert into public.project_milestones (
        organization_id, project_id, title, intended_outcome, owner_id, planned_start, planned_finish,
        progress_percent, acceptance_criteria, next_action, next_action_due, created_by, updated_by
      ) values (
        v_organization_id, v_project_id, trim(coalesce(p_payload->>'title', '')),
        nullif(trim(p_payload->>'intendedOutcome'), ''), v_owner_id,
        nullif(p_payload->>'plannedStart', '')::date, nullif(p_payload->>'plannedFinish', '')::date,
        coalesce((p_payload->>'progressPercent')::integer, 0), nullif(trim(p_payload->>'acceptanceCriteria'), ''),
        nullif(trim(p_payload->>'nextAction'), ''), nullif(p_payload->>'nextActionDue', '')::date,
        v_actor_id, v_actor_id
      ) returning to_jsonb(project_milestones.*) into v_result;
    else
      if not v_is_admin and v_owner_id <> v_actor_id then raise exception 'PROJECT_RECORD_NOT_ASSIGNED'; end if;
      if v_status not in ('draft', 'active', 'blocked', 'revision_requested') then raise exception 'PROJECT_RECORD_LOCKED'; end if;
      update public.project_milestones record set
        title = case when p_payload ? 'title' then trim(p_payload->>'title') else record.title end,
        intended_outcome = case when p_payload ? 'intendedOutcome' then nullif(trim(p_payload->>'intendedOutcome'), '') else record.intended_outcome end,
        owner_id = case when v_is_admin and p_payload ? 'ownerId' then (p_payload->>'ownerId')::uuid else record.owner_id end,
        planned_start = case when p_payload ? 'plannedStart' then nullif(p_payload->>'plannedStart', '')::date else record.planned_start end,
        planned_finish = case when p_payload ? 'plannedFinish' then nullif(p_payload->>'plannedFinish', '')::date else record.planned_finish end,
        progress_percent = case when p_payload ? 'progressPercent' then (p_payload->>'progressPercent')::integer else record.progress_percent end,
        acceptance_criteria = case when p_payload ? 'acceptanceCriteria' then nullif(trim(p_payload->>'acceptanceCriteria'), '') else record.acceptance_criteria end,
        next_action = case when p_payload ? 'nextAction' then nullif(trim(p_payload->>'nextAction'), '') else record.next_action end,
        next_action_due = case when p_payload ? 'nextActionDue' then nullif(p_payload->>'nextActionDue', '')::date else record.next_action_due end,
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where record.id = p_record_id and record.updated_at = p_expected_updated_at
      returning to_jsonb(record.*) into v_result;
    end if;
  elsif p_record_type = 'blocker' then
    if p_record_id is null then
      if nullif(p_payload->>'sourceType', '') is not null and (
        nullif(p_payload->>'sourceId', '') is null
        or p_payload->>'sourceType' not in ('task','respondent','session','evidence','product_event','value_exchange','observation','milestone','blocker','risk','decision')
        or not private.aoi_actor_can_access_work_source(v_actor_id, v_organization_id, v_project_id,
          p_payload->>'sourceType', (p_payload->>'sourceId')::uuid)
      ) then raise exception 'PROJECT_BLOCKER_SOURCE_INVALID'; end if;
      insert into public.project_blockers (
        organization_id, project_id, title, description, source_type, source_id, blocking_party,
        resolution_owner_id, expected_resolution_date, impact, next_action, next_action_due,
        reported_by, created_by, updated_by
      ) values (
        v_organization_id, v_project_id, trim(coalesce(p_payload->>'title', '')),
        nullif(trim(p_payload->>'description'), ''), nullif(p_payload->>'sourceType', ''), nullif(p_payload->>'sourceId', '')::uuid,
        nullif(trim(p_payload->>'blockingParty'), ''), v_owner_id, nullif(p_payload->>'expectedResolutionDate', '')::date,
        coalesce(nullif(p_payload->>'impact', ''), 'medium'), nullif(trim(p_payload->>'nextAction'), ''),
        nullif(p_payload->>'nextActionDue', '')::date, v_actor_id, v_actor_id, v_actor_id
      ) returning to_jsonb(project_blockers.*) into v_result;
    else
      if not v_is_admin and not exists (select 1 from public.project_blockers blocker where blocker.id = p_record_id
        and (blocker.reported_by = v_actor_id or blocker.resolution_owner_id = v_actor_id)) then
        raise exception 'PROJECT_BLOCKER_EDIT_FORBIDDEN';
      end if;
      if not v_is_admin and p_payload ? 'resolutionOwnerId'
        and (p_payload->>'resolutionOwnerId')::uuid <> (select blocker.resolution_owner_id from public.project_blockers blocker where blocker.id = p_record_id)
        then raise exception 'PROJECT_BLOCKER_REASSIGN_ADMIN_REQUIRED'; end if;
      if v_status = 'resolved' then raise exception 'PROJECT_RECORD_LOCKED'; end if;
      update public.project_blockers record set
        title = case when p_payload ? 'title' then trim(p_payload->>'title') else record.title end,
        description = case when p_payload ? 'description' then nullif(trim(p_payload->>'description'), '') else record.description end,
        blocking_party = case when p_payload ? 'blockingParty' then nullif(trim(p_payload->>'blockingParty'), '') else record.blocking_party end,
        resolution_owner_id = case when v_is_admin and p_payload ? 'resolutionOwnerId' then (p_payload->>'resolutionOwnerId')::uuid else record.resolution_owner_id end,
        expected_resolution_date = case when p_payload ? 'expectedResolutionDate' then nullif(p_payload->>'expectedResolutionDate', '')::date else record.expected_resolution_date end,
        impact = case when p_payload ? 'impact' then p_payload->>'impact' else record.impact end,
        next_action = case when p_payload ? 'nextAction' then nullif(trim(p_payload->>'nextAction'), '') else record.next_action end,
        next_action_due = case when p_payload ? 'nextActionDue' then nullif(p_payload->>'nextActionDue', '')::date else record.next_action_due end,
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where record.id = p_record_id and record.updated_at = p_expected_updated_at
      returning to_jsonb(record.*) into v_result;
    end if;
  elsif p_record_type = 'risk' then
    if p_record_id is null then
      insert into public.project_risks (
        organization_id, project_id, statement, owner_id, probability, impact, trigger_condition,
        mitigation, next_action, next_action_due, review_date, created_by, updated_by
      ) values (
        v_organization_id, v_project_id, trim(coalesce(p_payload->>'statement', '')), v_owner_id,
        (p_payload->>'probability')::integer, (p_payload->>'impact')::integer,
        nullif(trim(p_payload->>'triggerCondition'), ''), nullif(trim(p_payload->>'mitigation'), ''),
        nullif(trim(p_payload->>'nextAction'), ''), nullif(p_payload->>'nextActionDue', '')::date,
        nullif(p_payload->>'reviewDate', '')::date, v_actor_id, v_actor_id
      ) returning to_jsonb(project_risks.*) into v_result;
    else
      if not v_is_admin and v_owner_id <> v_actor_id then raise exception 'PROJECT_RECORD_NOT_ASSIGNED'; end if;
      if v_status in ('accepted', 'closed') then raise exception 'PROJECT_RECORD_LOCKED'; end if;
      update public.project_risks record set
        statement = case when p_payload ? 'statement' then trim(p_payload->>'statement') else record.statement end,
        owner_id = case when v_is_admin and p_payload ? 'ownerId' then (p_payload->>'ownerId')::uuid else record.owner_id end,
        probability = case when p_payload ? 'probability' then (p_payload->>'probability')::integer else record.probability end,
        impact = case when p_payload ? 'impact' then (p_payload->>'impact')::integer else record.impact end,
        trigger_condition = case when p_payload ? 'triggerCondition' then nullif(trim(p_payload->>'triggerCondition'), '') else record.trigger_condition end,
        mitigation = case when p_payload ? 'mitigation' then nullif(trim(p_payload->>'mitigation'), '') else record.mitigation end,
        next_action = case when p_payload ? 'nextAction' then nullif(trim(p_payload->>'nextAction'), '') else record.next_action end,
        next_action_due = case when p_payload ? 'nextActionDue' then nullif(p_payload->>'nextActionDue', '')::date else record.next_action_due end,
        review_date = case when p_payload ? 'reviewDate' then nullif(p_payload->>'reviewDate', '')::date else record.review_date end,
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where record.id = p_record_id and record.updated_at = p_expected_updated_at
      returning to_jsonb(record.*) into v_result;
    end if;
  else
    if p_record_id is null then
      if not v_is_admin then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
      insert into public.project_decisions (
        organization_id, project_id, title, statement, owner_id, decision_maker_id,
        alternatives, rationale, expected_impact, created_by, updated_by
      ) values (
        v_organization_id, v_project_id, trim(coalesce(p_payload->>'title', '')),
        nullif(trim(p_payload->>'statement'), ''), v_owner_id, nullif(p_payload->>'decisionMakerId', '')::uuid,
        coalesce(p_payload->'alternatives', '[]'::jsonb), nullif(trim(p_payload->>'rationale'), ''),
        nullif(trim(p_payload->>'expectedImpact'), ''), v_actor_id, v_actor_id
      ) returning to_jsonb(project_decisions.*) into v_result;
      p_record_id := (v_result->>'id')::uuid;
    else
      if not v_is_admin and v_owner_id <> v_actor_id then raise exception 'PROJECT_RECORD_NOT_ASSIGNED'; end if;
      if v_status not in ('draft', 'revision_requested') then raise exception 'PROJECT_RECORD_LOCKED'; end if;
      update public.project_decisions record set
        title = case when p_payload ? 'title' then trim(p_payload->>'title') else record.title end,
        statement = case when p_payload ? 'statement' then nullif(trim(p_payload->>'statement'), '') else record.statement end,
        owner_id = case when v_is_admin and p_payload ? 'ownerId' then (p_payload->>'ownerId')::uuid else record.owner_id end,
        decision_maker_id = case when p_payload ? 'decisionMakerId' then nullif(p_payload->>'decisionMakerId', '')::uuid else record.decision_maker_id end,
        alternatives = case when p_payload ? 'alternatives' then p_payload->'alternatives' else record.alternatives end,
        rationale = case when p_payload ? 'rationale' then nullif(trim(p_payload->>'rationale'), '') else record.rationale end,
        expected_impact = case when p_payload ? 'expectedImpact' then nullif(trim(p_payload->>'expectedImpact'), '') else record.expected_impact end,
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where record.id = p_record_id and record.updated_at = p_expected_updated_at
      returning to_jsonb(record.*) into v_result;
    end if;

    if p_payload ? 'evidenceLinks' then
      if jsonb_typeof(p_payload->'evidenceLinks') <> 'array' then raise exception 'PROJECT_DECISION_EVIDENCE_INVALID'; end if;
      delete from public.project_decision_evidence where decision_id = p_record_id;
      for v_evidence in select value from jsonb_array_elements(p_payload->'evidenceLinks') loop
        if not exists (select 1 from public.evidence_records evidence
          where evidence.id = (v_evidence->>'evidenceId')::uuid
            and evidence.organization_id = v_organization_id and evidence.project_id = v_project_id) then
          raise exception 'PROJECT_DECISION_EVIDENCE_INVALID';
        end if;
        insert into public.project_decision_evidence (
          organization_id, project_id, decision_id, evidence_id, stance, relevance_note, linked_by
        ) values (
          v_organization_id, v_project_id, p_record_id, (v_evidence->>'evidenceId')::uuid,
          v_evidence->>'stance', nullif(trim(v_evidence->>'relevanceNote'), ''), v_actor_id
        );
      end loop;
    end if;
  end if;

  if v_result is null then raise exception 'PROJECT_RECORD_STALE_WRITE'; end if;
  if p_client_nonce is not null then
    insert into public.project_mutation_operations (
      organization_id, project_id, actor_id, client_nonce, operation_key, request_hash, result
    ) values (v_organization_id, v_project_id, v_actor_id, p_client_nonce, 'save_record', v_request_hash, v_result);
  end if;
  return v_result;
exception
  when not_null_violation or check_violation or invalid_text_representation then
    raise exception 'PROJECT_RECORD_VALIDATION_FAILED: %', sqlerrm;
end;
$$;

create function public.rpc_aoi_transition_project_record(
  p_record_type text,
  p_record_id uuid,
  p_action text,
  p_note text,
  p_expected_updated_at timestamptz,
  p_client_nonce uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_organization_id uuid;
  v_project_id uuid;
  v_owner_id uuid;
  v_from_status text;
  v_to_status text;
  v_is_admin boolean;
  v_result jsonb;
  v_snapshot jsonb;
  v_snapshot_version integer;
  v_replacement_id uuid;
  v_request_hash text;
  v_operation public.project_mutation_operations%rowtype;
begin
  if p_expected_updated_at is null then raise exception 'PROJECT_EXPECTED_UPDATED_AT_REQUIRED'; end if;
  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'recordType', p_record_type, 'recordId', p_record_id, 'action', p_action,
    'note', p_note, 'expectedUpdatedAt', p_expected_updated_at
  )::text, 'sha256'), 'hex');
  if p_client_nonce is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor_id::text || ':' || p_client_nonce::text, 0));
    select operation.* into v_operation from public.project_mutation_operations operation
    where operation.actor_id = v_actor_id and operation.client_nonce = p_client_nonce;
    if v_operation.id is not null then
      if v_operation.operation_key <> 'transition_record' or v_operation.request_hash <> v_request_hash then
        raise exception 'PROJECT_IDEMPOTENCY_MISMATCH';
      end if;
      return v_operation.result;
    end if;
  end if;
  case p_record_type
    when 'milestone' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_from_status from public.project_milestones where id = p_record_id for update;
    when 'blocker' then select organization_id, project_id, resolution_owner_id, status into v_organization_id, v_project_id, v_owner_id, v_from_status from public.project_blockers where id = p_record_id for update;
    when 'risk' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_from_status from public.project_risks where id = p_record_id for update;
    when 'decision' then select organization_id, project_id, owner_id, status into v_organization_id, v_project_id, v_owner_id, v_from_status from public.project_decisions where id = p_record_id for update;
    else raise exception 'PROJECT_RECORD_TYPE_INVALID';
  end case;
  if v_project_id is null or not private.aoi_actor_can_access_project(v_actor_id, v_organization_id, v_project_id) then raise exception 'PROJECT_RECORD_NOT_FOUND'; end if;
  v_is_admin := public.is_org_admin(v_organization_id);
  if exists (select 1 from public.projects project where project.id = v_project_id and project.lifecycle_status = 'archived') then
    raise exception 'PROJECT_READ_ONLY';
  end if;
  if not v_is_admin and v_owner_id <> v_actor_id and p_record_type <> 'blocker' then raise exception 'PROJECT_RECORD_NOT_ASSIGNED'; end if;

  if p_record_type = 'milestone' then
    if p_action = 'activate' and v_from_status = 'draft' and v_is_admin then v_to_status := 'active';
      update public.project_milestones set status = v_to_status, actual_start = coalesce(actual_start, current_date),
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'block' and v_from_status = 'active' then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'blocked';
      update public.project_milestones set status = v_to_status, progress_note = trim(p_note), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'unblock' and v_from_status = 'blocked' then v_to_status := 'active';
      update public.project_milestones set status = v_to_status, updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'cancel' and v_from_status in ('draft','active','blocked','revision_requested') and v_is_admin then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'cancelled';
      update public.project_milestones set status = v_to_status, review_note = trim(p_note), reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'submit' and v_from_status in ('draft', 'active', 'blocked', 'revision_requested') then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      if not exists (select 1 from public.project_milestones where id = p_record_id and length(trim(coalesce(acceptance_criteria, ''))) > 0) then raise exception 'PROJECT_MILESTONE_ACCEPTANCE_REQUIRED'; end if;
      v_to_status := 'submitted';
      update public.project_milestones set status = v_to_status, progress_note = trim(p_note), submitted_by = v_actor_id,
        submitted_at = clock_timestamp(), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'revise' and v_from_status = 'submitted' and v_is_admin then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'revision_requested';
      update public.project_milestones set status = v_to_status, review_note = trim(p_note), reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'approve' and v_from_status = 'submitted' and v_is_admin then
      v_to_status := 'approved';
      update public.project_milestones set status = v_to_status, review_note = nullif(trim(p_note), ''), reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    elsif p_action = 'complete' and v_from_status = 'approved' and v_is_admin then
      v_to_status := 'completed';
      update public.project_milestones set status = v_to_status, progress_percent = 100, actual_finish = coalesce(actual_finish, current_date),
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_milestones.*) into v_result;
    else raise exception 'PROJECT_TRANSITION_INVALID'; end if;
  elsif p_record_type = 'blocker' then
    if not v_is_admin and not exists (select 1 from public.project_blockers blocker where blocker.id = p_record_id
      and (blocker.reported_by = v_actor_id or blocker.resolution_owner_id = v_actor_id)) then
      raise exception 'PROJECT_BLOCKER_EDIT_FORBIDDEN';
    end if;
    if p_action = 'acknowledge' and v_from_status = 'open' then v_to_status := 'acknowledged';
    elsif p_action = 'start_resolving' and v_from_status in ('open', 'acknowledged') then v_to_status := 'resolving';
    elsif p_action = 'resolve' and v_from_status in ('open', 'acknowledged', 'resolving') then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'resolved';
    elsif p_action = 'reopen' and v_from_status = 'resolved' then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'open';
    elsif p_action = 'escalate' and v_from_status <> 'resolved' then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := v_from_status;
      update public.project_blockers set escalated = true, escalation_reason = trim(p_note), escalated_by = v_actor_id,
        escalated_at = clock_timestamp(), updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_blockers.*) into v_result;
    else raise exception 'PROJECT_TRANSITION_INVALID'; end if;
    if p_action <> 'escalate' then
      update public.project_blockers set status = v_to_status,
        resolution_note = case when p_action = 'resolve' then trim(p_note) else resolution_note end,
        resolved_by = case when p_action = 'resolve' then v_actor_id else resolved_by end,
        resolved_at = case when p_action = 'resolve' then clock_timestamp() else resolved_at end,
        updated_by = v_actor_id, updated_at = clock_timestamp()
      where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_blockers.*) into v_result;
    end if;
  elsif p_record_type = 'risk' then
    if p_action = 'assess' and v_from_status = 'identified' then v_to_status := 'assessing';
    elsif p_action = 'mitigate' and v_from_status in ('identified', 'assessing') then v_to_status := 'mitigating';
    elsif p_action = 'monitor' and v_from_status in ('mitigating', 'assessing') then v_to_status := 'monitoring';
    elsif p_action = 'accept' and v_from_status not in ('accepted', 'closed') and v_is_admin then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'accepted';
    elsif p_action = 'close' and v_from_status not in ('accepted', 'closed') then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'closed';
    else raise exception 'PROJECT_TRANSITION_INVALID'; end if;
    update public.project_risks set status = v_to_status,
      acceptance_rationale = case when p_action = 'accept' then trim(p_note) else acceptance_rationale end,
      closure_note = case when p_action = 'close' then trim(p_note) else closure_note end,
      updated_by = v_actor_id, updated_at = clock_timestamp()
    where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_risks.*) into v_result;
  else
    if p_action = 'submit' and v_from_status = 'draft' then v_to_status := 'submitted';
    elsif p_action = 'request_revision' and v_from_status in ('submitted', 'resubmitted') and v_is_admin then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'revision_requested';
    elsif p_action = 'resubmit' and v_from_status = 'revision_requested' then v_to_status := 'resubmitted';
    elsif p_action = 'approve' and v_from_status in ('submitted', 'resubmitted') and v_is_admin then
      if exists (select 1 from public.project_decisions decision where decision.id = p_record_id and (
        length(trim(coalesce(decision.statement, ''))) = 0 or length(trim(coalesce(decision.rationale, ''))) = 0
        or jsonb_array_length(decision.alternatives) = 0 or length(trim(coalesce(decision.expected_impact, ''))) = 0
      )) then raise exception 'PROJECT_DECISION_APPROVAL_FIELDS_REQUIRED'; end if;
      if not exists (select 1 from public.project_decision_evidence link where link.decision_id = p_record_id) then raise exception 'PROJECT_DECISION_EVIDENCE_REQUIRED'; end if;
      if exists (
        select 1 from public.project_decision_evidence link
        join public.evidence_records evidence on evidence.id = link.evidence_id
        where link.decision_id = p_record_id and (
          evidence.workflow_status <> 'approved'
          or evidence.consent_status not in ('granted', 'not_applicable')
          or (evidence.respondent_id is not null and not exists (
            select 1 from public.respondents respondent
            where respondent.id = evidence.respondent_id and respondent.organization_id = evidence.organization_id
              and respondent.project_id = evidence.project_id and respondent.consent_status = 'granted'
              and exists (select 1 from public.consent_records consent
                where consent.respondent_id = respondent.id and consent.status = 'granted'
                  and (consent.quotation_allowed or consent.interview_allowed)
                  and consent.version = (select max(latest.version) from public.consent_records latest where latest.respondent_id = respondent.id))
          ))
        )
      ) then raise exception 'PROJECT_DECISION_EVIDENCE_INELIGIBLE'; end if;
      v_to_status := 'approved';
    elsif p_action = 'reject' and v_from_status in ('submitted', 'resubmitted') and v_is_admin then
      if length(trim(coalesce(p_note, ''))) < 8 then raise exception 'PROJECT_TRANSITION_NOTE_REQUIRED'; end if;
      v_to_status := 'rejected';
    elsif p_action = 'supersede' and v_from_status = 'approved' and v_is_admin then
      begin v_replacement_id := trim(p_note)::uuid; exception when invalid_text_representation then raise exception 'PROJECT_DECISION_REPLACEMENT_REQUIRED'; end;
      if not exists (select 1 from public.project_decisions replacement where replacement.id = v_replacement_id
        and replacement.project_id = v_project_id and replacement.status = 'approved') then raise exception 'PROJECT_DECISION_REPLACEMENT_REQUIRED'; end if;
      v_to_status := 'superseded';
    else raise exception 'PROJECT_TRANSITION_INVALID'; end if;

    update public.project_decisions set status = v_to_status,
      review_guidance = case when p_action in ('request_revision', 'reject') then trim(p_note) else review_guidance end,
      submitted_by = case when p_action in ('submit', 'resubmit') then v_actor_id else submitted_by end,
      submitted_at = case when p_action in ('submit', 'resubmit') then clock_timestamp() else submitted_at end,
      reviewed_by = case when p_action in ('approve', 'reject', 'request_revision', 'supersede') then v_actor_id else reviewed_by end,
      reviewed_at = case when p_action in ('approve', 'reject', 'request_revision', 'supersede') then clock_timestamp() else reviewed_at end,
      decision_maker_id = case when p_action = 'approve' then coalesce(decision_maker_id, v_actor_id) else decision_maker_id end,
      superseded_by_decision_id = case when p_action = 'supersede' then v_replacement_id else superseded_by_decision_id end,
      updated_by = v_actor_id, updated_at = clock_timestamp()
    where id = p_record_id and updated_at = p_expected_updated_at returning to_jsonb(project_decisions.*) into v_result;

    if p_action = 'approve' and v_result is not null then
      select coalesce(max(snapshot.version), 0) + 1 into v_snapshot_version
      from public.project_decision_snapshots snapshot where snapshot.decision_id = p_record_id;
      select jsonb_build_object(
        'decisionId', decision.id, 'organizationId', decision.organization_id, 'projectId', decision.project_id,
        'title', decision.title, 'statement', decision.statement, 'alternatives', decision.alternatives,
        'rationale', decision.rationale, 'expectedImpact', decision.expected_impact,
        'ownerId', decision.owner_id, 'decisionMakerId', decision.decision_maker_id,
        'approvedBy', v_actor_id, 'approvedAt', decision.reviewed_at, 'version', v_snapshot_version,
        'evidence', coalesce((select jsonb_agg(jsonb_build_object(
          'sourceId', evidence.id, 'title', evidence.title, 'evidenceText', evidence.evidence_text,
          'sourceLink', evidence.source_link, 'stance', link.stance, 'relevanceNote', link.relevance_note,
          'limitations', evidence.limitations, 'eligibleAtApproval', true,
          'evidenceApprovedAt', evidence.reviewed_at,
          'consent', case when consent.id is null then jsonb_build_object('status', 'not_applicable') else jsonb_build_object(
            'recordId', consent.id, 'version', consent.version, 'status', consent.status,
            'recordedAt', consent.created_at, 'grantedAt', consent.granted_at
          ) end,
          'provenance', jsonb_build_object(
            'recordedBy', evidence.recorded_by, 'recordedAt', evidence.recorded_at,
            'respondentId', evidence.respondent_id, 'sessionId', evidence.session_id,
            'evidenceType', coalesce(evidence.evidence_type, evidence.type),
            'consentStatus', evidence.consent_status, 'workflowStatus', evidence.workflow_status
          )
        ) order by case link.stance when 'supporting' then 1 else 2 end, link.created_at, link.id)
          from public.project_decision_evidence link
          join public.evidence_records evidence on evidence.id = link.evidence_id
          left join lateral (select record.* from public.consent_records record
            where record.respondent_id = evidence.respondent_id order by record.version desc limit 1) consent on true
          where link.decision_id = decision.id), '[]'::jsonb)
      ) into v_snapshot from public.project_decisions decision where decision.id = p_record_id;
      insert into public.project_decision_snapshots (
        organization_id, project_id, decision_id, version, snapshot, approved_by
      ) values (v_organization_id, v_project_id, p_record_id, v_snapshot_version, v_snapshot, v_actor_id);
    end if;
    if p_action = 'supersede' and v_result is not null then
      insert into public.project_decision_supersessions (
        organization_id, project_id, predecessor_decision_id, successor_decision_id,
        predecessor_snapshot_id, successor_snapshot_id, superseded_by
      ) values (
        v_organization_id, v_project_id, p_record_id, v_replacement_id,
        (select snapshot.id from public.project_decision_snapshots snapshot where snapshot.decision_id = p_record_id order by snapshot.version desc limit 1),
        (select snapshot.id from public.project_decision_snapshots snapshot where snapshot.decision_id = v_replacement_id order by snapshot.version desc limit 1),
        v_actor_id
      );
    end if;
  end if;

  if v_result is null then raise exception 'PROJECT_RECORD_STALE_WRITE'; end if;
  insert into public.project_record_history (
    organization_id, project_id, record_type, record_id, actor_id, action, from_status, to_status, note,
    metadata
  ) values (
    v_organization_id, v_project_id, p_record_type, p_record_id, v_actor_id, p_action,
    v_from_status, v_to_status, nullif(trim(p_note), ''),
    case when p_action = 'supersede' then jsonb_build_object('replacementDecisionId', v_replacement_id) else '{}'::jsonb end
  );
  if p_client_nonce is not null then
    insert into public.project_mutation_operations (
      organization_id, project_id, actor_id, client_nonce, operation_key, request_hash, result
    ) values (v_organization_id, v_project_id, v_actor_id, p_client_nonce, 'transition_record', v_request_hash, v_result);
  end if;
  return v_result;
end;
$$;

-- Extend the checked collaboration source types without weakening the registry.
alter table public.work_inbox_items drop constraint work_inbox_items_source_type_check;
alter table public.work_inbox_items add constraint work_inbox_items_source_type_check check (source_type in (
  'task', 'respondent', 'session', 'evidence', 'product_event', 'value_exchange', 'observation',
  'milestone', 'blocker', 'risk', 'decision'
));
alter table public.work_comments drop constraint work_comments_source_type_check;
alter table public.work_comments add constraint work_comments_source_type_check check (source_type in (
  'task', 'respondent', 'session', 'evidence', 'product_event', 'value_exchange', 'observation',
  'milestone', 'blocker', 'risk', 'decision'
));

create or replace function public.aoi_can_access_work_source(
  p_organization_id uuid, p_project_id uuid, p_source_type text, p_source_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.aoi_can_access_project(p_organization_id, p_project_id) and
    case when p_source_type in ('milestone', 'blocker', 'risk', 'decision') then (
      (p_source_type = 'milestone' and exists (select 1 from public.project_milestones source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'blocker' and exists (select 1 from public.project_blockers source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'risk' and exists (select 1 from public.project_risks source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'decision' and exists (select 1 from public.project_decisions source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
    )
    else (
      (p_source_type = 'task' and exists (select 1 from public.tasks source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'respondent' and exists (select 1 from public.respondents source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'session' and exists (select 1 from public.research_sessions source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'evidence' and exists (select 1 from public.evidence_records source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'product_event' and exists (select 1 from public.product_events source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'value_exchange' and exists (select 1 from public.value_exchange_observations source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
      or (p_source_type = 'observation' and exists (select 1 from public.pmf_observations source where source.id = p_source_id and source.organization_id = p_organization_id and source.project_id = p_project_id))
    ) end;
$$;

create or replace function private.aoi_work_source_context(p_source_type text, p_source_id uuid)
returns table (organization_id uuid, project_id uuid, title text, source_status text, assigned_to uuid, priority text, due_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select task.organization_id, task.project_id, task.title, task.status, task.assigned_to, task.priority, task.due_date::timestamptz from public.tasks task where p_source_type = 'task' and task.id = p_source_id
  union all select source.organization_id, source.project_id, source.external_id, source.workflow_status, source.assigned_to, 'medium', source.retention_review_at::timestamptz from public.respondents source where p_source_type = 'respondent' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.method, source.workflow_status, source.assigned_to, 'medium', source.session_date::timestamptz from public.research_sessions source where p_source_type = 'session' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.title, source.workflow_status, source.assigned_to, 'medium', null::timestamptz from public.evidence_records source where p_source_type = 'evidence' and source.id = p_source_id
  union all select source.organization_id, source.project_id, 'Product event ' || source.event_date, source.workflow_status, source.assigned_to, 'medium', source.event_date::timestamptz from public.product_events source where p_source_type = 'product_event' and source.id = p_source_id
  union all select source.organization_id, source.project_id, 'Value exchange ' || source.observed_at, source.workflow_status, source.assigned_to, 'medium', source.observed_at::timestamptz from public.value_exchange_observations source where p_source_type = 'value_exchange' and source.id = p_source_id
  union all select source.organization_id, source.project_id, definition.label, source.workflow_status, source.assigned_to, 'medium', null::timestamptz from public.pmf_observations source join public.pmf_metric_definitions definition on definition.id = source.definition_id where p_source_type = 'observation' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.title, source.status, source.owner_id, 'medium', coalesce(source.next_action_due, source.planned_finish)::timestamptz from public.project_milestones source where p_source_type = 'milestone' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.title, source.status, source.resolution_owner_id, source.impact, coalesce(source.next_action_due, source.expected_resolution_date)::timestamptz from public.project_blockers source where p_source_type = 'blocker' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.statement, source.status, source.owner_id, case when source.score >= 16 then 'critical' when source.score >= 10 then 'high' when source.score >= 5 then 'medium' else 'low' end, coalesce(source.review_date, source.next_action_due)::timestamptz from public.project_risks source where p_source_type = 'risk' and source.id = p_source_id
  union all select source.organization_id, source.project_id, source.title, source.status, source.owner_id, 'medium', null::timestamptz from public.project_decisions source where p_source_type = 'decision' and source.id = p_source_id;
$$;

create or replace function private.aoi_actor_can_access_work_source(
  p_actor_id uuid, p_organization_id uuid, p_project_id uuid, p_source_type text, p_source_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.aoi_actor_can_access_project(p_actor_id, p_organization_id, p_project_id)
    and case when p_source_type in ('milestone', 'blocker', 'risk', 'decision')
    then exists (select 1 from private.aoi_work_source_context(p_source_type, p_source_id) source where source.organization_id = p_organization_id and source.project_id = p_project_id)
    else exists (
      select 1 from private.aoi_work_source_context(p_source_type, p_source_id) source
      join public.projects project on project.id = source.project_id and project.organization_id = source.organization_id and project.status = 'active'
      join public.organization_memberships membership on membership.organization_id = source.organization_id and membership.user_id = p_actor_id and membership.status = 'active'
      join public.profiles profile on profile.id = membership.user_id and profile.status = 'active' and not profile.must_change_password
      where source.organization_id = p_organization_id and source.project_id = p_project_id
        and (membership.role = 'admin' or source.assigned_to = p_actor_id or (p_source_type <> 'task' and source.source_status in ('approved', 'archived')))
    ) end;
$$;

create or replace function private.aoi_work_source_link(p_source_type text, p_source_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_source_type = 'task' then 'workspace.html?view=today&tab=tasks&task=' || p_source_id
    when p_source_type in ('milestone', 'blocker', 'risk', 'decision') then
      'workspace.html?view=projects&project=' || source.project_id || '&tab=' ||
      case p_source_type when 'milestone' then 'milestones&milestone='
        when 'blocker' then 'blockers&blocker=' when 'risk' then 'risks&risk='
        else 'decisions&decision=' end || p_source_id
    else 'workspace.html?view=research&tab=collect&type=' || p_source_type || '&id=' || p_source_id
  end
  from (select project_id from private.aoi_work_source_context(p_source_type, p_source_id) limit 1) source;
$$;

alter function private.refresh_aoi_work_inbox(uuid) rename to refresh_aoi_legacy_work_inbox;
revoke all on function private.refresh_aoi_legacy_work_inbox(uuid) from public, anon, authenticated;

create function private.refresh_aoi_work_inbox(p_project_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer := private.refresh_aoi_legacy_work_inbox(p_project_id);
  v_count integer;
begin
  with sources as (
    select 'milestone'::text source_type, id source_id, organization_id, project_id, title,
      status source_status, owner_id assigned_to, 'medium'::text priority,
      coalesce(next_action_due, planned_finish)::timestamptz due_at,
      case status when 'revision_requested' then 'Milestone revision requested' else 'Assigned milestone needs progress' end reason,
      case status when 'revision_requested' then '["resubmit"]'::jsonb else '["edit","submit"]'::jsonb end actions
    from public.project_milestones where status in ('draft', 'active', 'blocked', 'revision_requested')
    union all select 'blocker', id, organization_id, project_id, title, status, resolution_owner_id, impact,
      coalesce(next_action_due, expected_resolution_date)::timestamptz, 'Blocker resolution action required',
      '["acknowledge","start_resolving","resolve","escalate"]'::jsonb
    from public.project_blockers where status <> 'resolved'
    union all select 'risk', id, organization_id, project_id, statement, status, owner_id,
      case when score >= 16 then 'critical' when score >= 10 then 'high' when score >= 5 then 'medium' else 'low' end,
      coalesce(review_date, next_action_due)::timestamptz, 'Risk review or mitigation action required',
      '["assess","mitigate","monitor","accept","close"]'::jsonb
    from public.project_risks where status not in ('accepted', 'closed')
    union all select 'decision', id, organization_id, project_id, title, status, owner_id, 'medium', null::timestamptz,
      case status when 'revision_requested' then 'Decision revision requested' else 'Decision draft needs completion' end,
      case status when 'revision_requested' then '["edit","resubmit"]'::jsonb else '["edit","submit"]'::jsonb end
    from public.project_decisions where status in ('draft', 'revision_requested')
  )
  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role, source_type, source_id,
    dedupe_key, category, reason, summary, priority, due_at, assignee_id, deep_link, source_actions
  )
  select source.organization_id, source.project_id, source.assigned_to, membership.role,
    source.source_type, source.source_id, 'derived:assignee:' || source.source_type || ':' || source.source_id,
    'action', source.reason, source.title, source.priority, source.due_at, source.assigned_to,
    private.aoi_work_source_link(source.source_type, source.source_id), source.actions
  from sources source
  join public.organization_memberships membership on membership.organization_id = source.organization_id
    and membership.user_id = source.assigned_to and membership.status = 'active'
  where (p_project_id is null or source.project_id = p_project_id)
    and private.aoi_actor_can_access_project(source.assigned_to, source.organization_id, source.project_id)
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    reason = excluded.reason, summary = excluded.summary, priority = excluded.priority, due_at = excluded.due_at,
    assignee_id = excluded.assignee_id, resolved_at = null, source_actions = excluded.source_actions, updated_at = clock_timestamp();
  get diagnostics v_count = row_count; v_changed := v_changed + v_count;

  with reviews as (
    select 'milestone'::text source_type, id source_id, organization_id, project_id, title,
      'medium'::text priority, owner_id assigned_to, 'Submitted milestone requires administrator review' reason,
      '["approve","revise"]'::jsonb actions from public.project_milestones where status = 'submitted'
    union all select 'decision', id, organization_id, project_id, title, 'medium', owner_id,
      'Submitted decision requires administrator review', '["approve","request_revision","reject"]'::jsonb
      from public.project_decisions where status in ('submitted', 'resubmitted')
    union all select 'blocker', id, organization_id, project_id, title, impact, resolution_owner_id,
      'Escalated blocker requires administrator attention', '["acknowledge","start_resolving","resolve"]'::jsonb
      from public.project_blockers where escalated and status <> 'resolved'
  )
  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role, source_type, source_id,
    dedupe_key, category, reason, summary, priority, assignee_id, deep_link, source_actions
  )
  select source.organization_id, source.project_id, membership.user_id, membership.role,
    source.source_type, source.source_id, 'derived:review:' || source.source_type || ':' || source.source_id,
    'action', source.reason, source.title, source.priority, source.assigned_to,
    private.aoi_work_source_link(source.source_type, source.source_id), source.actions
  from reviews source
  join public.organization_memberships membership on membership.organization_id = source.organization_id
    and membership.role = 'admin' and membership.status = 'active'
  where p_project_id is null or source.project_id = p_project_id
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    reason = excluded.reason, summary = excluded.summary, priority = excluded.priority,
    assignee_id = excluded.assignee_id, resolved_at = null, source_actions = excluded.source_actions, updated_at = clock_timestamp();
  get diagnostics v_count = row_count; v_changed := v_changed + v_count;

  update public.work_inbox_items item set resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  where item.resolved_at is null and item.source_type in ('milestone', 'blocker', 'risk', 'decision')
    and item.dedupe_key like 'derived:%' and (p_project_id is null or item.project_id = p_project_id)
    and not exists (
      select 1 from private.aoi_work_source_context(item.source_type, item.source_id) source
      join public.organization_memberships membership on membership.organization_id = item.organization_id
        and membership.user_id = item.recipient_id and membership.status = 'active'
      where source.organization_id = item.organization_id and source.project_id = item.project_id
        and ((item.dedupe_key like 'derived:assignee:%' and source.assigned_to = item.recipient_id and (
          (item.source_type = 'milestone' and source.source_status in ('draft', 'active', 'blocked', 'revision_requested'))
          or (item.source_type = 'blocker' and source.source_status <> 'resolved')
          or (item.source_type = 'risk' and source.source_status not in ('accepted', 'closed'))
          or (item.source_type = 'decision' and source.source_status in ('draft', 'revision_requested'))
        )) or (item.dedupe_key like 'derived:review:%' and membership.role = 'admin' and (
          (item.source_type = 'milestone' and source.source_status = 'submitted')
          or (item.source_type = 'decision' and source.source_status in ('submitted', 'resubmitted'))
          or (item.source_type = 'blocker' and source.source_status <> 'resolved'
            and exists (select 1 from public.project_blockers blocker where blocker.id = item.source_id and blocker.escalated))
        )))
    );
  get diagnostics v_count = row_count; v_changed := v_changed + v_count;

  update public.work_handoffs handoff set resolved_at = clock_timestamp()
  where handoff.resolved_at is null and handoff.source_type in ('milestone', 'blocker', 'risk', 'decision')
    and (p_project_id is null or handoff.project_id = p_project_id)
    and exists (select 1 from private.aoi_work_source_context(handoff.source_type, handoff.source_id) source
      where source.organization_id = handoff.organization_id and source.project_id = handoff.project_id
        and ((handoff.source_type = 'milestone' and source.source_status in ('completed', 'cancelled'))
          or (handoff.source_type = 'blocker' and source.source_status = 'resolved')
          or (handoff.source_type = 'risk' and source.source_status in ('accepted', 'closed'))
          or (handoff.source_type = 'decision' and source.source_status in ('approved', 'rejected', 'superseded'))));
  get diagnostics v_count = row_count; v_changed := v_changed + v_count;
  update public.work_inbox_items item set resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  from public.work_handoffs handoff where item.resolved_at is null and item.dedupe_key = 'handoff:' || handoff.id and handoff.resolved_at is not null;
  get diagnostics v_count = row_count;
  return v_changed + v_count;
end;
$$;

revoke all on function private.aoi_work_source_context(text, uuid) from public, anon, authenticated;
revoke all on function private.aoi_actor_can_access_work_source(uuid, uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.aoi_work_source_link(text, uuid) from public, anon, authenticated;
revoke all on function private.refresh_aoi_work_inbox(uuid) from public, anon, authenticated;

alter function public.rpc_aoi_pmf_snapshot() rename to rpc_aoi_pmf_snapshot_legacy;
alter function public.rpc_aoi_collect_snapshot() rename to rpc_aoi_collect_snapshot_legacy;
alter function public.rpc_aoi_gamification_summary() rename to rpc_aoi_gamification_summary_legacy;
alter function public.rpc_aoi_inbox_snapshot(text, uuid) rename to rpc_aoi_inbox_snapshot_legacy;
alter function public.rpc_aoi_pmf_snapshot_legacy() set schema private;
alter function public.rpc_aoi_collect_snapshot_legacy() set schema private;
alter function public.rpc_aoi_gamification_summary_legacy() set schema private;
alter function public.rpc_aoi_inbox_snapshot_legacy(text, uuid) set schema private;
revoke all on function private.rpc_aoi_pmf_snapshot_legacy() from public, anon, authenticated;
revoke all on function private.rpc_aoi_collect_snapshot_legacy() from public, anon, authenticated;
revoke all on function private.rpc_aoi_gamification_summary_legacy() from public, anon, authenticated;
revoke all on function private.rpc_aoi_inbox_snapshot_legacy(text, uuid) from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
grant execute on function private.rpc_aoi_pmf_snapshot_legacy(), private.rpc_aoi_collect_snapshot_legacy(),
  private.rpc_aoi_gamification_summary_legacy() to authenticated, service_role;
grant execute on function private.rpc_aoi_inbox_snapshot_legacy(text, uuid) to service_role;

create function public.rpc_aoi_pmf_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_project_id uuid;
begin
  -- Consent-sensitive rows remain filtered inside the legacy payload query:
  -- respondent.consent_status = 'granted' and e.respondent_id is null or exists.
  -- aoi_apply_project_context resolves through private.aoi_resolve_project(auth.uid(), null).
  v_project_id := public.aoi_apply_project_context(null);
  return private.rpc_aoi_pmf_snapshot_legacy();
end; $$;

create function public.rpc_aoi_collect_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_project_id uuid;
begin
  -- Resolve through private.aoi_resolve_project(auth.uid(), null).
  v_project_id := public.aoi_apply_project_context(null);
  return private.rpc_aoi_collect_snapshot_legacy();
end; $$;

create function public.rpc_aoi_gamification_summary()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_project_id uuid;
begin
  -- Resolve through private.aoi_resolve_project(auth.uid(), null).
  v_project_id := public.aoi_apply_project_context(null);
  return private.rpc_aoi_gamification_summary_legacy();
end; $$;

create function public.rpc_aoi_inbox_snapshot(p_bucket text default 'needs_action', p_project_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_project_id uuid := private.aoi_resolve_project((select auth.uid()), p_project_id);
begin
  return private.rpc_aoi_inbox_snapshot_legacy(p_bucket, v_project_id);
end; $$;

create or replace function public.rpc_aoi_demo_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid;
  v_organization_id uuid;
  v_role text;
begin
  -- Resolution enforces profile.status = 'active', not profile.must_change_password,
  -- and organization.status = 'active' before any payload is built.
  begin
    v_project_id := private.aoi_resolve_project(v_actor_id, null);
  exception when others then
    if sqlerrm in ('PROJECT_NOT_FOUND', 'PROJECT_SELECTION_REQUIRED') then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
    raise;
  end;
  select project.organization_id into v_organization_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_organization_id and membership.user_id = v_actor_id and membership.status = 'active';
  return (select jsonb_build_object(
    'organization', jsonb_build_object('id', organization.id, 'name', organization.name, 'slug', organization.slug),
    'project', jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name, 'description', project.description, 'currentWeek', project.current_week, 'startDate', project.start_date, 'endDate', project.end_date),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', metric.metric_key, 'label', metric.label, 'value', metric.value, 'target', metric.target, 'unit', metric.unit, 'delta', metric.delta)) from public.project_metrics metric where metric.project_id = v_project_id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', task.id, 'title', task.title, 'objective', task.objective, 'status', task.status, 'priority', task.priority, 'ownerName', task.owner_name, 'ownerInitials', task.owner_initials, 'assignedTo', task.assigned_to, 'dueDate', task.due_date, 'pmfLayer', task.pmf_layer, 'progress', task.progress, 'points', task.points, 'acceptanceCriteria', task.acceptance_criteria, 'estimatedHours', task.estimated_hours, 'submittedAt', task.submitted_at, 'reviewedAt', task.reviewed_at, 'approvedAt', task.approved_at, 'completedAt', task.completed_at, 'updatedAt', task.updated_at) order by task.due_date nulls last, task.priority desc) from public.tasks task where task.organization_id = v_organization_id and task.project_id = v_project_id and (v_role = 'admin' or task.assigned_to = v_actor_id)), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object('id', sample.id, 'label', sample.label, 'pmfLayer', sample.pmf_layer, 'actual', sample.actual, 'target', sample.target, 'accent', sample.accent) order by sample.created_at, sample.id) from public.sample_plan_items sample where sample.project_id = v_project_id), '[]'::jsonb),
    'pmfLayers', coalesce((select jsonb_agg(jsonb_build_object('id', layer.id, 'code', layer.code, 'name', layer.name, 'sequence', layer.sequence, 'confidence', layer.confidence, 'status', layer.status, 'evidenceCount', layer.evidence_count, 'counterevidenceCount', layer.counterevidence_count, 'nextAction', layer.next_action) order by layer.sequence) from public.pmf_layers layer where layer.project_id = v_project_id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('id', activity.id, 'actorName', activity.actor_name, 'actorInitials', activity.actor_initials, 'action', activity.action, 'subject', activity.subject, 'eventType', activity.event_type, 'occurredAt', activity.occurred_at) order by activity.occurred_at desc) from public.activity_events activity where activity.project_id = v_project_id), '[]'::jsonb),
    'signals', coalesce((select jsonb_agg(jsonb_build_object('id', signal.id, 'theme', signal.theme, 'stance', signal.stance, 'evidenceCount', signal.evidence_count, 'changePercent', signal.change_percent, 'strength', signal.strength) order by signal.evidence_count desc) from public.research_signals signal where signal.project_id = v_project_id), '[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id', progress.id, 'displayName', progress.display_name, 'initials', progress.initials, 'roleLabel', progress.role_label, 'points', progress.points, 'weeklyPoints', progress.weekly_points, 'streakDays', progress.streak_days, 'completedTasks', progress.completed_tasks, 'rank', progress.rank) order by progress.rank) from public.team_progress progress where progress.project_id = v_project_id), '[]'::jsonb),
    'generatedAt', now()
  ) from public.projects project join public.organizations organization on organization.id = project.organization_id
  where project.id = v_project_id and project.organization_id = v_organization_id);
end; $$;

create or replace function public.rpc_aoi_operations_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor_id uuid := (select auth.uid()); v_project_id uuid := private.aoi_resolve_project(v_actor_id, null); v_org_id uuid; v_role text;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  return jsonb_build_object(
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'externalId', c.external_id, 'name', c.name, 'category', c.category, 'platforms', c.platforms, 'reach', c.reach, 'tier', c.tier, 'creatorType', c.creator_type, 'fitLevel', c.fit_level, 'contactReadiness', c.contact_readiness, 'contactChannel', c.contact_channel, 'contactDetail', c.contact_detail, 'sourceUrl', c.source_url, 'pmfCandidate', c.pmf_candidate, 'pmfRationale', c.pmf_rationale, 'priorityScore', c.priority_score, 'priorityBand', c.priority_band, 'ownerName', profile.display_name, 'outreachStatus', c.outreach_status, 'interestLevel', c.interest_level, 'preferredCollaboration', c.preferred_collaboration, 'deckIntroduced', c.deck_introduced, 'pmfAsked', c.pmf_asked, 'firstOutreach', c.first_outreach, 'nextStep', c.next_step, 'nextStepDue', c.next_step_due, 'notes', c.notes, 'lastUpdated', c.updated_at::date) order by c.priority_score desc, c.next_step_due nulls last) from public.candidates c left join public.profiles profile on profile.id = c.owner_id where c.organization_id = v_org_id and c.project_id = v_project_id and (v_role = 'admin' or c.owner_id = v_actor_id)), '[]'::jsonb),
    'outreachEvents', coalesce((select jsonb_agg(jsonb_build_object('id', event.id, 'candidateId', event.candidate_id, 'channel', event.channel, 'kind', event.kind, 'status', event.status, 'occurredAt', event.occurred_at, 'actorName', coalesce(profile.display_name, 'AOI'), 'summary', event.summary) order by event.occurred_at desc) from public.outreach_events event left join public.profiles profile on profile.id = event.actor_id where event.organization_id = v_org_id and event.project_id = v_project_id), '[]'::jsonb),
    'evidenceRecords', coalesce((select jsonb_agg(jsonb_build_object('id', record.id, 'candidateId', record.candidate_id, 'type', record.type, 'stance', record.stance, 'strength', record.strength, 'title', record.title, 'notes', record.notes, 'consentStatus', record.consent_status, 'recordedBy', coalesce(profile.display_name, 'AOI'), 'recordedAt', record.recorded_at) order by record.recorded_at desc) from public.evidence_records record left join public.profiles profile on profile.id = record.recorded_by where record.organization_id = v_org_id and record.project_id = v_project_id and (v_role = 'admin' or record.candidate_id in (select owned.id from public.candidates owned where owned.id = record.candidate_id and owned.owner_id = v_actor_id))), '[]'::jsonb)
  );
end; $$;

create or replace function public.rpc_aoi_crm_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor_id uuid := (select auth.uid()); v_project_id uuid := private.aoi_resolve_project(v_actor_id, null); v_org_id uuid; v_role text;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  return jsonb_build_object(
    'crmContacts', coalesce((select jsonb_agg(jsonb_build_object(
      'id', contact.id, 'candidateId', candidate.id, 'contactType', contact.contact_type,
      'name', contact.name, 'organization', contact.organization_name, 'email', contact.email,
      'phone', contact.phone, 'primaryChannel', contact.primary_channel, 'sourceUrl', contact.source_url,
      'tags', contact.tags, 'ownerId', contact.owner_id, 'ownerName', owner.display_name,
      'lifecycle', contact.lifecycle, 'nextAction', contact.next_action,
      'nextActionDue', contact.next_action_due, 'priorityScore', contact.priority_score,
      'notes', contact.notes, 'outreachStatus', candidate.outreach_status,
      'category', candidate.category, 'pmfCandidate', candidate.pmf_candidate,
      'activityCount', (select count(*) from public.crm_activity activity where activity.contact_id = contact.id)
    ) order by contact.next_action_due nulls last, contact.priority_score desc)
      from public.crm_contacts contact left join public.candidates candidate on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id and candidate.project_id = contact.project_id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.organization_id = v_org_id and contact.project_id = v_project_id and (v_role = 'admin' or contact.owner_id = v_actor_id)), '[]'::jsonb),
    'crmActivity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', activity.id, 'contactId', activity.contact_id, 'activityType', activity.activity_type,
      'summary', activity.summary, 'actorName', coalesce(actor.display_name, 'AOI'), 'createdAt', activity.created_at
    ) order by activity.created_at desc) from public.crm_activity activity join public.crm_contacts contact on contact.id = activity.contact_id
      left join public.profiles actor on actor.id = activity.actor_id where activity.organization_id = v_org_id and activity.project_id = v_project_id
        and (v_role = 'admin' or contact.owner_id = v_actor_id)), '[]'::jsonb),
    'crmProgress', jsonb_build_object(
      'xp', coalesce((select sum(reward.points) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = v_actor_id), 0),
      'completedToday', coalesce((select count(*) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = v_actor_id and reward.reward_date = current_date), 0),
      'streakDays', coalesce((select count(distinct reward.reward_date) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = v_actor_id and reward.reward_date >= current_date - 6), 0)
    )
  );
end; $$;

create or replace function public.rpc_aoi_daily_eod_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor_id uuid := (select auth.uid()); v_project_id uuid := private.aoi_resolve_project(v_actor_id, null); v_org_id uuid; v_role text; v_timezone text; v_local_now timestamp; v_brief_date date; v_is_workday boolean; v_brief public.daily_eod_briefs%rowtype; v_due_state text;
begin
  select project.organization_id, organization.timezone into v_org_id, v_timezone from public.projects project join public.organizations organization on organization.id = project.organization_id where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  v_local_now := timezone(v_timezone, clock_timestamp()); v_brief_date := v_local_now::date; v_is_workday := extract(isodow from v_brief_date) between 1 and 5;
  select brief.* into v_brief from public.daily_eod_briefs brief where brief.project_id = v_project_id and brief.author_id = v_actor_id and brief.brief_date = v_brief_date;
  v_due_state := case when v_brief.workflow_status = 'completed' then 'completed' when v_brief.workflow_status = 'submitted' then 'submitted' when not v_is_workday then 'not_required' when v_local_now >= v_brief_date + time '17:00' then 'overdue' else 'due' end;
  return jsonb_build_object('dailyEod', jsonb_build_object(
    'serverDate', v_brief_date, 'serverNow', clock_timestamp(), 'timezone', v_timezone, 'isWorkday', v_is_workday,
    'dueAt', (v_brief_date + time '17:00') at time zone v_timezone, 'dueState', v_due_state,
    'myBrief', case when v_brief.id is null then null else public.daily_eod_brief_json(v_brief) end,
    'members', coalesce((select jsonb_agg(jsonb_build_object('userId', membership.user_id, 'displayName', profile.display_name, 'role', membership.role) order by profile.display_name)
      from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'
        and (v_role = 'admin' or private.aoi_actor_can_access_project(membership.user_id, v_org_id, v_project_id))), '[]'::jsonb),
    'teamToday', case when v_role <> 'admin' then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
      'userId', membership.user_id, 'displayName', profile.display_name, 'role', membership.role, 'briefId', brief.id,
      'workflowStatus', coalesce(brief.workflow_status, case when v_is_workday then 'missing' else 'not_required' end),
      'brief', case when brief.id is null then null else public.daily_eod_brief_json(brief) end, 'submittedAt', brief.submitted_at,
      'isLate', coalesce(brief.is_late, false), 'projectStatus', brief.project_status, 'updatedAt', brief.updated_at) order by profile.display_name)
      from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      left join public.daily_eod_briefs brief on brief.project_id = v_project_id and brief.author_id = membership.user_id and brief.brief_date = v_brief_date
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'), '[]'::jsonb) end
  ));
end; $$;

create or replace function public.rpc_aoi_participant_tracker_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor_id uuid := (select auth.uid()); v_project_id uuid := private.aoi_resolve_project(v_actor_id, null); v_org_id uuid;
begin
  select project.organization_id into v_org_id from public.projects project where project.id = v_project_id;
  return jsonb_build_object('projectId', v_project_id,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.id, 'participantId', item.participant_id, 'name', item.full_name, 'email', item.email,
      'phone', item.phone, 'source', item.recruitment_source, 'timeZone', item.timezone, 'status', item.status,
      'segment', item.segment, 'consentStatus', item.consent_status, 'ownerId', item.owner_id, 'ownerName', owner.display_name,
      'nextAction', item.next_action, 'nextActionDue', item.next_action_due, 'interviewDate', item.interview_date,
      'qualificationNotes', item.qualification_notes, 'notes', item.notes, 'crmContactId', item.crm_contact_id,
      'respondentId', item.respondent_id, 'updatedAt', item.updated_at) order by item.next_action_due nulls last, item.created_at)
      from public.participant_recruitment item left join public.profiles owner on owner.id = item.owner_id
      where item.organization_id = v_org_id and item.project_id = v_project_id and (public.is_org_admin(v_org_id) or item.owner_id = v_actor_id)), '[]'::jsonb));
end; $$;

revoke all on public.project_preferences, public.project_members, public.project_milestones,
  public.project_blockers, public.project_risks, public.project_decisions,
  public.project_decision_evidence, public.project_decision_snapshots,
  public.project_record_history, public.project_history, public.project_decision_supersessions,
  public.project_mutation_operations from public, anon, authenticated;
grant select on public.project_preferences, public.project_members, public.project_milestones,
  public.project_blockers, public.project_risks, public.project_decisions,
  public.project_decision_evidence, public.project_decision_snapshots,
  public.project_record_history, public.project_history, public.project_decision_supersessions,
  public.project_mutation_operations to authenticated;
grant all on public.project_preferences, public.project_members, public.project_milestones,
  public.project_blockers, public.project_risks, public.project_decisions,
  public.project_decision_evidence, public.project_decision_snapshots,
  public.project_record_history, public.project_history, public.project_decision_supersessions,
  public.project_mutation_operations to service_role;

revoke all on function public.rpc_aoi_project_context() from public, anon, authenticated;
revoke all on function public.rpc_aoi_select_project(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_project_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_project_record_detail(text, uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_admin_save_project(jsonb, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.rpc_aoi_admin_set_project_member(uuid, uuid, boolean, text, timestamptz) from public, anon, authenticated;
revoke all on function public.rpc_aoi_transition_project(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.rpc_aoi_save_project_record(text, jsonb, uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_transition_project_record(text, uuid, text, text, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_pmf_snapshot(), public.rpc_aoi_collect_snapshot(),
  public.rpc_aoi_gamification_summary(), public.rpc_aoi_inbox_snapshot(text, uuid) from public, anon, authenticated;
grant execute on function public.rpc_aoi_project_context() to authenticated, service_role;
grant execute on function public.rpc_aoi_select_project(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_project_snapshot(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_project_record_detail(text, uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_admin_save_project(jsonb, uuid, timestamptz) to authenticated, service_role;
grant execute on function public.rpc_aoi_admin_set_project_member(uuid, uuid, boolean, text, timestamptz) to authenticated, service_role;
grant execute on function public.rpc_aoi_transition_project(uuid, text, text, timestamptz) to authenticated, service_role;
grant execute on function public.rpc_aoi_save_project_record(text, jsonb, uuid, timestamptz, uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_transition_project_record(text, uuid, text, text, timestamptz, uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_pmf_snapshot(), public.rpc_aoi_collect_snapshot(),
  public.rpc_aoi_gamification_summary(), public.rpc_aoi_inbox_snapshot(text, uuid) to authenticated, service_role;

select private.refresh_aoi_work_inbox(null);

comment on table public.project_decision_snapshots is 'Immutable evidence-bearing decision state captured atomically at approval.';
comment on function public.rpc_aoi_project_context() is 'Returns explicit authorized organization/project options and the validated selected context.';
