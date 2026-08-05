-- Administrator password management with compensating state transitions.

create schema if not exists private;
grant usage on schema private to service_role;

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

  v_previous := jsonb_build_object(
    'profileStatus', v_profile.status,
    'membershipStatus', v_membership.status,
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

  if not v_membership.is_owner then
    update public.organization_memberships
    set status = 'password_change_required', updated_at = clock_timestamp()
    where organization_id = p_organization_id and user_id = p_target_user_id;
  end if;

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
  where id = p_target_user_id;
  update public.organization_memberships
  set status = p_previous->>'membershipStatus', updated_at = clock_timestamp()
  where organization_id = p_organization_id and user_id = p_target_user_id;
end;
$$;

create or replace function private.admin_complete_self_password_change(
  p_organization_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id and membership.user_id = p_actor_id
      and membership.role = 'admin' and membership.status = 'active' and profile.status = 'active'
  ) then raise exception 'ADMIN_REQUIRED'; end if;

  update public.profiles
  set must_change_password = false, status = 'active', password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null, updated_at = clock_timestamp()
  where id = p_actor_id;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (p_organization_id, p_actor_id, 'profile', p_actor_id, 'password_changed_self', jsonb_build_object('source', 'administration'));
end;
$$;

create or replace function private.admin_record_password_reset(
  p_organization_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid,
  p_reason text,
  p_mode text,
  p_previous jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id and membership.user_id = p_actor_id
      and membership.role = 'admin' and membership.status = 'active'
      and profile.status = 'active' and not profile.must_change_password
  ) then raise exception 'ADMIN_REQUIRED'; end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (
    p_organization_id, p_actor_id, 'profile', p_target_user_id, 'password_reset_by_admin',
    jsonb_build_object(
      'reason', trim(p_reason),
      'mode', p_mode,
      'previousProfileStatus', p_previous->>'profileStatus',
      'previousMembershipStatus', p_previous->>'membershipStatus'
    )
  );
end;
$$;

create or replace function public.rpc_admin_prepare_password_reset(
  p_organization_id uuid, p_actor_id uuid, p_target_user_id uuid, p_reason text, p_mode text
)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.admin_prepare_password_reset(p_organization_id, p_actor_id, p_target_user_id, p_reason, p_mode);
$$;
create or replace function public.rpc_admin_restore_password_state(
  p_organization_id uuid, p_actor_id uuid, p_target_user_id uuid, p_previous jsonb
)
returns void language sql security invoker set search_path = '' as $$
  select private.admin_restore_password_state(p_organization_id, p_actor_id, p_target_user_id, p_previous);
$$;
create or replace function public.rpc_admin_complete_self_password_change(p_organization_id uuid, p_actor_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.admin_complete_self_password_change(p_organization_id, p_actor_id);
$$;
create or replace function public.rpc_admin_record_password_reset(
  p_organization_id uuid, p_actor_id uuid, p_target_user_id uuid, p_reason text, p_mode text, p_previous jsonb
)
returns void language sql security invoker set search_path = '' as $$
  select private.admin_record_password_reset(p_organization_id, p_actor_id, p_target_user_id, p_reason, p_mode, p_previous);
$$;

revoke all on function private.admin_prepare_password_reset(uuid,uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function private.admin_restore_password_state(uuid,uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function private.admin_complete_self_password_change(uuid,uuid) from public, anon, authenticated;
revoke all on function private.admin_record_password_reset(uuid,uuid,uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function private.admin_prepare_password_reset(uuid,uuid,uuid,text,text) to service_role;
grant execute on function private.admin_restore_password_state(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function private.admin_complete_self_password_change(uuid,uuid) to service_role;
grant execute on function private.admin_record_password_reset(uuid,uuid,uuid,text,text,jsonb) to service_role;

revoke all on function public.rpc_admin_prepare_password_reset(uuid,uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.rpc_admin_restore_password_state(uuid,uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.rpc_admin_complete_self_password_change(uuid,uuid) from public, anon, authenticated;
revoke all on function public.rpc_admin_record_password_reset(uuid,uuid,uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.rpc_admin_prepare_password_reset(uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.rpc_admin_restore_password_state(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function public.rpc_admin_complete_self_password_change(uuid,uuid) to service_role;
grant execute on function public.rpc_admin_record_password_reset(uuid,uuid,uuid,text,text,jsonb) to service_role;
