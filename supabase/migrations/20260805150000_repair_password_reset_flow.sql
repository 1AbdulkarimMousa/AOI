-- Repair legacy temporary-password accounts and support both password reset paths.

alter table public.organization_memberships drop constraint if exists organization_memberships_owner_check;
alter table public.organization_memberships add constraint organization_memberships_owner_check
  check (not is_owner or (role = 'admin' and status in ('active', 'password_change_required'))) not valid;
alter table public.organization_memberships validate constraint organization_memberships_owner_check;

update public.profiles
set status = 'password_change_required', updated_at = clock_timestamp()
where must_change_password and status = 'active';

update public.organization_memberships membership
set status = 'password_change_required', updated_at = clock_timestamp()
where status = 'active'
  and exists (
    select 1
    from public.profiles profile
    where profile.id = membership.user_id
      and profile.must_change_password
      and profile.status = 'password_change_required'
  );

create or replace function public.rpc_mark_password_changed()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_org_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = v_user_id
    and membership.status in ('active', 'password_change_required')
    and profile.status in ('active', 'password_change_required')
  order by case when membership.status = 'active' then 1 else 2 end, membership.joined_at
  limit 1;

  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  update public.profiles
  set must_change_password = false,
      status = 'active',
      password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = v_user_id;

  update public.organization_memberships
  set status = 'active', updated_at = clock_timestamp()
  where organization_id = v_org_id and user_id = v_user_id;

  update public.staff_onboarding_steps
  set status = 'completed', completed_at = coalesce(completed_at, clock_timestamp()), completed_by = v_user_id, updated_at = clock_timestamp()
  where organization_id = v_org_id and user_id = v_user_id and step_key = 'secure_account';

  return jsonb_build_object('changedAt', clock_timestamp());
end;
$$;

create or replace function public.rpc_complete_password_change(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_result jsonb;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = p_user_id
    and membership.status in ('active', 'password_change_required')
    and profile.status in ('active', 'password_change_required')
    and profile.must_change_password
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'PASSWORD_CHANGE_NOT_REQUIRED'; end if;

  update public.profiles
  set must_change_password = false,
      status = 'active',
      password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = p_user_id;
  update public.organization_memberships
  set status = 'active', updated_at = clock_timestamp()
  where organization_id = v_org_id and user_id = p_user_id;
  update public.staff_onboarding_steps
  set status = 'completed', completed_at = coalesce(completed_at, clock_timestamp()), completed_by = p_user_id, updated_at = clock_timestamp()
  where organization_id = v_org_id and user_id = p_user_id and step_key = 'secure_account';

  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'loginIdentifier', profile.login_identifier,
    'locale', profile.locale,
    'mustChangePassword', false,
    'role', membership.role,
    'isOwner', membership.is_owner,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  ) into v_result
  from public.profiles profile
  join public.organization_memberships membership on membership.user_id = profile.id and membership.organization_id = v_org_id and membership.status = 'active'
  join public.organizations organization on organization.id = v_org_id
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = v_org_id and project_row.status = 'active'
    order by project_row.created_at
    limit 1
  ) project on true
  where profile.id = p_user_id;
  return v_result;
end;
$$;

revoke all on function public.rpc_mark_password_changed() from public, anon;
revoke all on function public.rpc_complete_password_change(uuid) from public, anon, authenticated;
grant execute on function public.rpc_mark_password_changed() to authenticated;
grant execute on function public.rpc_complete_password_change(uuid) to service_role;
