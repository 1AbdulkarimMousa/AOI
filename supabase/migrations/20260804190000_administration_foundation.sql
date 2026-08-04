-- Administration foundation: durable staff lifecycle, ownership, onboarding, and data transfer.
-- People are archived rather than deleted so assignments, authorship, activity, and audit history remain intact.

alter table public.profiles
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id) on delete restrict;
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check
  check (status in ('active', 'invited', 'password_change_required', 'disabled', 'archived')) not valid;
alter table public.profiles validate constraint profiles_status_check;
alter table public.profiles drop constraint if exists profiles_id_fkey;
alter table public.profiles add constraint profiles_id_fkey
  foreign key (id) references auth.users(id) on delete restrict not valid;
alter table public.profiles validate constraint profiles_id_fkey;

alter table public.organization_memberships
  add column if not exists is_owner boolean not null default false,
  add column if not exists departure_date date,
  add column if not exists archive_reason text,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id) on delete restrict;
alter table public.organization_memberships drop constraint if exists organization_memberships_status_check;
alter table public.organization_memberships add constraint organization_memberships_status_check
  check (status in ('active', 'invited', 'password_change_required', 'disabled', 'archived')) not valid;
alter table public.organization_memberships validate constraint organization_memberships_status_check;
alter table public.organization_memberships drop constraint if exists organization_memberships_user_id_fkey;
alter table public.organization_memberships add constraint organization_memberships_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete restrict not valid;
alter table public.organization_memberships validate constraint organization_memberships_user_id_fkey;

with ranked_owners as (
  select membership.organization_id, membership.user_id,
    row_number() over (
      partition by membership.organization_id
      order by case membership.role when 'admin' then 1 else 2 end,
        membership.joined_at, membership.user_id
    ) as owner_rank
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.status = 'active' and profile.status = 'active'
)
update public.organization_memberships membership
set role = 'admin', is_owner = true, updated_at = now()
from ranked_owners candidate
where candidate.organization_id = membership.organization_id
  and candidate.user_id = membership.user_id
  and candidate.owner_rank = 1
  and not exists (
    select 1 from public.organization_memberships existing
    where existing.organization_id = membership.organization_id and existing.is_owner
  );

alter table public.organization_memberships
  add constraint organization_memberships_owner_check
  check (not is_owner or (role = 'admin' and status = 'active')) not valid;
alter table public.organization_memberships validate constraint organization_memberships_owner_check;
create unique index organization_memberships_one_owner_idx
  on public.organization_memberships (organization_id) where is_owner;
create index memberships_admin_lifecycle_idx
  on public.organization_memberships (organization_id, status, role, joined_at);

create table public.staff_profiles (
  organization_id uuid not null,
  user_id uuid not null,
  phone text,
  timezone text not null default 'America/New_York',
  manager_id uuid,
  skills text[] not null default '{}'::text[],
  availability text,
  start_date date,
  end_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  foreign key (organization_id, user_id)
    references public.organization_memberships (organization_id, user_id) on delete restrict,
  foreign key (organization_id, manager_id)
    references public.organization_memberships (organization_id, user_id) on delete restrict,
  check (manager_id is null or manager_id <> user_id)
);
create index staff_profiles_manager_idx
  on public.staff_profiles (organization_id, manager_id) where manager_id is not null;
create index staff_profiles_skills_idx on public.staff_profiles using gin (skills);

create table public.staff_onboarding_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  user_id uuid not null,
  step_key text not null,
  label text not null,
  sequence integer not null default 0 check (sequence >= 0),
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'completed', 'waived')),
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id, step_key),
  foreign key (organization_id, user_id)
    references public.staff_profiles (organization_id, user_id) on delete restrict,
  check ((status = 'completed' and completed_at is not null) or status <> 'completed')
);
create index staff_onboarding_user_status_idx
  on public.staff_onboarding_steps (organization_id, user_id, status, sequence);

create table public.administration_transfer_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  job_type text not null check (job_type in ('archive_handoff', 'export', 'import')),
  mode text not null check (mode in ('handoff', 'preview', 'merge', 'full_restore', 'full', 'people', 'work', 'audit')),
  status text not null default 'pending' check (status in ('pending', 'previewed', 'running', 'completed', 'failed')),
  source_user_id uuid references public.profiles(id) on delete restrict,
  replacement_user_id uuid references public.profiles(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  summary jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (source_user_id is null or source_user_id <> replacement_user_id)
);
create index administration_transfer_jobs_org_created_idx
  on public.administration_transfer_jobs (organization_id, created_at desc);
create index administration_transfer_jobs_user_idx
  on public.administration_transfer_jobs (organization_id, source_user_id, created_at desc)
  where source_user_id is not null;

alter table public.staff_profiles enable row level security;
alter table public.staff_onboarding_steps enable row level security;
alter table public.administration_transfer_jobs enable row level security;

create or replace function public.is_org_member(target_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and profile.status = 'active'
      and not profile.must_change_password
  );
$$;

create or replace function public.is_org_admin(target_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role = 'admin'
      and membership.status = 'active'
      and profile.status = 'active'
      and not profile.must_change_password
  );
$$;

create or replace function public.is_org_owner(target_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.is_owner
      and membership.role = 'admin'
      and membership.status = 'active'
      and profile.status = 'active'
      and not profile.must_change_password
  );
$$;

create or replace function public.rpc_current_user_context()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'loginIdentifier', profile.login_identifier,
    'locale', profile.locale,
    'mustChangePassword', profile.must_change_password,
    'role', membership.role,
    'isOwner', membership.is_owner,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles profile
  join public.organization_memberships membership on membership.user_id = profile.id
    and membership.status in ('active', 'password_change_required')
  join public.organizations organization on organization.id = membership.organization_id
  left join lateral (
    select project_row.id, project_row.name from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at limit 1
  ) project on true
  where profile.id = (select auth.uid())
    and profile.status in ('active', 'password_change_required')
  order by membership.joined_at limit 1;
$$;

drop policy if exists staff_profiles_self_or_admin_read on public.staff_profiles;
create policy staff_profiles_self_or_admin_read on public.staff_profiles for select to authenticated
  using ((user_id = (select auth.uid()) and public.is_org_member(organization_id)) or public.is_org_admin(organization_id));
drop policy if exists staff_onboarding_self_or_admin_read on public.staff_onboarding_steps;
create policy staff_onboarding_self_or_admin_read on public.staff_onboarding_steps for select to authenticated
  using ((user_id = (select auth.uid()) and public.is_org_member(organization_id)) or public.is_org_admin(organization_id));
drop policy if exists administration_transfer_admin_read on public.administration_transfer_jobs;
create policy administration_transfer_admin_read on public.administration_transfer_jobs for select to authenticated
  using (public.is_org_admin(organization_id));

revoke all on public.staff_profiles, public.staff_onboarding_steps,
  public.administration_transfer_jobs from public, anon, authenticated;
grant select on public.staff_profiles, public.staff_onboarding_steps,
  public.administration_transfer_jobs to authenticated;
grant all on public.staff_profiles, public.staff_onboarding_steps,
  public.administration_transfer_jobs to service_role;
grant delete on public.profiles, public.organization_memberships to service_role;

insert into public.staff_profiles (organization_id, user_id, timezone)
select membership.organization_id, membership.user_id, organization.timezone
from public.organization_memberships membership
join public.organizations organization on organization.id = membership.organization_id
on conflict (organization_id, user_id) do nothing;

insert into public.staff_onboarding_steps (organization_id, user_id, step_key, label, sequence)
select staff.organization_id, staff.user_id, template.step_key, template.label, template.sequence
from public.staff_profiles staff
cross join (values
  ('secure_account', 'Secure your account', 10),
  ('review_workspace', 'Review workspace responsibilities', 20),
  ('review_data_handling', 'Review data handling rules', 30),
  ('file_first_eod', 'File your first EOD brief', 40)
) as template(step_key, label, sequence)
on conflict (organization_id, user_id, step_key) do nothing;

create or replace function public.rpc_admin_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;

  return jsonb_build_object(
    'organizationId', v_org_id,
    'people', jsonb_build_object(
      'total', (select count(*) from public.organization_memberships membership where membership.organization_id = v_org_id),
      'active', (select count(*) from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'),
      'invited', (select count(*) from public.organization_memberships membership where membership.organization_id = v_org_id and membership.status = 'invited'),
      'disabled', (select count(*) from public.organization_memberships membership where membership.organization_id = v_org_id and membership.status = 'disabled'),
      'archived', (select count(*) from public.organization_memberships membership where membership.organization_id = v_org_id and membership.status = 'archived'),
      'admins', (select count(*) from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id where membership.organization_id = v_org_id and membership.role = 'admin' and membership.status = 'active' and profile.status = 'active')
    ),
    'onboarding', jsonb_build_object(
      'pending', (select count(*) from public.staff_onboarding_steps step where step.organization_id = v_org_id and step.status in ('pending', 'in_progress')),
      'completed', (select count(*) from public.staff_onboarding_steps step where step.organization_id = v_org_id and step.status in ('completed', 'waived'))
    ),
    'work', jsonb_build_object(
      'unassignedTasks', (select count(*) from public.tasks task where task.organization_id = v_org_id and task.assigned_to is null),
      'activeTasks', (select count(*) from public.tasks task where task.organization_id = v_org_id and task.status not in ('completed', 'cancelled')),
      'crmContacts', (select count(*) from public.crm_contacts contact where contact.organization_id = v_org_id)
    ),
    'recentTransfers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', job.id, 'jobType', job.job_type, 'mode', job.mode, 'status', job.status,
        'sourceUserId', job.source_user_id, 'replacementUserId', job.replacement_user_id,
        'requestedBy', job.requested_by, 'summary', job.summary, 'createdAt', job.created_at,
        'completedAt', job.completed_at
      ) order by job.created_at desc)
      from (select * from public.administration_transfer_jobs transfer where transfer.organization_id = v_org_id order by transfer.created_at desc limit 10) job
    ), '[]'::jsonb),
    'generatedAt', now()
  );
end;
$$;

create or replace function public.rpc_admin_people(
  p_query text default null,
  p_role text default null,
  p_status text default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_role is not null and p_role not in ('admin', 'intern') then raise exception 'ROLE_INVALID'; end if;
  if p_status is not null and p_status not in ('active', 'invited', 'password_change_required', 'disabled', 'archived') then raise exception 'STATUS_INVALID'; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'userId', profile.id,
      'displayName', profile.display_name,
      'loginIdentifier', profile.login_identifier,
      'locale', profile.locale,
      'profileStatus', profile.status,
      'role', membership.role,
      'membershipStatus', membership.status,
      'isOwner', membership.is_owner,
      'phone', staff.phone,
      'timezone', staff.timezone,
      'managerId', staff.manager_id,
      'managerName', manager.display_name,
      'skills', coalesce(to_jsonb(staff.skills), '[]'::jsonb),
      'availability', staff.availability,
      'startDate', staff.start_date,
      'endDate', staff.end_date,
      'joinedAt', membership.joined_at,
      'archivedAt', membership.archived_at,
      'departureDate', membership.departure_date,
      'archiveReason', membership.archive_reason,
      'onboardingCompleted', (select count(*) from public.staff_onboarding_steps step where step.organization_id = v_org_id and step.user_id = profile.id and step.status in ('completed', 'waived')),
      'onboardingTotal', (select count(*) from public.staff_onboarding_steps step where step.organization_id = v_org_id and step.user_id = profile.id)
    ) order by membership.is_owner desc, case membership.role when 'admin' then 1 else 2 end, profile.display_name)
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    left join public.staff_profiles staff on staff.organization_id = membership.organization_id and staff.user_id = membership.user_id
    left join public.profiles manager on manager.id = staff.manager_id
    where membership.organization_id = v_org_id
      and (p_role is null or membership.role = p_role)
      and (p_status is null or membership.status = p_status)
      and (p_query is null or trim(p_query) = ''
        or profile.display_name ilike '%' || trim(p_query) || '%'
        or profile.login_identifier ilike '%' || trim(p_query) || '%'
        or coalesce(array_to_string(staff.skills, ' '), '') ilike '%' || trim(p_query) || '%')
  ), '[]'::jsonb);
end;
$$;

create or replace function public.rpc_admin_person_detail(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_result jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;

  select jsonb_build_object(
    'person', jsonb_build_object(
      'userId', profile.id, 'displayName', profile.display_name,
      'loginIdentifier', profile.login_identifier, 'locale', profile.locale,
      'profileStatus', profile.status, 'role', membership.role,
      'membershipStatus', membership.status, 'isOwner', membership.is_owner,
      'phone', staff.phone, 'timezone', staff.timezone, 'managerId', staff.manager_id,
      'skills', coalesce(to_jsonb(staff.skills), '[]'::jsonb),
      'availability', staff.availability, 'startDate', staff.start_date, 'endDate', staff.end_date,
      'notes', staff.notes, 'joinedAt', membership.joined_at, 'archivedAt', membership.archived_at,
      'departureDate', membership.departure_date, 'archiveReason', membership.archive_reason
    ),
    'onboarding', coalesce((select jsonb_agg(jsonb_build_object(
      'id', step.id, 'key', step.step_key, 'label', step.label, 'sequence', step.sequence,
      'status', step.status, 'completedAt', step.completed_at, 'completedBy', step.completed_by,
      'metadata', step.metadata
    ) order by step.sequence) from public.staff_onboarding_steps step
      where step.organization_id = v_org_id and step.user_id = p_user_id), '[]'::jsonb),
    'workload', jsonb_build_object(
      'tasks', (select count(*) from public.tasks task where task.organization_id = v_org_id and task.assigned_to = p_user_id and task.status not in ('completed', 'cancelled')),
      'candidates', (select count(*) from public.candidates candidate where candidate.organization_id = v_org_id and candidate.assigned_to = p_user_id and candidate.workflow_status <> 'archived'),
      'crmContacts', (select count(*) from public.crm_contacts contact where contact.organization_id = v_org_id and contact.owner_id = p_user_id),
      'researchRecords',
        (select count(*) from public.respondents respondent where respondent.organization_id = v_org_id and respondent.assigned_to = p_user_id and respondent.workflow_status <> 'archived')
        + (select count(*) from public.research_sessions session where session.organization_id = v_org_id and session.assigned_to = p_user_id and session.workflow_status <> 'archived')
        + (select count(*) from public.evidence_records evidence where evidence.organization_id = v_org_id and evidence.assigned_to = p_user_id and evidence.workflow_status <> 'archived')
    ),
    'recentAudit', coalesce((select jsonb_agg(jsonb_build_object(
      'id', audit.id, 'entityType', audit.entity_type, 'entityId', audit.entity_id,
      'action', audit.action, 'metadata', audit.metadata, 'createdAt', audit.created_at
    ) order by audit.created_at desc) from (
      select * from public.audit_events event
      where event.organization_id = v_org_id and (event.actor_id = p_user_id or event.entity_id = p_user_id)
      order by event.created_at desc limit 25
    ) audit), '[]'::jsonb)
  ) into v_result
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  left join public.staff_profiles staff on staff.organization_id = membership.organization_id and staff.user_id = membership.user_id
  where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  if v_result is null then raise exception 'PERSON_NOT_FOUND'; end if;
  return v_result;
end;
$$;

create or replace function public.rpc_admin_upsert_staff_profile(p_user_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_org_timezone text;
  v_target public.organization_memberships%rowtype;
  v_manager_id uuid;
  v_skills text[];
begin
  select membership.organization_id, organization.timezone into v_org_id, v_org_timezone
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  join public.organizations organization on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org_id::text, 0));

  select membership.* into v_target from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  if v_target.user_id is null then raise exception 'PERSON_NOT_FOUND'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'STAFF_PROFILE_INVALID'; end if;
  if p_payload ? 'displayName' and length(trim(coalesce(p_payload->>'displayName', ''))) < 2 then raise exception 'DISPLAY_NAME_REQUIRED'; end if;
  if p_payload ? 'locale' and p_payload->>'locale' not in ('en', 'zh-CN') then raise exception 'LOCALE_INVALID'; end if;
  if p_payload ? 'role' and p_payload->>'role' not in ('admin', 'intern') then raise exception 'ROLE_INVALID'; end if;

  if p_payload ? 'role' and p_payload->>'role' <> v_target.role then
    if (v_target.role = 'admin' or p_payload->>'role' = 'admin') and not public.is_org_owner(v_org_id) then
      raise exception 'OWNER_REQUIRED';
    end if;
    if v_target.is_owner then raise exception 'OWNER_TRANSFER_REQUIRED'; end if;
    if v_target.role = 'admin' and v_target.status = 'active' and not exists (
      select 1 from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id <> p_user_id
        and membership.role = 'admin' and membership.status = 'active' and profile.status = 'active'
    ) then raise exception 'LAST_ACTIVE_ADMIN'; end if;
    update public.organization_memberships membership
    set role = p_payload->>'role', updated_at = now()
    where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  end if;

  v_manager_id := nullif(p_payload->>'managerId', '')::uuid;
  if v_manager_id is not null and (v_manager_id = p_user_id or not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.user_id = v_manager_id
      and membership.status = 'active' and profile.status = 'active'
  )) then raise exception 'MANAGER_INVALID'; end if;

  if p_payload ? 'skills' then
    if jsonb_typeof(p_payload->'skills') <> 'array' then raise exception 'SKILLS_INVALID'; end if;
    select coalesce(array_agg(distinct trim(skill)) filter (where trim(skill) <> ''), '{}'::text[])
    into v_skills from jsonb_array_elements_text(p_payload->'skills') skill;
  end if;

  update public.profiles profile set
    display_name = case when p_payload ? 'displayName' then trim(p_payload->>'displayName') else profile.display_name end,
    locale = case when p_payload ? 'locale' then p_payload->>'locale' else profile.locale end,
    updated_at = now()
  where profile.id = p_user_id;

  insert into public.staff_profiles (
    organization_id, user_id, phone, timezone, manager_id, skills,
    availability, start_date, end_date, notes, updated_at
  ) values (
    v_org_id, p_user_id, nullif(trim(p_payload->>'phone'), ''),
    coalesce(nullif(trim(p_payload->>'timezone'), ''), v_org_timezone),
    v_manager_id, coalesce(v_skills, '{}'::text[]), nullif(trim(p_payload->>'availability'), ''),
    nullif(p_payload->>'startDate', '')::date, nullif(p_payload->>'endDate', '')::date,
    nullif(trim(p_payload->>'notes'), ''), now()
  ) on conflict (organization_id, user_id) do update set
    phone = case when p_payload ? 'phone' then excluded.phone else public.staff_profiles.phone end,
    timezone = case when p_payload ? 'timezone' then excluded.timezone else public.staff_profiles.timezone end,
    manager_id = case when p_payload ? 'managerId' then excluded.manager_id else public.staff_profiles.manager_id end,
    skills = case when p_payload ? 'skills' then excluded.skills else public.staff_profiles.skills end,
    availability = case when p_payload ? 'availability' then excluded.availability else public.staff_profiles.availability end,
    start_date = case when p_payload ? 'startDate' then excluded.start_date else public.staff_profiles.start_date end,
    end_date = case when p_payload ? 'endDate' then excluded.end_date else public.staff_profiles.end_date end,
    notes = case when p_payload ? 'notes' then excluded.notes else public.staff_profiles.notes end,
    updated_at = now();

  insert into public.staff_onboarding_steps (organization_id, user_id, step_key, label, sequence)
  values
    (v_org_id, p_user_id, 'secure_account', 'Secure your account', 10),
    (v_org_id, p_user_id, 'review_workspace', 'Review workspace responsibilities', 20),
    (v_org_id, p_user_id, 'review_data_handling', 'Review data handling rules', 30),
    (v_org_id, p_user_id, 'file_first_eod', 'File your first EOD brief', 40)
  on conflict (organization_id, user_id, step_key) do nothing;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'staff_profile', p_user_id, 'profile_updated',
    jsonb_build_object('fields', (select coalesce(jsonb_agg(key), '[]'::jsonb) from jsonb_object_keys(p_payload) key)));
  return public.rpc_admin_person_detail(p_user_id);
end;
$$;

create or replace function public.rpc_admin_archive_user(
  p_user_id uuid,
  p_replacement_user_id uuid default null,
  p_reason text default null,
  p_departure_date date default current_date
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_target public.organization_memberships%rowtype;
  v_replacement public.organization_memberships%rowtype;
  v_replacement_name text;
  v_replacement_initials text;
  v_handoff_count integer := 0;
  v_job_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org_id::text, 0));
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'ARCHIVE_REASON_REQUIRED'; end if;
  if p_user_id = (select auth.uid()) and p_replacement_user_id is null then raise exception 'REPLACEMENT_USER_REQUIRED'; end if;

  select membership.* into v_target from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = p_user_id for update;
  if v_target.user_id is null then raise exception 'PERSON_NOT_FOUND'; end if;
  if v_target.status = 'archived' then raise exception 'PERSON_ALREADY_ARCHIVED'; end if;
  if v_target.role = 'admin' and not public.is_org_owner(v_org_id) then raise exception 'OWNER_REQUIRED'; end if;

  if p_replacement_user_id is not null then
    if p_replacement_user_id = p_user_id then raise exception 'REPLACEMENT_USER_INVALID'; end if;
    select membership.* into v_replacement
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.user_id = p_replacement_user_id
      and membership.status = 'active' and profile.status = 'active';
    if v_replacement.user_id is null then raise exception 'REPLACEMENT_USER_INVALID'; end if;
    select profile.display_name into v_replacement_name
    from public.profiles profile where profile.id = p_replacement_user_id;
    v_replacement_initials := upper(left(split_part(v_replacement_name, ' ', 1), 1)
      || left(split_part(v_replacement_name, ' ', 2), 1));
  end if;

  if v_target.is_owner and p_replacement_user_id is null then raise exception 'OWNER_TRANSFER_REQUIRED'; end if;
  if v_target.is_owner and v_replacement.role <> 'admin' then raise exception 'OWNER_TRANSFER_REQUIRED'; end if;
  if v_target.role = 'admin' and v_target.status = 'active' and not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.user_id <> p_user_id
      and membership.role = 'admin' and membership.status = 'active' and profile.status = 'active'
  ) then raise exception 'LAST_ACTIVE_ADMIN'; end if;
  select
    (select count(*) from public.tasks task where task.organization_id = v_org_id and task.assigned_to = p_user_id and task.status not in ('completed', 'cancelled'))
    + (select count(*) from public.candidates candidate where candidate.organization_id = v_org_id and candidate.assigned_to = p_user_id and candidate.workflow_status <> 'archived')
    + (select count(*) from public.crm_contacts contact where contact.organization_id = v_org_id and contact.owner_id = p_user_id)
    + (select count(*) from public.respondents respondent where respondent.organization_id = v_org_id and respondent.assigned_to = p_user_id and respondent.workflow_status <> 'archived')
    + (select count(*) from public.research_sessions session where session.organization_id = v_org_id and session.assigned_to = p_user_id and session.workflow_status <> 'archived')
    + (select count(*) from public.evidence_records evidence where evidence.organization_id = v_org_id and evidence.assigned_to = p_user_id and evidence.workflow_status <> 'archived')
    + (select count(*) from public.pmf_observations observation where observation.organization_id = v_org_id and observation.assigned_to = p_user_id and observation.workflow_status <> 'archived')
    + (select count(*) from public.product_events event where event.organization_id = v_org_id and event.assigned_to = p_user_id and event.workflow_status <> 'archived')
    + (select count(*) from public.value_exchange_observations value where value.organization_id = v_org_id and value.assigned_to = p_user_id and value.workflow_status <> 'archived')
    + (select count(*) from public.hypotheses hypothesis where hypothesis.organization_id = v_org_id and hypothesis.owner_id = p_user_id)
    + (select count(*) from public.staff_profiles staff where staff.organization_id = v_org_id and staff.manager_id = p_user_id)
    + (select count(*) from public.daily_eod_briefs brief where brief.organization_id = v_org_id and brief.workflow_status <> 'completed' and (brief.engagement_manager_id = p_user_id or brief.person_in_charge_id = p_user_id))
  into v_handoff_count;
  if v_handoff_count > 0 and p_replacement_user_id is null then raise exception 'REPLACEMENT_USER_REQUIRED'; end if;

  insert into public.administration_transfer_jobs (
    organization_id, job_type, mode, status, source_user_id,
    replacement_user_id, requested_by, summary
  ) values (
    v_org_id, 'archive_handoff', 'handoff', 'running', p_user_id,
    p_replacement_user_id, (select auth.uid()),
    jsonb_build_object('reason', nullif(trim(p_reason), ''), 'recordsDetected', v_handoff_count)
  ) returning id into v_job_id;

  if p_replacement_user_id is not null then
    update public.crm_contacts contact set owner_id = p_replacement_user_id, updated_at = now()
      where contact.organization_id = v_org_id and contact.owner_id = p_user_id;
    update public.candidates candidate set owner_id = p_replacement_user_id,
      assigned_to = p_replacement_user_id, updated_at = now()
      where candidate.organization_id = v_org_id and candidate.assigned_to = p_user_id and candidate.workflow_status <> 'archived';
    update public.tasks task set assigned_to = p_replacement_user_id,
      owner_name = v_replacement_name, owner_initials = coalesce(nullif(v_replacement_initials, ''), 'AO'), updated_at = now()
      where task.organization_id = v_org_id and task.assigned_to = p_user_id and task.status not in ('completed', 'cancelled');
    update public.respondents respondent set assigned_to = p_replacement_user_id, updated_at = now()
      where respondent.organization_id = v_org_id and respondent.assigned_to = p_user_id and respondent.workflow_status <> 'archived';
    update public.research_sessions session set assigned_to = p_replacement_user_id, updated_at = now()
      where session.organization_id = v_org_id and session.assigned_to = p_user_id and session.workflow_status <> 'archived';
    update public.evidence_records evidence set assigned_to = p_replacement_user_id, updated_at = now()
      where evidence.organization_id = v_org_id and evidence.assigned_to = p_user_id and evidence.workflow_status <> 'archived';
    update public.pmf_observations observation set assigned_to = p_replacement_user_id, updated_at = now()
      where observation.organization_id = v_org_id and observation.assigned_to = p_user_id and observation.workflow_status <> 'archived';
    update public.product_events event set assigned_to = p_replacement_user_id, updated_at = now()
      where event.organization_id = v_org_id and event.assigned_to = p_user_id and event.workflow_status <> 'archived';
    update public.value_exchange_observations value set assigned_to = p_replacement_user_id, updated_at = now()
      where value.organization_id = v_org_id and value.assigned_to = p_user_id and value.workflow_status <> 'archived';
    update public.hypotheses hypothesis set owner_id = p_replacement_user_id, updated_at = now()
      where hypothesis.organization_id = v_org_id and hypothesis.owner_id = p_user_id;
    update public.staff_profiles staff set manager_id = p_replacement_user_id, updated_at = now()
      where staff.organization_id = v_org_id and staff.manager_id = p_user_id;
    update public.daily_eod_briefs brief set
      engagement_manager_id = case when brief.engagement_manager_id = p_user_id then p_replacement_user_id else brief.engagement_manager_id end,
      person_in_charge_id = case when brief.person_in_charge_id = p_user_id then p_replacement_user_id else brief.person_in_charge_id end,
      updated_at = now()
      where brief.organization_id = v_org_id and brief.workflow_status <> 'completed'
        and (brief.engagement_manager_id = p_user_id or brief.person_in_charge_id = p_user_id);
  end if;

  if v_target.is_owner then
    update public.organization_memberships membership set is_owner = false, updated_at = now()
      where membership.organization_id = v_org_id and membership.user_id = p_user_id;
    update public.organization_memberships membership set is_owner = true, updated_at = now()
      where membership.organization_id = v_org_id and membership.user_id = p_replacement_user_id;
  end if;
  update public.organization_memberships membership set
    status = 'archived', is_owner = false, archived_at = now(),
    archived_by = (select auth.uid()), departure_date = coalesce(p_departure_date, current_date),
    archive_reason = trim(p_reason), updated_at = now()
  where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  update public.staff_profiles staff set end_date = coalesce(p_departure_date, current_date), updated_at = now()
  where staff.organization_id = v_org_id and staff.user_id = p_user_id;
  update public.profiles profile set status = 'archived', archived_at = now(),
    archived_by = (select auth.uid()), updated_at = now()
  where profile.id = p_user_id and not exists (
    select 1 from public.organization_memberships membership
    where membership.user_id = p_user_id and membership.status = 'active'
  );

  update public.administration_transfer_jobs job set status = 'completed', completed_at = now(),
    summary = job.summary || jsonb_build_object('recordsHandedOff', v_handoff_count)
  where job.id = v_job_id;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'profile', p_user_id, 'user_archived',
    jsonb_build_object('replacementUserId', p_replacement_user_id, 'reason', nullif(trim(p_reason), ''), 'transferJobId', v_job_id));
  return jsonb_build_object('userId', p_user_id, 'status', 'archived',
    'replacementUserId', p_replacement_user_id, 'recordsHandedOff', v_handoff_count, 'transferJobId', v_job_id);
end;
$$;

create or replace function public.rpc_admin_restore_user(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org_id::text, 0));
  if not exists (select 1 from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.user_id = p_user_id and membership.status = 'archived') then
    raise exception 'ARCHIVED_PERSON_NOT_FOUND';
  end if;
  if exists (select 1 from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.user_id = p_user_id and membership.role = 'admin')
    and not public.is_org_owner(v_org_id) then raise exception 'OWNER_REQUIRED'; end if;

  update public.profiles profile set status = case when profile.must_change_password then 'password_change_required' else 'active' end,
    archived_at = null, archived_by = null, updated_at = now() where profile.id = p_user_id;
  update public.organization_memberships membership set status = case
      when (select profile.must_change_password from public.profiles profile where profile.id = p_user_id) then 'password_change_required'
      else 'active' end,
    archived_at = null, archived_by = null, departure_date = null, archive_reason = null, updated_at = now()
  where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  update public.staff_profiles staff set end_date = null, updated_at = now()
  where staff.organization_id = v_org_id and staff.user_id = p_user_id;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'profile', p_user_id, 'user_restored', '{}'::jsonb);
  return public.rpc_admin_person_detail(p_user_id);
end;
$$;

create or replace function public.rpc_admin_export_data(p_scope text default 'full')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_job_id uuid;
  v_package jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_scope not in ('full', 'people', 'work', 'audit') then raise exception 'EXPORT_SCOPE_INVALID'; end if;

  v_package := jsonb_build_object(
    'schemaVersion', 1,
    'exportedAt', now(),
    'scope', p_scope,
    'organization', (select jsonb_build_object('id', organization.id, 'name', organization.name, 'slug', organization.slug, 'timezone', organization.timezone) from public.organizations organization where organization.id = v_org_id),
    'people', case when p_scope in ('full', 'people') then coalesce((select jsonb_agg(jsonb_build_object(
      'userId', profile.id, 'displayName', profile.display_name, 'loginIdentifier', profile.login_identifier,
      'locale', profile.locale, 'profileStatus', profile.status, 'role', membership.role,
      'membershipStatus', membership.status, 'isOwner', membership.is_owner,
      'phone', staff.phone, 'timezone', staff.timezone, 'managerId', staff.manager_id,
      'skills', coalesce(to_jsonb(staff.skills), '[]'::jsonb), 'availability', staff.availability,
      'startDate', staff.start_date, 'endDate', staff.end_date, 'notes', staff.notes,
      'joinedAt', membership.joined_at, 'archivedAt', membership.archived_at,
      'departureDate', membership.departure_date, 'archiveReason', membership.archive_reason
    ) order by membership.is_owner desc, profile.display_name)
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      left join public.staff_profiles staff on staff.organization_id = membership.organization_id and staff.user_id = membership.user_id
      where membership.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'onboarding', case when p_scope in ('full', 'people') then coalesce((select jsonb_agg(jsonb_build_object(
      'id', step.id, 'userId', step.user_id, 'key', step.step_key, 'label', step.label,
      'sequence', step.sequence, 'status', step.status, 'completedAt', step.completed_at,
      'completedBy', step.completed_by, 'metadata', step.metadata
    ) order by step.user_id, step.sequence) from public.staff_onboarding_steps step where step.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'tasks', case when p_scope in ('full', 'work') then coalesce((select jsonb_agg(jsonb_build_object(
      'id', task.id, 'projectId', task.project_id, 'title', task.title, 'status', task.status,
      'priority', task.priority, 'assignedTo', task.assigned_to, 'createdBy', task.created_by,
      'dueDate', task.due_date, 'updatedAt', task.updated_at
    ) order by task.created_at) from public.tasks task where task.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'crmOwnership', case when p_scope in ('full', 'work') then coalesce((select jsonb_agg(jsonb_build_object(
      'id', contact.id, 'projectId', contact.project_id, 'name', contact.name,
      'ownerId', contact.owner_id, 'lifecycle', contact.lifecycle, 'updatedAt', contact.updated_at
    ) order by contact.created_at) from public.crm_contacts contact where contact.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'activity', case when p_scope in ('full', 'work', 'audit') then coalesce((select jsonb_agg(jsonb_build_object(
      'id', activity.id, 'contactId', activity.contact_id, 'actorId', activity.actor_id,
      'projectId', activity.project_id, 'action', activity.activity_type,
      'summary', activity.summary, 'createdAt', activity.created_at
    ) order by activity.created_at) from public.crm_activity activity where activity.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end,
    'audit', case when p_scope in ('full', 'audit') then coalesce((select jsonb_agg(jsonb_build_object(
      'id', audit.id, 'actorId', audit.actor_id, 'entityType', audit.entity_type,
      'entityId', audit.entity_id, 'action', audit.action, 'metadata', audit.metadata,
      'createdAt', audit.created_at
    ) order by audit.created_at) from public.audit_events audit where audit.organization_id = v_org_id), '[]'::jsonb) else '[]'::jsonb end
  );

  insert into public.administration_transfer_jobs (
    organization_id, job_type, mode, status, requested_by, summary, completed_at
  ) values (
    v_org_id, 'export', p_scope, 'completed', (select auth.uid()),
    jsonb_build_object(
      'people', jsonb_array_length(v_package->'people'),
      'tasks', jsonb_array_length(v_package->'tasks'),
      'crmOwnership', jsonb_array_length(v_package->'crmOwnership'),
      'audit', jsonb_array_length(v_package->'audit')
    ), now()
  ) returning id into v_job_id;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'administration_transfer', v_job_id, 'data_exported', jsonb_build_object('scope', p_scope));
  return v_package || jsonb_build_object('transferJobId', v_job_id);
end;
$$;

create or replace function public.rpc_admin_import_data(
  p_package jsonb,
  p_mode text default 'preview',
  p_preview_job_id uuid default null,
  p_preview_mode text default 'merge'
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_job_id uuid;
  v_person jsonb;
  v_task jsonb;
  v_contact jsonb;
  v_step jsonb;
  v_activity jsonb;
  v_audit jsonb;
  v_user_id uuid;
  v_assignee_id uuid;
  v_desired_owner_id uuid;
  v_people_count integer;
  v_tasks_count integer;
  v_contacts_count integer;
  v_applied integer := 0;
  v_skipped integer := 0;
  v_package_hash text;
  v_conflicts jsonb := '[]'::jsonb;
  v_preview_summary jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_mode not in ('preview', 'merge', 'full_restore') then raise exception 'IMPORT_MODE_INVALID'; end if;
  if p_preview_mode not in ('merge', 'full_restore') then raise exception 'IMPORT_MODE_INVALID'; end if;
  if p_mode = 'full_restore' and not public.is_org_owner(v_org_id) then raise exception 'FULL_RESTORE_OWNER_REQUIRED'; end if;
  if p_package is null or jsonb_typeof(p_package) <> 'object' or coalesce((p_package->>'schemaVersion')::integer, 0) <> 1 then
    raise exception 'IMPORT_PACKAGE_INVALID';
  end if;
  if p_package->'organization'->>'id' is not null and p_package->'organization'->>'id' <> v_org_id::text then
    raise exception 'IMPORT_ORGANIZATION_MISMATCH';
  end if;
  if coalesce(jsonb_typeof(p_package->'people'), 'array') <> 'array'
    or coalesce(jsonb_typeof(p_package->'tasks'), 'array') <> 'array'
    or coalesce(jsonb_typeof(p_package->'crmOwnership'), 'array') <> 'array'
    or coalesce(jsonb_typeof(p_package->'onboarding'), 'array') <> 'array' then
    raise exception 'IMPORT_PACKAGE_INVALID';
  end if;

  v_package_hash := hashtextextended(p_package::text, 0)::text;
  for v_person in select value from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) loop
    if coalesce(v_person->>'userId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'person_id_invalid', 'value', v_person->>'userId'));
    elsif not exists (select 1 from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = (v_person->>'userId')::uuid) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'identity_missing', 'userId', v_person->>'userId', 'email', v_person->>'loginIdentifier'));
    elsif v_person ? 'role' and v_person->>'role' not in ('admin', 'intern') then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'role_invalid', 'userId', v_person->>'userId'));
    elsif v_person ? 'membershipStatus' and v_person->>'membershipStatus' not in ('active', 'invited', 'password_change_required', 'disabled', 'archived') then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'status_invalid', 'userId', v_person->>'userId'));
    end if;
  end loop;
  if p_preview_mode = 'full_restore' and (
    (select count(*) from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) person
      where person->>'isOwner' = 'true' and person->>'role' = 'admin' and person->>'membershipStatus' = 'active') <> 1
    or not exists (
      select 1 from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) person
      join public.organization_memberships membership on membership.user_id::text = person->>'userId'
      join public.profiles profile on profile.id = membership.user_id
      where person->>'isOwner' = 'true' and membership.organization_id = v_org_id
        and profile.status = 'active' and not profile.must_change_password
    )
  ) then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'full_restore_owner_invalid'));
  end if;
  for v_task in select value from jsonb_array_elements(coalesce(p_package->'tasks', '[]'::jsonb)) loop
    if coalesce(v_task->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'task_id_invalid', 'value', v_task->>'id'));
    elsif not exists (select 1 from public.tasks task where task.organization_id = v_org_id and task.id = (v_task->>'id')::uuid) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'task_missing', 'taskId', v_task->>'id'));
    elsif nullif(v_task->>'assignedTo', '') is not null and coalesce(v_task->>'assignedTo', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'task_assignee_invalid', 'taskId', v_task->>'id'));
    elsif nullif(v_task->>'assignedTo', '') is not null and not exists (
      select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = (v_task->>'assignedTo')::uuid
        and membership.status = 'active' and profile.status = 'active'
    ) then v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'task_assignee_invalid', 'taskId', v_task->>'id'));
    end if;
  end loop;
  for v_contact in select value from jsonb_array_elements(coalesce(p_package->'crmOwnership', '[]'::jsonb)) loop
    if coalesce(v_contact->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(v_contact->>'ownerId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'crm_ownership_invalid', 'contactId', v_contact->>'id'));
    elsif not exists (select 1 from public.crm_contacts contact where contact.organization_id = v_org_id and contact.id = (v_contact->>'id')::uuid) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'crm_contact_missing', 'contactId', v_contact->>'id'));
    elsif not exists (select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = (v_contact->>'ownerId')::uuid
        and membership.status = 'active' and profile.status = 'active') then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('type', 'crm_owner_invalid', 'contactId', v_contact->>'id'));
    end if;
  end loop;

  if p_mode <> 'preview' then
    if p_preview_job_id is null then raise exception 'IMPORT_PREVIEW_REQUIRED'; end if;
    select job.summary into v_preview_summary from public.administration_transfer_jobs job
    where job.id = p_preview_job_id and job.organization_id = v_org_id and job.job_type = 'import'
      and job.mode = 'preview' and job.status = 'previewed' and job.requested_by = (select auth.uid())
      and job.created_at > now() - interval '1 hour'
    for update;
    if v_preview_summary is null or v_preview_summary->>'packageHash' <> v_package_hash
      or v_preview_summary->>'applyMode' <> p_mode
      or coalesce((v_preview_summary->>'conflictCount')::integer, 0) <> 0
      or jsonb_array_length(v_conflicts) <> 0 then raise exception 'IMPORT_PREVIEW_REQUIRED'; end if;
    update public.administration_transfer_jobs set status = 'running', completed_at = now()
    where id = p_preview_job_id and status = 'previewed';
    if not found then raise exception 'IMPORT_PREVIEW_REQUIRED'; end if;
  end if;

  v_people_count := jsonb_array_length(coalesce(p_package->'people', '[]'::jsonb));
  v_tasks_count := jsonb_array_length(coalesce(p_package->'tasks', '[]'::jsonb));
  v_contacts_count := jsonb_array_length(coalesce(p_package->'crmOwnership', '[]'::jsonb));
  insert into public.administration_transfer_jobs (
    organization_id, job_type, mode, status, requested_by, summary
  ) values (
    v_org_id, 'import', p_mode, case when p_mode = 'preview' then 'previewed' else 'running' end,
    (select auth.uid()), jsonb_build_object(
      'schemaVersion', 1, 'people', v_people_count, 'tasks', v_tasks_count,
      'crmOwnership', v_contacts_count, 'packageHash', v_package_hash, 'applyMode', p_preview_mode,
      'conflictCount', jsonb_array_length(v_conflicts), 'conflicts', v_conflicts
    )
  ) returning id into v_job_id;

  if p_mode = 'preview' then
    insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
    values (v_org_id, (select auth.uid()), 'administration_transfer', v_job_id, 'data_import_previewed',
      jsonb_build_object('people', v_people_count, 'tasks', v_tasks_count, 'crmOwnership', v_contacts_count));
    return jsonb_build_object(
      'jobId', v_job_id, 'mode', 'preview', 'status', 'previewed',
      'canApply', jsonb_array_length(v_conflicts) = 0,
      'packageHash', v_package_hash, 'conflicts', v_conflicts,
      'requiresOwner', false, 'contract', jsonb_build_object(
        'merge', 'Updates existing staff metadata and current assignments; never creates or deletes identities.',
        'fullRestore', 'Owner-only lifecycle, role, ownership, staff metadata, and assignment restore.'
      ),
      'counts', jsonb_build_object('people', v_people_count, 'tasks', v_tasks_count, 'crmOwnership', v_contacts_count)
    );
  end if;

  if p_mode = 'full_restore' then
    if (select count(*) from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) person
      where coalesce((person->>'isOwner')::boolean, false)
        and person->>'role' = 'admin' and person->>'membershipStatus' = 'active') <> 1 then
      raise exception 'FULL_RESTORE_OWNER_REQUIRED';
    end if;
    select (person->>'userId')::uuid into v_desired_owner_id
    from jsonb_array_elements(p_package->'people') person
    where coalesce((person->>'isOwner')::boolean, false)
      and person->>'role' = 'admin' and person->>'membershipStatus' = 'active';
    if not exists (select 1 from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_desired_owner_id
        and profile.status = 'active' and not profile.must_change_password) then
      raise exception 'FULL_RESTORE_OWNER_REQUIRED';
    end if;
    update public.profiles profile set status = 'active', archived_at = null, archived_by = null, updated_at = now()
      where profile.id = v_desired_owner_id;
    update public.organization_memberships membership set role = 'admin', status = 'active',
      archived_at = null, archived_by = null, updated_at = now()
      where membership.organization_id = v_org_id and membership.user_id = v_desired_owner_id;
    update public.organization_memberships membership set is_owner = false, updated_at = now()
      where membership.organization_id = v_org_id and membership.is_owner;
    update public.organization_memberships membership set is_owner = true, updated_at = now()
      where membership.organization_id = v_org_id and membership.user_id = v_desired_owner_id;
  end if;

  for v_person in select value from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) loop
    if coalesce(v_person->>'userId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_user_id := (v_person->>'userId')::uuid;
    if not exists (select 1 from public.organization_memberships membership
      where membership.organization_id = v_org_id and membership.user_id = v_user_id) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    perform public.rpc_admin_upsert_staff_profile(
      v_user_id,
      v_person - 'userId' - 'loginIdentifier' - 'profileStatus' - 'role'
        - 'membershipStatus' - 'isOwner' - 'joinedAt' - 'archivedAt' - 'replacementUserId'
    );
    v_applied := v_applied + 1;
  end loop;

  if p_mode = 'full_restore' then
    for v_person in select value from jsonb_array_elements(coalesce(p_package->'people', '[]'::jsonb)) loop
      if coalesce(v_person->>'userId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then continue; end if;
      v_user_id := (v_person->>'userId')::uuid;
      if not exists (select 1 from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = v_user_id) then continue; end if;
      if v_person->>'role' not in ('admin', 'intern') or v_person->>'membershipStatus' not in ('active', 'invited', 'password_change_required', 'disabled', 'archived') then
        raise exception 'IMPORT_PERSON_LIFECYCLE_INVALID';
      end if;
      update public.organization_memberships membership set role = v_person->>'role', updated_at = now()
        where membership.organization_id = v_org_id and membership.user_id = v_user_id and not membership.is_owner;
      if v_person->>'membershipStatus' = 'archived' then
        if (select status from public.organization_memberships membership where membership.organization_id = v_org_id and membership.user_id = v_user_id) <> 'archived' then
              perform public.rpc_admin_archive_user(v_user_id, coalesce(nullif(v_person->>'replacementUserId', '')::uuid, v_desired_owner_id), 'Administration full restore', nullif(v_person->>'departureDate', '')::date);
        end if;
      else
        update public.organization_memberships membership set
          status = case
            when v_person->>'membershipStatus' = 'active'
              and (select profile.must_change_password from public.profiles profile where profile.id = v_user_id)
              then 'password_change_required'
            else v_person->>'membershipStatus'
          end,
          archived_at = null, archived_by = null, updated_at = now()
          where membership.organization_id = v_org_id and membership.user_id = v_user_id;
        update public.profiles profile set
          status = case when v_person->>'membershipStatus' = 'active' and profile.must_change_password then 'password_change_required' else v_person->>'membershipStatus' end,
          archived_at = null, archived_by = null, updated_at = now()
          where profile.id = v_user_id and not exists (
            select 1 from public.organization_memberships other
            where other.user_id = v_user_id and other.organization_id <> v_org_id and other.status = 'active'
          );
      end if;
    end loop;
    if not exists (select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.role = 'admin' and membership.status = 'active' and profile.status = 'active') then
      raise exception 'LAST_ACTIVE_ADMIN';
    end if;
    if (select count(*) from public.organization_memberships membership where membership.organization_id = v_org_id and membership.is_owner) <> 1 then
      raise exception 'FULL_RESTORE_OWNER_REQUIRED';
    end if;
  end if;

  for v_task in select value from jsonb_array_elements(coalesce(p_package->'tasks', '[]'::jsonb)) loop
    if coalesce(v_task->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(v_task->>'assignedTo', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_assignee_id := (v_task->>'assignedTo')::uuid;
    if exists (select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_assignee_id
        and membership.status = 'active' and profile.status = 'active') then
      update public.tasks task set assigned_to = v_assignee_id, updated_at = now()
      where task.organization_id = v_org_id and task.id = (v_task->>'id')::uuid;
      if found then v_applied := v_applied + 1; else v_skipped := v_skipped + 1; end if;
    else v_skipped := v_skipped + 1;
    end if;
  end loop;

  for v_contact in select value from jsonb_array_elements(coalesce(p_package->'crmOwnership', '[]'::jsonb)) loop
    if coalesce(v_contact->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(v_contact->>'ownerId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_assignee_id := (v_contact->>'ownerId')::uuid;
    if exists (select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_assignee_id
        and membership.status = 'active' and profile.status = 'active') then
      update public.crm_contacts contact set owner_id = v_assignee_id, updated_at = now()
      where contact.organization_id = v_org_id and contact.id = (v_contact->>'id')::uuid;
      if found then
        update public.candidates candidate set owner_id = v_assignee_id, assigned_to = v_assignee_id, updated_at = now()
          where candidate.organization_id = v_org_id and candidate.crm_contact_id = (v_contact->>'id')::uuid;
        v_applied := v_applied + 1;
      else v_skipped := v_skipped + 1;
      end if;
    else v_skipped := v_skipped + 1;
    end if;
  end loop;

  for v_step in select value from jsonb_array_elements(coalesce(p_package->'onboarding', '[]'::jsonb)) loop
    if coalesce(v_step->>'userId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and v_step->>'status' in ('pending', 'in_progress', 'completed', 'waived') then
      update public.staff_onboarding_steps step set status = v_step->>'status',
        completed_at = case when v_step->>'status' = 'completed' then coalesce(nullif(v_step->>'completedAt', '')::timestamptz, now()) else null end,
        completed_by = case when v_step->>'status' = 'completed' then (select auth.uid()) else null end,
        updated_at = now()
      where step.organization_id = v_org_id and step.user_id = (v_step->>'userId')::uuid and step.step_key = v_step->>'key';
      if found then v_applied := v_applied + 1; end if;
    end if;
  end loop;

  for v_activity in select value from jsonb_array_elements(coalesce(p_package->'activity', '[]'::jsonb)) loop
    if coalesce(v_activity->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and coalesce(v_activity->>'contactId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and v_activity->>'action' in ('enrich','outreach','follow_up','qualify','note','status_change','import')
      and exists (select 1 from public.crm_contacts contact where contact.organization_id = v_org_id and contact.id = (v_activity->>'contactId')::uuid) then
      insert into public.crm_activity (id, organization_id, project_id, contact_id, actor_id, activity_type, summary, created_at)
      select (v_activity->>'id')::uuid, v_org_id, contact.project_id, contact.id,
        case when coalesce(v_activity->>'actorId', '') ~* '^[0-9a-f-]{36}$'
          and exists (select 1 from public.profiles profile where profile.id = (v_activity->>'actorId')::uuid)
          then (v_activity->>'actorId')::uuid else null end,
        v_activity->>'action', coalesce(nullif(v_activity->>'summary', ''), 'Imported administration activity'),
        coalesce(nullif(v_activity->>'createdAt', '')::timestamptz, now())
      from public.crm_contacts contact where contact.organization_id = v_org_id and contact.id = (v_activity->>'contactId')::uuid
      on conflict (id) do nothing;
      if found then v_applied := v_applied + 1; end if;
    end if;
  end loop;

  for v_audit in select value from jsonb_array_elements(coalesce(p_package->'audit', '[]'::jsonb)) loop
    if coalesce(v_audit->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and nullif(trim(v_audit->>'action'), '') is not null then
      insert into public.audit_events (id, organization_id, actor_id, entity_type, entity_id, action, metadata, created_at)
      values ((v_audit->>'id')::uuid, v_org_id,
        case when coalesce(v_audit->>'actorId', '') ~* '^[0-9a-f-]{36}$'
          and exists (select 1 from public.profiles profile where profile.id = (v_audit->>'actorId')::uuid)
          then (v_audit->>'actorId')::uuid else null end,
        coalesce(nullif(v_audit->>'entityType', ''), 'administration_import'),
        case when coalesce(v_audit->>'entityId', '') ~* '^[0-9a-f-]{36}$' then (v_audit->>'entityId')::uuid else null end,
        v_audit->>'action', coalesce(v_audit->'metadata', '{}'::jsonb),
        coalesce(nullif(v_audit->>'createdAt', '')::timestamptz, now()))
      on conflict (id) do nothing;
      if found then v_applied := v_applied + 1; end if;
    end if;
  end loop;

  update public.administration_transfer_jobs job set status = 'completed', completed_at = now(),
    summary = job.summary || jsonb_build_object('applied', v_applied, 'skipped', v_skipped)
  where job.id = v_job_id;
  update public.administration_transfer_jobs job set status = 'completed', completed_at = now()
  where job.id = p_preview_job_id and job.status = 'previewed';
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'administration_transfer', v_job_id, 'data_imported',
    jsonb_build_object('mode', p_mode, 'applied', v_applied, 'skipped', v_skipped));
  return jsonb_build_object('jobId', v_job_id, 'mode', p_mode, 'status', 'completed',
    'applied', v_applied, 'skipped', v_skipped);
end;
$$;

create or replace function public.rpc_accept_invitation()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid())
    and membership.status = 'invited'
    and profile.status = 'invited'
  order by membership.joined_at
  limit 1
  for update of membership;
  if v_org_id is null then raise exception 'INVITATION_NOT_FOUND'; end if;

  update public.profiles profile
  set status = 'active', must_change_password = false, updated_at = now()
  where profile.id = (select auth.uid());
  update public.organization_memberships membership
  set status = 'active', updated_at = now()
  where membership.organization_id = v_org_id and membership.user_id = (select auth.uid());
  update public.staff_onboarding_steps step
  set status = 'completed', completed_at = now(), completed_by = (select auth.uid()), updated_at = now()
  where step.organization_id = v_org_id and step.user_id = (select auth.uid()) and step.step_key = 'secure_account';
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'profile', (select auth.uid()), 'invitation_accepted', '{}'::jsonb);
  return public.rpc_current_user_context();
end;
$$;

create or replace function public.rpc_admin_create_task_v2(p_task jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_assignee_id uuid;
  v_assignee_name text;
  v_assignee_initials text;
  v_created public.tasks%rowtype;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.role = 'admin'
    and membership.status = 'active' and profile.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_task is null or jsonb_typeof(p_task) <> 'object' then raise exception 'TASK_INVALID'; end if;
  if length(trim(coalesce(p_task->>'title', ''))) < 3 then raise exception 'TASK_TITLE_REQUIRED'; end if;
  if coalesce(p_task->>'priority', 'medium') not in ('low', 'medium', 'high', 'critical') then raise exception 'TASK_PRIORITY_INVALID'; end if;

  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  v_assignee_id := nullif(p_task->>'assignedTo', '')::uuid;
  if v_assignee_id is not null then
    select profile.display_name into v_assignee_name
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.user_id = v_assignee_id
      and membership.status = 'active' and profile.status = 'active';
    if v_assignee_name is null then raise exception 'ASSIGNEE_INVALID'; end if;
  else
    select profile.display_name into v_assignee_name from public.profiles profile where profile.id = (select auth.uid());
  end if;
  v_assignee_initials := upper(left(split_part(v_assignee_name, ' ', 1), 1) || left(split_part(v_assignee_name, ' ', 2), 1));

  insert into public.tasks (
    organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, due_date, pmf_layer, progress, points,
    assigned_to, created_by, estimated_hours, acceptance_criteria
  ) values (
    v_org_id, v_project_id, trim(p_task->>'title'), nullif(trim(p_task->>'objective'), ''),
    case when v_assignee_id is null then 'draft' else 'assigned' end,
    coalesce(p_task->>'priority', 'medium'), v_assignee_name,
    coalesce(nullif(v_assignee_initials, ''), 'AO'), nullif(p_task->>'dueDate', '')::date,
    nullif(trim(p_task->>'pmfLayer'), ''), 0, greatest(coalesce((p_task->>'points')::integer, 100), 0),
    v_assignee_id, (select auth.uid()), nullif(p_task->>'estimatedHours', '')::numeric,
    nullif(trim(p_task->>'acceptanceCriteria'), '')
  ) returning * into v_created;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'task', v_created.id, 'task_created', jsonb_build_object('assignedTo', v_assignee_id));
  return jsonb_build_object('id', v_created.id, 'title', v_created.title, 'status', v_created.status,
    'priority', v_created.priority, 'ownerName', v_created.owner_name, 'dueDate', v_created.due_date,
    'points', v_created.points, 'acceptanceCriteria', v_created.acceptance_criteria);
end;
$$;

create or replace function public.rpc_complete_password_change(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_result jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = p_user_id
    and membership.status = 'password_change_required'
    and profile.status = 'password_change_required'
    and profile.must_change_password
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'PASSWORD_CHANGE_NOT_REQUIRED'; end if;
  update public.profiles profile set must_change_password = false, updated_at = now()
  where profile.id = p_user_id;
  update public.profiles profile set status = 'active', updated_at = now() where profile.id = p_user_id;
  update public.organization_memberships membership set status = 'active', updated_at = now()
  where membership.organization_id = v_org_id and membership.user_id = p_user_id;
  update public.staff_onboarding_steps step
  set status = 'completed', completed_at = now(), completed_by = p_user_id, updated_at = now()
  where step.organization_id = v_org_id and step.user_id = p_user_id and step.step_key = 'secure_account';
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, p_user_id, 'profile', p_user_id, 'password_changed', '{}'::jsonb);
  select jsonb_build_object(
    'userId', profile.id, 'displayName', profile.display_name, 'loginIdentifier', profile.login_identifier,
    'locale', profile.locale, 'mustChangePassword', false, 'role', membership.role,
    'isOwner', membership.is_owner, 'organizationId', organization.id, 'organizationName', organization.name,
    'projectId', project.id, 'projectName', project.name
  ) into v_result
  from public.profiles profile
  join public.organization_memberships membership on membership.user_id = profile.id and membership.organization_id = v_org_id
  join public.organizations organization on organization.id = v_org_id
  left join lateral (select project_row.id, project_row.name from public.projects project_row
    where project_row.organization_id = v_org_id and project_row.status = 'active'
    order by project_row.created_at limit 1) project on true
  where profile.id = p_user_id;
  return v_result;
end;
$$;

create or replace function public.sync_candidate_to_crm()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_contact_id uuid;
  v_lifecycle text;
begin
  if new.assigned_to is null then return new; end if;
  v_lifecycle := case
    when new.outreach_status in ('Confirmed', 'Interested') then 'qualified'
    when new.outreach_status in ('Replied', 'Meeting Booked', 'Negotiating') then 'engaged'
    when new.outreach_status in ('Sent', 'Contacted', 'No Response', 'Follow-up 1', 'Follow-up 2') then 'contacted'
    when new.outreach_status in ('Declined', 'Unreachable') then 'paused'
    when new.outreach_status in ('Ready to Send', 'Drafted') then 'ready'
    when new.contact_readiness = 'Research needed' then 'researching'
    else 'new'
  end;

  if new.crm_contact_id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, email, phone, primary_channel,
      source_url, tags, owner_id, lifecycle, next_action, next_action_due,
      priority_score, notes, created_by
    ) values (
      new.organization_id, new.project_id, coalesce(nullif(new.category, ''), 'KOL'), new.name,
      case when coalesce(new.contact_detail, '') like '%@%' then new.contact_detail else null end,
      case when coalesce(new.contact_detail, '') not like '%@%' then nullif(new.contact_detail, '') else null end,
      coalesce(nullif(new.contact_channel, ''), split_part(coalesce(new.platforms, 'Email'), ' / ', 1), 'Email'),
      new.source_url, case when new.pmf_candidate then 'PMF candidate' else null end,
      new.assigned_to, v_lifecycle, new.next_step, new.next_step_due,
      coalesce(new.priority_score, 0), new.notes, coalesce(new.created_by, (select auth.uid()))
    ) returning id into v_contact_id;
    update public.candidates candidate set crm_contact_id = v_contact_id
    where candidate.id = new.id and candidate.crm_contact_id is null;
  else
    update public.crm_contacts contact set
      contact_type = coalesce(nullif(new.category, ''), contact.contact_type),
      name = new.name,
      email = case when coalesce(new.contact_detail, '') like '%@%' then new.contact_detail else contact.email end,
      phone = case when coalesce(new.contact_detail, '') not like '%@%' and nullif(new.contact_detail, '') is not null then new.contact_detail else contact.phone end,
      primary_channel = coalesce(nullif(new.contact_channel, ''), contact.primary_channel),
      source_url = coalesce(nullif(new.source_url, ''), contact.source_url),
      tags = case when new.pmf_candidate then 'PMF candidate' else contact.tags end,
      owner_id = new.assigned_to,
      lifecycle = v_lifecycle,
      next_action = new.next_step,
      next_action_due = new.next_step_due,
      priority_score = coalesce(new.priority_score, contact.priority_score),
      notes = coalesce(nullif(new.notes, ''), contact.notes),
      updated_at = now()
    where contact.organization_id = new.organization_id and contact.project_id = new.project_id and contact.id = new.crm_contact_id;
  end if;
  return new;
end;
$$;
drop trigger if exists candidate_crm_sync on public.candidates;
create trigger candidate_crm_sync
after insert or update of name, category, contact_channel, contact_detail, source_url,
  pmf_candidate, priority_score, owner_id, assigned_to, outreach_status, next_step,
  next_step_due, notes
on public.candidates for each row execute function public.sync_candidate_to_crm();

create or replace function public.rpc_update_onboarding_step(
  p_step_key text,
  p_status text default 'completed'
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_step public.staff_onboarding_steps%rowtype;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = (select auth.uid()) and membership.status = 'active'
    and profile.status = 'active' and not profile.must_change_password
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ACTIVE_MEMBERSHIP_REQUIRED'; end if;
  if p_step_key not in ('review_workspace', 'review_data_handling') then raise exception 'ONBOARDING_STEP_INVALID'; end if;
  if p_status not in ('in_progress', 'completed') then raise exception 'ONBOARDING_STATUS_INVALID'; end if;
  update public.staff_onboarding_steps step set status = p_status,
    completed_at = case when p_status = 'completed' then now() else null end,
    completed_by = case when p_status = 'completed' then (select auth.uid()) else null end,
    updated_at = now()
  where step.organization_id = v_org_id and step.user_id = (select auth.uid()) and step.step_key = p_step_key
  returning * into v_step;
  if v_step.id is null then raise exception 'ONBOARDING_STEP_NOT_FOUND'; end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'staff_onboarding', v_step.id, 'onboarding_step_updated', jsonb_build_object('stepKey', p_step_key, 'status', p_status));
  return jsonb_build_object('id', v_step.id, 'key', v_step.step_key, 'status', v_step.status, 'completedAt', v_step.completed_at);
end;
$$;

create or replace function public.complete_first_eod_onboarding()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.workflow_status in ('submitted', 'completed') then
    update public.staff_onboarding_steps step set status = 'completed',
      completed_at = coalesce(step.completed_at, now()), completed_by = new.author_id, updated_at = now()
    where step.organization_id = new.organization_id and step.user_id = new.author_id
      and step.step_key = 'file_first_eod' and step.status <> 'completed';
  end if;
  return new;
end;
$$;
drop trigger if exists onboarding_first_eod on public.daily_eod_briefs;
create trigger onboarding_first_eod after insert or update of workflow_status on public.daily_eod_briefs
for each row execute function public.complete_first_eod_onboarding();

revoke all on function public.is_org_member(uuid) from public, anon, authenticated;
revoke all on function public.is_org_admin(uuid) from public, anon, authenticated;
revoke all on function public.is_org_owner(uuid) from public, anon, authenticated;
revoke all on function public.rpc_admin_overview() from public, anon, authenticated;
revoke all on function public.rpc_admin_people(text,text,text) from public, anon, authenticated;
revoke all on function public.rpc_admin_person_detail(uuid) from public, anon, authenticated;
revoke all on function public.rpc_admin_upsert_staff_profile(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.rpc_admin_archive_user(uuid,uuid,text,date) from public, anon, authenticated;
revoke all on function public.rpc_admin_restore_user(uuid) from public, anon, authenticated;
revoke all on function public.rpc_admin_export_data(text) from public, anon, authenticated;
revoke all on function public.rpc_admin_import_data(jsonb,text,uuid,text) from public, anon, authenticated;
revoke all on function public.rpc_accept_invitation() from public, anon, authenticated;
revoke all on function public.rpc_complete_password_change(uuid) from public, anon, authenticated;
revoke all on function public.rpc_admin_create_task_v2(jsonb) from public, anon, authenticated;
revoke all on function public.sync_candidate_to_crm() from public, anon, authenticated;
revoke all on function public.rpc_update_onboarding_step(text,text) from public, anon, authenticated;
revoke all on function public.complete_first_eod_onboarding() from public, anon, authenticated;

grant execute on function public.is_org_member(uuid) to authenticated, service_role;
grant execute on function public.is_org_admin(uuid) to authenticated, service_role;
grant execute on function public.is_org_owner(uuid) to authenticated, service_role;
grant execute on function public.rpc_admin_overview() to authenticated, service_role;
grant execute on function public.rpc_admin_people(text,text,text) to authenticated, service_role;
grant execute on function public.rpc_admin_person_detail(uuid) to authenticated, service_role;
grant execute on function public.rpc_admin_upsert_staff_profile(uuid,jsonb) to authenticated, service_role;
grant execute on function public.rpc_admin_archive_user(uuid,uuid,text,date) to authenticated, service_role;
grant execute on function public.rpc_admin_restore_user(uuid) to authenticated, service_role;
grant execute on function public.rpc_admin_export_data(text) to authenticated, service_role;
grant execute on function public.rpc_admin_import_data(jsonb,text,uuid,text) to authenticated, service_role;
grant execute on function public.rpc_accept_invitation() to authenticated, service_role;
grant execute on function public.rpc_complete_password_change(uuid) to service_role;
grant execute on function public.rpc_admin_create_task_v2(jsonb) to authenticated, service_role;
grant execute on function public.rpc_update_onboarding_step(text,text) to authenticated, service_role;

comment on function public.rpc_admin_import_data(jsonb,text,uuid,text) is
  'Preview validates an Administration package; merge updates existing identities and assignments; full_restore additionally restores lifecycle and ownership and requires the organization owner.';
