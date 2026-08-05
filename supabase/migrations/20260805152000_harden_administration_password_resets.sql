-- Block every active organization while a global Auth password reset is pending.

alter table public.organization_memberships drop constraint if exists organization_memberships_owner_check;
alter table public.organization_memberships add constraint organization_memberships_owner_check
  check (not is_owner or (role = 'admin' and status in ('active', 'password_change_required'))) not valid;
alter table public.organization_memberships validate constraint organization_memberships_owner_check;

create or replace function private.admin_prepare_password_reset(
  p_organization_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid,
  p_reason text,
  p_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_membership public.organization_memberships%rowtype;
  v_membership_statuses jsonb;
  v_previous jsonb;
begin
  if p_actor_id = p_target_user_id then raise exception 'USE_SELF_PASSWORD_CHANGE'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'PASSWORD_RESET_REASON_REQUIRED'; end if;
  if p_mode not in ('generated', 'custom') then raise exception 'PASSWORD_RESET_MODE_INVALID'; end if;
  if not exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id
      and membership.user_id = p_actor_id
      and membership.role = 'admin'
      and membership.status = 'active'
      and profile.status = 'active'
      and not profile.must_change_password
  ) then raise exception 'ADMIN_REQUIRED'; end if;

  select profile.* into v_profile from public.profiles profile where profile.id = p_target_user_id for update;
  select membership.* into v_membership
  from public.organization_memberships membership
  where membership.organization_id = p_organization_id and membership.user_id = p_target_user_id
  for update;
  if v_profile.id is null or v_membership.user_id is null then raise exception 'PASSWORD_RESET_TARGET_NOT_FOUND'; end if;
  if v_profile.status <> 'active' or v_membership.status <> 'active' or v_profile.must_change_password then
    raise exception 'PASSWORD_RESET_TARGET_NOT_ACTIVE';
  end if;

  select coalesce(jsonb_object_agg(membership.organization_id::text, membership.status), '{}'::jsonb)
  into v_membership_statuses
  from public.organization_memberships membership
  where membership.user_id = p_target_user_id and membership.status = 'active';
  v_previous := jsonb_build_object(
    'profileStatus', v_profile.status,
    'membershipStatus', v_membership.status,
    'membershipStatuses', v_membership_statuses,
    'mustChangePassword', v_profile.must_change_password,
    'passwordReminderSeededAt', v_profile.password_reminder_seeded_at,
    'passwordReminderSnoozedUntil', v_profile.password_reminder_snoozed_until
  );

  update public.profiles
  set must_change_password = true,
      status = 'password_change_required',
      password_reminder_seeded_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = p_target_user_id;
  update public.organization_memberships
  set status = 'password_change_required', updated_at = clock_timestamp()
  where user_id = p_target_user_id and status = 'active';
  return v_previous;
end;
$$;

create or replace function private.admin_restore_password_state(
  p_organization_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid,
  p_previous jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_expected integer;
  v_restored integer := 0;
  v_row_count integer;
begin
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id and membership.user_id = p_actor_id
      and membership.role = 'admin' and membership.status = 'active'
      and profile.status = 'active' and not profile.must_change_password
  ) then raise exception 'ADMIN_REQUIRED'; end if;

  update public.profiles
  set status = p_previous->>'profileStatus',
      must_change_password = coalesce((p_previous->>'mustChangePassword')::boolean, false),
      password_reminder_seeded_at = nullif(p_previous->>'passwordReminderSeededAt', '')::timestamptz,
      password_reminder_snoozed_until = nullif(p_previous->>'passwordReminderSnoozedUntil', '')::timestamptz,
      updated_at = clock_timestamp()
  where id = p_target_user_id and status = 'password_change_required' and must_change_password;
  get diagnostics v_row_count = row_count;
  if v_row_count <> 1 then raise exception 'PASSWORD_RESET_STATE_CHANGED'; end if;

  if jsonb_typeof(p_previous->'membershipStatuses') = 'object' then
    v_expected := jsonb_object_length(p_previous->'membershipStatuses');
    for v_item in select key, value from jsonb_each_text(p_previous->'membershipStatuses') loop
      update public.organization_memberships
      set status = v_item.value, updated_at = clock_timestamp()
      where organization_id = v_item.key::uuid and user_id = p_target_user_id and status = 'password_change_required';
      get diagnostics v_row_count = row_count;
      v_restored := v_restored + v_row_count;
    end loop;
  else
    v_expected := 1;
    update public.organization_memberships
    set status = p_previous->>'membershipStatus', updated_at = clock_timestamp()
    where organization_id = p_organization_id and user_id = p_target_user_id and status = 'password_change_required';
    get diagnostics v_restored = row_count;
  end if;
  if v_restored <> v_expected then raise exception 'PASSWORD_RESET_STATE_CHANGED'; end if;
end;
$$;

create or replace function public.rpc_mark_password_changed()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if not exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.user_id = v_user_id
      and membership.status in ('active', 'password_change_required')
      and profile.status in ('active', 'password_change_required')
  ) then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  update public.profiles
  set must_change_password = false,
      status = 'active',
      password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = v_user_id;
  update public.organization_memberships
  set status = 'active', updated_at = clock_timestamp()
  where user_id = v_user_id and status = 'password_change_required';
  update public.staff_onboarding_steps
  set status = 'completed', completed_at = coalesce(completed_at, clock_timestamp()), completed_by = v_user_id, updated_at = clock_timestamp()
  where user_id = v_user_id and step_key = 'secure_account';
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
  order by case when membership.status = 'password_change_required' then 0 else 1 end,
    case membership.role when 'admin' then 0 else 1 end, membership.joined_at
  limit 1;
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
  where user_id = p_user_id and status = 'password_change_required';
  update public.staff_onboarding_steps
  set status = 'completed', completed_at = coalesce(completed_at, clock_timestamp()), completed_by = p_user_id, updated_at = clock_timestamp()
  where user_id = p_user_id and step_key = 'secure_account';

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

revoke all on function public.rpc_mark_password_changed() from public, anon, authenticated;
revoke all on function public.rpc_complete_password_change(uuid) from public, anon, authenticated;
grant execute on function public.rpc_complete_password_change(uuid) to service_role;
