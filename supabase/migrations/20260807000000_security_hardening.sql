-- Phase 1 security hardening: drop dead function and enforce email confirmation.

-- The dead rpc_mark_password_changed function was granted to authenticated in
-- 202608050001, revoked in 20260805152000 and 20260805153000, and is never
-- invoked from the client. Drop it to remove the latent surface.
drop function if exists public.rpc_mark_password_changed();

-- Require a confirmed email before granting workspace context. Invited users
-- never reach this RPC (they are filtered by membership status) and temp
-- password users were created with email_confirm=true by admin-create-user.
-- Adding the email_confirmed_at check protects against future admin paths
-- that may toggle status without confirmation.
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
    'jobTitle', profile.job_title,
    'bio', profile.bio,
    'phone', profile.phone,
    'timezone', profile.timezone,
    'avatarKey', profile.avatar_key,
    'avatarPath', profile.avatar_path,
    'emailConfirmed', (auth_user.email_confirmed_at is not null),
    'role', membership.role,
    'isOwner', membership.is_owner,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles profile
  join public.organization_memberships membership
    on membership.user_id = profile.id
   and membership.status in ('active', 'password_change_required')
  join public.organizations organization
    on organization.id = membership.organization_id and organization.status = 'active'
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at, project_row.id
    limit 1
  ) project on true
  join auth.users auth_user
    on auth_user.id = profile.id
   and auth_user.email_confirmed_at is not null
  where profile.id = auth.uid()
    and profile.status in ('active', 'password_change_required')
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
$$;

revoke all on function public.rpc_current_user_context() from public, anon;
grant execute on function public.rpc_current_user_context() to authenticated;

-- Surface the new emailConfirmed flag to clients via the access payload.
comment on function public.rpc_current_user_context() is
  'Returns workspace context including an emailConfirmed boolean; requires auth.users.email_confirmed_at to be set.';
