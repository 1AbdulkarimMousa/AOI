-- Durable intern checkpoints, CRM onboarding completion, and password reminders.

alter table public.profiles
  add column if not exists password_reminder_seeded_at timestamptz,
  add column if not exists password_changed_at timestamptz,
  add column if not exists password_reminder_snoozed_until timestamptz;

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
    on membership.user_id = profile.id and membership.status = 'active'
  join public.organizations organization on organization.id = membership.organization_id
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at, project_row.id
    limit 1
  ) project on true
  where profile.id = auth.uid() and profile.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
$$;

create or replace function public.rpc_mark_password_changed()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = (select auth.uid()) and status = 'active';
  if not found then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object('changedAt', clock_timestamp());
end;
$$;

create or replace function public.rpc_snooze_password_reminder(p_until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_until is null or p_until <= clock_timestamp() then raise exception 'PASSWORD_SNOOZE_INVALID'; end if;
  update public.profiles
  set password_reminder_snoozed_until = p_until, updated_at = clock_timestamp()
  where id = (select auth.uid()) and status = 'active';
  if not found then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object('snoozedUntil', p_until);
end;
$$;

create or replace function public.rpc_aoi_update_task_checkpoint(
  p_task_id uuid,
  p_progress integer,
  p_status text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.tasks%rowtype;
  v_profile public.profiles%rowtype;
  v_status text;
begin
  if p_progress is null or p_progress < 0 or p_progress > 100 then raise exception 'TASK_PROGRESS_INVALID'; end if;
  if p_status is not null and p_status not in ('assigned', 'in_progress', 'blocked', 'submitted', 'resubmitted', 'completed') then raise exception 'TASK_STATUS_INVALID'; end if;

  select task.* into v_task
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
   and membership.user_id = (select auth.uid())
   and membership.status = 'active'
  join public.profiles profile
    on profile.id = membership.user_id and profile.status = 'active'
  where task.id = p_task_id and task.assigned_to = (select auth.uid());
  if v_task.id is null then raise exception 'TASK_NOT_ASSIGNED'; end if;

  select profile.* into v_profile from public.profiles profile where profile.id = (select auth.uid());
  v_status := coalesce(p_status, case when p_progress > 0 and v_task.status = 'assigned' then 'in_progress' else v_task.status end);
  update public.tasks
  set progress = p_progress, status = v_status, updated_at = clock_timestamp()
  where id = v_task.id;

  insert into public.activity_events (organization_id, project_id, actor_name, actor_initials, action, subject, event_type, occurred_at)
  values (v_task.organization_id, v_task.project_id, v_profile.display_name, upper(left(regexp_replace(v_profile.display_name, '[^A-Za-z]', '', 'g'), 2)),
    'updated task checkpoint to ' || p_progress || '%' || case when p_note is null or trim(p_note) = '' then '' else ': ' || trim(p_note) end,
    v_task.title, 'task_checkpoint', clock_timestamp());

  return jsonb_build_object('id', v_task.id, 'progress', p_progress, 'status', v_status);
end;
$$;

insert into public.staff_onboarding_steps (organization_id, user_id, step_key, label, sequence)
select staff.organization_id, staff.user_id, 'log_crm_outcome', 'Log CRM outcomes', 35
from public.staff_profiles staff
on conflict (organization_id, user_id, step_key) do nothing;

create or replace function public.rpc_update_onboarding_step(p_step_key text, p_status text default 'completed')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_step public.staff_onboarding_steps%rowtype;
begin
  if p_step_key not in ('review_workspace', 'review_data_handling', 'log_crm_outcome') then raise exception 'ONBOARDING_STEP_INVALID'; end if;
  if p_status not in ('pending', 'in_progress', 'completed', 'waived') then raise exception 'ONBOARDING_STATUS_INVALID'; end if;
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active' and not profile.must_change_password
  where membership.user_id = (select auth.uid()) and membership.status = 'active'
  limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  update public.staff_onboarding_steps step
  set status = p_status,
      completed_at = case when p_status in ('completed', 'waived') then coalesce(step.completed_at, clock_timestamp()) else null end,
      completed_by = case when p_status in ('completed', 'waived') then (select auth.uid()) else null end,
      updated_at = clock_timestamp()
  where step.organization_id = v_org_id and step.user_id = (select auth.uid()) and step.step_key = p_step_key
  returning * into v_step;
  if v_step.id is null then raise exception 'ONBOARDING_STEP_NOT_FOUND'; end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, (select auth.uid()), 'staff_onboarding', v_step.id, 'onboarding_step_updated', jsonb_build_object('stepKey', p_step_key, 'status', p_status));
  return jsonb_build_object('id', v_step.id, 'stepKey', v_step.step_key, 'status', v_step.status);
end;
$$;

revoke all on function public.rpc_mark_password_changed() from public, anon;
revoke all on function public.rpc_snooze_password_reminder(timestamptz) from public, anon;
revoke all on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) from public, anon;
revoke all on function public.rpc_update_onboarding_step(text, text) from public, anon;
grant execute on function public.rpc_mark_password_changed() to authenticated;
grant execute on function public.rpc_snooze_password_reminder(timestamptz) to authenticated;
grant execute on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) to authenticated;
grant execute on function public.rpc_update_onboarding_step(text, text) to authenticated;
