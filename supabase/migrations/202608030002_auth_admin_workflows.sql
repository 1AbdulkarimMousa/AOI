-- Authenticated AOI administrator and task-management foundation.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  login_identifier text not null,
  locale text not null default 'en' check (locale in ('en', 'zh-CN')),
  must_change_password boolean not null default false,
  status text not null default 'active' check (status in ('active', 'invited', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_login_identifier_idx on public.profiles (lower(login_identifier));

create table if not exists public.organization_memberships (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('admin', 'intern')),
  status text not null default 'active' check (status in ('active', 'invited', 'disabled')),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index if not exists memberships_user_idx on public.organization_memberships (user_id, status, organization_id);

alter table public.tasks add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
alter table public.tasks add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.tasks add column if not exists acceptance_criteria text;
alter table public.tasks add column if not exists estimated_hours numeric(6,2) check (estimated_hours is null or estimated_hours >= 0);
create index if not exists tasks_assigned_user_idx on public.tasks (organization_id, assigned_to, status, due_date);

alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;

create or replace function public.is_org_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  );
$$;

create or replace function public.is_org_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.role = 'admin'
      and membership.status = 'active'
  );
$$;

revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.is_org_admin(uuid) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.is_org_admin(uuid) to authenticated;

drop policy if exists profiles_self_or_org_read on public.profiles;
create policy profiles_self_or_org_read on public.profiles
for select to authenticated
using (
  id = auth.uid()
  or exists (
    select 1
    from public.organization_memberships mine
    join public.organization_memberships theirs on theirs.organization_id = mine.organization_id
    where mine.user_id = auth.uid()
      and mine.status = 'active'
      and theirs.user_id = profiles.id
      and theirs.status = 'active'
  )
);

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists memberships_org_read on public.organization_memberships;
create policy memberships_org_read on public.organization_memberships
for select to authenticated
using (public.is_org_member(organization_id));

drop policy if exists organizations_member_read on public.organizations;
create policy organizations_member_read on public.organizations
for select to authenticated
using (public.is_org_member(id));

drop policy if exists projects_member_read on public.projects;
create policy projects_member_read on public.projects
for select to authenticated
using (public.is_org_member(organization_id));

drop policy if exists tasks_role_read on public.tasks;
create policy tasks_role_read on public.tasks
for select to authenticated
using (
  public.is_org_admin(organization_id)
  or (
    public.is_org_member(organization_id)
    and assigned_to = auth.uid()
  )
);

drop policy if exists tasks_admin_insert on public.tasks;
create policy tasks_admin_insert on public.tasks
for insert to authenticated
with check (public.is_org_admin(organization_id) and created_by = auth.uid());

drop policy if exists tasks_admin_update on public.tasks;
create policy tasks_admin_update on public.tasks
for update to authenticated
using (public.is_org_admin(organization_id))
with check (public.is_org_admin(organization_id));

create or replace function public.rpc_current_user_context()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'userId', p.id,
    'displayName', p.display_name,
    'loginIdentifier', p.login_identifier,
    'locale', p.locale,
    'mustChangePassword', p.must_change_password,
    'role', membership.role,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles p
  join public.organization_memberships membership on membership.user_id = p.id and membership.status = 'active'
  join public.organizations organization on organization.id = membership.organization_id
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at
    limit 1
  ) project on true
  where p.id = auth.uid() and p.status = 'active'
  limit 1;
$$;

create or replace function public.rpc_admin_list_users()
returns table (
  user_id uuid,
  display_name text,
  login_identifier text,
  role text,
  membership_status text,
  joined_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.id, profile.display_name, profile.login_identifier, membership.role, membership.status, membership.joined_at
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.organization_id = (
    select mine.organization_id
    from public.organization_memberships mine
    where mine.user_id = auth.uid() and mine.role = 'admin' and mine.status = 'active'
    limit 1
  )
  and public.is_org_admin(membership.organization_id)
  order by case membership.role when 'admin' then 1 else 2 end, profile.display_name;
$$;

create or replace function public.rpc_admin_create_task(
  task_title text,
  task_objective text,
  task_priority text,
  task_due_date date,
  task_pmf_layer text,
  task_assigned_to uuid default null,
  task_estimated_hours numeric default null,
  task_points integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_organization_id uuid;
  active_project_id uuid;
  assigned_profile public.profiles%rowtype;
  created_task public.tasks%rowtype;
begin
  if length(trim(task_title)) < 3 then
    raise exception 'TASK_TITLE_REQUIRED';
  end if;

  if task_priority not in ('low', 'medium', 'high', 'critical') then
    raise exception 'TASK_PRIORITY_INVALID';
  end if;

  select membership.organization_id into caller_organization_id
  from public.organization_memberships membership
  where membership.user_id = auth.uid()
    and membership.role = 'admin'
    and membership.status = 'active'
  limit 1;

  if caller_organization_id is null or not public.is_org_admin(caller_organization_id) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  select project.id into active_project_id
  from public.projects project
  where project.organization_id = caller_organization_id and project.status = 'active'
  order by project.created_at
  limit 1;

  if active_project_id is null then
    raise exception 'ACTIVE_PROJECT_REQUIRED';
  end if;

  if task_assigned_to is not null then
    select profile.* into assigned_profile
    from public.profiles profile
    join public.organization_memberships membership on membership.user_id = profile.id
    where profile.id = task_assigned_to
      and membership.organization_id = caller_organization_id
      and membership.status = 'active';
    if assigned_profile.id is null then
      raise exception 'ASSIGNEE_INVALID';
    end if;
  end if;

  insert into public.tasks (
    organization_id, project_id, title, objective, status, priority,
    owner_name, owner_initials, due_date, pmf_layer, progress, points,
    assigned_to, created_by, estimated_hours
  ) values (
    caller_organization_id,
    active_project_id,
    trim(task_title),
    nullif(trim(task_objective), ''),
    case when task_assigned_to is null then 'draft' else 'assigned' end,
    task_priority,
    coalesce(assigned_profile.display_name, (select display_name from public.profiles where id = auth.uid())),
    coalesce(
      nullif(upper(left(split_part(assigned_profile.display_name, ' ', 1), 1) || left(split_part(assigned_profile.display_name, ' ', 2), 1)), ''),
      'AO'
    ),
    task_due_date,
    nullif(trim(task_pmf_layer), ''),
    0,
    greatest(coalesce(task_points, 100), 0),
    task_assigned_to,
    auth.uid(),
    task_estimated_hours
  )
  returning * into created_task;

  return jsonb_build_object(
    'id', created_task.id,
    'title', created_task.title,
    'status', created_task.status,
    'priority', created_task.priority,
    'ownerName', created_task.owner_name,
    'dueDate', created_task.due_date,
    'points', created_task.points
  );
end;
$$;

revoke all on function public.rpc_current_user_context() from public;
revoke all on function public.rpc_admin_list_users() from public;
revoke all on function public.rpc_admin_create_task(text,text,text,date,text,uuid,numeric,integer) from public;
grant execute on function public.rpc_current_user_context() to authenticated;
grant execute on function public.rpc_admin_list_users() to authenticated;
grant execute on function public.rpc_admin_create_task(text,text,text,date,text,uuid,numeric,integer) to authenticated;
