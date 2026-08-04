-- Scope CRM records, restrict sensitive contacts, and derive bounded rewards server-side.
create unique index if not exists crm_contacts_scope_id_unique
  on public.crm_contacts (organization_id, project_id, id);

update public.crm_contacts set owner_id = created_by where owner_id is null and created_by is not null;
alter table public.crm_contacts alter column owner_id set not null;
alter table public.crm_contacts drop constraint if exists crm_contacts_owner_id_fkey;
alter table public.crm_contacts add constraint crm_contacts_owner_id_fkey
  foreign key (owner_id) references public.profiles(id) on delete restrict;
alter table public.crm_contacts add constraint crm_contacts_project_scope_fk
  foreign key (organization_id, project_id)
  references public.projects (organization_id, id) on delete cascade not valid;
alter table public.crm_contacts validate constraint crm_contacts_project_scope_fk;

alter table public.candidates add constraint candidates_crm_contact_scope_fk
  foreign key (organization_id, project_id, crm_contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete set null (crm_contact_id) not valid;
alter table public.candidates validate constraint candidates_crm_contact_scope_fk;
alter table public.crm_activity add constraint crm_activity_contact_scope_fk
  foreign key (organization_id, project_id, contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete cascade not valid;
alter table public.crm_activity validate constraint crm_activity_contact_scope_fk;
alter table public.crm_reward_events drop constraint if exists crm_reward_events_contact_id_fkey;
alter table public.crm_reward_events add constraint crm_reward_contact_scope_fk
  foreign key (organization_id, project_id, contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete set null (contact_id) not valid;
alter table public.crm_reward_events validate constraint crm_reward_contact_scope_fk;
alter table public.crm_reward_events add column if not exists reward_date date not null default current_date;
create unique index if not exists crm_reward_daily_unique
  on public.crm_reward_events (project_id, actor_id, contact_id, action, reward_date);

create or replace function public.validate_crm_candidate_link()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.crm_contact_id is null then return new; end if;
  if not exists (
    select 1 from public.crm_contacts contact
    where contact.id = new.crm_contact_id
      and contact.organization_id = new.organization_id
      and contact.project_id = new.project_id
      and contact.owner_id = new.assigned_to
  ) then
    raise exception 'CRM_CANDIDATE_OWNER_MISMATCH';
  end if;
  return new;
end; $$;
drop trigger if exists validate_crm_candidate_link on public.candidates;
create trigger validate_crm_candidate_link before insert or update of crm_contact_id, assigned_to on public.candidates
  for each row execute function public.validate_crm_candidate_link();
revoke all on function public.validate_crm_candidate_link() from public, anon, authenticated;

drop policy if exists crm_contacts_member_read on public.crm_contacts;
drop policy if exists crm_contacts_member_write on public.crm_contacts;
drop policy if exists crm_contacts_member_update on public.crm_contacts;
create policy crm_contacts_assigned_read on public.crm_contacts for select to authenticated using (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and owner_id = (select auth.uid()))
);
create policy crm_contacts_assigned_insert on public.crm_contacts for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = (select auth.uid())
  and (public.is_org_admin(organization_id) or owner_id = (select auth.uid()))
);
create policy crm_contacts_assigned_update on public.crm_contacts for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())));

drop policy if exists crm_activity_member_read on public.crm_activity;
drop policy if exists crm_activity_member_write on public.crm_activity;
create policy crm_activity_assigned_read on public.crm_activity for select to authenticated using (
  public.is_org_admin(organization_id) or (
    public.is_org_member(organization_id) and exists (
      select 1 from public.crm_contacts contact
      where contact.id = contact_id and contact.owner_id = (select auth.uid())
    )
  )
);
create policy crm_activity_assigned_insert on public.crm_activity for insert to authenticated with check (
  actor_id = (select auth.uid()) and public.is_org_member(organization_id) and (
    public.is_org_admin(organization_id) or exists (
      select 1 from public.crm_contacts contact
      where contact.id = contact_id and contact.owner_id = (select auth.uid())
    )
  )
);

drop policy if exists crm_reward_member_read on public.crm_reward_events;
drop policy if exists crm_reward_member_write on public.crm_reward_events;
create policy crm_reward_personal_read on public.crm_reward_events for select to authenticated using (
  public.is_org_admin(organization_id) or actor_id = (select auth.uid())
);

revoke all on public.crm_contacts, public.crm_activity, public.crm_reward_events from anon, authenticated;

create or replace function public.rpc_aoi_crm_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_role text;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'crmContacts', coalesce((select jsonb_agg(jsonb_build_object(
      'id', contact.id, 'candidateId', candidate.id, 'contactType', contact.contact_type,
      'name', contact.name, 'organization', contact.organization_name, 'email', contact.email,
      'phone', contact.phone, 'primaryChannel', contact.primary_channel, 'sourceUrl', contact.source_url,
      'tags', contact.tags, 'ownerId', contact.owner_id, 'ownerName', owner.display_name,
      'lifecycle', contact.lifecycle, 'nextAction', contact.next_action,
      'nextActionDue', contact.next_action_due, 'priorityScore', contact.priority_score,
      'notes', contact.notes, 'outreachStatus', candidate.outreach_status,
      'category', candidate.category, 'pmfCandidate', candidate.pmf_candidate,
      'activityCount', (select count(*) from public.crm_activity activity where activity.contact_id = contact.id)
    ) order by contact.next_action_due nulls last, contact.priority_score desc)
      from public.crm_contacts contact
      left join public.candidates candidate on candidate.crm_contact_id = contact.id
        and candidate.organization_id = contact.organization_id and candidate.project_id = contact.project_id
      left join public.profiles owner on owner.id = contact.owner_id
      where contact.project_id = v_project_id and (v_role = 'admin' or contact.owner_id = auth.uid())), '[]'::jsonb),
    'crmActivity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', activity.id, 'contactId', activity.contact_id, 'activityType', activity.activity_type,
      'summary', activity.summary, 'actorName', coalesce(actor.display_name, 'AOI'), 'createdAt', activity.created_at
    ) order by activity.created_at desc)
      from public.crm_activity activity
      join public.crm_contacts contact on contact.id = activity.contact_id
        and contact.organization_id = activity.organization_id and contact.project_id = activity.project_id
      left join public.profiles actor on actor.id = activity.actor_id
      where activity.project_id = v_project_id and (v_role = 'admin' or contact.owner_id = auth.uid())), '[]'::jsonb),
    'crmProgress', jsonb_build_object(
      'xp', coalesce((select sum(reward.points) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = auth.uid()), 0),
      'completedToday', coalesce((select count(*) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = auth.uid() and reward.reward_date = current_date), 0),
      'streakDays', coalesce((select count(distinct reward.reward_date) from public.crm_reward_events reward where reward.project_id = v_project_id and reward.actor_id = auth.uid() and reward.reward_date >= current_date - 6), 0)
    )
  );
end; $$;

create or replace function public.rpc_aoi_upsert_crm_contact(contact jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid; v_project_id uuid; v_role text; v_contact_id uuid; v_candidate_id uuid;
  v_owner_id uuid; v_points integer := 35; v_awarded integer := 0;
  v_saved public.crm_contacts%rowtype;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(contact->>'name', ''))) < 2 then raise exception 'CRM_CONTACT_NAME_REQUIRED'; end if;

  v_contact_id := nullif(contact->>'id', '')::uuid;
  v_candidate_id := nullif(contact->>'candidateId', '')::uuid;
  if v_contact_id is not null then
    select existing.* into v_saved from public.crm_contacts existing
    where existing.id = v_contact_id and existing.organization_id = v_org_id and existing.project_id = v_project_id
      and (v_role = 'admin' or existing.owner_id = auth.uid());
    if v_saved.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;
  end if;

  v_owner_id := coalesce(v_saved.owner_id, auth.uid());
  if v_role = 'admin' and nullif(contact->>'ownerId', '') is not null then
    select membership.user_id into v_owner_id from public.organization_memberships membership
    where membership.organization_id = v_org_id and membership.user_id = (contact->>'ownerId')::uuid and membership.status = 'active';
  elsif v_role = 'admin' and nullif(contact->>'ownerName', '') is not null then
    select membership.user_id into v_owner_id
    from public.organization_memberships membership join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_org_id and membership.status = 'active'
      and lower(profile.display_name) = lower(trim(contact->>'ownerName'))
    order by membership.joined_at limit 1;
  end if;
  if v_owner_id is null then raise exception 'CRM_OWNER_INVALID'; end if;

  if v_contact_id is null then
    insert into public.crm_contacts (
      organization_id, project_id, contact_type, name, organization_name, email, phone,
      primary_channel, source_url, tags, owner_id, lifecycle, next_action, next_action_due,
      priority_score, notes, created_by
    ) values (
      v_org_id, v_project_id, coalesce(nullif(contact->>'contactType', ''), 'KOL'), trim(contact->>'name'),
      nullif(contact->>'organization', ''), nullif(contact->>'email', ''), nullif(contact->>'phone', ''),
      coalesce(nullif(contact->>'primaryChannel', ''), 'Email'), nullif(contact->>'sourceUrl', ''),
      nullif(contact->>'tags', ''), v_owner_id, coalesce(nullif(contact->>'lifecycle', ''), 'new'),
      nullif(contact->>'nextAction', ''), nullif(contact->>'nextActionDue', '')::date,
      greatest(0, least(100, coalesce((contact->>'priorityScore')::integer, 50))),
      nullif(contact->>'notes', ''), auth.uid()
    ) returning * into v_saved;
  else
    update public.crm_contacts existing set
      contact_type = coalesce(nullif(contact->>'contactType', ''), existing.contact_type),
      name = trim(contact->>'name'), organization_name = nullif(contact->>'organization', ''),
      email = nullif(contact->>'email', ''), phone = nullif(contact->>'phone', ''),
      primary_channel = coalesce(nullif(contact->>'primaryChannel', ''), existing.primary_channel),
      source_url = nullif(contact->>'sourceUrl', ''), tags = nullif(contact->>'tags', ''),
      owner_id = v_owner_id, lifecycle = coalesce(nullif(contact->>'lifecycle', ''), existing.lifecycle),
      next_action = nullif(contact->>'nextAction', ''), next_action_due = nullif(contact->>'nextActionDue', '')::date,
      priority_score = greatest(0, least(100, coalesce((contact->>'priorityScore')::integer, existing.priority_score))),
      notes = nullif(contact->>'notes', ''), updated_at = now()
    where existing.id = v_contact_id returning existing.* into v_saved;
  end if;

  if v_candidate_id is not null then
    if not exists (select 1 from public.candidates candidate where candidate.id = v_candidate_id
      and candidate.organization_id = v_org_id and candidate.project_id = v_project_id
      and (v_role = 'admin' or candidate.assigned_to = auth.uid())) then
      raise exception 'CRM_CANDIDATE_NOT_ASSIGNED';
    end if;
    update public.candidates candidate set crm_contact_id = v_saved.id, name = v_saved.name,
      category = v_saved.contact_type, contact_channel = v_saved.primary_channel,
      source_url = v_saved.source_url, owner_id = v_saved.owner_id, assigned_to = v_saved.owner_id,
      next_step = v_saved.next_action, next_step_due = v_saved.next_action_due,
      notes = v_saved.notes, updated_at = now()
    where candidate.id = v_candidate_id;
  elsif coalesce((contact->>'createOutreach')::boolean, true) then
    insert into public.candidates (
      organization_id, project_id, crm_contact_id, name, category, contact_channel, source_url,
      owner_id, assigned_to, outreach_status, next_step, next_step_due, notes, created_by
    ) values (
      v_org_id, v_project_id, v_saved.id, v_saved.name, v_saved.contact_type, v_saved.primary_channel,
      v_saved.source_url, v_saved.owner_id, v_saved.owner_id, 'Not Contacted', v_saved.next_action,
      v_saved.next_action_due, v_saved.notes, auth.uid()
    ) on conflict (crm_contact_id) where crm_contact_id is not null do nothing;
  end if;

  insert into public.crm_activity (organization_id, project_id, contact_id, actor_id, activity_type, summary)
  values (v_org_id, v_project_id, v_saved.id, auth.uid(), 'enrich', 'Contact record saved');
  if v_saved.source_url is not null and v_saved.next_action is not null and v_saved.next_action_due is not null then v_points := v_points + 10; end if;
  insert into public.crm_reward_events (organization_id, project_id, contact_id, actor_id, action, points)
  values (v_org_id, v_project_id, v_saved.id, auth.uid(), 'enrich', v_points)
  on conflict do nothing returning points into v_awarded;

  return jsonb_build_object(
    'id', v_saved.id,
    'candidateId', coalesce(v_candidate_id, (select candidate.id from public.candidates candidate where candidate.crm_contact_id = v_saved.id limit 1)),
    'ownerId', v_saved.owner_id, 'name', v_saved.name, 'rewardPoints', coalesce(v_awarded, 0)
  );
end; $$;

create or replace function public.rpc_aoi_log_crm_activity(
  contact_id uuid, activity_type text, activity_summary text, next_action text default null,
  next_action_due date default null, lifecycle text default null, reward_points integer default 0
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid; v_project_id uuid; v_role text; v_points integer; v_awarded integer := 0;
  v_contact public.crm_contacts%rowtype; v_saved public.crm_activity%rowtype;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if activity_type not in ('enrich','outreach','follow_up','qualify','note','status_change','import') then raise exception 'CRM_ACTIVITY_INVALID'; end if;
  if length(trim(coalesce(activity_summary, ''))) < 3 then raise exception 'CRM_ACTIVITY_REQUIRED'; end if;
  if lifecycle is not null and lifecycle not in ('new','researching','ready','contacted','engaged','qualified','paused') then raise exception 'CRM_LIFECYCLE_INVALID'; end if;

  select contact.* into v_contact from public.crm_contacts contact
  where contact.id = rpc_aoi_log_crm_activity.contact_id
    and contact.organization_id = v_org_id and contact.project_id = v_project_id
    and (v_role = 'admin' or contact.owner_id = auth.uid());
  if v_contact.id is null then raise exception 'CRM_CONTACT_NOT_FOUND'; end if;

  insert into public.crm_activity (organization_id, project_id, contact_id, actor_id, activity_type, summary)
  values (v_org_id, v_project_id, v_contact.id, auth.uid(), activity_type, trim(activity_summary))
  returning * into v_saved;
  update public.crm_contacts existing set
    next_action = coalesce(nullif(trim(rpc_aoi_log_crm_activity.next_action), ''), existing.next_action),
    next_action_due = coalesce(rpc_aoi_log_crm_activity.next_action_due, existing.next_action_due),
    lifecycle = coalesce(rpc_aoi_log_crm_activity.lifecycle, existing.lifecycle), updated_at = now()
  where existing.id = v_contact.id returning existing.* into v_contact;

  v_points := case activity_type when 'enrich' then 35 when 'outreach' then 45 when 'follow_up' then 55 when 'qualify' then 70 else 20 end;
  if v_contact.source_url is not null and v_contact.next_action is not null and v_contact.next_action_due is not null then v_points := v_points + 10; end if;
  insert into public.crm_reward_events (organization_id, project_id, contact_id, actor_id, action, points)
  values (v_org_id, v_project_id, v_contact.id, auth.uid(), activity_type, v_points)
  on conflict do nothing returning points into v_awarded;

  return jsonb_build_object('id', v_saved.id, 'contactId', v_saved.contact_id, 'rewardPoints', coalesce(v_awarded, 0));
end; $$;

revoke all on function public.rpc_aoi_crm_snapshot() from public, anon;
revoke all on function public.rpc_aoi_upsert_crm_contact(jsonb) from public, anon;
revoke all on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) from public, anon;
grant execute on function public.rpc_aoi_crm_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_crm_contact(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_crm_activity(uuid,text,text,text,date,text,integer) to authenticated;
