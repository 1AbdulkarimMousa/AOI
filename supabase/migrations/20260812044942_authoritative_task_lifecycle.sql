-- Authoritative, review-gated task lifecycle with optimistic concurrency.

alter table public.tasks
  add column if not exists submitted_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text,
  add column if not exists approved_at timestamptz,
  add column if not exists completed_by uuid references public.profiles(id) on delete set null,
  add column if not exists completed_at timestamptz;

create table public.task_review_history (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('request_revision', 'approve', 'complete')),
  from_status text not null,
  to_status text not null,
  note text,
  created_at timestamptz not null default clock_timestamp()
);

create index task_review_history_task_idx
  on public.task_review_history (task_id, created_at, id);
create index task_review_history_scope_idx
  on public.task_review_history (organization_id, project_id, created_at desc);

alter table public.task_review_history enable row level security;

create policy task_review_history_role_read on public.task_review_history
for select to authenticated
using (
  public.is_org_admin(organization_id)
  or (
    public.is_org_member(organization_id)
    and exists (
      select 1
      from public.tasks task
      where task.id = task_review_history.task_id
        and task.organization_id = task_review_history.organization_id
        and task.project_id = task_review_history.project_id
        and task.assigned_to = (select auth.uid())
    )
  )
);

create or replace function private.prevent_task_review_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'TASK_REVIEW_HISTORY_APPEND_ONLY';
end;
$$;

revoke all on function private.prevent_task_review_history_mutation() from public, anon, authenticated;

create trigger prevent_task_review_history_mutation
before update or delete on public.task_review_history
for each row execute function private.prevent_task_review_history_mutation();

create or replace function public.rpc_aoi_task_detail(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_task public.tasks%rowtype;
  v_is_admin boolean;
begin
  select task.* into v_task
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
   and membership.user_id = v_actor_id
   and membership.status = 'active'
  join public.profiles profile
    on profile.id = membership.user_id
   and profile.status = 'active'
   and not profile.must_change_password
  join public.organizations organization
    on organization.id = task.organization_id
   and organization.status = 'active'
  where task.id = p_task_id
  limit 1;

  if v_task.id is null then raise exception 'TASK_NOT_FOUND'; end if;
  v_is_admin := public.is_org_admin(v_task.organization_id);
  if not v_is_admin and v_task.assigned_to is distinct from v_actor_id then
    raise exception 'TASK_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'id', v_task.id,
    'title', v_task.title,
    'objective', v_task.objective,
    'status', v_task.status,
    'priority', v_task.priority,
    'ownerName', v_task.owner_name,
    'ownerInitials', v_task.owner_initials,
    'assignedTo', v_task.assigned_to,
    'createdBy', v_task.created_by,
    'dueDate', v_task.due_date,
    'pmfLayer', v_task.pmf_layer,
    'progress', v_task.progress,
    'points', v_task.points,
    'acceptanceCriteria', v_task.acceptance_criteria,
    'estimatedHours', v_task.estimated_hours,
    'submittedAt', v_task.submitted_at,
    'reviewedBy', v_task.reviewed_by,
    'reviewedAt', v_task.reviewed_at,
    'reviewNote', v_task.review_note,
    'approvedAt', v_task.approved_at,
    'completedBy', v_task.completed_by,
    'completedAt', v_task.completed_at,
    'createdAt', v_task.created_at,
    'updatedAt', v_task.updated_at,
    'reviewHistory', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id,
        'action', history.action,
        'fromStatus', history.from_status,
        'toStatus', history.to_status,
        'note', history.note,
        'actorId', history.actor_id,
        'actorName', actor.display_name,
        'createdAt', history.created_at
      ) order by history.created_at, history.id)
      from public.task_review_history history
      join public.profiles actor on actor.id = history.actor_id
      where history.task_id = v_task.id
        and history.organization_id = v_task.organization_id
        and history.project_id = v_task.project_id
    ), '[]'::jsonb)
  );
end;
$$;

drop function if exists public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text);

create or replace function public.rpc_aoi_update_task_checkpoint(
  p_task_id uuid,
  p_progress integer,
  p_status text default null,
  p_note text default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_task public.tasks%rowtype;
  v_profile public.profiles%rowtype;
  v_status text;
  v_updated_at timestamptz;
begin
  if p_expected_updated_at is null then raise exception 'TASK_EXPECTED_UPDATED_AT_REQUIRED'; end if;
  if p_progress is null or p_progress < 0 or p_progress > 100 then raise exception 'TASK_PROGRESS_INVALID'; end if;
  if p_status is not null and p_status not in ('assigned', 'in_progress', 'blocked', 'submitted', 'resubmitted') then
    if p_status = 'completed' then raise exception 'TASK_SELF_COMPLETION_FORBIDDEN'; end if;
    raise exception 'TASK_STATUS_INVALID';
  end if;
  if p_status = 'resubmitted' and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'TASK_CHECKPOINT_NOTE_REQUIRED';
  end if;

  select task.* into v_task
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
   and membership.user_id = v_actor_id
   and membership.status = 'active'
  join public.profiles profile
    on profile.id = membership.user_id
   and profile.status = 'active'
   and not profile.must_change_password
  join public.organizations organization
    on organization.id = task.organization_id
   and organization.status = 'active'
  where task.id = p_task_id and task.assigned_to = v_actor_id
  for update of task;
  if v_task.id is null then raise exception 'TASK_NOT_ASSIGNED'; end if;
  if v_task.updated_at is distinct from p_expected_updated_at then raise exception 'TASK_STALE_WRITE'; end if;
  if v_task.status in ('submitted', 'resubmitted', 'approved', 'completed', 'cancelled') then raise exception 'TASK_CHECKPOINT_LOCKED'; end if;

  if p_status is not null then
    if p_status = 'resubmitted' and v_task.status <> 'revision_requested' then
      raise exception 'TASK_RESUBMISSION_INVALID';
    elsif p_status in ('in_progress', 'blocked', 'submitted')
      and v_task.status not in ('assigned', 'in_progress', 'blocked') then
      raise exception 'TASK_TRANSITION_INVALID';
    elsif p_status = 'assigned' and v_task.status <> 'assigned' then
      raise exception 'TASK_TRANSITION_INVALID';
    end if;
  end if;

  select profile.* into v_profile from public.profiles profile where profile.id = v_actor_id;
  v_status := coalesce(
    p_status,
    case when p_progress > 0 and v_task.status = 'assigned' then 'in_progress' else v_task.status end
  );
  v_updated_at := clock_timestamp();

  update public.tasks
  set progress = p_progress,
      status = v_status,
      submitted_at = case when v_status in ('submitted', 'resubmitted') then v_updated_at else submitted_at end,
      updated_at = v_updated_at
  where id = v_task.id;

  insert into public.activity_events (
    organization_id, project_id, actor_name, actor_initials,
    action, subject, event_type, occurred_at
  ) values (
    v_task.organization_id,
    v_task.project_id,
    v_profile.display_name,
    upper(left(regexp_replace(v_profile.display_name, '[^A-Za-z]', '', 'g'), 2)),
    'updated task checkpoint to ' || p_progress || '%' ||
      case when p_note is null or trim(p_note) = '' then '' else ': ' || trim(p_note) end,
    v_task.title,
    'task_checkpoint',
    v_updated_at
  );

  return jsonb_build_object(
    'id', v_task.id,
    'progress', p_progress,
    'status', v_status,
    'updatedAt', v_updated_at
  );
end;
$$;

create or replace function public.rpc_aoi_review_task(
  p_task_id uuid,
  p_action text,
  p_note text default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_task public.tasks%rowtype;
  v_status text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_updated_at timestamptz;
begin
  if p_expected_updated_at is null then raise exception 'TASK_EXPECTED_UPDATED_AT_REQUIRED'; end if;
  if p_action not in ('request_revision', 'approve', 'complete') then raise exception 'TASK_REVIEW_ACTION_INVALID'; end if;
  if p_action = 'request_revision' and length(coalesce(v_note, '')) < 12 then
    raise exception 'TASK_REVIEW_NOTE_REQUIRED';
  end if;

  select task.* into v_task
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
   and membership.user_id = v_actor_id
   and membership.role = 'admin'
   and membership.status = 'active'
  join public.profiles profile
    on profile.id = membership.user_id
   and profile.status = 'active'
   and not profile.must_change_password
  join public.organizations organization
    on organization.id = task.organization_id
   and organization.status = 'active'
  where task.id = p_task_id
  for update of task;
  if v_task.id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if v_task.updated_at is distinct from p_expected_updated_at then raise exception 'TASK_STALE_WRITE'; end if;

  if p_action = 'request_revision' then
    if v_task.status not in ('submitted', 'resubmitted') then raise exception 'TASK_REVIEW_TRANSITION_INVALID'; end if;
    v_status := 'revision_requested';
  elsif p_action = 'approve' then
    if v_task.status not in ('submitted', 'resubmitted') then raise exception 'TASK_REVIEW_TRANSITION_INVALID'; end if;
    v_status := 'approved';
  else
    if v_task.status <> 'approved' then raise exception 'TASK_REVIEW_TRANSITION_INVALID'; end if;
    v_status := 'completed';
  end if;

  v_updated_at := clock_timestamp();
  update public.tasks
  set status = v_status,
      reviewed_by = case when p_action in ('request_revision', 'approve') then v_actor_id else reviewed_by end,
      reviewed_at = case when p_action in ('request_revision', 'approve') then v_updated_at else reviewed_at end,
      review_note = case when p_action in ('request_revision', 'approve') then v_note else review_note end,
      approved_at = case when p_action = 'approve' then v_updated_at else approved_at end,
      completed_by = case when p_action = 'complete' then v_actor_id else completed_by end,
      completed_at = case when p_action = 'complete' then v_updated_at else completed_at end,
      progress = case when p_action = 'complete' then 100 else progress end,
      updated_at = v_updated_at
  where id = v_task.id;

  insert into public.task_review_history (
    organization_id, project_id, task_id, actor_id,
    action, from_status, to_status, note, created_at
  ) values (
    v_task.organization_id, v_task.project_id, v_task.id, v_actor_id,
    p_action, v_task.status, v_status, v_note, v_updated_at
  );

  insert into public.activity_events (
    organization_id, project_id, actor_name, actor_initials,
    action, subject, event_type, occurred_at
  )
  select
    v_task.organization_id,
    v_task.project_id,
    profile.display_name,
    upper(left(regexp_replace(profile.display_name, '[^A-Za-z]', '', 'g'), 2)),
    case p_action
      when 'request_revision' then 'requested task revision: ' || v_note
      when 'approve' then 'approved task' || case when v_note is null then '' else ': ' || v_note end
      else 'completed approved task' || case when v_note is null then '' else ': ' || v_note end
    end,
    v_task.title,
    'task_review',
    v_updated_at
  from public.profiles profile where profile.id = v_actor_id;

  return jsonb_build_object(
    'id', v_task.id,
    'status', v_status,
    'updatedAt', v_updated_at
  );
end;
$$;

create or replace function public.rpc_aoi_demo_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_organization_id uuid;
  current_project_id uuid;
  membership_role text;
  result jsonb;
begin
  select membership.organization_id, membership.role
  into current_organization_id, membership_role
  from public.organization_memberships membership
  join public.profiles profile
    on profile.id = membership.user_id
   and profile.status = 'active'
   and not profile.must_change_password
  join public.organizations organization
    on organization.id = membership.organization_id
   and organization.status = 'active'
  join auth.users auth_user
    on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end,
    membership.joined_at, membership.organization_id
  limit 1;
  if current_organization_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id into current_project_id
  from public.projects project
  where project.organization_id = current_organization_id and project.status = 'active'
  order by project.created_at, project.id
  limit 1;
  if current_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  select jsonb_build_object(
    'organization', jsonb_build_object('id', organization.id, 'name', organization.name, 'slug', organization.slug),
    'project', jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name, 'description', project.description, 'currentWeek', project.current_week, 'startDate', project.start_date, 'endDate', project.end_date),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', metric.metric_key, 'label', metric.label, 'value', metric.value, 'target', metric.target, 'unit', metric.unit, 'delta', metric.delta) order by case metric.metric_key when 'weekly_plan' then 1 when 'evidence_records' then 2 when 'pending_reviews' then 3 when 'active_blockers' then 4 else 99 end) from public.project_metrics metric where metric.project_id = project.id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
      'id', task.id, 'title', task.title, 'objective', task.objective,
      'status', task.status, 'priority', task.priority,
      'ownerName', task.owner_name, 'ownerInitials', task.owner_initials,
      'assignedTo', task.assigned_to, 'dueDate', task.due_date,
      'pmfLayer', task.pmf_layer, 'progress', task.progress, 'points', task.points,
      'acceptanceCriteria', task.acceptance_criteria, 'estimatedHours', task.estimated_hours,
      'submittedAt', task.submitted_at, 'reviewedAt', task.reviewed_at,
      'approvedAt', task.approved_at, 'completedAt', task.completed_at,
      'updatedAt', task.updated_at
    ) order by task.due_date nulls last, task.priority desc)
      from public.tasks task
      where task.organization_id = current_organization_id
        and task.project_id = project.id
        and (membership_role = 'admin' or task.assigned_to = auth.uid())), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object('id', sample.id, 'label', sample.label, 'pmfLayer', sample.pmf_layer, 'actual', sample.actual, 'target', sample.target, 'accent', sample.accent) order by case sample.label when 'Dental professionals' then 1 when 'Consumer interviews' then 2 when 'Concept-test responses' then 3 when 'Product test users' then 4 else 99 end) from public.sample_plan_items sample where sample.project_id = project.id), '[]'::jsonb),
    'pmfLayers', coalesce((select jsonb_agg(jsonb_build_object('id', layer.id, 'code', layer.code, 'name', layer.name, 'sequence', layer.sequence, 'confidence', layer.confidence, 'status', layer.status, 'evidenceCount', layer.evidence_count, 'counterevidenceCount', layer.counterevidence_count, 'nextAction', layer.next_action) order by layer.sequence) from public.pmf_layers layer where layer.project_id = project.id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('id', activity.id, 'actorName', activity.actor_name, 'actorInitials', activity.actor_initials, 'action', activity.action, 'subject', activity.subject, 'eventType', activity.event_type, 'occurredAt', activity.occurred_at) order by activity.occurred_at desc) from public.activity_events activity where activity.project_id = project.id), '[]'::jsonb),
    'signals', coalesce((select jsonb_agg(jsonb_build_object('id', signal.id, 'theme', signal.theme, 'stance', signal.stance, 'evidenceCount', signal.evidence_count, 'changePercent', signal.change_percent, 'strength', signal.strength) order by signal.evidence_count desc) from public.research_signals signal where signal.project_id = project.id), '[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id', progress.id, 'displayName', progress.display_name, 'initials', progress.initials, 'roleLabel', progress.role_label, 'points', progress.points, 'weeklyPoints', progress.weekly_points, 'streakDays', progress.streak_days, 'completedTasks', progress.completed_tasks, 'rank', progress.rank) order by progress.rank) from public.team_progress progress where progress.project_id = project.id), '[]'::jsonb),
    'generatedAt', now()
  ) into result
  from public.projects project
  join public.organizations organization on organization.id = project.organization_id
  where project.id = current_project_id and project.organization_id = current_organization_id;
  return result;
end;
$$;

revoke all on public.tasks, public.task_review_history from public, anon, authenticated;
grant select on public.tasks, public.task_review_history to authenticated;
grant all on public.tasks, public.task_review_history to service_role;

revoke all on function public.rpc_aoi_task_detail(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.rpc_aoi_review_task(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.rpc_aoi_demo_dashboard() from public, anon;
grant execute on function public.rpc_aoi_task_detail(uuid) to authenticated;
grant execute on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text, timestamptz) to authenticated;
grant execute on function public.rpc_aoi_review_task(uuid, text, text, timestamptz) to authenticated;
grant execute on function public.rpc_aoi_demo_dashboard() to authenticated;
grant execute on function public.rpc_aoi_task_detail(uuid) to service_role;
grant execute on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text, timestamptz) to service_role;
grant execute on function public.rpc_aoi_review_task(uuid, text, text, timestamptz) to service_role;

comment on table public.task_review_history is 'Append-only administrator decisions for task review and completion.';
comment on function public.rpc_aoi_task_detail(uuid) is 'Authorized task detail including acceptance criteria, estimated hours, lifecycle metadata, and review history.';
comment on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text, timestamptz) is 'Concurrency-safe assignee checkpoint; terminal completion remains administrator-controlled.';
comment on function public.rpc_aoi_review_task(uuid, text, text, timestamptz) is 'Administrator task revision, approval, and completion transitions with append-only history.';
