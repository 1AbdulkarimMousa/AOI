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

-- Keep unlinked aggregate observations, but exclude respondent-bound observations
-- whose current consent is not granted from the PMF matrix source.
do $patch$
declare
  v_definition text;
  v_original text;
begin
  select pg_get_functiondef('public.rpc_aoi_pmf_snapshot()'::regprocedure) into v_definition;
  if position('o.respondent_id is null or exists' in v_definition) = 0 then
    v_original := v_definition;
    v_definition := replace(
      v_definition,
      'where o.project_id=v_project_id),''[]''::jsonb)',
      'where o.project_id=v_project_id and (o.respondent_id is null or exists (select 1 from public.respondents respondent where respondent.id = o.respondent_id and respondent.consent_status = ''granted'')),''[]''::jsonb)'
    );
    if v_definition = v_original then raise exception 'PMF_SNAPSHOT_PATCH_FAILED'; end if;
    execute v_definition;
  end if;
end;
$patch$;

-- Apply the same consent rule to evidence and Gate snapshots.
do $patch$
declare
  v_definition text;
  v_original text;
begin
  select pg_get_functiondef('private.create_aoi_gate_snapshot(text,text,text)'::regprocedure) into v_definition;
  if position('respondent.consent_status = ''granted''' in v_definition) = 0 then
    v_original := v_definition;
    v_definition := replace(
      v_definition,
      'and evidence.pmf_layer = p_pmf_layer and evidence.workflow_status = ''approved''',
      'and evidence.pmf_layer = p_pmf_layer and evidence.workflow_status = ''approved'' and (evidence.respondent_id is null or exists (select 1 from public.respondents respondent where respondent.id = evidence.respondent_id and respondent.consent_status = ''granted''))'
    );
    v_definition := replace(
      v_definition,
      'and observation.workflow_status = ''approved''',
      'and observation.workflow_status = ''approved'' and (observation.respondent_id is null or exists (select 1 from public.respondents respondent where respondent.id = observation.respondent_id and respondent.consent_status = ''granted''))'
    );
    if v_definition = v_original then raise exception 'GATE_SNAPSHOT_PATCH_FAILED'; end if;
    execute v_definition;
  end if;
end;
$patch$;

-- EOD archive searches must not cross the active project boundary.
do $patch$
declare
  v_definition text;
  v_original text;
begin
  select pg_get_functiondef('public.rpc_aoi_daily_eod_reports(jsonb,integer,integer)'::regprocedure) into v_definition;
  if position('brief.project_id = v_project_id' in v_definition) = 0 then
    v_original := v_definition;
    if position('v_project_id uuid' in v_definition) = 0 then
      v_definition := replace(v_definition, 'v_org_id uuid;', 'v_org_id uuid; v_project_id uuid;');
    end if;
    v_definition := replace(
      v_definition,
      'if v_org_id is null then raise exception ''WORKSPACE_ACCESS_REQUIRED''; end if;',
      'if v_org_id is null then raise exception ''WORKSPACE_ACCESS_REQUIRED''; end if;' || chr(10) || chr(10) ||
      '  select project.id into v_project_id from public.projects project' || chr(10) ||
      '  where project.organization_id = v_org_id and project.status = ''active''' || chr(10) ||
      '  order by project.created_at, project.id limit 1;' || chr(10) ||
      '  if v_project_id is null then raise exception ''ACTIVE_PROJECT_REQUIRED''; end if;'
    );
    v_definition := replace(v_definition, 'where brief.organization_id = v_org_id', 'where brief.organization_id = v_org_id and brief.project_id = v_project_id');
    if v_definition = v_original then raise exception 'EOD_REPORT_PATCH_FAILED'; end if;
    execute v_definition;
  end if;
end;
$patch$;

revoke all on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) from public, anon;
grant execute on function public.rpc_aoi_update_task_checkpoint(uuid, integer, text, text) to authenticated;
