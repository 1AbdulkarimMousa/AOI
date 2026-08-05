-- Connect CRM, recruitment, and research identities; expose collected data; and
-- replace presentation-only rewards with server-authored personal/cooperative progress.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create unique index if not exists crm_contacts_scope_id_unique
  on public.crm_contacts (organization_id, project_id, id);
create unique index if not exists participant_recruitment_scope_id_unique
  on public.participant_recruitment (organization_id, project_id, id);

create table if not exists public.contact_external_identities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  crm_contact_id uuid not null,
  namespace text not null check (namespace in ('candidate_import','recruitment','respondent','survey','partner_system')),
  external_id text not null,
  source text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (project_id, namespace, external_id),
  foreign key (organization_id, project_id, crm_contact_id)
    references public.crm_contacts (organization_id, project_id, id) on delete cascade
);
create index if not exists contact_external_identities_contact_idx
  on public.contact_external_identities (organization_id, project_id, crm_contact_id);

alter table public.respondents
  add column if not exists crm_contact_id uuid,
  add column if not exists participant_recruitment_id uuid;
alter table public.respondent_contacts
  add column if not exists crm_contact_id uuid;

alter table public.respondents drop constraint if exists respondents_crm_contact_scope_fk;
alter table public.respondents add constraint respondents_crm_contact_scope_fk
  foreign key (organization_id, project_id, crm_contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete restrict;
alter table public.respondents drop constraint if exists respondents_recruitment_scope_fk;
alter table public.respondents add constraint respondents_recruitment_scope_fk
  foreign key (organization_id, project_id, participant_recruitment_id)
  references public.participant_recruitment (organization_id, project_id, id) on delete restrict;
create unique index if not exists respondents_project_crm_contact_unique
  on public.respondents (project_id, crm_contact_id) where crm_contact_id is not null;
create unique index if not exists respondents_recruitment_unique
  on public.respondents (participant_recruitment_id) where participant_recruitment_id is not null;

alter table public.respondent_contacts drop constraint if exists respondent_contacts_crm_contact_scope_fk;
alter table public.respondent_contacts add constraint respondent_contacts_crm_contact_scope_fk
  foreign key (organization_id, project_id, crm_contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete restrict;

alter table public.participant_recruitment drop constraint if exists participant_recruitment_crm_contact_id_fkey;
alter table public.participant_recruitment drop constraint if exists participant_recruitment_respondent_id_fkey;
alter table public.participant_recruitment drop constraint if exists participant_recruitment_crm_contact_scope_fk;
alter table public.participant_recruitment add constraint participant_recruitment_crm_contact_scope_fk
  foreign key (organization_id, project_id, crm_contact_id)
  references public.crm_contacts (organization_id, project_id, id) on delete set null (crm_contact_id);
alter table public.participant_recruitment drop constraint if exists participant_recruitment_respondent_scope_fk;
alter table public.participant_recruitment add constraint participant_recruitment_respondent_scope_fk
  foreign key (organization_id, project_id, respondent_id)
  references public.respondents (organization_id, project_id, id) on delete set null (respondent_id);
create unique index if not exists participant_recruitment_respondent_unique
  on public.participant_recruitment (respondent_id) where respondent_id is not null;

insert into public.contact_external_identities (
  organization_id, project_id, crm_contact_id, namespace, external_id, source, created_by
)
select candidate.organization_id, candidate.project_id, candidate.crm_contact_id,
  'candidate_import', candidate.external_id, 'Existing candidate record', candidate.created_by
from public.candidates candidate
where candidate.crm_contact_id is not null and nullif(trim(candidate.external_id), '') is not null
on conflict (project_id, namespace, external_id) do nothing;

insert into public.contact_external_identities (
  organization_id, project_id, crm_contact_id, namespace, external_id, source, created_by
)
select recruitment.organization_id, recruitment.project_id, recruitment.crm_contact_id,
  'recruitment', recruitment.participant_id, recruitment.recruitment_source, recruitment.created_by
from public.participant_recruitment recruitment
where recruitment.crm_contact_id is not null
on conflict (project_id, namespace, external_id) do nothing;

create table if not exists public.gamification_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  points integer not null check (points <> 0),
  source_type text not null,
  source_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_on date not null default current_date,
  created_at timestamptz not null default now(),
  unique (project_id, actor_id, action, source_type, source_id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);
create index if not exists gamification_events_actor_idx
  on public.gamification_events (organization_id, project_id, actor_id, occurred_on desc, created_at desc);

create table if not exists public.gamification_badges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  code text not null,
  name text not null,
  description text not null,
  icon text not null default 'star',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (project_id, code),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table if not exists public.gamification_badge_awards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  badge_id uuid not null references public.gamification_badges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_event_id uuid not null references public.gamification_events(id) on delete restrict,
  awarded_at timestamptz not null default now(),
  unique (badge_id, user_id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table if not exists public.gamification_team_goals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  code text not null,
  name text not null,
  description text not null,
  target integer not null check (target > 0),
  starts_on date not null default current_date,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (project_id, code),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

alter table public.contact_external_identities enable row level security;
alter table public.gamification_events enable row level security;
alter table public.gamification_badges enable row level security;
alter table public.gamification_badge_awards enable row level security;
alter table public.gamification_team_goals enable row level security;

drop policy if exists contact_external_identities_read on public.contact_external_identities;
create policy contact_external_identities_read on public.contact_external_identities
  for select to authenticated using (
    public.is_org_admin(organization_id)
    or exists (
      select 1 from public.respondents respondent
      where respondent.crm_contact_id = contact_external_identities.crm_contact_id
        and respondent.organization_id = contact_external_identities.organization_id
        and respondent.project_id = contact_external_identities.project_id
        and (respondent.assigned_to = (select auth.uid()) or respondent.workflow_status = 'approved')
    )
  );

drop policy if exists gamification_events_personal_read on public.gamification_events;
create policy gamification_events_personal_read on public.gamification_events
  for select to authenticated using (
    public.is_org_admin(organization_id)
    or (public.is_org_member(organization_id) and actor_id = (select auth.uid()))
  );
drop policy if exists gamification_badges_member_read on public.gamification_badges;
create policy gamification_badges_member_read on public.gamification_badges
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists gamification_badge_awards_personal_read on public.gamification_badge_awards;
create policy gamification_badge_awards_personal_read on public.gamification_badge_awards
  for select to authenticated using (
    public.is_org_admin(organization_id)
    or (public.is_org_member(organization_id) and user_id = (select auth.uid()))
  );
drop policy if exists gamification_team_goals_member_read on public.gamification_team_goals;
create policy gamification_team_goals_member_read on public.gamification_team_goals
  for select to authenticated using (public.is_org_member(organization_id));

revoke all on public.contact_external_identities, public.gamification_events,
  public.gamification_badges, public.gamification_badge_awards,
  public.gamification_team_goals from public, anon, authenticated;
grant select on public.contact_external_identities, public.gamification_events,
  public.gamification_badges, public.gamification_badge_awards,
  public.gamification_team_goals to authenticated;
grant select on public.participant_recruitment to authenticated;

insert into public.gamification_badges (organization_id, project_id, code, name, description, icon)
select project.organization_id, project.id, seed.code, seed.name, seed.description, seed.icon
from public.projects project
cross join (values
  ('first_clean_respondent','First Clean Respondent','Connected a qualified, consented recruitment prospect to a respondent.','user-check'),
  ('evidence_scout','Evidence Scout','Contributed an evidence record that passed administrator review.','search-check'),
  ('consent_guardian','Consent Guardian','Recorded a granted consent version with an auditable source.','shield-check'),
  ('task_finisher','Task Finisher','Completed an assigned operational task.','circle-check')
) as seed(code,name,description,icon)
on conflict (project_id, code) do update set
  name = excluded.name, description = excluded.description, icon = excluded.icon, active = true;

insert into public.gamification_team_goals (organization_id, project_id, code, name, description, target, starts_on)
select project.organization_id, project.id, seed.code, seed.name, seed.description, seed.target, current_date
from public.projects project
cross join (values
  ('connected_research_chain','Connect the research chain','Convert qualified recruitment prospects into traceable respondents.',10),
  ('weekly_evidence_loop','Close the evidence loop','Approve research records with provenance and limitations.',12)
) as seed(code,name,description,target)
on conflict (project_id, code) do update set
  name = excluded.name, description = excluded.description, target = excluded.target, active = true;

create or replace function private.award_aoi_gamification_event(
  p_organization_id uuid,
  p_project_id uuid,
  p_actor_id uuid,
  p_action text,
  p_points integer,
  p_source_type text,
  p_source_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_badge_code text;
begin
  if p_actor_id is null or p_points = 0 then return null; end if;
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.organization_id = p_organization_id and membership.user_id = p_actor_id
      and membership.status in ('active','password_change_required')
  ) then return null; end if;

  insert into public.gamification_events (
    organization_id, project_id, actor_id, action, points, source_type, source_id, metadata
  ) values (
    p_organization_id, p_project_id, p_actor_id, p_action, p_points,
    p_source_type, p_source_id, coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (project_id, actor_id, action, source_type, source_id) do nothing
  returning id into v_event_id;
  if v_event_id is null then return null; end if;

  v_badge_code := case p_action
    when 'respondent_converted' then 'first_clean_respondent'
    when 'evidence_approved' then 'evidence_scout'
    when 'consent_granted' then 'consent_guardian'
    when 'task_completed' then 'task_finisher'
    else null
  end;
  if v_badge_code is not null then
    insert into public.gamification_badge_awards (
      organization_id, project_id, badge_id, user_id, source_event_id
    )
    select p_organization_id, p_project_id, badge.id, p_actor_id, v_event_id
    from public.gamification_badges badge
    where badge.project_id = p_project_id and badge.code = v_badge_code and badge.active
    on conflict (badge_id, user_id) do nothing;
  end if;
  return v_event_id;
end;
$$;
revoke all on function private.award_aoi_gamification_event(uuid,uuid,uuid,text,integer,text,uuid,jsonb)
  from public, anon, authenticated;

create or replace function private.reward_aoi_research_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_points integer;
begin
  if new.workflow_status <> 'approved' or old.workflow_status = 'approved' then return new; end if;
  v_action := case tg_table_name
    when 'evidence_records' then 'evidence_approved'
    when 'research_sessions' then 'session_approved'
    when 'product_events' then 'product_event_approved'
    when 'value_exchange_observations' then 'value_exchange_approved'
    when 'pmf_observations' then 'observation_approved'
  end;
  v_points := case tg_table_name when 'evidence_records' then 35 else 25 end;
  perform private.award_aoi_gamification_event(
    new.organization_id, new.project_id, new.assigned_to, v_action, v_points,
    tg_table_name, new.id, jsonb_build_object('reviewedBy', new.reviewed_by)
  );
  return new;
end;
$$;
revoke all on function private.reward_aoi_research_approval() from public, anon, authenticated;

drop trigger if exists reward_aoi_evidence_approval on public.evidence_records;
create trigger reward_aoi_evidence_approval after update of workflow_status on public.evidence_records
  for each row execute function private.reward_aoi_research_approval();
drop trigger if exists reward_aoi_session_approval on public.research_sessions;
create trigger reward_aoi_session_approval after update of workflow_status on public.research_sessions
  for each row execute function private.reward_aoi_research_approval();
drop trigger if exists reward_aoi_product_event_approval on public.product_events;
create trigger reward_aoi_product_event_approval after update of workflow_status on public.product_events
  for each row execute function private.reward_aoi_research_approval();
drop trigger if exists reward_aoi_value_exchange_approval on public.value_exchange_observations;
create trigger reward_aoi_value_exchange_approval after update of workflow_status on public.value_exchange_observations
  for each row execute function private.reward_aoi_research_approval();
drop trigger if exists reward_aoi_observation_approval on public.pmf_observations;
create trigger reward_aoi_observation_approval after update of workflow_status on public.pmf_observations
  for each row execute function private.reward_aoi_research_approval();

create or replace function private.reward_aoi_task_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status <> 'completed' and new.assigned_to is not null then
    perform private.award_aoi_gamification_event(
      new.organization_id, new.project_id, new.assigned_to, 'task_completed', 30,
      'tasks', new.id, jsonb_build_object('title', new.title)
    );
  end if;
  return new;
end;
$$;
revoke all on function private.reward_aoi_task_completion() from public, anon, authenticated;
drop trigger if exists reward_aoi_task_completion on public.tasks;
create trigger reward_aoi_task_completion after update of status on public.tasks
  for each row execute function private.reward_aoi_task_completion();

create or replace function private.reward_aoi_consent_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'granted' then
    perform private.award_aoi_gamification_event(
      new.organization_id, new.project_id, new.recorded_by, 'consent_granted', 20,
      'consent_records', new.id, jsonb_build_object('respondentId', new.respondent_id, 'version', new.version)
    );
  end if;
  return new;
end;
$$;
revoke all on function private.reward_aoi_consent_grant() from public, anon, authenticated;
drop trigger if exists reward_aoi_consent_grant on public.consent_records;
create trigger reward_aoi_consent_grant after insert on public.consent_records
  for each row execute function private.reward_aoi_consent_grant();

create or replace function private.mirror_aoi_crm_reward()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.award_aoi_gamification_event(
    new.organization_id, new.project_id, new.actor_id, 'crm_' || new.action,
    new.points, 'crm_reward_events', new.id, jsonb_build_object('contactId', new.contact_id)
  );
  return new;
end;
$$;
revoke all on function private.mirror_aoi_crm_reward() from public, anon, authenticated;
drop trigger if exists mirror_aoi_crm_reward on public.crm_reward_events;
create trigger mirror_aoi_crm_reward after insert on public.crm_reward_events
  for each row execute function private.mirror_aoi_crm_reward();

insert into public.gamification_events (
  organization_id, project_id, actor_id, action, points, source_type, source_id, metadata, occurred_on, created_at
)
select reward.organization_id, reward.project_id, reward.actor_id, 'crm_' || reward.action,
  reward.points, 'crm_reward_events', reward.id, jsonb_build_object('contactId', reward.contact_id),
  reward.reward_date, reward.created_at
from public.crm_reward_events reward
on conflict (project_id, actor_id, action, source_type, source_id) do nothing;

create or replace function public.rpc_aoi_convert_recruitment_to_respondent(
  p_recruitment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_org_id uuid;
  v_project_id uuid;
  v_recruitment public.participant_recruitment%rowtype;
  v_contact public.crm_contacts%rowtype;
  v_segment public.research_segments%rowtype;
  v_respondent_id uuid;
  v_respondent_code text;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = v_actor_id and membership.status = 'active' and membership.role = 'admin'
  order by membership.joined_at limit 1;
  if v_org_id is null then raise exception 'ADMIN_CONVERSION_REQUIRED'; end if;

  select recruitment.* into v_recruitment
  from public.participant_recruitment recruitment
  where recruitment.id = p_recruitment_id and recruitment.organization_id = v_org_id
  for update;
  if v_recruitment.id is null then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
  v_project_id := v_recruitment.project_id;
  if v_recruitment.respondent_id is not null then
    return jsonb_build_object(
      'respondentId', v_recruitment.respondent_id,
      'crmContactId', v_recruitment.crm_contact_id,
      'alreadyConverted', true
    );
  end if;
  if v_recruitment.status not in ('screening','scheduled','completed') then raise exception 'PARTICIPANT_SCREENING_REQUIRED'; end if;
  if nullif(trim(v_recruitment.segment), '') is null then raise exception 'PARTICIPANT_SEGMENT_REQUIRED'; end if;
  if v_recruitment.consent_status <> 'granted' then raise exception 'PARTICIPANT_CONSENT_REQUIRED'; end if;

  select segment.* into v_segment
  from public.research_segments segment
  where segment.organization_id = v_org_id and segment.project_id = v_project_id and segment.active
    and (lower(segment.name) = lower(v_recruitment.segment) or lower(segment.code) = lower(v_recruitment.segment))
  order by segment.sequence, segment.id limit 1;
  if v_segment.id is null then raise exception 'PARTICIPANT_SEGMENT_INVALID'; end if;

  if v_recruitment.crm_contact_id is not null then
    select contact.* into v_contact from public.crm_contacts contact
    where contact.id = v_recruitment.crm_contact_id and contact.organization_id = v_org_id
      and contact.project_id = v_project_id;
    if v_contact.id is null then raise exception 'PARTICIPANT_CRM_SCOPE_INVALID'; end if;
  else
    select contact.* into v_contact
    from public.crm_contacts contact
    where contact.organization_id = v_org_id and contact.project_id = v_project_id
      and (
        (nullif(trim(v_recruitment.email), '') is not null and lower(contact.email) = lower(trim(v_recruitment.email)))
        or (nullif(regexp_replace(coalesce(v_recruitment.phone,''), '[^0-9]', '', 'g'), '') is not null
          and regexp_replace(coalesce(contact.phone,''), '[^0-9]', '', 'g') = regexp_replace(v_recruitment.phone, '[^0-9]', '', 'g'))
      )
    order by contact.updated_at desc limit 1;

    if v_contact.id is null then
      insert into public.crm_contacts (
        organization_id, project_id, contact_type, name, email, phone, primary_channel,
        tags, owner_id, lifecycle, next_action, next_action_due, priority_score, notes, created_by
      ) values (
        v_org_id, v_project_id, 'Customer', v_recruitment.full_name,
        v_recruitment.email, v_recruitment.phone,
        case when v_recruitment.email is not null then 'Email' else 'Phone' end,
        'research-participant', v_recruitment.owner_id, 'qualified',
        'Complete the first research session', v_recruitment.interview_date,
        70, 'Created from qualified participant recruitment ' || v_recruitment.participant_id, v_actor_id
      ) returning * into v_contact;
    end if;
    update public.participant_recruitment set crm_contact_id = v_contact.id, updated_at = clock_timestamp()
    where id = v_recruitment.id;
  end if;

  v_respondent_code := 'CON-' || to_char(current_date, 'YYYY') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  insert into public.respondents (
    organization_id, project_id, external_id, segment_id, respondent_type,
    specialty_status, recruitment_source, consent_status, stage, status,
    workflow_status, assigned_to, created_by, submitted_at, reviewed_by,
    reviewed_at, notes, crm_contact_id, participant_recruitment_id
  ) values (
    v_org_id, v_project_id, v_respondent_code, v_segment.id, 'Consumer',
    nullif(v_recruitment.qualification_notes, ''), v_recruitment.recruitment_source,
    'granted', 'Concept', case when v_recruitment.status = 'completed' then 'completed' when v_recruitment.status = 'scheduled' then 'scheduled' else 'screening' end,
    'approved', v_recruitment.owner_id, v_actor_id, clock_timestamp(), v_actor_id,
    clock_timestamp(), v_recruitment.notes, v_contact.id, v_recruitment.id
  ) returning id into v_respondent_id;

  insert into public.respondent_contacts (
    respondent_id, organization_id, project_id, contact_name, email, phone,
    contact_reference, preferred_channel, created_by, crm_contact_id
  ) values (
    v_respondent_id, v_org_id, v_project_id, v_recruitment.full_name,
    v_recruitment.email, v_recruitment.phone, v_recruitment.participant_id,
    case when v_recruitment.email is not null then 'Email' else 'Phone' end,
    v_actor_id, v_contact.id
  );

  insert into public.consent_records (
    organization_id, project_id, respondent_id, status, interview_allowed,
    recording_allowed, images_allowed, quotation_allowed, recontact_allowed,
    granted_at, recorded_by
  ) values (
    v_org_id, v_project_id, v_respondent_id, 'granted', true,
    false, false, false, true, clock_timestamp(), v_actor_id
  );

  insert into public.contact_external_identities (
    organization_id, project_id, crm_contact_id, namespace, external_id, source, created_by
  ) values
    (v_org_id, v_project_id, v_contact.id, 'recruitment', v_recruitment.participant_id, v_recruitment.recruitment_source, v_actor_id),
    (v_org_id, v_project_id, v_contact.id, 'respondent', v_respondent_code, 'Ambiloop respondent conversion', v_actor_id)
  on conflict (project_id, namespace, external_id) do nothing;

  update public.participant_recruitment
  set crm_contact_id = v_contact.id, respondent_id = v_respondent_id,
    next_action = 'Open respondent profile and complete the research session',
    updated_at = clock_timestamp()
  where id = v_recruitment.id;

  perform private.award_aoi_gamification_event(
    v_org_id, v_project_id, v_actor_id, 'respondent_converted', 40,
    'participant_recruitment', v_recruitment.id,
    jsonb_build_object('respondentId', v_respondent_id, 'participantId', v_recruitment.participant_id)
  );

  return jsonb_build_object(
    'respondentId', v_respondent_id, 'respondentCode', v_respondent_code,
    'crmContactId', v_contact.id, 'participantId', v_recruitment.participant_id,
    'alreadyConverted', false
  );
end;
$$;

create or replace function public.rpc_aoi_collect_snapshot()
returns jsonb
language plpgsql
stable
security invoker
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
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at, project.id limit 1;
  if v_org_id is null or v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  return jsonb_build_object(
    'respondents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', respondent.id, 'respondentCode', respondent.external_id,
      'crmContactId', respondent.crm_contact_id,
      'participantRecruitmentId', respondent.participant_recruitment_id,
      'recruitmentCode', recruitment.participant_id,
      'externalIds', coalesce((select jsonb_agg(identity.external_id order by identity.namespace, identity.external_id)
        from public.contact_external_identities identity where identity.crm_contact_id = respondent.crm_contact_id), '[]'::jsonb),
      'segmentCode', segment.code, 'segmentName', segment.name,
      'respondentType', respondent.respondent_type, 'specialtyStatus', respondent.specialty_status,
      'recruitmentSource', respondent.recruitment_source,
      'consentStatus', respondent.consent_status, 'stage', respondent.stage,
      'status', respondent.status, 'workflowStatus', respondent.workflow_status,
      'ownerId', respondent.assigned_to, 'ownerName', owner.display_name,
      'notes', respondent.notes, 'reviewNotes', respondent.review_notes,
      'createdAt', respondent.created_at, 'updatedAt', respondent.updated_at
    ) order by respondent.updated_at desc) from public.respondents respondent
      join public.research_segments segment on segment.id = respondent.segment_id
      left join public.participant_recruitment recruitment on recruitment.id = respondent.participant_recruitment_id
      left join public.profiles owner on owner.id = respondent.assigned_to
      where respondent.organization_id = v_org_id and respondent.project_id = v_project_id), '[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', session.id, 'respondentId', session.respondent_id,
      'respondentCode', respondent.external_id, 'segmentName', segment.name,
      'pmfLayer', session.pmf_layer, 'method', session.method,
      'sessionDate', session.session_date, 'currentBehavior', session.current_behavior,
      'recentIncident', session.recent_incident, 'biggestHassle', session.biggest_hassle,
      'currentAction', session.current_action, 'unmetNeed', session.unmet_need,
      'limitations', session.limitations, 'workflowStatus', session.workflow_status,
      'ownerId', session.assigned_to, 'ownerName', owner.display_name,
      'reviewNotes', session.review_notes, 'createdAt', session.created_at, 'updatedAt', session.updated_at
    ) order by session.updated_at desc) from public.research_sessions session
      join public.respondents respondent on respondent.id = session.respondent_id
      join public.research_segments segment on segment.id = session.segment_id
      left join public.profiles owner on owner.id = session.assigned_to
      where session.organization_id = v_org_id and session.project_id = v_project_id), '[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object(
      'id', evidence.id, 'respondentId', evidence.respondent_id,
      'respondentCode', respondent.external_id, 'sessionId', evidence.session_id,
      'segmentName', segment.name, 'pmfLayer', evidence.pmf_layer,
      'dimension', evidence.dimension, 'topic', evidence.topic,
      'title', evidence.title, 'evidenceText', evidence.evidence_text,
      'evidenceType', evidence.evidence_type, 'stance', evidence.stance,
      'strength', evidence.strength, 'sourceLink', evidence.source_link,
      'decisionRelevance', evidence.decision_relevance,
      'followUpNeeded', evidence.follow_up_needed, 'limitations', evidence.limitations,
      'notes', evidence.notes, 'workflowStatus', evidence.workflow_status,
      'ownerId', evidence.assigned_to, 'ownerName', owner.display_name,
      'reviewNotes', evidence.review_notes, 'createdAt', evidence.recorded_at, 'updatedAt', evidence.updated_at
    ) order by evidence.updated_at desc) from public.evidence_records evidence
      left join public.respondents respondent on respondent.id = evidence.respondent_id
      left join public.research_segments segment on segment.id = evidence.segment_id
      left join public.profiles owner on owner.id = evidence.assigned_to
      where evidence.organization_id = v_org_id and evidence.project_id = v_project_id), '[]'::jsonb),
    'productEvents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', event.id, 'respondentId', event.respondent_id,
      'respondentCode', respondent.external_id, 'segmentName', segment.name,
      'eventDate', event.event_date, 'studyWeek', event.study_week,
      'triggerType', event.trigger_type, 'triggerDescription', event.trigger_description,
      'targetUser', event.target_user, 'sessionDurationMinutes', event.session_duration_minutes,
      'captureSuccess', event.capture_success, 'validImage', event.valid_image,
      'compareUsed', event.compare_used, 'resultUnderstood', event.result_understood,
      'valueObtained', event.value_obtained, 'actionTaken', event.action_taken,
      'sharedWithDoctor', event.shared_with_doctor, 'mainFriction', event.main_friction,
      'notes', event.notes, 'workflowStatus', event.workflow_status,
      'ownerId', event.assigned_to, 'ownerName', owner.display_name,
      'reviewNotes', event.review_notes, 'createdAt', event.created_at, 'updatedAt', event.updated_at
    ) order by event.updated_at desc) from public.product_events event
      join public.respondents respondent on respondent.id = event.respondent_id
      join public.research_segments segment on segment.id = event.segment_id
      left join public.profiles owner on owner.id = event.assigned_to
      where event.organization_id = v_org_id and event.project_id = v_project_id), '[]'::jsonb),
    'valueExchange', coalesce((select jsonb_agg(jsonb_build_object(
      'id', value.id, 'respondentId', value.respondent_id,
      'respondentCode', respondent.external_id, 'segmentName', segment.name,
      'observedAt', value.observed_at, 'hardwarePrice', value.hardware_price,
      'reasonablePriceMin', value.reasonable_price_min, 'reasonablePriceMax', value.reasonable_price_max,
      'purchaseIntent', value.purchase_intent, 'preferredOffer', value.preferred_offer,
      'subscriptionPlan', value.subscription_plan, 'commitmentType', value.commitment_type,
      'commitmentAmount', value.commitment_amount, 'mainObjection', value.main_objection,
      'postTrialPurchaseIntent', value.post_trial_purchase_intent, 'notes', value.notes,
      'workflowStatus', value.workflow_status, 'ownerId', value.assigned_to,
      'ownerName', owner.display_name, 'reviewNotes', value.review_notes,
      'createdAt', value.created_at, 'updatedAt', value.updated_at
    ) order by value.updated_at desc) from public.value_exchange_observations value
      join public.respondents respondent on respondent.id = value.respondent_id
      join public.research_segments segment on segment.id = value.segment_id
      left join public.profiles owner on owner.id = value.assigned_to
      where value.organization_id = v_org_id and value.project_id = v_project_id), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object(
      'id', observation.id, 'respondentId', observation.respondent_id,
      'respondentCode', respondent.external_id, 'sessionId', observation.session_id,
      'segmentName', segment.name, 'definitionId', observation.definition_id,
      'metricLabel', definition.label, 'pmfLayer', definition.pmf_layer,
      'numericValue', observation.numeric_value, 'booleanValue', observation.boolean_value,
      'textValue', observation.text_value, 'sourceLink', observation.source_link,
      'notes', observation.notes, 'workflowStatus', observation.workflow_status,
      'ownerId', observation.assigned_to, 'ownerName', owner.display_name,
      'reviewNotes', observation.review_notes, 'createdAt', observation.created_at, 'updatedAt', observation.updated_at
    ) order by observation.updated_at desc) from public.pmf_observations observation
      join public.pmf_metric_definitions definition on definition.id = observation.definition_id
      join public.research_segments segment on segment.id = observation.segment_id
      left join public.respondents respondent on respondent.id = observation.respondent_id
      left join public.profiles owner on owner.id = observation.assigned_to
      where observation.organization_id = v_org_id and observation.project_id = v_project_id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_collect_record_detail(
  p_record_type text,
  p_record_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_record_type = 'respondent' then
    select jsonb_build_object(
      'record', to_jsonb(respondent),
      'contact', (select to_jsonb(contact) from public.respondent_contacts contact where contact.respondent_id = respondent.id),
      'consentHistory', coalesce((select jsonb_agg(to_jsonb(consent) order by consent.version desc) from public.consent_records consent where consent.respondent_id = respondent.id), '[]'::jsonb),
      'sessions', coalesce((select jsonb_agg(to_jsonb(session) order by session.session_date desc) from public.research_sessions session where session.respondent_id = respondent.id), '[]'::jsonb),
      'evidence', coalesce((select jsonb_agg(to_jsonb(evidence) order by evidence.recorded_at desc) from public.evidence_records evidence where evidence.respondent_id = respondent.id), '[]'::jsonb),
      'productEvents', coalesce((select jsonb_agg(to_jsonb(event) order by event.event_date desc) from public.product_events event where event.respondent_id = respondent.id), '[]'::jsonb),
      'valueExchange', coalesce((select jsonb_agg(to_jsonb(value) order by value.observed_at desc) from public.value_exchange_observations value where value.respondent_id = respondent.id), '[]'::jsonb),
      'attachments', coalesce((select jsonb_agg(to_jsonb(attachment) order by attachment.created_at desc) from public.research_attachments attachment where attachment.respondent_id = respondent.id), '[]'::jsonb)
    ) into v_result
    from public.respondents respondent where respondent.id = p_record_id;
  elsif p_record_type = 'session' then
    select jsonb_build_object('record', to_jsonb(record)) into v_result from public.research_sessions record where record.id = p_record_id;
  elsif p_record_type = 'evidence' then
    select jsonb_build_object('record', to_jsonb(record)) into v_result from public.evidence_records record where record.id = p_record_id;
  elsif p_record_type = 'product_event' then
    select jsonb_build_object('record', to_jsonb(record)) into v_result from public.product_events record where record.id = p_record_id;
  elsif p_record_type = 'value_exchange' then
    select jsonb_build_object('record', to_jsonb(record)) into v_result from public.value_exchange_observations record where record.id = p_record_id;
  elsif p_record_type = 'observation' then
    select jsonb_build_object('record', to_jsonb(record)) into v_result from public.pmf_observations record where record.id = p_record_id;
  else
    raise exception 'COLLECT_RECORD_TYPE_INVALID';
  end if;
  if v_result is null then raise exception 'COLLECT_RECORD_NOT_FOUND'; end if;
  return v_result;
end;
$$;

create or replace function public.rpc_aoi_gamification_summary()
returns jsonb
language plpgsql
stable
security definer
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
        when 'connected_research_chain' then (select count(*) from public.respondents respondent where respondent.project_id = v_project_id and respondent.crm_contact_id is not null)
        when 'weekly_evidence_loop' then (select count(*) from public.gamification_events event where event.project_id = v_project_id and event.action in ('evidence_approved','session_approved','product_event_approved','value_exchange_approved','observation_approved') and event.occurred_on >= date_trunc('week', current_date)::date)
        else 0 end
    ) order by goal.created_at) from public.gamification_team_goals goal
      where goal.project_id = v_project_id and goal.active
        and goal.starts_on <= current_date and (goal.ends_on is null or goal.ends_on >= current_date)), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) from public, anon;
revoke all on function public.rpc_aoi_collect_snapshot() from public, anon;
revoke all on function public.rpc_aoi_collect_record_detail(text,uuid) from public, anon;
revoke all on function public.rpc_aoi_gamification_summary() from public, anon;
grant execute on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) to authenticated;
grant execute on function public.rpc_aoi_collect_snapshot() to authenticated;
grant execute on function public.rpc_aoi_collect_record_detail(text,uuid) to authenticated;
grant execute on function public.rpc_aoi_gamification_summary() to authenticated;
