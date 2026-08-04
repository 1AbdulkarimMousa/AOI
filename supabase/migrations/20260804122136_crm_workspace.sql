-- Connected CRM layer for shared contact ownership, enrichment, activity, and personal progress.

create table if not exists public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  contact_type text not null default 'KOL',
  name text not null,
  organization_name text,
  email text,
  phone text,
  primary_channel text not null default 'Email',
  source_url text,
  tags text,
  owner_id uuid references public.profiles(id) on delete set null,
  lifecycle text not null default 'new' check (lifecycle in ('new','researching','ready','contacted','engaged','qualified','paused')),
  next_action text,
  next_action_due date,
  priority_score integer not null default 50 check (priority_score between 0 and 100),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists crm_contacts_queue_idx on public.crm_contacts (organization_id, project_id, owner_id, lifecycle, next_action_due);
create index if not exists crm_contacts_search_idx on public.crm_contacts (project_id, lower(name), lower(organization_name));

alter table public.candidates add column if not exists crm_contact_id uuid references public.crm_contacts(id) on delete set null;
create unique index if not exists candidates_crm_contact_idx on public.candidates (crm_contact_id) where crm_contact_id is not null;

create table if not exists public.crm_activity (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  contact_id uuid not null references public.crm_contacts(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  activity_type text not null check (activity_type in ('enrich','outreach','follow_up','qualify','note','status_change','import')),
  summary text not null,
  created_at timestamptz not null default now()
);
create index if not exists crm_activity_contact_idx on public.crm_activity (organization_id, contact_id, created_at desc);

create table if not exists public.crm_reward_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  points integer not null check (points > 0),
  created_at timestamptz not null default now()
);
create index if not exists crm_reward_events_actor_idx on public.crm_reward_events (organization_id, actor_id, created_at desc);

alter table public.crm_contacts enable row level security;
alter table public.crm_activity enable row level security;
alter table public.crm_reward_events enable row level security;

drop policy if exists crm_contacts_member_read on public.crm_contacts;
create policy crm_contacts_member_read on public.crm_contacts for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists crm_contacts_member_write on public.crm_contacts;
create policy crm_contacts_member_write on public.crm_contacts for insert to authenticated with check (public.is_org_member(organization_id));
drop policy if exists crm_contacts_member_update on public.crm_contacts;
create policy crm_contacts_member_update on public.crm_contacts for update to authenticated using (public.is_org_member(organization_id)) with check (public.is_org_member(organization_id));
drop policy if exists crm_activity_member_read on public.crm_activity;
create policy crm_activity_member_read on public.crm_activity for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists crm_activity_member_write on public.crm_activity;
create policy crm_activity_member_write on public.crm_activity for insert to authenticated with check (public.is_org_member(organization_id));
drop policy if exists crm_reward_member_read on public.crm_reward_events;
create policy crm_reward_member_read on public.crm_reward_events for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists crm_reward_member_write on public.crm_reward_events;
create policy crm_reward_member_write on public.crm_reward_events for insert to authenticated with check (actor_id = auth.uid() and public.is_org_member(organization_id));

do $$
declare
  candidate_row record;
  contact_id uuid;
begin
  for candidate_row in select * from public.candidates where crm_contact_id is null loop
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, primary_channel, source_url,
      owner_id, lifecycle, next_action, next_action_due, priority_score, notes, created_by
    ) values (
      candidate_row.organization_id,
      candidate_row.project_id,
      coalesce(nullif(candidate_row.category, ''), 'KOL'),
      candidate_row.name,
      coalesce(nullif(candidate_row.contact_channel, ''), 'Email'),
      candidate_row.source_url,
      candidate_row.owner_id,
      case
        when candidate_row.outreach_status = 'Confirmed' then 'qualified'
        when candidate_row.outreach_status in ('Interested', 'Replied') then 'engaged'
        when candidate_row.outreach_status in ('Sent', 'Drafted') then 'contacted'
        when candidate_row.contact_readiness in ('Email ready', 'Form ready', 'Social DM ready') then 'ready'
        else 'researching'
      end,
      candidate_row.next_step,
      candidate_row.next_step_due,
      candidate_row.priority_score,
      candidate_row.notes,
      candidate_row.created_by
    ) returning id into contact_id;
    update public.candidates set crm_contact_id = contact_id where id = candidate_row.id;
  end loop;
end $$;

create or replace function public.rpc_aoi_crm_snapshot()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  org_id uuid;
  active_project_id uuid;
  current_role text;
begin
  select membership.organization_id, membership.role into org_id, current_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end limit 1;
  if org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  select project.id into active_project_id from public.projects project
  where project.organization_id = org_id and project.status = 'active'
  order by project.created_at limit 1;

  return jsonb_build_object(
    'crmContacts', coalesce((select jsonb_agg(jsonb_build_object(
      'id', contact.id,
      'candidateId', candidate.id,
      'contactType', contact.contact_type,
      'name', contact.name,
      'organization', contact.organization_name,
      'email', contact.email,
      'phone', contact.phone,
      'primaryChannel', contact.primary_channel,
      'sourceUrl', contact.source_url,
      'tags', contact.tags,
      'ownerName', owner.display_name,
      'lifecycle', contact.lifecycle,
      'nextAction', contact.next_action,
      'nextActionDue', contact.next_action_due,
      'priorityScore', contact.priority_score,
      'notes', contact.notes,
      'outreachStatus', candidate.outreach_status,
      'category', candidate.category,
      'pmfCandidate', candidate.pmf_candidate,
      'activityCount', (select count(*) from public.crm_activity activity where activity.contact_id = contact.id)
    ) order by contact.next_action_due nulls last, contact.priority_score desc)
      from public.crm_contacts contact
      left join public.candidates candidate on candidate.crm_contact_id = contact.id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.project_id = active_project_id and (current_role = 'admin' or contact.owner_id = auth.uid())), '[]'::jsonb),
    'crmActivity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', activity.id, 'contactId', activity.contact_id, 'activityType', activity.activity_type,
      'summary', activity.summary, 'actorName', coalesce(actor.display_name, 'AOI'), 'createdAt', activity.created_at
    ) order by activity.created_at desc)
      from public.crm_activity activity left join public.profiles actor on actor.id = activity.actor_id
      where activity.project_id = active_project_id and (current_role = 'admin' or activity.actor_id = auth.uid())), '[]'::jsonb),
    'crmProgress', jsonb_build_object(
      'xp', coalesce((select sum(points) from public.crm_reward_events reward where reward.project_id = active_project_id and reward.actor_id = auth.uid()), 0),
      'completedToday', coalesce((select count(*) from public.crm_reward_events reward where reward.project_id = active_project_id and reward.actor_id = auth.uid() and reward.created_at::date = current_date), 0),
      'streakDays', coalesce((select count(distinct reward.created_at::date) from public.crm_reward_events reward where reward.project_id = active_project_id and reward.actor_id = auth.uid() and reward.created_at >= current_date - interval '7 days'), 0)
    )
  );
end $$;

create or replace function public.rpc_aoi_upsert_crm_contact(contact jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  org_id uuid;
  active_project_id uuid;
  contact_id uuid;
  owner_id uuid;
  saved public.crm_contacts%rowtype;
  candidate_id uuid;
begin
  select membership.organization_id into org_id from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active' limit 1;
  select project.id into active_project_id from public.projects project
  where project.organization_id = org_id and project.status = 'active' order by project.created_at limit 1;
  if org_id is null or active_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(contact->>'name', ''))) < 2 then raise exception 'CRM_CONTACT_NAME_REQUIRED'; end if;

  contact_id := nullif(contact->>'id', '')::uuid;
  candidate_id := nullif(contact->>'candidateId', '')::uuid;
  select profile.id into owner_id from public.profiles profile where lower(profile.display_name) = lower(coalesce(contact->>'ownerName', '')) limit 1;
  owner_id := coalesce(owner_id, auth.uid());

  if contact_id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, organization_name, email, phone,
      primary_channel, source_url, tags, owner_id, lifecycle, next_action, next_action_due,
      priority_score, notes, created_by
    ) values (
      org_id, active_project_id, coalesce(nullif(contact->>'contactType', ''), 'KOL'), trim(contact->>'name'),
      nullif(contact->>'organization', ''), nullif(contact->>'email', ''), nullif(contact->>'phone', ''),
      coalesce(nullif(contact->>'primaryChannel', ''), 'Email'), nullif(contact->>'sourceUrl', ''),
      nullif(contact->>'tags', ''), owner_id, coalesce(nullif(contact->>'lifecycle', ''), 'new'),
      nullif(contact->>'nextAction', ''), nullif(contact->>'nextActionDue', '')::date,
      greatest(0, least(100, coalesce((contact->>'priorityScore')::integer, 50))), nullif(contact->>'notes', ''), auth.uid()
    ) returning * into saved;
  else
    update public.crm_contacts set
      contact_type = coalesce(nullif(contact->>'contactType', ''), contact_type),
      name = trim(contact->>'name'), organization_name = nullif(contact->>'organization', ''),
      email = nullif(contact->>'email', ''), phone = nullif(contact->>'phone', ''),
      primary_channel = coalesce(nullif(contact->>'primaryChannel', ''), primary_channel),
      source_url = nullif(contact->>'sourceUrl', ''), tags = nullif(contact->>'tags', ''),
      owner_id = owner_id, lifecycle = coalesce(nullif(contact->>'lifecycle', ''), lifecycle),
      next_action = nullif(contact->>'nextAction', ''), next_action_due = nullif(contact->>'nextActionDue', '')::date,
      priority_score = greatest(0, least(100, coalesce((contact->>'priorityScore')::integer, priority_score))),
      notes = nullif(contact->>'notes', ''), updated_at = now()
    where id = contact_id and organization_id = org_id and project_id = active_project_id
    returning * into saved;
    if saved.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  end if;

  if candidate_id is not null then
    update public.candidates set crm_contact_id = saved.id, name = saved.name, category = saved.contact_type,
      contact_channel = saved.primary_channel, source_url = saved.source_url, owner_id = saved.owner_id,
      next_step = saved.next_action, next_step_due = saved.next_action_due, notes = saved.notes, updated_at = now()
    where id = candidate_id and organization_id = org_id and project_id = active_project_id;
  elsif coalesce((contact->>'createOutreach')::boolean, true) then
    insert into public.candidates (organization_id, project_id, crm_contact_id, name, category, contact_channel, source_url, owner_id, outreach_status, next_step, next_step_due, notes, created_by)
    values (org_id, active_project_id, saved.id, saved.name, saved.contact_type, saved.primary_channel, saved.source_url, saved.owner_id, 'Not Contacted', saved.next_action, saved.next_action_due, saved.notes, auth.uid())
    on conflict (crm_contact_id) where crm_contact_id is not null do nothing;
  end if;

  insert into public.crm_activity (organization_id, project_id, contact_id, actor_id, activity_type, summary)
  values (org_id, active_project_id, saved.id, auth.uid(), 'enrich', 'Contact record saved');
  return jsonb_build_object('id', saved.id, 'candidateId', coalesce(candidate_id, (select id from public.candidates where crm_contact_id = saved.id limit 1)), 'name', saved.name);
end $$;

create or replace function public.rpc_aoi_log_crm_activity(
  contact_id uuid,
  activity_type text,
  activity_summary text,
  next_action text default null,
  next_action_due date default null,
  lifecycle text default null,
  reward_points integer default 0
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  org_id uuid;
  active_project_id uuid;
  saved public.crm_activity%rowtype;
begin
  select membership.organization_id into org_id from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active' limit 1;
  select project.id into active_project_id from public.projects project where project.organization_id = org_id and project.status = 'active' order by project.created_at limit 1;
  if org_id is null or active_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if activity_type not in ('enrich','outreach','follow_up','qualify','note','status_change','import') then raise exception 'CRM_ACTIVITY_INVALID'; end if;
  if length(trim(coalesce(activity_summary, ''))) < 3 then raise exception 'CRM_ACTIVITY_REQUIRED'; end if;
  insert into public.crm_activity (organization_id, project_id, contact_id, actor_id, activity_type, summary)
  select org_id, active_project_id, contact.id, auth.uid(), activity_type, trim(activity_summary)
  from public.crm_contacts contact where contact.id = rpc_aoi_log_crm_activity.contact_id and contact.organization_id = org_id and contact.project_id = active_project_id
  returning * into saved;
  if saved.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  update public.crm_contacts set next_action = coalesce(nullif(trim(rpc_aoi_log_crm_activity.next_action), ''), next_action), next_action_due = coalesce(rpc_aoi_log_crm_activity.next_action_due, next_action_due), lifecycle = coalesce(rpc_aoi_log_crm_activity.lifecycle, lifecycle), updated_at = now() where id = saved.contact_id;
  if reward_points > 0 then
    insert into public.crm_reward_events (organization_id, project_id, contact_id, actor_id, action, points) values (org_id, active_project_id, saved.contact_id, auth.uid(), activity_type, least(reward_points, 100));
  end if;
  return jsonb_build_object('id', saved.id, 'contactId', saved.contact_id);
end $$;

revoke all on function public.rpc_aoi_crm_snapshot() from public;
revoke all on function public.rpc_aoi_upsert_crm_contact(jsonb) from public;
revoke all on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) from public;
grant execute on function public.rpc_aoi_crm_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_crm_contact(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) to authenticated;
