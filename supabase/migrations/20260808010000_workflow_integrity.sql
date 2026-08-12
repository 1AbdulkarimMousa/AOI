-- Phase 4 workflow integrity: consent-aware analysis, auditable task transitions,
-- and active-project EOD reporting.

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
  if p_progress is null or p_progress < 0 or p_progress > 100 then
    raise exception 'TASK_PROGRESS_INVALID';
  end if;
  if p_status is not null and p_status not in ('assigned', 'in_progress', 'blocked', 'submitted', 'resubmitted', 'completed') then
    raise exception 'TASK_STATUS_INVALID';
  end if;
  if p_status in ('completed', 'resubmitted') and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'TASK_CHECKPOINT_NOTE_REQUIRED';
  end if;
  if p_status = 'completed' and p_progress < 100 then
    raise exception 'TASK_COMPLETION_PROGRESS_REQUIRED';
  end if;

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
  if v_task.status in ('submitted', 'approved', 'completed', 'cancelled') then
    raise exception 'TASK_CHECKPOINT_LOCKED';
  end if;
  if p_status is not null then
    if p_status = 'resubmitted' and v_task.status <> 'revision_requested' then
      raise exception 'TASK_RESUBMISSION_INVALID';
    elsif p_status = 'completed' and v_task.status not in ('in_progress', 'blocked', 'resubmitted') then
      raise exception 'TASK_TRANSITION_INVALID';
    elsif p_status in ('in_progress', 'blocked', 'submitted') and v_task.status not in ('assigned', 'in_progress', 'blocked', 'resubmitted') then
      raise exception 'TASK_TRANSITION_INVALID';
    elsif p_status = 'assigned' and v_task.status <> 'assigned' then
      raise exception 'TASK_TRANSITION_INVALID';
    end if;
  end if;

  select profile.* into v_profile from public.profiles profile where profile.id = (select auth.uid());
  v_status := coalesce(p_status, case when p_progress > 0 and v_task.status = 'assigned' then 'in_progress' else v_task.status end);
  update public.tasks
  set progress = p_progress, status = v_status, updated_at = clock_timestamp()
  where id = v_task.id;

  insert into public.activity_events (organization_id, project_id, actor_name, actor_initials, action, subject, event_type, occurred_at)
  values (
    v_task.organization_id, v_task.project_id, v_profile.display_name,
    upper(left(regexp_replace(v_profile.display_name, '[^A-Za-z]', '', 'g'), 2)),
    'updated task checkpoint to ' || p_progress || '%' || case when p_note is null or trim(p_note) = '' then '' else ': ' || trim(p_note) end,
    v_task.title, 'task_checkpoint', clock_timestamp()
  );

  return jsonb_build_object('id', v_task.id, 'progress', p_progress, 'status', v_status);
end;
$$;

-- Consent-aware PMF/Gate snapshots and project-scoped EOD reporting are
-- replaced explicitly by the later forward hardening migration. Avoid the
-- historical function-text rewrites here: they are schema-format dependent and
-- can produce invalid SQL on a fresh installation.

revoke all on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) from public, anon;
grant execute on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) to authenticated;
