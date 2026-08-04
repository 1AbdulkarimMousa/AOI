-- Required weekday end-of-day briefs with role-scoped review and reporting.

create table public.daily_eod_briefs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  author_role text not null check (author_role in ('admin', 'intern')),
  brief_date date not null,
  engagement_manager_id uuid references public.profiles(id) on delete restrict,
  person_in_charge_id uuid references public.profiles(id) on delete restrict,
  moved_outcome text,
  evidence_gathered text,
  deliverables_completed text,
  key_insight text,
  current_blocker text,
  blocker_impact text,
  proposed_solution text,
  executive_owners text[] not null default '{}'::text[],
  executive_request text,
  tomorrow_priorities text[] not null default array['', '', '']::text[],
  project_status text check (project_status is null or project_status in ('on_track', 'at_risk', 'off_track')),
  evidence_links jsonb not null default '[]'::jsonb,
  workflow_status text not null default 'draft' check (workflow_status in ('draft', 'submitted', 'completed')),
  submitted_at timestamptz,
  is_late boolean not null default false,
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  last_edited_by uuid references public.profiles(id) on delete set null,
  last_edit_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, author_id, brief_date),
  constraint daily_eod_project_scope_fk foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade,
  constraint daily_eod_executive_owners_check check (
    executive_owners <@ array['Eason', 'Zhenzhen', 'Mike', 'None']::text[]
    and not ('None' = any(executive_owners) and cardinality(executive_owners) > 1)
  ),
  constraint daily_eod_priorities_check check (cardinality(tomorrow_priorities) = 3),
  constraint daily_eod_evidence_links_check check (jsonb_typeof(evidence_links) = 'array')
);

create index daily_eod_project_date_idx
  on public.daily_eod_briefs (organization_id, project_id, brief_date desc, workflow_status);
create index daily_eod_author_date_idx
  on public.daily_eod_briefs (author_id, brief_date desc);

alter table public.daily_eod_briefs enable row level security;

create policy daily_eod_own_read on public.daily_eod_briefs
for select to authenticated
using (public.is_org_member(organization_id) and author_id = (select auth.uid()));

create policy daily_eod_admin_read on public.daily_eod_briefs
for select to authenticated
using (public.is_org_admin(organization_id));

revoke all on public.daily_eod_briefs from anon, authenticated;

create or replace function public.assert_daily_eod_payload(p_payload jsonb)
returns void language plpgsql immutable set search_path = '' as $$
declare
  v_owners text[];
  v_priorities text[];
begin
  if nullif(trim(p_payload->>'engagementManagerId'), '') is null
    or nullif(trim(p_payload->>'personInChargeId'), '') is null
    or nullif(trim(p_payload->>'movedOutcome'), '') is null
    or nullif(trim(p_payload->>'evidenceGathered'), '') is null
    or nullif(trim(p_payload->>'deliverablesCompleted'), '') is null
    or nullif(trim(p_payload->>'keyInsight'), '') is null
    or nullif(trim(p_payload->>'currentBlocker'), '') is null
    or nullif(trim(p_payload->>'blockerImpact'), '') is null
    or nullif(trim(p_payload->>'proposedSolution'), '') is null
    or nullif(trim(p_payload->>'executiveRequest'), '') is null then
    raise exception 'EOD_REQUIRED_FIELDS';
  end if;

  if coalesce(p_payload->>'projectStatus', '') not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'EOD_STATUS_INVALID';
  end if;

  if coalesce(jsonb_typeof(p_payload->'executiveOwners'), 'null') <> 'array' then raise exception 'EOD_EXECUTIVE_OWNER_REQUIRED'; end if;
  select coalesce(array_agg(value), '{}'::text[]) into v_owners
  from jsonb_array_elements_text(p_payload->'executiveOwners') value;
  if cardinality(v_owners) = 0
    or not (v_owners <@ array['Eason', 'Zhenzhen', 'Mike', 'None']::text[])
    or ('None' = any(v_owners) and cardinality(v_owners) > 1) then
    raise exception 'EOD_EXECUTIVE_OWNER_INVALID';
  end if;

  if coalesce(jsonb_typeof(p_payload->'tomorrowPriorities'), 'null') <> 'array' then raise exception 'EOD_PRIORITIES_REQUIRED'; end if;
  select coalesce(array_agg(trim(value)), '{}'::text[]) into v_priorities
  from jsonb_array_elements_text(p_payload->'tomorrowPriorities') value;
  if cardinality(v_priorities) <> 3 or exists (select 1 from unnest(v_priorities) priority where priority = '') then
    raise exception 'EOD_PRIORITIES_REQUIRED';
  end if;

  if coalesce(jsonb_typeof(p_payload->'evidenceLinks'), 'null') <> 'array'
    or jsonb_array_length(p_payload->'evidenceLinks') = 0
    or exists (
      select 1 from jsonb_array_elements(p_payload->'evidenceLinks') link
      where coalesce(link->>'sourceType', '') not in ('onedrive', 'crm', 'evidence_log', 'participant_tracker', 'other')
        or nullif(trim(link->>'label'), '') is null
        or coalesce(link->>'url', '') !~* '^https?://[^[:space:]]+$'
    ) then
    raise exception 'EOD_EVIDENCE_LINK_INVALID';
  end if;
end;
$$;

create or replace function public.daily_eod_brief_json(p_brief public.daily_eod_briefs)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_brief.id,
    'briefDate', p_brief.brief_date,
    'projectId', p_brief.project_id,
    'projectCode', (select project.code from public.projects project where project.id = p_brief.project_id),
    'projectName', (select project.name from public.projects project where project.id = p_brief.project_id),
    'authorId', p_brief.author_id,
    'authorName', (select profile.display_name from public.profiles profile where profile.id = p_brief.author_id),
    'authorRole', p_brief.author_role,
    'engagementManagerId', p_brief.engagement_manager_id,
    'engagementManagerName', (select profile.display_name from public.profiles profile where profile.id = p_brief.engagement_manager_id),
    'personInChargeId', p_brief.person_in_charge_id,
    'personInChargeName', (select profile.display_name from public.profiles profile where profile.id = p_brief.person_in_charge_id),
    'movedOutcome', p_brief.moved_outcome,
    'evidenceGathered', p_brief.evidence_gathered,
    'deliverablesCompleted', p_brief.deliverables_completed,
    'keyInsight', p_brief.key_insight,
    'currentBlocker', p_brief.current_blocker,
    'blockerImpact', p_brief.blocker_impact,
    'proposedSolution', p_brief.proposed_solution,
    'executiveOwners', to_jsonb(p_brief.executive_owners),
    'executiveRequest', p_brief.executive_request,
    'tomorrowPriorities', to_jsonb(p_brief.tomorrow_priorities),
    'projectStatus', p_brief.project_status,
    'evidenceLinks', p_brief.evidence_links,
    'workflowStatus', p_brief.workflow_status,
    'submittedAt', p_brief.submitted_at,
    'isLate', p_brief.is_late,
    'completedBy', p_brief.completed_by,
    'completedByName', (select profile.display_name from public.profiles profile where profile.id = p_brief.completed_by),
    'completedAt', p_brief.completed_at,
    'lastEditedBy', p_brief.last_edited_by,
    'lastEditedByName', (select profile.display_name from public.profiles profile where profile.id = p_brief.last_edited_by),
    'lastEditReason', p_brief.last_edit_reason,
    'createdAt', p_brief.created_at,
    'updatedAt', p_brief.updated_at
  );
$$;

revoke all on function public.assert_daily_eod_payload(jsonb) from public, anon, authenticated;
revoke all on function public.daily_eod_brief_json(public.daily_eod_briefs) from public, anon, authenticated;

create or replace function public.rpc_aoi_daily_eod_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_timezone text;
  v_local_now timestamp;
  v_brief_date date;
  v_is_workday boolean;
  v_brief public.daily_eod_briefs%rowtype;
  v_due_state text;
begin
  select membership.organization_id, membership.role, organization.timezone
  into v_org_id, v_role, v_timezone
  from public.organization_memberships membership
  join public.organizations organization on organization.id = membership.organization_id
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  v_local_now := timezone(v_timezone, clock_timestamp());
  v_brief_date := v_local_now::date;
  v_is_workday := extract(isodow from v_brief_date) between 1 and 5;
  select brief.* into v_brief from public.daily_eod_briefs brief
  where brief.project_id = v_project_id and brief.author_id = auth.uid() and brief.brief_date = v_brief_date;

  v_due_state := case
    when v_brief.workflow_status = 'completed' then 'completed'
    when v_brief.workflow_status = 'submitted' then 'submitted'
    when not v_is_workday then 'not_required'
    when v_local_now >= v_brief_date + time '17:00' then 'overdue'
    else 'due'
  end;

  return jsonb_build_object('dailyEod', jsonb_build_object(
    'serverDate', v_brief_date,
    'serverNow', clock_timestamp(),
    'timezone', v_timezone,
    'isWorkday', v_is_workday,
    'dueAt', (v_brief_date + time '17:00') at time zone v_timezone,
    'dueState', v_due_state,
    'myBrief', case when v_brief.id is null then null else public.daily_eod_brief_json(v_brief) end,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', membership.user_id, 'displayName', profile.display_name, 'role', membership.role)
        order by case membership.role when 'admin' then 1 else 2 end, profile.display_name)
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'
    ), '[]'::jsonb),
    'teamToday', case when v_role <> 'admin' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', membership.user_id,
        'displayName', profile.display_name,
        'role', membership.role,
        'briefId', brief.id,
        'workflowStatus', coalesce(brief.workflow_status, case when v_is_workday then 'missing' else 'not_required' end),
        'brief', case when brief.id is null then null else public.daily_eod_brief_json(brief) end,
        'submittedAt', brief.submitted_at,
        'isLate', coalesce(brief.is_late, false),
        'projectStatus', brief.project_status,
        'updatedAt', brief.updated_at
      ) order by case when brief.id is null then 1 when brief.workflow_status = 'submitted' then 2 else 3 end, profile.display_name)
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      left join public.daily_eod_briefs brief on brief.project_id = v_project_id
        and brief.author_id = membership.user_id and brief.brief_date = v_brief_date
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'
    ), '[]'::jsonb) end
  ));
end;
$$;

create or replace function public.rpc_aoi_save_daily_eod_brief(
  p_payload jsonb,
  p_expected_updated_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_timezone text;
  v_local_now timestamp;
  v_brief_date date;
  v_workflow text;
  v_manager_id uuid;
  v_pic_id uuid;
  v_before public.daily_eod_briefs%rowtype;
  v_saved public.daily_eod_briefs%rowtype;
  v_before_json jsonb;
begin
  select membership.organization_id, membership.role, organization.timezone
  into v_org_id, v_role, v_timezone
  from public.organization_memberships membership
  join public.organizations organization on organization.id = membership.organization_id
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  v_local_now := timezone(v_timezone, clock_timestamp());
  v_brief_date := v_local_now::date;
  if not (extract(isodow from v_brief_date) between 1 and 5) then raise exception 'EOD_NOT_REQUIRED_TODAY'; end if;
  v_workflow := coalesce(nullif(p_payload->>'workflowStatus', ''), 'draft');
  if v_workflow not in ('draft', 'submitted') then raise exception 'EOD_WORKFLOW_INVALID'; end if;
  if v_workflow = 'submitted' then perform public.assert_daily_eod_payload(p_payload); end if;

  v_manager_id := nullif(p_payload->>'engagementManagerId', '')::uuid;
  v_pic_id := nullif(p_payload->>'personInChargeId', '')::uuid;
  if (v_manager_id is not null and not exists (
      select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_manager_id and membership.status = 'active' and profile.status = 'active'
    )) or (v_pic_id is not null and not exists (
      select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_pic_id and membership.status = 'active' and profile.status = 'active'
    )) then raise exception 'EOD_MEMBER_INVALID'; end if;

  select brief.* into v_before from public.daily_eod_briefs brief
  where brief.project_id = v_project_id and brief.author_id = auth.uid() and brief.brief_date = v_brief_date
  for update;
  if v_before.workflow_status = 'completed' then raise exception 'EOD_ALREADY_COMPLETED'; end if;
  if v_before.id is not null and (p_expected_updated_at is null or v_before.updated_at <> p_expected_updated_at) then raise exception 'EOD_STALE_WRITE'; end if;
  if v_before.workflow_status = 'submitted' and v_workflow = 'draft' then raise exception 'EOD_WORKFLOW_INVALID'; end if;
  v_before_json := case when v_before.id is null then null else public.daily_eod_brief_json(v_before) end;

  if v_before.id is null then
    insert into public.daily_eod_briefs (
      organization_id, project_id, author_id, author_role, brief_date, engagement_manager_id,
      person_in_charge_id, moved_outcome, evidence_gathered, deliverables_completed, key_insight,
      current_blocker, blocker_impact, proposed_solution, executive_owners, executive_request,
      tomorrow_priorities, project_status, evidence_links, workflow_status, submitted_at, is_late,
      last_edited_by
    ) values (
      v_org_id, v_project_id, auth.uid(), v_role, v_brief_date, v_manager_id, v_pic_id,
      nullif(trim(p_payload->>'movedOutcome'), ''), nullif(trim(p_payload->>'evidenceGathered'), ''),
      nullif(trim(p_payload->>'deliverablesCompleted'), ''), nullif(trim(p_payload->>'keyInsight'), ''),
      nullif(trim(p_payload->>'currentBlocker'), ''), nullif(trim(p_payload->>'blockerImpact'), ''),
      nullif(trim(p_payload->>'proposedSolution'), ''),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners', '[]'::jsonb))), '{}'::text[]),
      nullif(trim(p_payload->>'executiveRequest'), ''),
      array[coalesce(p_payload#>>'{tomorrowPriorities,0}', ''), coalesce(p_payload#>>'{tomorrowPriorities,1}', ''), coalesce(p_payload#>>'{tomorrowPriorities,2}', '')],
      nullif(p_payload->>'projectStatus', ''),
      case when jsonb_typeof(p_payload->'evidenceLinks') = 'array' then p_payload->'evidenceLinks' else '[]'::jsonb end,
      v_workflow,
      case when v_workflow = 'submitted' then clock_timestamp() end,
      v_workflow = 'submitted' and v_local_now >= v_brief_date + time '17:00',
      auth.uid()
    ) returning * into v_saved;
  else
    update public.daily_eod_briefs brief set
      engagement_manager_id = v_manager_id,
      person_in_charge_id = v_pic_id,
      moved_outcome = nullif(trim(p_payload->>'movedOutcome'), ''),
      evidence_gathered = nullif(trim(p_payload->>'evidenceGathered'), ''),
      deliverables_completed = nullif(trim(p_payload->>'deliverablesCompleted'), ''),
      key_insight = nullif(trim(p_payload->>'keyInsight'), ''),
      current_blocker = nullif(trim(p_payload->>'currentBlocker'), ''),
      blocker_impact = nullif(trim(p_payload->>'blockerImpact'), ''),
      proposed_solution = nullif(trim(p_payload->>'proposedSolution'), ''),
      executive_owners = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners', '[]'::jsonb))), '{}'::text[]),
      executive_request = nullif(trim(p_payload->>'executiveRequest'), ''),
      tomorrow_priorities = array[coalesce(p_payload#>>'{tomorrowPriorities,0}', ''), coalesce(p_payload#>>'{tomorrowPriorities,1}', ''), coalesce(p_payload#>>'{tomorrowPriorities,2}', '')],
      project_status = nullif(p_payload->>'projectStatus', ''),
      evidence_links = case when jsonb_typeof(p_payload->'evidenceLinks') = 'array' then p_payload->'evidenceLinks' else '[]'::jsonb end,
      workflow_status = v_workflow,
      submitted_at = case when v_workflow = 'submitted' then coalesce(brief.submitted_at, clock_timestamp()) else brief.submitted_at end,
      is_late = case when v_workflow = 'submitted' then brief.is_late or v_local_now >= v_brief_date + time '17:00' else brief.is_late end,
      last_edited_by = auth.uid(),
      last_edit_reason = null,
      updated_at = clock_timestamp()
    where brief.id = v_before.id returning brief.* into v_saved;
  end if;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'daily_eod_brief', v_saved.id,
    case when v_workflow = 'submitted' and v_before.workflow_status is distinct from 'submitted' then 'submitted' else 'saved' end,
    jsonb_build_object('before', v_before_json, 'after', public.daily_eod_brief_json(v_saved)));
  return public.daily_eod_brief_json(v_saved);
end;
$$;

create or replace function public.rpc_aoi_admin_update_daily_eod_brief(
  p_brief_id uuid,
  p_payload jsonb,
  p_edit_reason text,
  p_expected_updated_at timestamptz,
  p_action text default 'save'
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_manager_id uuid;
  v_pic_id uuid;
  v_before public.daily_eod_briefs%rowtype;
  v_saved public.daily_eod_briefs%rowtype;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.role = 'admin' and membership.status = 'active' and caller.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_action not in ('save', 'complete') then raise exception 'EOD_ADMIN_ACTION_INVALID'; end if;
  if length(trim(coalesce(p_edit_reason, ''))) < 3 then raise exception 'EOD_ADMIN_EDIT_REASON_REQUIRED'; end if;

  select brief.* into v_before from public.daily_eod_briefs brief
  where brief.id = p_brief_id and brief.organization_id = v_org_id for update;
  if v_before.id is null then raise exception 'EOD_BRIEF_NOT_FOUND'; end if;
  if p_expected_updated_at is null or v_before.updated_at <> p_expected_updated_at then raise exception 'EOD_STALE_WRITE'; end if;
  if p_action = 'complete' and v_before.workflow_status <> 'submitted' then raise exception 'EOD_MUST_BE_SUBMITTED'; end if;
  if p_action = 'complete' or v_before.workflow_status in ('submitted', 'completed') then perform public.assert_daily_eod_payload(p_payload); end if;

  v_manager_id := nullif(p_payload->>'engagementManagerId', '')::uuid;
  v_pic_id := nullif(p_payload->>'personInChargeId', '')::uuid;
  if (v_manager_id is not null and not exists (
      select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_manager_id and membership.status = 'active' and profile.status = 'active'
    )) or (v_pic_id is not null and not exists (
      select 1 from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.user_id = v_pic_id and membership.status = 'active' and profile.status = 'active'
    )) then raise exception 'EOD_MEMBER_INVALID'; end if;

  update public.daily_eod_briefs brief set
    engagement_manager_id = v_manager_id,
    person_in_charge_id = v_pic_id,
    moved_outcome = nullif(trim(p_payload->>'movedOutcome'), ''),
    evidence_gathered = nullif(trim(p_payload->>'evidenceGathered'), ''),
    deliverables_completed = nullif(trim(p_payload->>'deliverablesCompleted'), ''),
    key_insight = nullif(trim(p_payload->>'keyInsight'), ''),
    current_blocker = nullif(trim(p_payload->>'currentBlocker'), ''),
    blocker_impact = nullif(trim(p_payload->>'blockerImpact'), ''),
    proposed_solution = nullif(trim(p_payload->>'proposedSolution'), ''),
    executive_owners = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners', '[]'::jsonb))), '{}'::text[]),
    executive_request = nullif(trim(p_payload->>'executiveRequest'), ''),
    tomorrow_priorities = array[coalesce(p_payload#>>'{tomorrowPriorities,0}', ''), coalesce(p_payload#>>'{tomorrowPriorities,1}', ''), coalesce(p_payload#>>'{tomorrowPriorities,2}', '')],
    project_status = nullif(p_payload->>'projectStatus', ''),
    evidence_links = case when jsonb_typeof(p_payload->'evidenceLinks') = 'array' then p_payload->'evidenceLinks' else '[]'::jsonb end,
    workflow_status = case when p_action = 'complete' then 'completed' else brief.workflow_status end,
    completed_by = case when p_action = 'complete' then auth.uid() else brief.completed_by end,
    completed_at = case when p_action = 'complete' then clock_timestamp() else brief.completed_at end,
    last_edited_by = auth.uid(),
    last_edit_reason = trim(p_edit_reason),
    updated_at = clock_timestamp()
  where brief.id = v_before.id returning brief.* into v_saved;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'daily_eod_brief', v_saved.id,
    case when p_action = 'complete' then 'completed' else 'admin_edited' end,
    jsonb_build_object('reason', trim(p_edit_reason), 'before', public.daily_eod_brief_json(v_before), 'after', public.daily_eod_brief_json(v_saved)));
  return public.daily_eod_brief_json(v_saved);
end;
$$;

create or replace function public.rpc_aoi_daily_eod_reports(
  p_filters jsonb default '{}'::jsonb,
  p_page integer default 1,
  p_page_size integer default 25
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_role text;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 25), 100));
  v_result jsonb;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  with filtered as (
    select brief.* from public.daily_eod_briefs brief
    join public.profiles author on author.id = brief.author_id
    left join public.profiles manager on manager.id = brief.engagement_manager_id
    left join public.profiles person_in_charge on person_in_charge.id = brief.person_in_charge_id
    where brief.organization_id = v_org_id
      and (v_role = 'admin' or brief.author_id = auth.uid())
      and (nullif(p_filters->>'search', '') is null or concat_ws(' ', author.display_name, manager.display_name, person_in_charge.display_name) ilike '%' || trim(p_filters->>'search') || '%')
      and (nullif(p_filters->>'fromDate', '') is null or brief.brief_date >= (p_filters->>'fromDate')::date)
      and (nullif(p_filters->>'toDate', '') is null or brief.brief_date <= (p_filters->>'toDate')::date)
      and (nullif(p_filters->>'authorRole', '') is null or brief.author_role = p_filters->>'authorRole')
      and (nullif(p_filters->>'projectStatus', '') is null or brief.project_status = p_filters->>'projectStatus')
      and (nullif(p_filters->>'workflowStatus', '') is null or brief.workflow_status = p_filters->>'workflowStatus')
  ), paged as (
    select brief.* from filtered brief
    order by brief.brief_date desc, brief.updated_at desc
    limit v_page_size offset (v_page - 1) * v_page_size
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'page', v_page,
    'pageSize', v_page_size,
    'items', coalesce((select jsonb_agg(
      public.daily_eod_brief_json(brief) || jsonb_build_object('auditHistory', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', audit.id, 'action', audit.action, 'actorName', coalesce(actor.display_name, 'AOI'),
          'metadata', audit.metadata, 'createdAt', audit.created_at
        ) order by audit.created_at desc)
        from public.audit_events audit left join public.profiles actor on actor.id = audit.actor_id
        where audit.entity_type = 'daily_eod_brief' and audit.entity_id = brief.id
      ), '[]'::jsonb))
      order by brief.brief_date desc, brief.updated_at desc
    ) from paged brief), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.rpc_aoi_daily_eod_snapshot() from public, anon;
revoke all on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) from public, anon;
revoke all on function public.rpc_aoi_admin_update_daily_eod_brief(uuid,jsonb,text,timestamptz,text) from public, anon;
revoke all on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) from public, anon;
grant execute on function public.rpc_aoi_daily_eod_snapshot() to authenticated;
grant execute on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) to authenticated;
grant execute on function public.rpc_aoi_admin_update_daily_eod_brief(uuid,jsonb,text,timestamptz,text) to authenticated;
grant execute on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) to authenticated;
