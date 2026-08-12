-- Preserve historical collected values while closing direct invitation activation.

revoke all on function public.rpc_accept_invitation() from public, anon, authenticated;
grant execute on function public.rpc_accept_invitation() to service_role;

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
  if current_user not in ('service_role', 'postgres') then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.user_id = p_user_id
    and membership.status in ('invited', 'active', 'password_change_required')
    and profile.status in ('invited', 'active', 'password_change_required')
    and profile.must_change_password
  order by case membership.status when 'invited' then 0 when 'password_change_required' then 1 else 2 end,
    case membership.role when 'admin' then 0 else 1 end,
    membership.joined_at,
    membership.organization_id
  limit 1
  for update of membership;
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
  where user_id = p_user_id and status in ('invited', 'password_change_required');
  update public.staff_onboarding_steps
  set status = 'completed',
      completed_at = coalesce(completed_at, clock_timestamp()),
      completed_by = p_user_id,
      updated_at = clock_timestamp()
  where user_id = p_user_id and step_key = 'secure_account';

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, p_user_id, 'profile', p_user_id, 'password_established', '{}'::jsonb);

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
  join public.organization_memberships membership
    on membership.user_id = profile.id
   and membership.organization_id = v_org_id
   and membership.status = 'active'
  join public.organizations organization on organization.id = v_org_id
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = v_org_id and project_row.status = 'active'
    order by project_row.created_at, project_row.id
    limit 1
  ) project on true
  where profile.id = p_user_id;
  return v_result;
end;
$$;

revoke all on function public.rpc_complete_password_change(uuid) from public, anon, authenticated;
grant execute on function public.rpc_complete_password_change(uuid) to service_role;
