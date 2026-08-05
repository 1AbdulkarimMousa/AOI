-- Shared participant recruitment tracker linked to restricted CRM contacts.

create table if not exists public.participant_recruitment (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  participant_id text not null,
  full_name text not null,
  email text,
  phone text,
  recruitment_source text not null default 'Other',
  timezone text,
  status text not null default 'new' check (status in ('new','contacted','responded','screening','scheduled','completed','declined','no_response')),
  segment text,
  consent_status text not null default 'pending' check (consent_status in ('pending','granted','declined','withdrawn')),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  next_action text,
  next_action_due date,
  interview_date date,
  qualification_notes text,
  notes text,
  crm_contact_id uuid references public.crm_contacts(id) on delete set null,
  respondent_id uuid references public.respondents(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, participant_id),
  unique (project_id, email)
);

create index if not exists participant_recruitment_queue_idx
  on public.participant_recruitment (organization_id, project_id, owner_id, status, next_action_due);

alter table public.participant_recruitment enable row level security;

drop policy if exists participant_recruitment_read on public.participant_recruitment;
create policy participant_recruitment_read on public.participant_recruitment
  for select to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())));

drop policy if exists participant_recruitment_insert on public.participant_recruitment;
create policy participant_recruitment_insert on public.participant_recruitment
  for insert to authenticated
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())));

drop policy if exists participant_recruitment_update on public.participant_recruitment;
create policy participant_recruitment_update on public.participant_recruitment
  for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and owner_id = (select auth.uid())));

create or replace function public.rpc_aoi_participant_tracker_snapshot()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = (select auth.uid()) and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'projectId', v_project_id,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.id,
      'participantId', item.participant_id,
      'name', item.full_name,
      'email', item.email,
      'phone', item.phone,
      'source', item.recruitment_source,
      'timeZone', item.timezone,
      'status', item.status,
      'segment', item.segment,
      'consentStatus', item.consent_status,
      'ownerId', item.owner_id,
      'ownerName', owner.display_name,
      'nextAction', item.next_action,
      'nextActionDue', item.next_action_due,
      'interviewDate', item.interview_date,
      'qualificationNotes', item.qualification_notes,
      'notes', item.notes,
      'crmContactId', item.crm_contact_id,
      'respondentId', item.respondent_id,
      'updatedAt', item.updated_at
    ) order by item.next_action_due nulls last, item.created_at)
      from public.participant_recruitment item
      left join public.profiles owner on owner.id = item.owner_id
      where item.organization_id = v_org_id and item.project_id = v_project_id
        and (public.is_org_admin(v_org_id) or item.owner_id = (select auth.uid()))), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_participant_recruitment(p_payload jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_id uuid;
  v_owner_id uuid;
  v_saved public.participant_recruitment%rowtype;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = (select auth.uid()) and membership.status = 'active'
  limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(p_payload->>'participantId', ''))) < 3 then raise exception 'PARTICIPANT_ID_REQUIRED'; end if;
  if length(trim(coalesce(p_payload->>'name', ''))) < 2 then raise exception 'PARTICIPANT_NAME_REQUIRED'; end if;
  if coalesce(p_payload->>'status', 'new') not in ('new','contacted','responded','screening','scheduled','completed','declined','no_response') then raise exception 'PARTICIPANT_STATUS_INVALID'; end if;
  if coalesce(p_payload->>'consentStatus', 'pending') not in ('pending','granted','declined','withdrawn') then raise exception 'PARTICIPANT_CONSENT_INVALID'; end if;

  v_id := nullif(p_payload->>'id', '')::uuid;
  v_owner_id := case when public.is_org_admin(v_org_id) then coalesce(nullif(p_payload->>'ownerId', '')::uuid, (select auth.uid())) else (select auth.uid()) end;
  if not exists (select 1 from public.profiles profile join public.organization_memberships membership on membership.user_id = profile.id and membership.organization_id = v_org_id and membership.status = 'active' where profile.id = v_owner_id) then raise exception 'PARTICIPANT_OWNER_INVALID'; end if;

  if v_id is null then
    insert into public.participant_recruitment (
      organization_id, project_id, participant_id, full_name, email, phone, recruitment_source,
      timezone, status, segment, consent_status, owner_id, next_action, next_action_due,
      interview_date, qualification_notes, notes, crm_contact_id, respondent_id, created_by
    ) values (
      v_org_id, v_project_id, trim(p_payload->>'participantId'), trim(p_payload->>'name'), nullif(trim(p_payload->>'email'), ''),
      nullif(trim(p_payload->>'phone'), ''), coalesce(nullif(trim(p_payload->>'source'), ''), 'Other'), nullif(trim(p_payload->>'timeZone'), ''),
      coalesce(nullif(p_payload->>'status', ''), 'new'), nullif(trim(p_payload->>'segment'), ''), coalesce(nullif(p_payload->>'consentStatus', ''), 'pending'),
      v_owner_id, nullif(trim(p_payload->>'nextAction'), ''), nullif(p_payload->>'nextActionDue', '')::date, nullif(p_payload->>'interviewDate', '')::date,
      nullif(trim(p_payload->>'qualificationNotes'), ''), nullif(trim(p_payload->>'notes'), ''), nullif(p_payload->>'crmContactId', '')::uuid, nullif(p_payload->>'respondentId', '')::uuid, (select auth.uid())
    ) returning * into v_saved;
  else
    update public.participant_recruitment item set
      participant_id = trim(p_payload->>'participantId'), full_name = trim(p_payload->>'name'), email = nullif(trim(p_payload->>'email'), ''),
      phone = nullif(trim(p_payload->>'phone'), ''), recruitment_source = coalesce(nullif(trim(p_payload->>'source'), ''), item.recruitment_source),
      timezone = nullif(trim(p_payload->>'timeZone'), ''), status = coalesce(nullif(p_payload->>'status', ''), item.status), segment = nullif(trim(p_payload->>'segment'), ''),
      consent_status = coalesce(nullif(p_payload->>'consentStatus', ''), item.consent_status), owner_id = v_owner_id,
      next_action = nullif(trim(p_payload->>'nextAction'), ''), next_action_due = nullif(p_payload->>'nextActionDue', '')::date,
      interview_date = nullif(p_payload->>'interviewDate', '')::date, qualification_notes = nullif(trim(p_payload->>'qualificationNotes'), ''),
      notes = nullif(trim(p_payload->>'notes'), ''), crm_contact_id = nullif(p_payload->>'crmContactId', '')::uuid,
      respondent_id = nullif(p_payload->>'respondentId', '')::uuid, updated_at = clock_timestamp()
    where item.id = v_id and item.organization_id = v_org_id
      and (public.is_org_admin(v_org_id) or item.owner_id = (select auth.uid()))
    returning * into v_saved;
    if v_saved.id is null then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
  end if;

  return jsonb_build_object('id', v_saved.id, 'participantId', v_saved.participant_id, 'status', v_saved.status, 'crmContactId', v_saved.crm_contact_id);
end;
$$;

revoke all on function public.rpc_aoi_participant_tracker_snapshot() from public, anon;
revoke all on function public.rpc_aoi_upsert_participant_recruitment(jsonb) from public, anon;
grant execute on function public.rpc_aoi_participant_tracker_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_participant_recruitment(jsonb) to authenticated;
