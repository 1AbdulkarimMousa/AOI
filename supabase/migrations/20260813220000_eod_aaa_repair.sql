-- Restore first-save scope, organization reporting, and audited legacy completion.

alter table public.daily_eod_briefs
  add column if not exists legacy_evidence_missing boolean not null default false;

update public.daily_eod_briefs
set legacy_evidence_missing = true
where workflow_status in ('submitted', 'completed')
  and evidence_links = '[]'::jsonb
  and brief_date between date '2026-07-29' and date '2026-08-04';

create or replace function public.daily_eod_brief_json(p_brief public.daily_eod_briefs)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_brief.id, 'briefDate', p_brief.brief_date, 'projectId', p_brief.project_id,
    'projectCode', (select project.code from public.projects project where project.id = p_brief.project_id),
    'projectName', (select project.name from public.projects project where project.id = p_brief.project_id),
    'authorId', p_brief.author_id, 'authorName', (select profile.display_name from public.profiles profile where profile.id = p_brief.author_id),
    'authorRole', p_brief.author_role, 'engagementManagerId', p_brief.engagement_manager_id,
    'engagementManagerName', (select profile.display_name from public.profiles profile where profile.id = p_brief.engagement_manager_id),
    'personInChargeId', p_brief.person_in_charge_id,
    'personInChargeName', (select profile.display_name from public.profiles profile where profile.id = p_brief.person_in_charge_id),
    'movedOutcome', p_brief.moved_outcome, 'evidenceGathered', p_brief.evidence_gathered,
    'deliverablesCompleted', p_brief.deliverables_completed, 'keyInsight', p_brief.key_insight,
    'currentBlocker', p_brief.current_blocker, 'blockerImpact', p_brief.blocker_impact,
    'proposedSolution', p_brief.proposed_solution, 'executiveOwners', to_jsonb(p_brief.executive_owners),
    'executiveRequest', p_brief.executive_request, 'tomorrowPriorities', to_jsonb(p_brief.tomorrow_priorities),
    'projectStatus', p_brief.project_status, 'evidenceLinks', p_brief.evidence_links,
    'legacyEvidenceMissing', p_brief.legacy_evidence_missing, 'workflowStatus', p_brief.workflow_status,
    'submittedAt', p_brief.submitted_at, 'isLate', p_brief.is_late, 'completedBy', p_brief.completed_by,
    'completedByName', (select profile.display_name from public.profiles profile where profile.id = p_brief.completed_by),
    'completedAt', p_brief.completed_at, 'lastEditedBy', p_brief.last_edited_by,
    'lastEditedByName', (select profile.display_name from public.profiles profile where profile.id = p_brief.last_edited_by),
    'lastEditReason', p_brief.last_edit_reason, 'createdAt', p_brief.created_at, 'updatedAt', p_brief.updated_at
  );
$$;

create or replace function public.rpc_aoi_save_daily_eod_brief(
  p_payload jsonb, p_expected_updated_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid; v_role text; v_timezone text; v_brief_date date; v_workflow text;
  v_manager_id uuid; v_pic_id uuid; v_before public.daily_eod_briefs%rowtype; v_saved public.daily_eod_briefs%rowtype;
begin
  select project.organization_id, organization.timezone into v_org_id, v_timezone
  from public.projects project join public.organizations organization on organization.id=project.organization_id
  where project.id=v_project_id;
  select membership.role into v_role from public.organization_memberships membership join public.profiles caller on caller.id=membership.user_id
  where membership.organization_id=v_org_id and membership.user_id=v_actor_id and membership.status='active' and caller.status='active';
  if v_role is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  v_brief_date := timezone(v_timezone, clock_timestamp())::date;
  if not (p_payload ? 'scopeDate') or not (p_payload ? 'scopeProjectId')
    or nullif(p_payload->>'scopeDate','')::date is distinct from v_brief_date
    or nullif(p_payload->>'scopeProjectId','')::uuid is distinct from v_project_id then raise exception 'EOD_SCOPE_CHANGED'; end if;
  if not (extract(isodow from v_brief_date) between 1 and 5) then raise exception 'EOD_NOT_REQUIRED_TODAY'; end if;
  v_workflow := coalesce(nullif(p_payload->>'workflowStatus',''),'draft');
  if v_workflow not in ('draft','submitted') then raise exception 'EOD_WORKFLOW_INVALID'; end if;
  if v_workflow='submitted' then perform public.assert_daily_eod_payload(p_payload); end if;
  v_manager_id := nullif(p_payload->>'engagementManagerId','')::uuid; v_pic_id := nullif(p_payload->>'personInChargeId','')::uuid;
  if (v_manager_id is not null and not exists(select 1 from public.organization_memberships m join public.profiles p on p.id=m.user_id where m.organization_id=v_org_id and m.user_id=v_manager_id and m.status='active' and p.status='active'))
    or (v_pic_id is not null and not exists(select 1 from public.organization_memberships m join public.profiles p on p.id=m.user_id where m.organization_id=v_org_id and m.user_id=v_pic_id and m.status='active' and p.status='active')) then raise exception 'EOD_MEMBER_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_actor_id::text || ':' || v_project_id::text || ':' || v_brief_date::text,0));
  select brief.* into v_before from public.daily_eod_briefs brief where brief.project_id=v_project_id and brief.author_id=v_actor_id and brief.brief_date=v_brief_date for update;
  if v_before.workflow_status='completed' then raise exception 'EOD_ALREADY_COMPLETED'; end if;
  if v_before.id is not null and (p_expected_updated_at is null or v_before.updated_at<>p_expected_updated_at) then raise exception 'EOD_STALE_WRITE'; end if;
  if v_before.workflow_status='submitted' and v_workflow='draft' then raise exception 'EOD_WORKFLOW_INVALID'; end if;
  if v_before.id is null then
    insert into public.daily_eod_briefs(organization_id,project_id,author_id,author_role,brief_date,engagement_manager_id,person_in_charge_id,moved_outcome,evidence_gathered,deliverables_completed,key_insight,current_blocker,blocker_impact,proposed_solution,executive_owners,executive_request,tomorrow_priorities,project_status,evidence_links,workflow_status,submitted_at,last_edited_by)
    values(v_org_id,v_project_id,v_actor_id,v_role,v_brief_date,v_manager_id,v_pic_id,nullif(trim(p_payload->>'movedOutcome'),''),nullif(trim(p_payload->>'evidenceGathered'),''),nullif(trim(p_payload->>'deliverablesCompleted'),''),nullif(trim(p_payload->>'keyInsight'),''),nullif(trim(p_payload->>'currentBlocker'),''),nullif(trim(p_payload->>'blockerImpact'),''),nullif(trim(p_payload->>'proposedSolution'),''),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners','[]'::jsonb))),'{}'::text[]),nullif(trim(p_payload->>'executiveRequest'),''),array[coalesce(p_payload#>>'{tomorrowPriorities,0}',''),coalesce(p_payload#>>'{tomorrowPriorities,1}',''),coalesce(p_payload#>>'{tomorrowPriorities,2}','')],nullif(p_payload->>'projectStatus',''),case when jsonb_typeof(p_payload->'evidenceLinks')='array' then p_payload->'evidenceLinks' else '[]'::jsonb end,v_workflow,case when v_workflow='submitted' then clock_timestamp() end,v_actor_id) returning * into v_saved;
  else
    update public.daily_eod_briefs brief set engagement_manager_id=v_manager_id,person_in_charge_id=v_pic_id,moved_outcome=nullif(trim(p_payload->>'movedOutcome'),''),evidence_gathered=nullif(trim(p_payload->>'evidenceGathered'),''),deliverables_completed=nullif(trim(p_payload->>'deliverablesCompleted'),''),key_insight=nullif(trim(p_payload->>'keyInsight'),''),current_blocker=nullif(trim(p_payload->>'currentBlocker'),''),blocker_impact=nullif(trim(p_payload->>'blockerImpact'),''),proposed_solution=nullif(trim(p_payload->>'proposedSolution'),''),executive_owners=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners','[]'::jsonb))),'{}'::text[]),executive_request=nullif(trim(p_payload->>'executiveRequest'),''),tomorrow_priorities=array[coalesce(p_payload#>>'{tomorrowPriorities,0}',''),coalesce(p_payload#>>'{tomorrowPriorities,1}',''),coalesce(p_payload#>>'{tomorrowPriorities,2}','')],project_status=nullif(p_payload->>'projectStatus',''),evidence_links=case when jsonb_typeof(p_payload->'evidenceLinks')='array' then p_payload->'evidenceLinks' else '[]'::jsonb end,legacy_evidence_missing=false,workflow_status=v_workflow,submitted_at=case when v_workflow='submitted' then coalesce(brief.submitted_at,clock_timestamp()) else brief.submitted_at end,last_edited_by=v_actor_id,last_edit_reason=null,updated_at=clock_timestamp() where brief.id=v_before.id returning brief.* into v_saved;
  end if;
  return public.daily_eod_brief_json(v_saved);
end;
$$;

create or replace function public.rpc_aoi_daily_eod_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid := private.aoi_resolve_project(v_actor_id, null);
  v_org_id uuid; v_role text; v_timezone text; v_local_now timestamp; v_brief_date date;
  v_is_workday boolean; v_brief public.daily_eod_briefs%rowtype; v_due_state text;
begin
  select project.organization_id, organization.timezone into v_org_id, v_timezone
  from public.projects project join public.organizations organization on organization.id = project.organization_id
  where project.id = v_project_id;
  select membership.role into v_role from public.organization_memberships membership
  where membership.organization_id = v_org_id and membership.user_id = v_actor_id and membership.status = 'active';
  if v_role is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  v_local_now := timezone(v_timezone, clock_timestamp());
  v_brief_date := v_local_now::date;
  v_is_workday := extract(isodow from v_brief_date) between 1 and 5;
  select brief.* into v_brief from public.daily_eod_briefs brief
  where brief.project_id = v_project_id and brief.author_id = v_actor_id and brief.brief_date = v_brief_date;
  v_due_state := case when v_brief.workflow_status = 'completed' then 'completed'
    when v_brief.workflow_status = 'submitted' then 'submitted' when not v_is_workday then 'not_required'
    when v_local_now >= v_brief_date + time '17:00' then 'overdue' else 'due' end;
  return jsonb_build_object('dailyEod', jsonb_build_object(
    'projectId', v_project_id, 'serverDate', v_brief_date, 'serverNow', clock_timestamp(),
    'timezone', v_timezone, 'isWorkday', v_is_workday,
    'dueAt', (v_brief_date + time '17:00') at time zone v_timezone, 'dueState', v_due_state,
    'myBrief', case when v_brief.id is null then null else public.daily_eod_brief_json(v_brief) end,
    'members', coalesce((select jsonb_agg(jsonb_build_object('userId', membership.user_id,
      'displayName', profile.display_name, 'role', membership.role)
      order by case membership.role when 'admin' then 1 else 2 end, profile.display_name)
      from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'
        and (v_role = 'admin' or private.aoi_actor_can_access_project(membership.user_id, v_org_id, v_project_id))), '[]'::jsonb),
    'teamToday', case when v_role <> 'admin' then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
      'userId', membership.user_id, 'displayName', profile.display_name, 'role', membership.role,
      'briefId', brief.id, 'workflowStatus', coalesce(brief.workflow_status, case when v_is_workday then 'missing' else 'not_required' end),
      'brief', case when brief.id is null then null else public.daily_eod_brief_json(brief) end,
      'submittedAt', brief.submitted_at, 'isLate', coalesce(brief.is_late, false),
      'projectStatus', brief.project_status, 'updatedAt', brief.updated_at) order by profile.display_name)
      from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
      left join public.daily_eod_briefs brief on brief.project_id = v_project_id and brief.author_id = membership.user_id and brief.brief_date = v_brief_date
      where membership.organization_id = v_org_id and membership.status = 'active' and profile.status = 'active'), '[]'::jsonb) end));
end;
$$;

create or replace function public.rpc_aoi_daily_eod_reports(
  p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 25
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid; v_role text; v_page integer := greatest(coalesce(p_page, 1), 1);
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 25), 100)); v_result jsonb;
begin
  select project.organization_id, membership.role into v_org_id, v_role
  from public.project_preferences preference join public.projects project on project.id=preference.selected_project_id and project.organization_id=preference.selected_organization_id
  join public.organization_memberships membership on membership.organization_id=project.organization_id and membership.user_id=preference.user_id
  join public.profiles caller on caller.id = membership.user_id
  join public.organizations organization on organization.id = membership.organization_id
  where preference.user_id=auth.uid() and membership.status = 'active' and caller.status = 'active'
    and not caller.must_change_password and organization.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  with filtered as (
    select brief.* from public.daily_eod_briefs brief
    join public.projects project on project.id = brief.project_id and project.organization_id = brief.organization_id
    join public.profiles author on author.id = brief.author_id
    left join public.profiles manager on manager.id = brief.engagement_manager_id
    left join public.profiles person on person.id = brief.person_in_charge_id
    where brief.organization_id = v_org_id and (v_role = 'admin' or brief.author_id = auth.uid())
      and (nullif(p_filters->>'search', '') is null or concat_ws(' ', author.display_name, manager.display_name, person.display_name, project.code, project.name) ilike '%' || trim(p_filters->>'search') || '%')
      and (nullif(p_filters->>'authorId', '') is null or brief.author_id = (p_filters->>'authorId')::uuid)
      and (nullif(p_filters->>'engagementManagerId', '') is null or brief.engagement_manager_id = (p_filters->>'engagementManagerId')::uuid)
      and (nullif(p_filters->>'personInChargeId', '') is null or brief.person_in_charge_id = (p_filters->>'personInChargeId')::uuid)
      and (nullif(p_filters->>'projectId', '') is null or brief.project_id = (p_filters->>'projectId')::uuid)
      and (nullif(p_filters->>'projectLifecycle', '') is null or project.lifecycle_status = p_filters->>'projectLifecycle')
      and (nullif(p_filters->>'fromDate', '') is null or brief.brief_date >= (p_filters->>'fromDate')::date)
      and (nullif(p_filters->>'toDate', '') is null or brief.brief_date <= (p_filters->>'toDate')::date)
      and (nullif(p_filters->>'authorRole', '') is null or brief.author_role = p_filters->>'authorRole')
      and (nullif(p_filters->>'projectStatus', '') is null or brief.project_status = p_filters->>'projectStatus')
      and (nullif(p_filters->>'workflowStatus', '') is null or brief.workflow_status = p_filters->>'workflowStatus')
  ), paged as (select brief.* from filtered brief order by brief.brief_date desc, brief.updated_at desc
    limit v_page_size offset (v_page - 1) * v_page_size)
  select jsonb_build_object('total', (select count(*) from filtered), 'page', v_page, 'pageSize', v_page_size,
    'items', coalesce((select jsonb_agg(public.daily_eod_brief_json(brief) || jsonb_build_object(
      'auditHistory', coalesce((select jsonb_agg(jsonb_build_object('id', audit.id, 'action', audit.action,
        'actorName', coalesce(actor.display_name, 'AOI'), 'reason', audit.metadata->>'reason', 'createdAt', audit.created_at)
        order by audit.created_at desc) from public.daily_eod_audit_events audit
        left join public.profiles actor on actor.id = audit.actor_id
        where audit.organization_id = brief.organization_id and audit.brief_id = brief.id), '[]'::jsonb))
      order by brief.brief_date desc, brief.updated_at desc) from paged brief), '[]'::jsonb)) into v_result;
  return v_result;
end;
$$;

create or replace function public.rpc_aoi_admin_update_daily_eod_brief(
  p_brief_id uuid, p_payload jsonb, p_edit_reason text, p_expected_updated_at timestamptz, p_action text default 'save'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid; v_manager_id uuid; v_pic_id uuid; v_before public.daily_eod_briefs%rowtype;
  v_saved public.daily_eod_briefs%rowtype; v_legacy_exception boolean := false;
begin
  select brief.organization_id into v_org_id from public.daily_eod_briefs brief
  join public.organization_memberships membership on membership.organization_id=brief.organization_id
  join public.profiles caller on caller.id = membership.user_id
  where brief.id=p_brief_id and membership.user_id = auth.uid() and membership.role = 'admin' and membership.status = 'active' and caller.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_action not in ('save', 'complete') then raise exception 'EOD_ADMIN_ACTION_INVALID'; end if;
  if length(trim(coalesce(p_edit_reason, ''))) < 3 then raise exception 'EOD_ADMIN_EDIT_REASON_REQUIRED'; end if;
  select brief.* into v_before from public.daily_eod_briefs brief
  where brief.id = p_brief_id and brief.organization_id = v_org_id for update;
  if v_before.id is null then raise exception 'EOD_BRIEF_NOT_FOUND'; end if;
  if p_expected_updated_at is null or v_before.updated_at <> p_expected_updated_at then raise exception 'EOD_STALE_WRITE'; end if;
  if p_action = 'complete' and v_before.workflow_status <> 'submitted' then raise exception 'EOD_MUST_BE_SUBMITTED'; end if;
  v_legacy_exception := p_action = 'complete' and v_before.legacy_evidence_missing and v_before.evidence_links = '[]'::jsonb
    and coalesce(p_payload->'evidenceLinks', '[]'::jsonb) = '[]'::jsonb;
  if p_action = 'complete' or v_before.workflow_status in ('submitted', 'completed') then
    if v_legacy_exception then
      perform public.assert_daily_eod_payload(p_payload || jsonb_build_object('evidenceLinks', jsonb_build_array(jsonb_build_object('sourceType','other','label','legacy validation marker','url','https://invalid.local'))));
    else perform public.assert_daily_eod_payload(p_payload); end if;
  end if;
  v_manager_id := nullif(p_payload->>'engagementManagerId', '')::uuid;
  v_pic_id := nullif(p_payload->>'personInChargeId', '')::uuid;
  if (v_manager_id is not null and not exists (select 1 from public.organization_memberships m join public.profiles p on p.id=m.user_id where m.organization_id=v_org_id and m.user_id=v_manager_id and m.status='active' and p.status='active'))
    or (v_pic_id is not null and not exists (select 1 from public.organization_memberships m join public.profiles p on p.id=m.user_id where m.organization_id=v_org_id and m.user_id=v_pic_id and m.status='active' and p.status='active')) then raise exception 'EOD_MEMBER_INVALID'; end if;
  update public.daily_eod_briefs brief set engagement_manager_id=v_manager_id, person_in_charge_id=v_pic_id,
    moved_outcome=nullif(trim(p_payload->>'movedOutcome'),''), evidence_gathered=nullif(trim(p_payload->>'evidenceGathered'),''),
    deliverables_completed=nullif(trim(p_payload->>'deliverablesCompleted'),''), key_insight=nullif(trim(p_payload->>'keyInsight'),''),
    current_blocker=nullif(trim(p_payload->>'currentBlocker'),''), blocker_impact=nullif(trim(p_payload->>'blockerImpact'),''),
    proposed_solution=nullif(trim(p_payload->>'proposedSolution'),''),
    executive_owners=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'executiveOwners','[]'::jsonb))),'{}'::text[]),
    executive_request=nullif(trim(p_payload->>'executiveRequest'),''),
    tomorrow_priorities=array[coalesce(p_payload#>>'{tomorrowPriorities,0}',''),coalesce(p_payload#>>'{tomorrowPriorities,1}',''),coalesce(p_payload#>>'{tomorrowPriorities,2}','')],
    project_status=nullif(p_payload->>'projectStatus',''),
    evidence_links=case when v_legacy_exception then brief.evidence_links when jsonb_typeof(p_payload->'evidenceLinks')='array' then p_payload->'evidenceLinks' else '[]'::jsonb end,
    legacy_evidence_missing=case when v_legacy_exception then true else false end,
    workflow_status=case when p_action='complete' then 'completed' else brief.workflow_status end,
    completed_by=case when p_action='complete' then auth.uid() else brief.completed_by end,
    completed_at=case when p_action='complete' then clock_timestamp() else brief.completed_at end,
    last_edited_by=auth.uid(), last_edit_reason=trim(p_edit_reason), updated_at=clock_timestamp()
  where brief.id=v_before.id returning brief.* into v_saved;
  if v_legacy_exception then
    update public.daily_eod_audit_events audit set metadata = audit.metadata || jsonb_build_object('legacyEvidenceException', true)
    where audit.id = (select latest.id from public.daily_eod_audit_events latest where latest.brief_id=v_saved.id order by latest.created_at desc limit 1);
  end if;
  return public.daily_eod_brief_json(v_saved);
end;
$$;

revoke all on function public.rpc_aoi_daily_eod_snapshot() from public, anon;
revoke all on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) from public, anon;
revoke all on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) from public, anon;
revoke all on function public.rpc_aoi_admin_update_daily_eod_brief(uuid,jsonb,text,timestamptz,text) from public, anon;
grant execute on function public.rpc_aoi_daily_eod_snapshot() to authenticated, service_role;
grant execute on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) to authenticated, service_role;
grant execute on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) to authenticated, service_role;
grant execute on function public.rpc_aoi_admin_update_daily_eod_brief(uuid,jsonb,text,timestamptz,text) to authenticated, service_role;
