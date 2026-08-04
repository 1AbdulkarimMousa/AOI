-- Repair EOD scope consistency, audit provenance, submission timing, and first-save races.

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

revoke all on function public.rpc_current_user_context() from public, anon;
grant execute on function public.rpc_current_user_context() to authenticated;

create table public.daily_eod_audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  brief_id uuid not null references public.daily_eod_briefs(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (action in ('saved', 'submitted', 'admin_edited', 'completed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index daily_eod_audit_brief_created_idx
  on public.daily_eod_audit_events (organization_id, brief_id, created_at desc);
alter table public.daily_eod_audit_events enable row level security;
revoke all on public.daily_eod_audit_events from anon, authenticated;

insert into public.daily_eod_audit_events (id, organization_id, brief_id, actor_id, action, metadata, created_at)
select audit.id, brief.organization_id, brief.id, audit.actor_id,
  case audit.action
    when 'submitted' then 'submitted'
    when 'completed' then 'completed'
    when 'admin_edited' then 'admin_edited'
    else 'saved'
  end,
  audit.metadata || jsonb_build_object('legacyUnverified', true),
  audit.created_at
from public.audit_events audit
join public.daily_eod_briefs brief on brief.id = audit.entity_id
where audit.entity_type = 'daily_eod_brief'
on conflict (id) do nothing;

create or replace function private.preserve_daily_eod_lateness()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_timezone text;
begin
  if tg_op = 'UPDATE' and old.submitted_at is not null then
    new.is_late := old.is_late;
    return new;
  end if;
  if new.submitted_at is null then
    new.is_late := false;
    return new;
  end if;
  select organization.timezone into v_timezone
  from public.organizations organization where organization.id = new.organization_id;
  new.is_late := new.submitted_at >= ((new.brief_date + time '17:00') at time zone v_timezone);
  return new;
end;
$$;
revoke all on function private.preserve_daily_eod_lateness() from public, anon, authenticated;
update public.daily_eod_briefs brief
set is_late = brief.submitted_at >= ((brief.brief_date + time '17:00') at time zone organization.timezone)
from public.organizations organization
where organization.id = brief.organization_id and brief.submitted_at is not null;
drop trigger if exists preserve_daily_eod_lateness on public.daily_eod_briefs;
create trigger preserve_daily_eod_lateness
before insert or update of workflow_status, submitted_at, is_late on public.daily_eod_briefs
for each row execute function private.preserve_daily_eod_lateness();

create or replace function private.capture_daily_eod_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_action text;
  v_metadata jsonb;
begin
  v_action := case
    when tg_op = 'INSERT' and new.workflow_status = 'submitted' then 'submitted'
    when tg_op = 'INSERT' then 'saved'
    when old.workflow_status is distinct from 'completed' and new.workflow_status = 'completed' then 'completed'
    when old.workflow_status is distinct from 'submitted' and new.workflow_status = 'submitted' then 'submitted'
    when new.last_edit_reason is not null then 'admin_edited'
    else 'saved'
  end;
  v_metadata := jsonb_build_object(
    'reason', new.last_edit_reason,
    'before', case when tg_op = 'INSERT' then null else public.daily_eod_brief_json(old) end,
    'after', public.daily_eod_brief_json(new)
  );
  insert into public.daily_eod_audit_events (organization_id, brief_id, actor_id, action, metadata)
  values (new.organization_id, new.id, auth.uid(), v_action, v_metadata);
  return new;
end;
$$;
revoke all on function private.capture_daily_eod_audit() from public, anon, authenticated;
drop trigger if exists capture_daily_eod_audit on public.daily_eod_briefs;
create trigger capture_daily_eod_audit
after insert or update on public.daily_eod_briefs
for each row execute function private.capture_daily_eod_audit();

alter function public.rpc_aoi_daily_eod_snapshot()
  rename to rpc_aoi_daily_eod_snapshot_unscoped;
revoke all on function public.rpc_aoi_daily_eod_snapshot_unscoped()
  from public, anon, authenticated;

create function public.rpc_aoi_daily_eod_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_snapshot jsonb;
  v_org_id uuid;
  v_project_id uuid;
begin
  v_snapshot := public.rpc_aoi_daily_eod_snapshot_unscoped();
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  return jsonb_set(v_snapshot, '{dailyEod,projectId}', to_jsonb(v_project_id), true);
end;
$$;

revoke all on function public.rpc_aoi_daily_eod_snapshot() from public, anon;
grant execute on function public.rpc_aoi_daily_eod_snapshot() to authenticated;

alter function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz)
  rename to rpc_aoi_save_daily_eod_brief_unlocked;
revoke all on function public.rpc_aoi_save_daily_eod_brief_unlocked(jsonb,timestamptz)
  from public, anon, authenticated;

create function public.rpc_aoi_save_daily_eod_brief(
  p_payload jsonb,
  p_expected_updated_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_timezone text;
  v_brief_date date;
begin
  if auth.uid() is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  select membership.organization_id, organization.timezone into v_org_id, v_timezone
  from public.organization_memberships membership
  join public.organizations organization on organization.id = membership.organization_id
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  v_brief_date := timezone(v_timezone, clock_timestamp())::date;
  if not (p_payload ? 'scopeDate') or not (p_payload ? 'scopeProjectId')
    or nullif(p_payload->>'scopeDate', '')::date is distinct from v_brief_date
    or nullif(p_payload->>'scopeProjectId', '')::uuid is distinct from v_project_id then
    raise exception 'EOD_SCOPE_CHANGED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  return public.rpc_aoi_save_daily_eod_brief_unlocked(p_payload, p_expected_updated_at);
end;
$$;

revoke all on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) from public, anon;
grant execute on function public.rpc_aoi_save_daily_eod_brief(jsonb,timestamptz) to authenticated;

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
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
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
        from public.daily_eod_audit_events audit
        left join public.profiles actor on actor.id = audit.actor_id
        where audit.organization_id = brief.organization_id and audit.brief_id = brief.id
      ), '[]'::jsonb))
      order by brief.brief_date desc, brief.updated_at desc
    ) from paged brief), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) from public, anon;
grant execute on function public.rpc_aoi_daily_eod_reports(jsonb,integer,integer) to authenticated;
