-- Keep password-change-required sessions visible to the login setup flow.

create or replace function public.rpc_current_user_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'loginIdentifier', profile.login_identifier,
    'locale', profile.locale,
    'mustChangePassword', profile.must_change_password,
    'passwordReminderSeededAt', profile.password_reminder_seeded_at,
    'passwordChangedAt', profile.password_changed_at,
    'passwordReminderSnoozedUntil', profile.password_reminder_snoozed_until,
    'role', membership.role,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles profile
  join public.organization_memberships membership
    on membership.user_id = profile.id
   and membership.status in ('active', 'password_change_required')
  join public.organizations organization on organization.id = membership.organization_id
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at, project_row.id
    limit 1
  ) project on true
  where profile.id = auth.uid()
    and profile.status in ('active', 'password_change_required')
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
$$;

revoke all on function public.rpc_current_user_context() from public, anon;
grant execute on function public.rpc_current_user_context() to authenticated;
