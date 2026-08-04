-- KOL outreach, evidence, consent, and import audit foundation.
-- All records are organization/project scoped and require an active membership.

create table if not exists public.candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  external_id text,
  name text not null,
  category text not null default 'Other / Discovery',
  platforms text,
  reach text,
  tier text,
  creator_type text,
  fit_level text,
  contact_readiness text not null default 'Research needed',
  contact_channel text,
  contact_detail text,
  source_url text,
  pmf_candidate boolean not null default false,
  pmf_rationale text,
  priority_score integer not null default 0 check (priority_score between 0 and 100),
  priority_band text,
  owner_id uuid references public.profiles(id) on delete set null,
  outreach_status text not null default 'Not Contacted',
  interest_level text default 'Unknown',
  preferred_collaboration text,
  deck_introduced boolean not null default false,
  pmf_asked boolean not null default false,
  first_outreach date,
  next_step text,
  next_step_due date,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists candidates_project_pipeline_idx on public.candidates (organization_id, project_id, outreach_status, next_step_due);
create unique index if not exists candidates_external_id_idx on public.candidates (project_id, external_id) where external_id is not null;

create table if not exists public.outreach_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  channel text not null,
  kind text not null default 'Initial',
  status text not null default 'Drafted',
  occurred_at timestamptz not null default now(),
  actor_id uuid references public.profiles(id) on delete set null,
  summary text not null,
  provider_message_id text,
  created_at timestamptz not null default now()
);
create index if not exists outreach_events_candidate_idx on public.outreach_events (organization_id, candidate_id, occurred_at desc);

create table if not exists public.evidence_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  candidate_id uuid references public.candidates(id) on delete set null,
  type text not null,
  stance text not null check (stance in ('supporting','contradicting','neutral')),
  strength integer not null default 1 check (strength between 1 and 4),
  title text not null,
  notes text,
  consent_status text not null default 'pending' check (consent_status in ('pending','granted','declined','not_applicable')),
  retention_until date,
  recorded_by uuid references public.profiles(id) on delete set null,
  recorded_at date not null default current_date,
  created_at timestamptz not null default now()
);
create index if not exists evidence_records_project_idx on public.evidence_records (organization_id, project_id, recorded_at desc);

create table if not exists public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  file_name text not null,
  file_format text not null check (file_format in ('csv','json','tsv')),
  row_count integer not null default 0,
  rejected_count integer not null default 0,
  status text not null default 'previewed' check (status in ('previewed','committed','rejected')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.candidates enable row level security;
alter table public.outreach_events enable row level security;
alter table public.evidence_records enable row level security;
alter table public.import_jobs enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists candidates_member_read on public.candidates;
create policy candidates_member_read on public.candidates for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists candidates_member_write on public.candidates;
create policy candidates_member_write on public.candidates for insert to authenticated with check (public.is_org_member(organization_id));
drop policy if exists candidates_member_update on public.candidates;
create policy candidates_member_update on public.candidates for update to authenticated using (public.is_org_member(organization_id)) with check (public.is_org_member(organization_id));
drop policy if exists outreach_member_read on public.outreach_events;
create policy outreach_member_read on public.outreach_events for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists outreach_member_write on public.outreach_events;
create policy outreach_member_write on public.outreach_events for insert to authenticated with check (public.is_org_member(organization_id));
drop policy if exists evidence_member_read on public.evidence_records;
create policy evidence_member_read on public.evidence_records for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists evidence_member_write on public.evidence_records;
create policy evidence_member_write on public.evidence_records for insert to authenticated with check (public.is_org_member(organization_id));
drop policy if exists import_admin_read on public.import_jobs;
create policy import_admin_read on public.import_jobs for select to authenticated using (public.is_org_admin(organization_id));
drop policy if exists audit_admin_read on public.audit_events;
create policy audit_admin_read on public.audit_events for select to authenticated using (public.is_org_admin(organization_id));

create or replace function public.rpc_aoi_operations_snapshot()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  org_id uuid;
  project_id uuid;
  role_name text;
begin
  select membership.organization_id, membership.role into org_id, role_name
  from public.organization_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end limit 1;
  if org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  select project.id into project_id from public.projects project where project.organization_id = org_id and project.status = 'active' order by project.created_at limit 1;
  return jsonb_build_object(
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'externalId', c.external_id, 'name', c.name, 'category', c.category, 'platforms', c.platforms, 'reach', c.reach, 'tier', c.tier, 'creatorType', c.creator_type, 'fitLevel', c.fit_level, 'contactReadiness', c.contact_readiness, 'contactChannel', c.contact_channel, 'contactDetail', c.contact_detail, 'sourceUrl', c.source_url, 'pmfCandidate', c.pmf_candidate, 'pmfRationale', c.pmf_rationale, 'priorityScore', c.priority_score, 'priorityBand', c.priority_band, 'ownerName', profile.display_name, 'outreachStatus', c.outreach_status, 'interestLevel', c.interest_level, 'preferredCollaboration', c.preferred_collaboration, 'deckIntroduced', c.deck_introduced, 'pmfAsked', c.pmf_asked, 'firstOutreach', c.first_outreach, 'nextStep', c.next_step, 'nextStepDue', c.next_step_due, 'notes', c.notes, 'lastUpdated', c.updated_at::date) order by c.priority_score desc, c.next_step_due nulls last) from public.candidates c left join public.profiles profile on profile.id = c.owner_id where c.project_id = project_id and (role_name = 'admin' or c.owner_id = auth.uid())), '[]'::jsonb),
    'outreachEvents', coalesce((select jsonb_agg(jsonb_build_object('id', event.id, 'candidateId', event.candidate_id, 'channel', event.channel, 'kind', event.kind, 'status', event.status, 'occurredAt', event.occurred_at, 'actorName', coalesce(profile.display_name, 'AOI'), 'summary', event.summary) order by event.occurred_at desc) from public.outreach_events event left join public.profiles profile on profile.id = event.actor_id where event.project_id = project_id), '[]'::jsonb),
    'evidenceRecords', coalesce((select jsonb_agg(jsonb_build_object('id', record.id, 'candidateId', record.candidate_id, 'type', record.type, 'stance', record.stance, 'strength', record.strength, 'title', record.title, 'notes', record.notes, 'consentStatus', record.consent_status, 'recordedBy', coalesce(profile.display_name, 'AOI'), 'recordedAt', record.recorded_at) order by record.recorded_at desc) from public.evidence_records record left join public.profiles profile on profile.id = record.recorded_by where record.project_id = project_id and (role_name = 'admin' or record.candidate_id in (select owned.id from public.candidates owned where owned.id = record.candidate_id and owned.owner_id = auth.uid()))), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_candidate(candidate jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare org_id uuid; project_id uuid; result public.candidates%rowtype;
begin
  select membership.organization_id into org_id from public.organization_memberships membership where membership.user_id = auth.uid() and membership.status = 'active' limit 1;
  select project.id into project_id from public.projects project where project.organization_id = org_id and project.status = 'active' order by project.created_at limit 1;
  if org_id is null or project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  insert into public.candidates (organization_id, project_id, external_id, name, category, platforms, reach, tier, contact_readiness, pmf_candidate, owner_id, outreach_status, source_url, next_step, next_step_due, notes, created_by, updated_at)
  values (org_id, project_id, nullif(candidate->>'externalId',''), trim(candidate->>'name'), coalesce(nullif(candidate->>'category',''), 'Other / Discovery'), candidate->>'platforms', candidate->>'reach', candidate->>'tier', coalesce(nullif(candidate->>'contactReadiness',''), 'Research needed'), coalesce((candidate->>'pmfCandidate')::boolean, false), (select id from public.profiles where lower(display_name)=lower(candidate->>'ownerName') limit 1), coalesce(nullif(candidate->>'outreachStatus',''), 'Not Contacted'), candidate->>'sourceUrl', candidate->>'nextStep', nullif(candidate->>'nextStepDue','')::date, candidate->>'notes', auth.uid(), now())
  on conflict (project_id, external_id) where external_id is not null do update set name=excluded.name, category=excluded.category, platforms=excluded.platforms, reach=excluded.reach, tier=excluded.tier, contact_readiness=excluded.contact_readiness, pmf_candidate=excluded.pmf_candidate, outreach_status=excluded.outreach_status, source_url=excluded.source_url, next_step=excluded.next_step, next_step_due=excluded.next_step_due, notes=excluded.notes, updated_at=now()
  returning * into result;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata) values (org_id, auth.uid(), 'candidate', result.id, 'upsert', jsonb_build_object('name', result.name));
  return jsonb_build_object('id', result.id, 'externalId', result.external_id, 'name', result.name, 'category', result.category, 'outreachStatus', result.outreach_status);
end; $$;

create or replace function public.rpc_aoi_log_outreach(candidate_id uuid, event_channel text, event_kind text, event_status text, event_summary text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare org_id uuid; project_id uuid; result public.outreach_events%rowtype;
begin
  select membership.organization_id into org_id from public.organization_memberships membership where membership.user_id=auth.uid() and membership.status='active' limit 1;
  select c.project_id into project_id from public.candidates c where c.id=candidate_id and c.organization_id=org_id;
  if project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  insert into public.outreach_events (organization_id, project_id, candidate_id, channel, kind, status, actor_id, summary) values (org_id, project_id, candidate_id, event_channel, event_kind, event_status, auth.uid(), trim(event_summary)) returning * into result;
  update public.candidates set outreach_status=case when event_status='Sent' then 'Sent' when event_status='Replied' then 'Replied' when event_status='Interested' then 'Interested' else outreach_status end, updated_at=now() where id=candidate_id;
  return jsonb_build_object('id', result.id, 'candidateId', result.candidate_id);
end; $$;

create or replace function public.rpc_aoi_add_evidence(candidate_id uuid, evidence_type text, evidence_stance text, evidence_strength integer, evidence_title text, evidence_notes text, evidence_consent text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare org_id uuid; project_id uuid; result public.evidence_records%rowtype;
begin
  select membership.organization_id into org_id from public.organization_memberships membership where membership.user_id=auth.uid() and membership.status='active' limit 1;
  select c.project_id into project_id from public.candidates c where c.id=candidate_id and c.organization_id=org_id;
  if project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  insert into public.evidence_records (organization_id, project_id, candidate_id, type, stance, strength, title, notes, consent_status, recorded_by) values (org_id, project_id, candidate_id, evidence_type, evidence_stance, greatest(1,least(4,evidence_strength)), trim(evidence_title), evidence_notes, evidence_consent, auth.uid()) returning * into result;
  return jsonb_build_object('id', result.id, 'candidateId', result.candidate_id);
end; $$;

revoke all on function public.rpc_aoi_operations_snapshot() from public;
revoke all on function public.rpc_aoi_upsert_candidate(jsonb) from public;
revoke all on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) from public;
revoke all on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) from public;
grant execute on function public.rpc_aoi_operations_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) to authenticated;
grant execute on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) to authenticated;
