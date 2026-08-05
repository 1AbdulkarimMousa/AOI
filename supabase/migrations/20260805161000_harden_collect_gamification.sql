-- Keep cooperative aggregates RLS-aware and cover the new foreign-key paths.

alter function public.rpc_aoi_gamification_summary() security invoker;

create index if not exists contact_external_identities_created_by_idx
  on public.contact_external_identities (created_by);
create index if not exists gamification_events_actor_id_idx
  on public.gamification_events (actor_id);
create index if not exists gamification_badges_scope_idx
  on public.gamification_badges (organization_id, project_id);
create index if not exists gamification_badge_awards_scope_idx
  on public.gamification_badge_awards (organization_id, project_id);
create index if not exists gamification_badge_awards_source_event_idx
  on public.gamification_badge_awards (source_event_id);
create index if not exists gamification_badge_awards_user_id_idx
  on public.gamification_badge_awards (user_id);
create index if not exists gamification_team_goals_scope_idx
  on public.gamification_team_goals (organization_id, project_id);

create or replace function public.rpc_aoi_gamification_summary()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_org_id uuid;
  v_project_id uuid;
  v_xp integer;
  v_streak integer;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = v_actor_id and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select coalesce(sum(event.points),0)::integer into v_xp
  from public.gamification_events event
  where event.organization_id = v_org_id and event.project_id = v_project_id and event.actor_id = v_actor_id;

  with recursive event_days as (
    select distinct event.occurred_on as day from public.gamification_events event
    where event.project_id = v_project_id and event.actor_id = v_actor_id
  ), anchor as (
    select max(day) as day from event_days where day >= current_date - 1
  ), streak(day, count) as (
    select anchor.day, case when anchor.day is null then 0 else 1 end from anchor
    union all
    select streak.day - 1, streak.count + 1 from streak
    where streak.day is not null and exists (select 1 from event_days where event_days.day = streak.day - 1)
  )
  select coalesce(max(count),0) into v_streak from streak;

  return jsonb_build_object(
    'xp', v_xp,
    'completedToday', (select count(*) from public.gamification_events event
      where event.project_id = v_project_id and event.actor_id = v_actor_id and event.occurred_on = current_date),
    'streakDays', v_streak,
    'badges', coalesce((select jsonb_agg(jsonb_build_object(
      'code', badge.code, 'name', badge.name, 'description', badge.description,
      'icon', badge.icon, 'awardedAt', award.awarded_at
    ) order by award.awarded_at desc) from public.gamification_badge_awards award
      join public.gamification_badges badge on badge.id = award.badge_id
      where award.project_id = v_project_id and award.user_id = v_actor_id), '[]'::jsonb),
    'recentEvents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', event.id, 'action', event.action, 'points', event.points,
      'sourceType', event.source_type, 'occurredOn', event.occurred_on, 'createdAt', event.created_at
    ) order by event.created_at desc) from (
      select * from public.gamification_events source
      where source.project_id = v_project_id and source.actor_id = v_actor_id
      order by source.created_at desc limit 12
    ) event), '[]'::jsonb),
    'teamGoals', coalesce((select jsonb_agg(jsonb_build_object(
      'code', goal.code, 'name', goal.name, 'description', goal.description,
      'target', goal.target,
      'progress', case goal.code
        when 'connected_research_chain' then (
          select count(*) from public.respondents respondent
          where respondent.project_id = v_project_id and respondent.crm_contact_id is not null
            and respondent.workflow_status = 'approved'
        )
        when 'weekly_evidence_loop' then (
          (select count(*) from public.evidence_records evidence where evidence.project_id = v_project_id and evidence.workflow_status = 'approved' and evidence.reviewed_at >= date_trunc('week', current_date))
          + (select count(*) from public.research_sessions session where session.project_id = v_project_id and session.workflow_status = 'approved' and session.reviewed_at >= date_trunc('week', current_date))
          + (select count(*) from public.product_events event where event.project_id = v_project_id and event.workflow_status = 'approved' and event.reviewed_at >= date_trunc('week', current_date))
          + (select count(*) from public.value_exchange_observations value where value.project_id = v_project_id and value.workflow_status = 'approved' and value.reviewed_at >= date_trunc('week', current_date))
          + (select count(*) from public.pmf_observations observation where observation.project_id = v_project_id and observation.workflow_status = 'approved' and observation.reviewed_at >= date_trunc('week', current_date))
        )
        else 0 end
    ) order by goal.created_at) from public.gamification_team_goals goal
      where goal.project_id = v_project_id and goal.active
        and goal.starts_on <= current_date and (goal.ends_on is null or goal.ends_on >= current_date)), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_gamification_summary() from public, anon;
grant execute on function public.rpc_aoi_gamification_summary() to authenticated;
