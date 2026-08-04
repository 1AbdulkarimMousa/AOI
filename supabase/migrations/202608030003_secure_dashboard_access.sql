-- Require an active workspace membership for dashboard data and scope intern tasks.

create or replace function public.rpc_aoi_demo_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
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
  where membership.user_id = auth.uid()
    and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end
  limit 1;

  if current_organization_id is null then
    raise exception 'WORKSPACE_ACCESS_REQUIRED';
  end if;

  select project.id
  into current_project_id
  from public.projects project
  where project.organization_id = current_organization_id
    and project.status = 'active'
  order by project.created_at
  limit 1;

  if current_project_id is null then
    raise exception 'ACTIVE_PROJECT_REQUIRED';
  end if;

  select jsonb_build_object(
    'organization', jsonb_build_object('id', organization.id, 'name', organization.name, 'slug', organization.slug),
    'project', jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name, 'description', project.description, 'currentWeek', project.current_week, 'startDate', project.start_date, 'endDate', project.end_date),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', metric.metric_key, 'label', metric.label, 'value', metric.value, 'target', metric.target, 'unit', metric.unit, 'delta', metric.delta) order by case metric.metric_key when 'weekly_plan' then 1 when 'evidence_records' then 2 when 'pending_reviews' then 3 when 'active_blockers' then 4 else 99 end) from public.project_metrics metric where metric.project_id = project.id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', task.id, 'title', task.title, 'objective', task.objective, 'status', task.status, 'priority', task.priority, 'ownerName', task.owner_name, 'ownerInitials', task.owner_initials, 'dueDate', task.due_date, 'pmfLayer', task.pmf_layer, 'progress', task.progress, 'points', task.points) order by task.due_date nulls last, task.priority desc) from public.tasks task where task.project_id = project.id and (membership_role = 'admin' or task.assigned_to = auth.uid())), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object('id', sample.id, 'label', sample.label, 'pmfLayer', sample.pmf_layer, 'actual', sample.actual, 'target', sample.target, 'accent', sample.accent) order by case sample.label when 'Dental professionals' then 1 when 'Consumer interviews' then 2 when 'Concept-test responses' then 3 when 'Product test users' then 4 else 99 end) from public.sample_plan_items sample where sample.project_id = project.id), '[]'::jsonb),
    'pmfLayers', coalesce((select jsonb_agg(jsonb_build_object('id', layer.id, 'code', layer.code, 'name', layer.name, 'sequence', layer.sequence, 'confidence', layer.confidence, 'status', layer.status, 'evidenceCount', layer.evidence_count, 'counterevidenceCount', layer.counterevidence_count, 'nextAction', layer.next_action) order by layer.sequence) from public.pmf_layers layer where layer.project_id = project.id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('id', activity.id, 'actorName', activity.actor_name, 'actorInitials', activity.actor_initials, 'action', activity.action, 'subject', activity.subject, 'eventType', activity.event_type, 'occurredAt', activity.occurred_at) order by activity.occurred_at desc) from public.activity_events activity where activity.project_id = project.id), '[]'::jsonb),
    'signals', coalesce((select jsonb_agg(jsonb_build_object('id', signal.id, 'theme', signal.theme, 'stance', signal.stance, 'evidenceCount', signal.evidence_count, 'changePercent', signal.change_percent, 'strength', signal.strength) order by signal.evidence_count desc) from public.research_signals signal where signal.project_id = project.id), '[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id', progress.id, 'displayName', progress.display_name, 'initials', progress.initials, 'roleLabel', progress.role_label, 'points', progress.points, 'weeklyPoints', progress.weekly_points, 'streakDays', progress.streak_days, 'completedTasks', progress.completed_tasks, 'rank', progress.rank) order by progress.rank) from public.team_progress progress where progress.project_id = project.id), '[]'::jsonb),
    'generatedAt', now()
  )
  into result
  from public.projects project
  join public.organizations organization on organization.id = project.organization_id
  where project.id = current_project_id
    and project.organization_id = current_organization_id;

  return result;
end;
$$;

revoke all on function public.rpc_aoi_demo_dashboard() from public;
revoke execute on function public.rpc_aoi_demo_dashboard() from anon;
grant execute on function public.rpc_aoi_demo_dashboard() to authenticated;

comment on function public.rpc_aoi_demo_dashboard() is 'Authenticated, tenant-scoped AOI dashboard payload; intern tasks are assignment-scoped.';
