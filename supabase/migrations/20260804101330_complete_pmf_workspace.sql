-- Complete Ambiloop PMF collection, review, analysis, and media foundation.
-- This migration repairs the deployed outreach RPCs without rewriting history.

create unique index if not exists projects_organization_id_unique
  on public.projects (organization_id, id);
create unique index if not exists candidates_scope_id_unique
  on public.candidates (organization_id, project_id, id);
create unique index if not exists candidates_organization_id_unique
  on public.candidates (organization_id, id);
create unique index if not exists email_templates_organization_id_unique
  on public.email_templates (organization_id, id);

alter table public.outreach_events add constraint outreach_events_candidate_scope_fk
  foreign key (organization_id, project_id, candidate_id)
  references public.candidates (organization_id, project_id, id) on delete cascade not valid;
alter table public.outreach_events validate constraint outreach_events_candidate_scope_fk;
alter table public.email_deliveries add constraint email_deliveries_candidate_scope_fk
  foreign key (organization_id, project_id, candidate_id)
  references public.candidates (organization_id, project_id, id) on delete cascade not valid;
alter table public.email_deliveries validate constraint email_deliveries_candidate_scope_fk;
alter table public.email_deliveries add constraint email_deliveries_template_scope_fk
  foreign key (organization_id, template_id)
  references public.email_templates (organization_id, id) on delete set null (template_id) not valid;
alter table public.email_deliveries validate constraint email_deliveries_template_scope_fk;
alter table public.contact_preferences add constraint contact_preferences_candidate_scope_fk
  foreign key (organization_id, candidate_id)
  references public.candidates (organization_id, id) on delete cascade not valid;
alter table public.contact_preferences validate constraint contact_preferences_candidate_scope_fk;

create table if not exists public.research_segments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  code text not null,
  name text not null,
  audience_type text not null check (audience_type in ('consumer', 'professional')),
  description text,
  active boolean not null default true,
  sequence integer not null default 0,
  created_at timestamptz not null default now(),
  unique (project_id, code),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table if not exists public.respondents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  external_id text not null,
  segment_id uuid not null,
  respondent_type text not null check (respondent_type in ('Consumer', 'Dental Professional')),
  specialty_status text,
  age_child_age text,
  recruitment_source text,
  consent_status text not null default 'pending'
    check (consent_status in ('pending', 'granted', 'declined', 'withdrawn', 'expired', 'not_applicable')),
  stage text not null default 'Concept' check (stage in ('Concept', 'Product', 'Launch', 'Concept + Product')),
  status text not null default 'recruiting'
    check (status in ('recruiting', 'screening', 'scheduled', 'active', 'completed', 'dropped', 'archived')),
  workflow_status text not null default 'draft'
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')),
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  start_date date,
  end_date date,
  notes text,
  retention_review_at date,
  legal_hold boolean not null default false,
  purge_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, external_id),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade,
  foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete restrict
);
create index if not exists respondents_project_workflow_idx
  on public.respondents (organization_id, project_id, workflow_status, assigned_to);
create index if not exists respondents_segment_status_idx
  on public.respondents (project_id, segment_id, status);

create table if not exists public.respondent_contacts (
  respondent_id uuid primary key references public.respondents(id) on delete cascade,
  organization_id uuid not null,
  project_id uuid not null,
  contact_name text,
  email text,
  phone text,
  contact_reference text,
  preferred_channel text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade
);

create table if not exists public.consent_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  respondent_id uuid not null,
  version integer not null default 1 check (version > 0),
  status text not null check (status in ('pending', 'granted', 'declined', 'withdrawn', 'expired')),
  interview_allowed boolean not null default false,
  recording_allowed boolean not null default false,
  images_allowed boolean not null default false,
  quotation_allowed boolean not null default false,
  recontact_allowed boolean not null default false,
  granted_at timestamptz,
  withdrawn_at timestamptz,
  withdrawal_reason text,
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (respondent_id, version),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade
);
create index if not exists consent_records_respondent_status_idx
  on public.consent_records (respondent_id, status, version desc);

create table if not exists public.research_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  respondent_id uuid not null,
  segment_id uuid not null,
  pmf_layer text not null check (pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')),
  method text not null,
  session_date date not null default current_date,
  current_behavior text,
  biggest_hassle text,
  recent_incident text,
  current_action text,
  unmet_need text,
  limitations text,
  workflow_status text not null default 'draft'
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')),
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete restrict
);
create index if not exists research_sessions_review_idx
  on public.research_sessions (project_id, workflow_status, assigned_to, session_date desc);

create table if not exists public.hypotheses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  code text not null,
  pmf_layer text not null check (pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')),
  statement text not null,
  success_criteria text not null,
  decision_status text not null default 'open'
    check (decision_status in ('open', 'collecting', 'ready_for_review', 'supported', 'partial', 'contradicted', 'insufficient')),
  owner_id uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (project_id, code),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table if not exists public.pmf_metric_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  code text not null,
  pmf_layer text not null check (pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')),
  dimension text not null,
  label text not null,
  value_type text not null check (value_type in ('boolean', 'numeric', 'text')),
  unit text,
  sequence integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (project_id, code),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);

create table if not exists public.pmf_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  definition_id uuid not null,
  respondent_id uuid,
  session_id uuid,
  segment_id uuid not null,
  numeric_value numeric,
  boolean_value boolean,
  text_value text,
  source_link text,
  notes text,
  workflow_status text not null default 'draft'
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')),
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(numeric_value, boolean_value, text_value) = 1),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade,
  foreign key (organization_id, project_id, definition_id)
    references public.pmf_metric_definitions (organization_id, project_id, id) on delete restrict,
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete set null (respondent_id),
  foreign key (organization_id, project_id, session_id)
    references public.research_sessions (organization_id, project_id, id) on delete set null (session_id),
  foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete restrict
);
create index if not exists pmf_observations_matrix_idx
  on public.pmf_observations (project_id, definition_id, segment_id, workflow_status);

create table if not exists public.product_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  respondent_id uuid not null,
  segment_id uuid not null,
  event_date date not null default current_date,
  study_week integer not null default 0 check (study_week between 0 and 52),
  trigger_type text,
  trigger_description text,
  target_user text,
  session_duration_minutes numeric check (session_duration_minutes is null or session_duration_minutes >= 0),
  capture_success boolean,
  valid_image boolean,
  compare_used boolean,
  result_understood boolean,
  value_obtained boolean,
  action_taken boolean,
  shared_with_doctor boolean,
  main_friction text,
  notes text,
  workflow_status text not null default 'draft'
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')),
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete restrict
);
create index if not exists product_events_reuse_idx
  on public.product_events (project_id, segment_id, study_week, workflow_status);

create table if not exists public.value_exchange_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  respondent_id uuid not null,
  segment_id uuid not null,
  observed_at date not null default current_date,
  hardware_price numeric check (hardware_price is null or hardware_price >= 0),
  reasonable_price_min numeric check (reasonable_price_min is null or reasonable_price_min >= 0),
  reasonable_price_max numeric check (reasonable_price_max is null or reasonable_price_max >= 0),
  purchase_intent integer check (purchase_intent is null or purchase_intent between 1 and 5),
  preferred_offer text,
  subscription_plan text,
  commitment_type text,
  commitment_amount numeric check (commitment_amount is null or commitment_amount >= 0),
  main_objection text,
  post_trial_purchase_intent integer check (post_trial_purchase_intent is null or post_trial_purchase_intent between 1 and 5),
  notes text,
  workflow_status text not null default 'draft'
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')),
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (reasonable_price_min is null or reasonable_price_max is null or reasonable_price_min <= reasonable_price_max),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete restrict
);
create index if not exists value_exchange_segment_idx
  on public.value_exchange_observations (project_id, segment_id, hardware_price, workflow_status);

create table if not exists public.gate_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  pmf_layer text not null check (pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')),
  decision text not null check (decision in ('go', 'revise', 'stop', 'insufficient')),
  rationale text not null,
  snapshot jsonb not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (organization_id, project_id)
    references public.projects (organization_id, id) on delete cascade
);
create index if not exists gate_snapshots_layer_idx
  on public.gate_snapshots (project_id, pmf_layer, created_at desc);

create table if not exists public.research_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  respondent_id uuid not null,
  session_id uuid,
  bucket_id text not null check (bucket_id in ('aoi-consent', 'aoi-sources', 'aoi-recordings', 'aoi-oral-images')),
  object_path text not null,
  original_name text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  checksum text,
  consent_version integer,
  status text not null default 'active' check (status in ('active', 'restricted', 'withdrawn', 'archived')),
  retention_review_at date,
  legal_hold boolean not null default false,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (bucket_id, object_path),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, session_id)
    references public.research_sessions (organization_id, project_id, id) on delete set null (session_id),
  foreign key (respondent_id, consent_version)
    references public.consent_records (respondent_id, version) on delete restrict
);

alter table public.import_jobs drop constraint if exists import_jobs_file_format_check;
alter table public.import_jobs add constraint import_jobs_file_format_check
  check (file_format in ('csv', 'json', 'tsv', 'xlsx'));

alter table public.candidates
  add column if not exists workflow_status text not null default 'draft',
  add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
update public.candidates set assigned_to = coalesce(assigned_to, owner_id, created_by) where assigned_to is null;
alter table public.candidates drop constraint if exists candidates_assigned_to_fkey;
alter table public.candidates add constraint candidates_assigned_to_fkey
  foreign key (assigned_to) references public.profiles(id) on delete restrict;
alter table public.candidates add constraint candidates_project_scope_fk
  foreign key (organization_id, project_id)
  references public.projects (organization_id, id) on delete cascade not valid;
alter table public.candidates validate constraint candidates_project_scope_fk;
alter table public.candidates
  add constraint candidates_workflow_status_check
  check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')) not valid;
alter table public.candidates validate constraint candidates_workflow_status_check;

alter table public.evidence_records
  add column if not exists respondent_id uuid references public.respondents(id) on delete set null,
  add column if not exists session_id uuid references public.research_sessions(id) on delete set null,
  add column if not exists segment_id uuid references public.research_segments(id) on delete set null,
  add column if not exists pmf_layer text,
  add column if not exists dimension text,
  add column if not exists topic text,
  add column if not exists evidence_text text,
  add column if not exists evidence_type text,
  add column if not exists decision_relevance text,
  add column if not exists source_link text,
  add column if not exists follow_up_needed boolean not null default false,
  add column if not exists limitations text,
  add column if not exists workflow_status text not null default 'draft',
  add column if not exists assigned_to uuid references public.profiles(id) on delete set null,
  add column if not exists submitted_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_notes text,
  add column if not exists updated_at timestamptz not null default now();
update public.evidence_records set assigned_to = recorded_by where assigned_to is null;
alter table public.evidence_records drop constraint if exists evidence_records_assigned_to_fkey;
alter table public.evidence_records add constraint evidence_records_assigned_to_fkey
  foreign key (assigned_to) references public.profiles(id) on delete restrict;
alter table public.evidence_records
  add constraint evidence_records_pmf_layer_check
    check (pmf_layer is null or pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')) not valid,
  add constraint evidence_records_workflow_status_check
    check (workflow_status in ('draft', 'submitted', 'revision_requested', 'approved', 'archived')) not valid;
alter table public.evidence_records validate constraint evidence_records_pmf_layer_check;
alter table public.evidence_records validate constraint evidence_records_workflow_status_check;

alter table public.evidence_records
  add constraint evidence_records_candidate_scope_fk
    foreign key (organization_id, project_id, candidate_id)
    references public.candidates (organization_id, project_id, id) on delete set null (candidate_id) not valid,
  add constraint evidence_records_respondent_scope_fk
    foreign key (organization_id, project_id, respondent_id)
    references public.respondents (organization_id, project_id, id) on delete set null (respondent_id) not valid,
  add constraint evidence_records_session_scope_fk
    foreign key (organization_id, project_id, session_id)
    references public.research_sessions (organization_id, project_id, id) on delete set null (session_id) not valid,
  add constraint evidence_records_segment_scope_fk
    foreign key (organization_id, project_id, segment_id)
    references public.research_segments (organization_id, project_id, id) on delete set null (segment_id) not valid;
alter table public.evidence_records validate constraint evidence_records_candidate_scope_fk;
alter table public.evidence_records validate constraint evidence_records_respondent_scope_fk;
alter table public.evidence_records validate constraint evidence_records_session_scope_fk;
alter table public.evidence_records validate constraint evidence_records_segment_scope_fk;

create or replace function public.enforce_aoi_assignee_membership()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.assigned_to is null or not exists (
    select 1 from public.organization_memberships m
    where m.organization_id = new.organization_id
      and m.user_id = new.assigned_to
      and m.status = 'active'
  ) then
    raise exception 'ASSIGNEE_MEMBERSHIP_REQUIRED';
  end if;
  return new;
end; $$;

create or replace function public.enforce_aoi_research_workflow()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if public.is_org_admin(old.organization_id) then return new; end if;
  if old.organization_id is not distinct from new.organization_id
    and old.project_id is not distinct from new.project_id
    and old.assigned_to is not distinct from new.assigned_to
    and old.workflow_status is not distinct from new.workflow_status
    and old.reviewed_by is not distinct from new.reviewed_by
    and old.reviewed_at is not distinct from new.reviewed_at
    and old.review_notes is not distinct from new.review_notes then
    return new;
  end if;
  if old.organization_id is distinct from new.organization_id
    or old.project_id is distinct from new.project_id
    or old.assigned_to is distinct from new.assigned_to then
    raise exception 'RESEARCH_SCOPE_IMMUTABLE';
  end if;
  if old.workflow_status = 'submitted' then raise exception 'SUBMITTED_RECORD_LOCKED'; end if;
  if new.workflow_status not in ('draft', 'submitted', 'revision_requested') then
    raise exception 'ADMIN_REVIEW_REQUIRED';
  end if;
  if old.reviewed_by is distinct from new.reviewed_by
    or old.reviewed_at is distinct from new.reviewed_at
    or old.review_notes is distinct from new.review_notes then
    raise exception 'REVIEW_FIELDS_ADMIN_ONLY';
  end if;
  return new;
end; $$;

create or replace function public.enforce_aoi_candidate_workflow()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if public.is_org_admin(old.organization_id) then return new; end if;
  if old.organization_id is distinct from new.organization_id
    or old.project_id is distinct from new.project_id
    or old.assigned_to is distinct from new.assigned_to then
    raise exception 'CANDIDATE_SCOPE_IMMUTABLE';
  end if;
  if old.workflow_status = 'submitted' then raise exception 'SUBMITTED_RECORD_LOCKED'; end if;
  if new.workflow_status <> 'draft' then
    raise exception 'ADMIN_REVIEW_REQUIRED';
  end if;
  return new;
end; $$;

create or replace function public.validate_aoi_observation_value()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_value_type text;
begin
  select d.value_type into v_value_type
  from public.pmf_metric_definitions d
  where d.id = new.definition_id
    and d.organization_id = new.organization_id
    and d.project_id = new.project_id;
  if v_value_type is null
    or (v_value_type = 'numeric' and new.numeric_value is null)
    or (v_value_type = 'boolean' and new.boolean_value is null)
    or (v_value_type = 'text' and nullif(new.text_value, '') is null) then
    raise exception 'OBSERVATION_VALUE_TYPE_MISMATCH';
  end if;
  return new;
end; $$;

create or replace function public.sync_aoi_consent_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_current public.consent_records%rowtype;
begin
  select c.* into v_current from public.consent_records c
  where c.respondent_id = new.respondent_id
  order by c.version desc limit 1;
  update public.respondents r
  set consent_status = v_current.status, updated_at = now()
  where r.id = v_current.respondent_id
    and r.organization_id = v_current.organization_id
    and r.project_id = v_current.project_id;
  if v_current.status <> 'granted' then
    update public.research_attachments a set status = 'withdrawn'
    where a.respondent_id = v_current.respondent_id and a.status = 'active'
      and a.bucket_id in ('aoi-recordings', 'aoi-oral-images');
  end if;
  return new;
end; $$;

create or replace function public.validate_aoi_session_respondent()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_respondent_id uuid;
begin
  if new.session_id is null then return new; end if;
  select s.respondent_id into v_respondent_id from public.research_sessions s
  where s.id = new.session_id and s.organization_id = new.organization_id and s.project_id = new.project_id;
  if v_respondent_id is null then raise exception 'SESSION_SCOPE_INVALID'; end if;
  if new.respondent_id is null then new.respondent_id := v_respondent_id; end if;
  if new.respondent_id <> v_respondent_id then raise exception 'SESSION_RESPONDENT_MISMATCH'; end if;
  return new;
end; $$;

create or replace function public.validate_aoi_attachment_path()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.object_path not like new.project_id::text || '/' || new.respondent_id::text || '/%' then
    raise exception 'ATTACHMENT_PATH_SCOPE_INVALID';
  end if;
  return new;
end; $$;

do $$
declare v_table text;
begin
  foreach v_table in array array['respondents','research_sessions','pmf_observations','product_events','value_exchange_observations','evidence_records'] loop
    execute format('drop trigger if exists enforce_aoi_assignee_membership on public.%I', v_table);
    execute format('create trigger enforce_aoi_assignee_membership before insert or update of assigned_to, organization_id on public.%I for each row execute function public.enforce_aoi_assignee_membership()', v_table);
    execute format('drop trigger if exists enforce_aoi_research_workflow on public.%I', v_table);
    execute format('create trigger enforce_aoi_research_workflow before update on public.%I for each row execute function public.enforce_aoi_research_workflow()', v_table);
  end loop;
end; $$;
drop trigger if exists enforce_aoi_assignee_membership on public.candidates;
create trigger enforce_aoi_assignee_membership before insert or update of assigned_to, organization_id on public.candidates
  for each row execute function public.enforce_aoi_assignee_membership();
drop trigger if exists enforce_aoi_candidate_workflow on public.candidates;
create trigger enforce_aoi_candidate_workflow before update on public.candidates
  for each row execute function public.enforce_aoi_candidate_workflow();
drop trigger if exists validate_aoi_observation_value on public.pmf_observations;
create trigger validate_aoi_observation_value before insert or update on public.pmf_observations
  for each row execute function public.validate_aoi_observation_value();
drop trigger if exists sync_aoi_consent_status on public.consent_records;
create trigger sync_aoi_consent_status after insert on public.consent_records
  for each row execute function public.sync_aoi_consent_status();
drop trigger if exists validate_aoi_session_respondent on public.evidence_records;
create trigger validate_aoi_session_respondent before insert or update of respondent_id, session_id on public.evidence_records
  for each row execute function public.validate_aoi_session_respondent();
drop trigger if exists validate_aoi_session_respondent on public.pmf_observations;
create trigger validate_aoi_session_respondent before insert or update of respondent_id, session_id on public.pmf_observations
  for each row execute function public.validate_aoi_session_respondent();
drop trigger if exists validate_aoi_session_respondent on public.research_attachments;
create trigger validate_aoi_session_respondent before insert or update of respondent_id, session_id on public.research_attachments
  for each row execute function public.validate_aoi_session_respondent();
drop trigger if exists validate_aoi_attachment_path on public.research_attachments;
create trigger validate_aoi_attachment_path before insert or update on public.research_attachments
  for each row execute function public.validate_aoi_attachment_path();

alter table public.research_segments enable row level security;
alter table public.respondents enable row level security;
alter table public.respondent_contacts enable row level security;
alter table public.consent_records enable row level security;
alter table public.research_sessions enable row level security;
alter table public.hypotheses enable row level security;
alter table public.pmf_metric_definitions enable row level security;
alter table public.pmf_observations enable row level security;
alter table public.product_events enable row level security;
alter table public.value_exchange_observations enable row level security;
alter table public.gate_snapshots enable row level security;
alter table public.research_attachments enable row level security;

-- Reference data is visible to active members and mutable only by administrators.
drop policy if exists research_segments_member_read on public.research_segments;
create policy research_segments_member_read on public.research_segments for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists research_segments_admin_write on public.research_segments;
create policy research_segments_admin_write on public.research_segments for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

drop policy if exists hypotheses_member_read on public.hypotheses;
create policy hypotheses_member_read on public.hypotheses for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists hypotheses_admin_write on public.hypotheses;
create policy hypotheses_admin_write on public.hypotheses for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

drop policy if exists metric_definitions_member_read on public.pmf_metric_definitions;
create policy metric_definitions_member_read on public.pmf_metric_definitions for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists metric_definitions_admin_write on public.pmf_metric_definitions;
create policy metric_definitions_admin_write on public.pmf_metric_definitions for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

-- Analytical rows are project-visible after approval; drafts remain assignment-scoped.
drop policy if exists respondents_read on public.respondents;
create policy respondents_read on public.respondents for select to authenticated using (
  public.is_org_admin(organization_id)
  or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
drop policy if exists respondents_insert on public.respondents;
create policy respondents_insert on public.respondents for insert to authenticated with check (
  public.is_org_member(organization_id)
  and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
);
drop policy if exists respondents_update on public.respondents;
create policy respondents_update on public.respondents for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists respondent_contacts_read on public.respondent_contacts;
create policy respondent_contacts_read on public.respondent_contacts for select to authenticated using (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);
drop policy if exists respondent_contacts_write on public.respondent_contacts;
create policy respondent_contacts_write on public.respondent_contacts for all to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid() and r.workflow_status not in ('submitted', 'approved', 'archived'))))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid())));

drop policy if exists consent_records_read on public.consent_records;
create policy consent_records_read on public.consent_records for select to authenticated using (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);
drop policy if exists consent_records_insert on public.consent_records;
create policy consent_records_insert on public.consent_records for insert to authenticated with check (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and recorded_by = auth.uid() and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);

drop policy if exists research_sessions_read on public.research_sessions;
create policy research_sessions_read on public.research_sessions for select to authenticated using (
  public.is_org_admin(organization_id)
  or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
drop policy if exists research_sessions_insert on public.research_sessions;
create policy research_sessions_insert on public.research_sessions for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
  and (public.is_org_admin(organization_id) or exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);
drop policy if exists research_sessions_update on public.research_sessions;
create policy research_sessions_update on public.research_sessions for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists pmf_observations_read on public.pmf_observations;
create policy pmf_observations_read on public.pmf_observations for select to authenticated using (
  public.is_org_admin(organization_id) or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
drop policy if exists pmf_observations_insert on public.pmf_observations;
create policy pmf_observations_insert on public.pmf_observations for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
);
drop policy if exists pmf_observations_update on public.pmf_observations;
create policy pmf_observations_update on public.pmf_observations for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists product_events_read on public.product_events;
create policy product_events_read on public.product_events for select to authenticated using (
  public.is_org_admin(organization_id) or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
drop policy if exists product_events_insert on public.product_events;
create policy product_events_insert on public.product_events for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
  and (public.is_org_admin(organization_id) or exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);
drop policy if exists product_events_update on public.product_events;
create policy product_events_update on public.product_events for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists value_exchange_read on public.value_exchange_observations;
create policy value_exchange_read on public.value_exchange_observations for select to authenticated using (
  public.is_org_admin(organization_id) or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
drop policy if exists value_exchange_insert on public.value_exchange_observations;
create policy value_exchange_insert on public.value_exchange_observations for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
  and (public.is_org_admin(organization_id) or exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid()))
);
drop policy if exists value_exchange_update on public.value_exchange_observations;
create policy value_exchange_update on public.value_exchange_observations for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists gate_snapshots_member_read on public.gate_snapshots;
create policy gate_snapshots_admin_read on public.gate_snapshots for select to authenticated
  using (public.is_org_admin(organization_id));
drop policy if exists gate_snapshots_admin_insert on public.gate_snapshots;
create policy gate_snapshots_admin_insert on public.gate_snapshots for insert to authenticated
  with check (public.is_org_admin(organization_id) and created_by = auth.uid());

drop policy if exists attachments_read on public.research_attachments;
create policy attachments_read on public.research_attachments for select to authenticated using (
  status = 'active' and (public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid())))
);
drop policy if exists attachments_insert on public.research_attachments;
create policy attachments_insert on public.research_attachments for insert to authenticated with check (
  uploaded_by = auth.uid() and public.is_org_member(organization_id) and (
    public.is_org_admin(organization_id)
    or exists (select 1 from public.respondents r where r.id = respondent_id and r.assigned_to = auth.uid())
  )
);
drop policy if exists attachments_admin_update on public.research_attachments;
create policy attachments_admin_update on public.research_attachments for update to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

-- Tighten the already-deployed outreach and email policies.
drop policy if exists candidates_member_read on public.candidates;
drop policy if exists candidates_member_write on public.candidates;
drop policy if exists candidates_member_update on public.candidates;
create policy candidates_assigned_read on public.candidates for select to authenticated using (
  public.is_org_admin(organization_id) or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
create policy candidates_assigned_insert on public.candidates for insert to authenticated with check (
  public.is_org_member(organization_id) and created_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
);
create policy candidates_assigned_update on public.candidates for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status = 'draft'));

drop policy if exists outreach_member_read on public.outreach_events;
drop policy if exists outreach_member_write on public.outreach_events;
create policy outreach_assigned_read on public.outreach_events for select to authenticated using (
  public.is_org_admin(organization_id)
  or (public.is_org_member(organization_id) and exists (select 1 from public.candidates c where c.id = candidate_id and c.assigned_to = auth.uid()))
);
create policy outreach_assigned_insert on public.outreach_events for insert to authenticated with check (
  actor_id = auth.uid() and public.is_org_member(organization_id) and (
    public.is_org_admin(organization_id)
    or exists (select 1 from public.candidates c where c.id = candidate_id and c.assigned_to = auth.uid())
  )
);

drop policy if exists evidence_member_read on public.evidence_records;
drop policy if exists evidence_member_write on public.evidence_records;
create policy evidence_assigned_read on public.evidence_records for select to authenticated using (
  public.is_org_admin(organization_id) or (assigned_to = auth.uid() and public.is_org_member(organization_id))
  or (workflow_status = 'approved' and public.is_org_member(organization_id))
);
create policy evidence_assigned_insert on public.evidence_records for insert to authenticated with check (
  public.is_org_member(organization_id) and recorded_by = auth.uid()
  and (assigned_to = auth.uid() or public.is_org_admin(organization_id))
);
create policy evidence_assigned_update on public.evidence_records for update to authenticated
  using (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status not in ('submitted', 'approved', 'archived')))
  with check (public.is_org_admin(organization_id) or (public.is_org_member(organization_id) and assigned_to = auth.uid() and workflow_status in ('draft', 'submitted', 'revision_requested')));

drop policy if exists email_templates_admin_read on public.email_templates;
drop policy if exists email_deliveries_member_read on public.email_deliveries;
drop policy if exists contact_preferences_member_read on public.contact_preferences;
create policy email_templates_admin_read on public.email_templates for select to authenticated
  using (public.is_org_admin(organization_id));
create policy email_deliveries_admin_read on public.email_deliveries for select to authenticated
  using (public.is_org_admin(organization_id));
drop policy if exists email_deliveries_admin_insert on public.email_deliveries;
create policy email_deliveries_admin_insert on public.email_deliveries for insert to authenticated
  with check (public.is_org_admin(organization_id) and created_by = auth.uid());
create policy contact_preferences_admin_read on public.contact_preferences for select to authenticated
  using (public.is_org_admin(organization_id));
drop policy if exists import_admin_insert on public.import_jobs;
create policy import_admin_insert on public.import_jobs for insert to authenticated
  with check (public.is_org_admin(organization_id) and created_by = auth.uid());
drop policy if exists import_admin_update on public.import_jobs;
create policy import_admin_update on public.import_jobs for update to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));
drop policy if exists audit_actor_insert on public.audit_events;
create policy audit_actor_insert on public.audit_events for insert to authenticated
  with check (public.is_org_member(organization_id) and actor_id = auth.uid());

-- Remove the unsafe broad profile update policy. Profile changes use controlled workflows.
drop policy if exists profiles_self_update on public.profiles;

-- Seed the project methodology.
insert into public.research_segments (organization_id, project_id, code, name, audience_type, sequence) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','families','Families with Children','consumer',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','orthodontic','Adult Orthodontic Patients','consumer',2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','implant','Implant Maintenance','consumer',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','oral-care','Highly Engaged Oral-Care Adults','consumer',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','pediatric-dentist','Pediatric Dentists','professional',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','orthodontist','Orthodontists','professional',6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','implant-dentist','Implant / Periodontal Dentists','professional',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','cosmetic-dentist','Cosmetic / Restorative Dentists','professional',8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','hygienist','General Dentists / Dental Hygienists','professional',9)
on conflict (project_id, code) do update set name = excluded.name, audience_type = excluded.audience_type, sequence = excluded.sequence;

insert into public.hypotheses (organization_id, project_id, code, pmf_layer, statement, success_criteria) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H1','H1','Important, recurring, image-visible, and actionable oral-health changes occur between routine dental visits.','At least one segment meets predefined Frequency, Significance, Visibility, and Actionability thresholds.'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H2','H2','Current solutions do not reliably complete the full Capture, Compare, Understand, and Act task.','At least one segment shows a frequent failure point, genuine dissatisfaction, and readiness to switch.'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H3','H3','Ambiloop performs the Capture, Compare, Understand, and Act task better than current alternatives.','Core task success, comprehension, or action metrics outperform current alternatives.'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H4','H4','Target users have natural recurring triggers and continue to reuse the product and obtain value in Weeks 1, 2, and 4.','A primary repeat trigger is identified and Week 4 reuse and repeated-value standards are met.'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H5','H5','Ambiloop value is strong enough to drive real purchase, subscription, or another commercial commitment.','$259 acceptance, commitment, post-trial purchase, or paid retention meets the predefined standard.')
on conflict (project_id, code) do update set statement = excluded.statement, success_criteria = excluded.success_criteria;

insert into public.pmf_metric_definitions (organization_id, project_id, code, pmf_layer, dimension, label, value_type, unit, sequence) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','recent_change_rate','H1','Frequency','Share experiencing target changes in the past six months','boolean','percent',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','change_events_per_user','H1','Frequency','Average target-change events per user','numeric','events',2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','clinician_importance','H1','Significance','Clinician-rated importance','numeric','score',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','user_importance','H1','Significance','User-perceived importance','numeric','score',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','image_visible_rate','H1','Visibility','Share observable through oral images','boolean','percent',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','professional_exam_required','H1','Visibility','Share requiring professional examination','boolean','percent',6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','effective_next_action','H1','Actionability','Observed changes with an effective next action','boolean','percent',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','current_observation_behavior','H2','Current Behavior','Actively observed, photographed, consulted, or returned early','boolean','percent',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','current_solution','H2','Current Behavior','Primary current solution','text',null,2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','current_task_completion','H2','Alternative Coverage','Current solution task-completion rate','boolean','percent',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','capture_failure','H2','Failure Point','Capture failure severity','numeric','score',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','compare_failure','H2','Failure Point','Compare failure severity','numeric','score',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','understand_failure','H2','Failure Point','Understand failure severity','numeric','score',6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','act_failure','H2','Failure Point','Act failure severity','numeric','score',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','switching_readiness','H2','Switching Readiness','Willingness to try a new solution','numeric','score',8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','capture_success','H3','Capture','First independent capture success','boolean','percent',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','valid_image_rate','H3','Capture','Valid-image rate','boolean','percent',2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','same_area_repeat','H3','Compare','Same-area repeat-capture success','boolean','percent',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','result_comprehension','H3','Understand','Correct result-comprehension rate','boolean','percent',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','clinician_agreement','H3','Compare','Clinician agreement on detected changes','boolean','percent',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','care_action','H3','Act','At-home care action rate','boolean','percent',6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','doctor_sharing','H3','Act','Image or report sharing with clinicians','boolean','percent',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','first_value','H3','Overall','First-value attainment rate','boolean','percent',8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','natural_trigger_frequency','H4','Recurring Trigger','Natural-trigger frequency','numeric','events',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','week_1_reuse','H4','Actual Reuse','Week 1 reuse','boolean','percent',2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','week_2_reuse','H4','Actual Reuse','Week 2 reuse','boolean','percent',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','week_4_reuse','H4','Actual Reuse','Week 4 reuse','boolean','percent',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','value_per_session','H4','Repeated Value','Value obtained per session','boolean','percent',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','workflow_convenience','H4','Routine Fit','Workflow convenience','numeric','score',6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','week_4_retention','H4','Retention','Week 4 active retention','boolean','percent',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','paid_value','H5','Paid Value','Primary paid value','text',null,1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','purchase_intent_229','H5','Price Acceptance','Purchase intent at $229','numeric','score',2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','purchase_intent_259','H5','Price Acceptance','Purchase intent at $259','numeric','score',3),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','purchase_intent_299','H5','Price Acceptance','Purchase intent at $299','numeric','score',4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','price_ceiling','H5','Price Acceptance','Price ceiling','numeric','USD',5),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','preferred_offer','H5','Offer Fit','Preferred purchase offer','text',null,6),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','plan_599','H5','Subscription Fit','$5.99 plan selection','boolean','percent',7),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','plan_999','H5','Subscription Fit','$9.99 plan selection','boolean','percent',8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','subscription_rejection','H5','Subscription Fit','Rejecting subscription','boolean','percent',9),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','waitlist_conversion','H5','Real Commitment','Waitlist conversion','boolean','percent',10),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','deposit_payment','H5','Real Commitment','Small-deposit payment','boolean','percent',11),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','post_trial_purchase','H5','Post-Trial Value','Post-trial actual purchase','boolean','percent',12)
on conflict (project_id, code) do update set dimension = excluded.dimension, label = excluded.label, value_type = excluded.value_type, unit = excluded.unit, sequence = excluded.sequence;

-- Repair deployed operation functions with unambiguous names and invoker security.
drop function if exists public.rpc_aoi_operations_snapshot();
create function public.rpc_aoi_operations_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
begin
  select m.organization_id into v_org_id
  from public.organization_memberships m
  where m.user_id = auth.uid() and m.status = 'active'
  order by case m.role when 'admin' then 1 else 2 end limit 1;
  select p.id into v_project_id from public.projects p
  where p.organization_id = v_org_id and p.status = 'active' order by p.created_at limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object(
    'candidates', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'externalId', c.external_id, 'name', c.name, 'category', c.category,
      'platforms', c.platforms, 'reach', c.reach, 'tier', c.tier,
      'creatorType', c.creator_type, 'fitLevel', c.fit_level,
      'contactReadiness', c.contact_readiness, 'contactChannel', c.contact_channel,
      'contactDetail', c.contact_detail, 'sourceUrl', c.source_url,
      'pmfCandidate', c.pmf_candidate, 'priorityScore', c.priority_score,
      'pmfRationale', c.pmf_rationale, 'priorityBand', c.priority_band,
      'ownerId', c.assigned_to, 'ownerName', pr.display_name,
      'outreachStatus', c.outreach_status, 'interestLevel', c.interest_level,
      'preferredCollaboration', c.preferred_collaboration, 'deckIntroduced', c.deck_introduced,
      'pmfAsked', c.pmf_asked, 'firstOutreach', c.first_outreach,
      'nextStep', c.next_step, 'nextStepDue', c.next_step_due,
      'notes', c.notes, 'workflowStatus', c.workflow_status, 'lastUpdated', c.updated_at::date
    ) order by c.priority_score desc, c.next_step_due nulls last)
      from public.candidates c left join public.profiles pr on pr.id = c.assigned_to
      where c.project_id = v_project_id), '[]'::jsonb),
    'outreachEvents', coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'candidateId', e.candidate_id, 'channel', e.channel, 'kind', e.kind,
      'status', e.status, 'occurredAt', e.occurred_at, 'actorName', coalesce(pr.display_name, 'AOI'), 'summary', e.summary
    ) order by e.occurred_at desc) from public.outreach_events e
      left join public.profiles pr on pr.id = e.actor_id where e.project_id = v_project_id), '[]'::jsonb),
    'evidenceRecords', coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'candidateId', e.candidate_id, 'type', e.type, 'stance', e.stance,
      'strength', e.strength, 'title', e.title, 'notes', e.notes,
      'consentStatus', e.consent_status, 'recordedBy', coalesce(pr.display_name, 'AOI'),
      'recordedAt', e.recorded_at, 'workflowStatus', e.workflow_status
    ) order by e.recorded_at desc) from public.evidence_records e
      left join public.profiles pr on pr.id = e.recorded_by where e.project_id = v_project_id), '[]'::jsonb)
  );
end; $$;

drop function if exists public.rpc_aoi_upsert_candidate(jsonb);
create function public.rpc_aoi_upsert_candidate(p_candidate jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_owner_id uuid;
  v_candidate_id uuid;
  v_owner_requested boolean := false;
  v_result public.candidates%rowtype;
begin
  select m.organization_id, m.role into v_org_id, v_role from public.organization_memberships m
  where m.user_id = auth.uid() and m.status = 'active'
  order by case m.role when 'admin' then 1 else 2 end limit 1;
  select p.id into v_project_id from public.projects p
  where p.organization_id = v_org_id and p.status = 'active' order by p.created_at limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if length(trim(coalesce(p_candidate->>'name', ''))) < 2 then raise exception 'CANDIDATE_NAME_REQUIRED'; end if;
  if coalesce(p_candidate->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_candidate_id := (p_candidate->>'id')::uuid;
  elsif nullif(p_candidate->>'externalId', '') is not null then
    select c.id into v_candidate_id from public.candidates c
    where c.project_id = v_project_id and c.external_id = p_candidate->>'externalId';
  end if;
  if v_candidate_id is not null then
    select c.assigned_to into v_owner_id from public.candidates c
    where c.id = v_candidate_id and c.organization_id = v_org_id and c.project_id = v_project_id;
    if v_owner_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  else
    v_owner_id := auth.uid();
  end if;
  if v_role = 'admin' and nullif(p_candidate->>'ownerId', '') is not null then
    v_owner_requested := true;
    select m.user_id into v_owner_id from public.organization_memberships m
    where m.organization_id = v_org_id and m.user_id = (p_candidate->>'ownerId')::uuid and m.status = 'active';
  elsif v_role = 'admin' and nullif(p_candidate->>'ownerName', '') is not null then
    v_owner_requested := true;
    select m.user_id into v_owner_id
    from public.organization_memberships m join public.profiles p on p.id = m.user_id
    where m.organization_id = v_org_id and m.status = 'active'
      and lower(p.display_name) = lower(trim(p_candidate->>'ownerName'))
    order by m.joined_at limit 1;
  end if;
  if v_owner_requested and v_owner_id is null then raise exception 'CANDIDATE_OWNER_INVALID'; end if;
  if v_candidate_id is not null then
    update public.candidates c set
      name = trim(p_candidate->>'name'), category = coalesce(nullif(p_candidate->>'category',''), c.category),
      platforms = p_candidate->>'platforms', reach = p_candidate->>'reach', tier = p_candidate->>'tier',
      creator_type = p_candidate->>'creatorType', fit_level = p_candidate->>'fitLevel',
      contact_readiness = coalesce(nullif(p_candidate->>'contactReadiness',''), c.contact_readiness),
      contact_channel = p_candidate->>'contactChannel', contact_detail = p_candidate->>'contactDetail',
      source_url = p_candidate->>'sourceUrl', pmf_candidate = coalesce((p_candidate->>'pmfCandidate')::boolean, false),
      pmf_rationale = p_candidate->>'pmfRationale',
      owner_id = v_owner_id, assigned_to = v_owner_id,
      outreach_status = coalesce(nullif(p_candidate->>'outreachStatus',''), c.outreach_status),
      interest_level = coalesce(nullif(p_candidate->>'interestLevel',''), c.interest_level),
      preferred_collaboration = p_candidate->>'preferredCollaboration',
      deck_introduced = coalesce((p_candidate->>'deckIntroduced')::boolean, c.deck_introduced),
      pmf_asked = coalesce((p_candidate->>'pmfAsked')::boolean, c.pmf_asked),
      first_outreach = nullif(p_candidate->>'firstOutreach','')::date,
      next_step = p_candidate->>'nextStep', next_step_due = nullif(p_candidate->>'nextStepDue','')::date,
      notes = p_candidate->>'notes', updated_at = now()
    where c.id = v_candidate_id and c.organization_id = v_org_id and c.project_id = v_project_id returning c.* into v_result;
  else
    insert into public.candidates (
      organization_id, project_id, external_id, name, category, platforms, reach, tier,
      creator_type, fit_level, contact_readiness, contact_channel, contact_detail, source_url,
      pmf_candidate, pmf_rationale, owner_id, assigned_to, outreach_status, interest_level,
      preferred_collaboration, deck_introduced, pmf_asked, first_outreach,
      next_step, next_step_due, notes, created_by
    ) values (
      v_org_id, v_project_id,
      case when coalesce(p_candidate->>'externalId','') like 'local-%' then null else nullif(p_candidate->>'externalId','') end,
      trim(p_candidate->>'name'), coalesce(nullif(p_candidate->>'category',''), 'Other / Discovery'),
      p_candidate->>'platforms', p_candidate->>'reach', p_candidate->>'tier',
      p_candidate->>'creatorType', p_candidate->>'fitLevel',
      coalesce(nullif(p_candidate->>'contactReadiness',''), 'Research needed'),
      p_candidate->>'contactChannel', p_candidate->>'contactDetail', p_candidate->>'sourceUrl',
      coalesce((p_candidate->>'pmfCandidate')::boolean, false), p_candidate->>'pmfRationale',
      v_owner_id, v_owner_id, coalesce(nullif(p_candidate->>'outreachStatus',''), 'Not Contacted'),
      coalesce(nullif(p_candidate->>'interestLevel',''), 'Unknown'), p_candidate->>'preferredCollaboration',
      coalesce((p_candidate->>'deckIntroduced')::boolean, false), coalesce((p_candidate->>'pmfAsked')::boolean, false),
      nullif(p_candidate->>'firstOutreach','')::date,
      p_candidate->>'nextStep', nullif(p_candidate->>'nextStepDue','')::date, p_candidate->>'notes', auth.uid()
    ) returning * into v_result;
  end if;
  if v_result.id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'candidate', v_result.id, 'upsert', jsonb_build_object('name', v_result.name));
  return jsonb_build_object('id', v_result.id, 'externalId', v_result.external_id, 'name', v_result.name,
    'category', v_result.category, 'ownerId', v_result.assigned_to,
    'outreachStatus', v_result.outreach_status, 'workflowStatus', v_result.workflow_status);
end; $$;

drop function if exists public.rpc_aoi_log_outreach(uuid,text,text,text,text);
create function public.rpc_aoi_log_outreach(p_candidate_id uuid, p_event_channel text, p_event_kind text, p_event_status text, p_event_summary text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_result public.outreach_events%rowtype;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id = auth.uid() and m.status = 'active' limit 1;
  select c.project_id into v_project_id from public.candidates c where c.id = p_candidate_id and c.organization_id = v_org_id;
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  insert into public.outreach_events (organization_id, project_id, candidate_id, channel, kind, status, actor_id, summary)
  values (v_org_id, v_project_id, p_candidate_id, p_event_channel, p_event_kind, p_event_status, auth.uid(), trim(p_event_summary)) returning * into v_result;
  update public.candidates c set outreach_status = case when p_event_status in ('Sent','Replied','Interested','Confirmed') then p_event_status else c.outreach_status end,
    updated_at = now() where c.id = p_candidate_id;
  return jsonb_build_object('id', v_result.id, 'candidateId', v_result.candidate_id);
end; $$;

drop function if exists public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text);
create function public.rpc_aoi_add_evidence(p_candidate_id uuid, p_evidence_type text, p_evidence_stance text, p_evidence_strength integer, p_evidence_title text, p_evidence_notes text, p_evidence_consent text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_segment_id uuid; v_result public.evidence_records%rowtype;
begin
  select m.organization_id into v_org_id from public.organization_memberships m
  where m.user_id = auth.uid() and m.status = 'active'
  order by case m.role when 'admin' then 1 else 2 end, m.joined_at limit 1;
  select c.project_id into v_project_id from public.candidates c
  where c.id = p_candidate_id and c.organization_id = v_org_id
    and (c.assigned_to = auth.uid() or public.is_org_admin(c.organization_id));
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if trim(coalesce(p_evidence_title, '')) = '' then raise exception 'EVIDENCE_TITLE_REQUIRED'; end if;
  insert into public.evidence_records (
    organization_id, project_id, candidate_id, segment_id, pmf_layer, type, evidence_type,
    stance, strength, title, notes, consent_status, workflow_status, assigned_to, recorded_by
  ) values (
    v_org_id, v_project_id, p_candidate_id, v_segment_id, null,
    coalesce(nullif(p_evidence_type, ''), 'PMF interview'), coalesce(nullif(p_evidence_type, ''), 'PMF interview'),
    p_evidence_stance, greatest(1, least(4, coalesce(p_evidence_strength, 1))), trim(p_evidence_title),
    p_evidence_notes, coalesce(nullif(p_evidence_consent, ''), 'pending'), 'draft', auth.uid(), auth.uid()
  ) returning * into v_result;
  return jsonb_build_object('id', v_result.id, 'candidateId', v_result.candidate_id);
end; $$;

drop function if exists public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid);
create function public.rpc_aoi_queue_email(p_candidate_id uuid, p_recipient text, p_email_subject text, p_email_body text, p_send_at timestamptz default now(), p_template_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_delivery public.email_deliveries%rowtype;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id = auth.uid() and m.status = 'active' limit 1;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_APPROVAL_REQUIRED'; end if;
  select c.project_id into v_project_id from public.candidates c where c.id = p_candidate_id and c.organization_id = v_org_id;
  if v_project_id is null then raise exception 'CANDIDATE_NOT_FOUND'; end if;
  if exists (select 1 from public.contact_preferences preference where preference.candidate_id = p_candidate_id and preference.email_opt_out) then raise exception 'EMAIL_OPTED_OUT'; end if;
  insert into public.email_deliveries (organization_id, project_id, candidate_id, template_id, recipient, subject, body, scheduled_for, created_by)
  values (v_org_id, v_project_id, p_candidate_id, p_template_id, trim(p_recipient), trim(p_email_subject), p_email_body, p_send_at, auth.uid()) returning * into v_delivery;
  return jsonb_build_object('id', v_delivery.id, 'status', v_delivery.status, 'scheduledFor', v_delivery.scheduled_for);
end; $$;

create or replace function public.rpc_aoi_import_candidates(p_rows jsonb, p_file_name text, p_file_format text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_row jsonb; v_count integer := 0; v_job_id uuid;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id = auth.uid() and m.status = 'active' limit 1;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select p.id into v_project_id from public.projects p where p.organization_id = v_org_id and p.status = 'active' order by p.created_at limit 1;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'IMPORT_ROWS_REQUIRED'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'IMPORT_TOO_LARGE'; end if;
  insert into public.import_jobs (organization_id, project_id, file_name, file_format, row_count, status, created_by)
  values (v_org_id, v_project_id, p_file_name, p_file_format, jsonb_array_length(p_rows), 'previewed', auth.uid()) returning id into v_job_id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    perform public.rpc_aoi_upsert_candidate(v_row);
    v_count := v_count + 1;
  end loop;
  update public.import_jobs set status = 'committed' where id = v_job_id;
  return jsonb_build_object('jobId', v_job_id, 'imported', v_count);
end; $$;

create or replace function public.rpc_aoi_save_research_record(p_record_type text, p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_org_id uuid; v_project_id uuid; v_status text; v_id uuid;
  v_segment_id uuid; v_respondent_id uuid; v_session_id uuid;
  v_definition public.pmf_metric_definitions%rowtype;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id = auth.uid() and m.status = 'active' limit 1;
  select p.id into v_project_id from public.projects p where p.organization_id = v_org_id and p.status = 'active' order by p.created_at limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  v_status := coalesce(nullif(p_payload->>'workflowStatus',''), 'draft');
  if v_status not in ('draft','submitted') then raise exception 'WORKFLOW_STATUS_INVALID'; end if;
  select s.id into v_segment_id from public.research_segments s where s.project_id = v_project_id and s.code = p_payload->>'segmentCode' and s.active;

  if p_record_type = 'respondent' then
    if v_segment_id is null then raise exception 'SEGMENT_REQUIRED'; end if;
    if v_status = 'submitted' and p_payload->>'consentStatus' <> 'granted' then raise exception 'CONSENT_REQUIRED'; end if;
    insert into public.respondents (
      organization_id, project_id, external_id, segment_id, respondent_type, specialty_status,
      age_child_age, recruitment_source, consent_status, stage, status, workflow_status,
      assigned_to, created_by, submitted_at, start_date, end_date, notes, retention_review_at
    ) values (
      v_org_id, v_project_id, coalesce(nullif(p_payload->>'externalId',''), 'R-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
      v_segment_id, p_payload->>'respondentType', p_payload->>'specialtyStatus', p_payload->>'ageChildAge',
      p_payload->>'recruitmentSource', coalesce(nullif(p_payload->>'consentStatus',''), 'pending'),
      coalesce(nullif(p_payload->>'stage',''), 'Concept'), coalesce(nullif(p_payload->>'status',''), 'recruiting'),
      v_status, auth.uid(), auth.uid(), case when v_status = 'submitted' then now() end,
      nullif(p_payload->>'startDate','')::date, nullif(p_payload->>'endDate','')::date,
      p_payload->>'notes', nullif(p_payload->>'retentionReviewAt','')::date
    ) returning id into v_id;
    if coalesce(nullif(p_payload->>'contactName', ''), nullif(p_payload->>'email', ''), nullif(p_payload->>'phone', ''), '') <> '' then
      insert into public.respondent_contacts (respondent_id, organization_id, project_id, contact_name, email, phone, contact_reference, preferred_channel, created_by)
      values (v_id, v_org_id, v_project_id, p_payload->>'contactName', p_payload->>'email', p_payload->>'phone', p_payload->>'contactReference', p_payload->>'preferredChannel', auth.uid());
    end if;
    if p_payload->>'consentStatus' in ('granted','declined') then
      insert into public.consent_records (organization_id, project_id, respondent_id, status, interview_allowed, recording_allowed, images_allowed, quotation_allowed, recontact_allowed, granted_at, recorded_by)
      values (v_org_id, v_project_id, v_id, p_payload->>'consentStatus',
        coalesce((p_payload->>'interviewAllowed')::boolean, false), coalesce((p_payload->>'recordingAllowed')::boolean, false),
        coalesce((p_payload->>'imagesAllowed')::boolean, false), coalesce((p_payload->>'quotationAllowed')::boolean, false),
        coalesce((p_payload->>'recontactAllowed')::boolean, false), case when p_payload->>'consentStatus' = 'granted' then now() end, auth.uid());
    end if;
  elsif p_record_type = 'session' then
    v_respondent_id := nullif(p_payload->>'respondentId','')::uuid;
    select r.segment_id into v_segment_id from public.respondents r
    where r.id = v_respondent_id and r.project_id = v_project_id
      and (r.assigned_to = auth.uid() or public.is_org_admin(r.organization_id));
    if v_segment_id is null then raise exception 'RESPONDENT_REQUIRED'; end if;
    insert into public.research_sessions (
      organization_id, project_id, respondent_id, segment_id, pmf_layer, method, session_date,
      current_behavior, biggest_hassle, recent_incident, current_action, unmet_need, limitations,
      workflow_status, assigned_to, created_by, submitted_at
    ) values (
      v_org_id, v_project_id, v_respondent_id, v_segment_id, p_payload->>'pmfLayer', p_payload->>'method',
      coalesce(nullif(p_payload->>'sessionDate','')::date, current_date), p_payload->>'currentBehavior',
      p_payload->>'biggestHassle', p_payload->>'recentIncident', p_payload->>'currentAction',
      p_payload->>'unmetNeed', p_payload->>'limitations', v_status, auth.uid(), auth.uid(),
      case when v_status = 'submitted' then now() end
    ) returning id into v_id;
  elsif p_record_type = 'evidence' then
    if v_status = 'submitted' and coalesce(nullif(p_payload->>'sourceLink',''), nullif(p_payload->>'sessionId','')) is null then raise exception 'SOURCE_REQUIRED'; end if;
    if v_status = 'submitted' and nullif(p_payload->>'limitations','') is null then raise exception 'LIMITATIONS_REQUIRED'; end if;
    v_respondent_id := nullif(p_payload->>'respondentId','')::uuid;
    v_session_id := nullif(p_payload->>'sessionId','')::uuid;
    if v_respondent_id is not null then
      select r.segment_id into v_segment_id from public.respondents r
      where r.id = v_respondent_id and r.project_id = v_project_id
        and (r.assigned_to = auth.uid() or public.is_org_admin(r.organization_id));
      if v_segment_id is null then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    end if;
    if v_session_id is not null and not exists (
      select 1 from public.research_sessions s where s.id = v_session_id and s.project_id = v_project_id
        and (s.assigned_to = auth.uid() or public.is_org_admin(s.organization_id))
    ) then raise exception 'SESSION_NOT_ASSIGNED'; end if;
    insert into public.evidence_records (
      organization_id, project_id, respondent_id, session_id, segment_id, pmf_layer, dimension, topic,
      type, evidence_type, stance, strength, title, evidence_text, notes, consent_status,
      decision_relevance, source_link, follow_up_needed, limitations, workflow_status,
      assigned_to, recorded_by, submitted_at
    ) values (
      v_org_id, v_project_id, v_respondent_id, v_session_id,
      v_segment_id, p_payload->>'pmfLayer', p_payload->>'dimension', p_payload->>'topic',
      coalesce(nullif(p_payload->>'evidenceType',''), 'Interview'), coalesce(nullif(p_payload->>'evidenceType',''), 'Interview'),
      p_payload->>'stance', greatest(1, least(4, coalesce((p_payload->>'strength')::integer, 1))),
      trim(p_payload->>'title'), p_payload->>'evidenceText', p_payload->>'notes',
      coalesce(nullif(p_payload->>'consentStatus',''), 'not_applicable'), p_payload->>'decisionRelevance',
      p_payload->>'sourceLink', coalesce((p_payload->>'followUpNeeded')::boolean, false), p_payload->>'limitations',
      v_status, auth.uid(), auth.uid(), case when v_status = 'submitted' then now() end
    ) returning id into v_id;
  elsif p_record_type = 'product_event' then
    v_respondent_id := nullif(p_payload->>'respondentId','')::uuid;
    select r.segment_id into v_segment_id from public.respondents r
    where r.id = v_respondent_id and r.project_id = v_project_id
      and (r.assigned_to = auth.uid() or public.is_org_admin(r.organization_id));
    if v_segment_id is null then raise exception 'RESPONDENT_REQUIRED'; end if;
    insert into public.product_events (
      organization_id, project_id, respondent_id, segment_id, event_date, study_week, trigger_type,
      trigger_description, target_user, session_duration_minutes, capture_success, valid_image,
      compare_used, result_understood, value_obtained, action_taken, shared_with_doctor,
      main_friction, notes, workflow_status, assigned_to, created_by, submitted_at
    ) values (
      v_org_id, v_project_id, v_respondent_id, v_segment_id, coalesce(nullif(p_payload->>'eventDate','')::date,current_date),
      coalesce((p_payload->>'studyWeek')::integer,0), p_payload->>'triggerType', p_payload->>'triggerDescription',
      p_payload->>'targetUser', nullif(p_payload->>'sessionDurationMinutes','')::numeric,
      nullif(p_payload->>'captureSuccess','')::boolean, nullif(p_payload->>'validImage','')::boolean,
      nullif(p_payload->>'compareUsed','')::boolean, nullif(p_payload->>'resultUnderstood','')::boolean,
      nullif(p_payload->>'valueObtained','')::boolean, nullif(p_payload->>'actionTaken','')::boolean,
      nullif(p_payload->>'sharedWithDoctor','')::boolean, p_payload->>'mainFriction', p_payload->>'notes',
      v_status, auth.uid(), auth.uid(), case when v_status = 'submitted' then now() end
    ) returning id into v_id;
  elsif p_record_type = 'value_exchange' then
    v_respondent_id := nullif(p_payload->>'respondentId','')::uuid;
    select r.segment_id into v_segment_id from public.respondents r
    where r.id = v_respondent_id and r.project_id = v_project_id
      and (r.assigned_to = auth.uid() or public.is_org_admin(r.organization_id));
    if v_segment_id is null then raise exception 'RESPONDENT_REQUIRED'; end if;
    insert into public.value_exchange_observations (
      organization_id, project_id, respondent_id, segment_id, observed_at, hardware_price,
      reasonable_price_min, reasonable_price_max, purchase_intent, preferred_offer, subscription_plan,
      commitment_type, commitment_amount, main_objection, post_trial_purchase_intent, notes,
      workflow_status, assigned_to, created_by, submitted_at
    ) values (
      v_org_id, v_project_id, v_respondent_id, v_segment_id, coalesce(nullif(p_payload->>'observedAt','')::date,current_date),
      nullif(p_payload->>'hardwarePrice','')::numeric, nullif(p_payload->>'reasonablePriceMin','')::numeric,
      nullif(p_payload->>'reasonablePriceMax','')::numeric, nullif(p_payload->>'purchaseIntent','')::integer,
      p_payload->>'preferredOffer', p_payload->>'subscriptionPlan', p_payload->>'commitmentType',
      nullif(p_payload->>'commitmentAmount','')::numeric, p_payload->>'mainObjection',
      nullif(p_payload->>'postTrialPurchaseIntent','')::integer, p_payload->>'notes',
      v_status, auth.uid(), auth.uid(), case when v_status = 'submitted' then now() end
    ) returning id into v_id;
  elsif p_record_type = 'observation' then
    select d.* into v_definition from public.pmf_metric_definitions d where d.id = (p_payload->>'definitionId')::uuid and d.project_id = v_project_id;
    if v_definition.id is null or v_segment_id is null then raise exception 'METRIC_AND_SEGMENT_REQUIRED'; end if;
    v_respondent_id := nullif(p_payload->>'respondentId','')::uuid;
    v_session_id := nullif(p_payload->>'sessionId','')::uuid;
    if v_respondent_id is not null and not exists (
      select 1 from public.respondents r where r.id = v_respondent_id and r.project_id = v_project_id
        and (r.assigned_to = auth.uid() or public.is_org_admin(r.organization_id))
    ) then raise exception 'RESPONDENT_NOT_ASSIGNED'; end if;
    if v_session_id is not null and not exists (
      select 1 from public.research_sessions s where s.id = v_session_id and s.project_id = v_project_id
        and (s.assigned_to = auth.uid() or public.is_org_admin(s.organization_id))
    ) then raise exception 'SESSION_NOT_ASSIGNED'; end if;
    insert into public.pmf_observations (
      organization_id, project_id, definition_id, respondent_id, session_id, segment_id,
      numeric_value, boolean_value, text_value, source_link, notes, workflow_status,
      assigned_to, created_by, submitted_at
    ) values (
      v_org_id, v_project_id, v_definition.id, v_respondent_id,
      v_session_id, v_segment_id,
      case when v_definition.value_type = 'numeric' then nullif(p_payload->>'numericValue','')::numeric end,
      case when v_definition.value_type = 'boolean' then nullif(p_payload->>'booleanValue','')::boolean end,
      case when v_definition.value_type = 'text' then nullif(p_payload->>'textValue','') end,
      p_payload->>'sourceLink', p_payload->>'notes', v_status, auth.uid(), auth.uid(),
      case when v_status = 'submitted' then now() end
    ) returning id into v_id;
  else
    raise exception 'RECORD_TYPE_INVALID';
  end if;
  return jsonb_build_object('id', v_id, 'recordType', p_record_type, 'workflowStatus', v_status);
end; $$;

create or replace function public.rpc_aoi_review_research_record(p_record_type text, p_record_id uuid, p_action text, p_notes text default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_status text;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id = auth.uid() and m.status = 'active' limit 1;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  v_status := case p_action when 'approve' then 'approved' when 'request_revision' then 'revision_requested' when 'archive' then 'archived' else null end;
  if v_status is null then raise exception 'REVIEW_ACTION_INVALID'; end if;
  if p_record_type = 'respondent' then update public.respondents set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  elsif p_record_type = 'session' then update public.research_sessions set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  elsif p_record_type = 'evidence' then update public.evidence_records set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  elsif p_record_type = 'product_event' then update public.product_events set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  elsif p_record_type = 'value_exchange' then update public.value_exchange_observations set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  elsif p_record_type = 'observation' then update public.pmf_observations set workflow_status=v_status, reviewed_by=auth.uid(), reviewed_at=now(), review_notes=p_notes, updated_at=now() where id=p_record_id and organization_id=v_org_id and workflow_status=case when v_status='archived' then 'approved' else 'submitted' end;
  else raise exception 'RECORD_TYPE_INVALID'; end if;
  if not found then raise exception 'RECORD_NOT_FOUND'; end if;
  return jsonb_build_object('id', p_record_id, 'recordType', p_record_type, 'workflowStatus', v_status);
end; $$;

create or replace function public.rpc_aoi_pmf_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id=auth.uid() and m.status='active' limit 1;
  select p.id into v_project_id from public.projects p where p.organization_id=v_org_id and p.status='active' order by p.created_at limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object(
    'segments', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name,'audienceType',s.audience_type) order by s.sequence) from public.research_segments s where s.project_id=v_project_id and s.active),'[]'::jsonb),
    'respondents', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'externalId',r.external_id,'segmentCode',s.code,'segmentName',s.name,'respondentType',r.respondent_type,'specialtyStatus',r.specialty_status,'recruitmentSource',r.recruitment_source,'consentStatus',r.consent_status,'status',r.status,'workflowStatus',r.workflow_status,'assignedTo',r.assigned_to,'createdAt',r.created_at) order by r.created_at desc) from public.respondents r join public.research_segments s on s.id=r.segment_id where r.project_id=v_project_id),'[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'respondentId',x.respondent_id,'segmentCode',s.code,'pmfLayer',x.pmf_layer,'method',x.method,'sessionDate',x.session_date,'unmetNeed',x.unmet_need,'workflowStatus',x.workflow_status,'createdAt',x.created_at) order by x.session_date desc) from public.research_sessions x join public.research_segments s on s.id=x.segment_id where x.project_id=v_project_id),'[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'respondentId',e.respondent_id,'sessionId',e.session_id,'segmentCode',s.code,'pmfLayer',e.pmf_layer,'dimension',e.dimension,'title',e.title,'evidenceText',e.evidence_text,'stance',e.stance,'strength',e.strength,'sourceLink',e.source_link,'limitations',e.limitations,'consentStatus',e.consent_status,'workflowStatus',e.workflow_status,'createdAt',e.created_at) order by e.created_at desc) from public.evidence_records e left join public.research_segments s on s.id=e.segment_id where e.project_id=v_project_id),'[]'::jsonb),
    'productEvents', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'respondentId',e.respondent_id,'segmentCode',s.code,'eventDate',e.event_date,'studyWeek',e.study_week,'triggerType',e.trigger_type,'captureSuccess',e.capture_success,'validImage',e.valid_image,'compareUsed',e.compare_used,'resultUnderstood',e.result_understood,'valueObtained',e.value_obtained,'actionTaken',e.action_taken,'sharedWithDoctor',e.shared_with_doctor,'mainFriction',e.main_friction,'workflowStatus',e.workflow_status,'createdAt',e.created_at) order by e.event_date desc) from public.product_events e join public.research_segments s on s.id=e.segment_id where e.project_id=v_project_id),'[]'::jsonb),
    'valueExchange', coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'respondentId',v.respondent_id,'segmentCode',s.code,'observedAt',v.observed_at,'hardwarePrice',v.hardware_price,'reasonablePriceMin',v.reasonable_price_min,'reasonablePriceMax',v.reasonable_price_max,'purchaseIntent',v.purchase_intent,'preferredOffer',v.preferred_offer,'subscriptionPlan',v.subscription_plan,'commitmentType',v.commitment_type,'commitmentAmount',v.commitment_amount,'mainObjection',v.main_objection,'postTrialPurchaseIntent',v.post_trial_purchase_intent,'workflowStatus',v.workflow_status,'createdAt',v.created_at) order by v.observed_at desc) from public.value_exchange_observations v join public.research_segments s on s.id=v.segment_id where v.project_id=v_project_id),'[]'::jsonb),
    'definitions', coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'code',d.code,'layer',d.pmf_layer,'dimension',d.dimension,'label',d.label,'valueType',d.value_type,'unit',d.unit) order by d.pmf_layer,d.sequence) from public.pmf_metric_definitions d where d.project_id=v_project_id and d.active),'[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'definitionId',o.definition_id,'respondentId',o.respondent_id,'segmentCode',s.code,'numericValue',o.numeric_value,'booleanValue',o.boolean_value,'textValue',o.text_value,'sourceLink',o.source_link,'workflowStatus',o.workflow_status,'createdAt',o.created_at) order by o.created_at desc) from public.pmf_observations o join public.research_segments s on s.id=o.segment_id where o.project_id=v_project_id),'[]'::jsonb),
    'hypotheses', coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'code',h.code,'pmfLayer',h.pmf_layer,'statement',h.statement,'successCriteria',h.success_criteria,'decisionStatus',h.decision_status) order by h.code) from public.hypotheses h where h.project_id=v_project_id),'[]'::jsonb),
    'reviewQueue', coalesce((select jsonb_agg(q order by q->>'submittedAt') from (
      select jsonb_build_object('id',r.id,'recordType','respondent','title',r.external_id,'workflowStatus',r.workflow_status,'submittedAt',r.submitted_at) q from public.respondents r where r.project_id=v_project_id and r.workflow_status='submitted'
      union all select jsonb_build_object('id',s.id,'recordType','session','title',s.method,'workflowStatus',s.workflow_status,'submittedAt',s.submitted_at) from public.research_sessions s where s.project_id=v_project_id and s.workflow_status='submitted'
      union all select jsonb_build_object('id',e.id,'recordType','evidence','title',e.title,'workflowStatus',e.workflow_status,'submittedAt',e.submitted_at) from public.evidence_records e where e.project_id=v_project_id and e.workflow_status='submitted'
      union all select jsonb_build_object('id',p.id,'recordType','product_event','title','Product event','workflowStatus',p.workflow_status,'submittedAt',p.submitted_at) from public.product_events p where p.project_id=v_project_id and p.workflow_status='submitted'
      union all select jsonb_build_object('id',v.id,'recordType','value_exchange','title','Value exchange','workflowStatus',v.workflow_status,'submittedAt',v.submitted_at) from public.value_exchange_observations v where v.project_id=v_project_id and v.workflow_status='submitted'
      union all select jsonb_build_object('id',o.id,'recordType','observation','title',d.label,'workflowStatus',o.workflow_status,'submittedAt',o.submitted_at) from public.pmf_observations o join public.pmf_metric_definitions d on d.id=o.definition_id where o.project_id=v_project_id and o.workflow_status='submitted'
    ) review_rows),'[]'::jsonb),
    'gateSnapshots', coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'pmfLayer',g.pmf_layer,'decision',g.decision,'rationale',g.rationale,'createdAt',g.created_at) order by g.created_at desc) from public.gate_snapshots g where g.project_id=v_project_id),'[]'::jsonb)
  );
end; $$;

create or replace function public.rpc_aoi_create_gate_snapshot(p_pmf_layer text, p_decision text, p_rationale text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_org_id uuid; v_project_id uuid; v_snapshot jsonb; v_id uuid;
begin
  select m.organization_id into v_org_id from public.organization_memberships m where m.user_id=auth.uid() and m.status='active' limit 1;
  if not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select p.id into v_project_id from public.projects p where p.organization_id=v_org_id and p.status='active' order by p.created_at limit 1;
  if p_pmf_layer not in ('H1','H2','H3','H4','H5') or p_decision not in ('go','revise','stop','insufficient') then raise exception 'GATE_INPUT_INVALID'; end if;
  v_snapshot := public.rpc_aoi_pmf_snapshot();
  insert into public.gate_snapshots (organization_id,project_id,pmf_layer,decision,rationale,snapshot,created_by)
  values (v_org_id,v_project_id,p_pmf_layer,p_decision,trim(p_rationale),v_snapshot,auth.uid()) returning id into v_id;
  return jsonb_build_object('id',v_id,'pmfLayer',p_pmf_layer,'decision',p_decision);
end; $$;

-- Private Storage buckets and path-based membership policies.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
('aoi-consent','aoi-consent',false,20971520,array['application/pdf','image/jpeg','image/png']),
('aoi-sources','aoi-sources',false,52428800,array['application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','image/jpeg','image/png']),
('aoi-recordings','aoi-recordings',false,524288000,array['audio/mpeg','audio/mp4','audio/wav','video/mp4','video/webm']),
('aoi-oral-images','aoi-oral-images',false,26214400,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists aoi_research_storage_read on storage.objects;
create policy aoi_research_storage_read on storage.objects for select to authenticated using (
  bucket_id in ('aoi-consent','aoi-sources','aoi-recordings','aoi-oral-images')
  and exists (
    select 1 from public.research_attachments a
    where a.bucket_id = storage.objects.bucket_id and a.object_path = storage.objects.name
      and a.status = 'active'
      and (
        a.bucket_id not in ('aoi-recordings', 'aoi-oral-images')
        or exists (
          select 1 from public.consent_records cr
          where cr.respondent_id = a.respondent_id and cr.version = a.consent_version
            and cr.status = 'granted'
            and not exists (select 1 from public.consent_records newer where newer.respondent_id = cr.respondent_id and newer.version > cr.version)
            and exists (select 1 from public.respondents r where r.id = a.respondent_id and r.consent_status = 'granted')
            and (a.bucket_id <> 'aoi-recordings' or cr.recording_allowed)
            and (a.bucket_id <> 'aoi-oral-images' or cr.images_allowed)
        )
      )
  ) and exists (
    select 1 from public.projects p join public.organization_memberships m on m.organization_id=p.organization_id
    where p.id::text=(storage.foldername(name))[1] and m.user_id=auth.uid() and m.status='active'
      and (m.role='admin' or exists (
        select 1 from public.respondents r where r.project_id=p.id and r.id::text=(storage.foldername(name))[2] and r.assigned_to=auth.uid()
      ))
  )
);
drop policy if exists aoi_research_storage_insert on storage.objects;
create policy aoi_research_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id in ('aoi-consent','aoi-sources','aoi-recordings','aoi-oral-images')
  and (
    bucket_id not in ('aoi-recordings', 'aoi-oral-images')
    or exists (
      select 1 from public.respondents r join public.consent_records cr on cr.respondent_id = r.id
      where r.id::text = (storage.foldername(name))[2]
        and r.project_id::text = (storage.foldername(name))[1]
        and r.consent_status = 'granted' and cr.status = 'granted'
        and not exists (select 1 from public.consent_records newer where newer.respondent_id = cr.respondent_id and newer.version > cr.version)
        and (bucket_id <> 'aoi-recordings' or cr.recording_allowed)
        and (bucket_id <> 'aoi-oral-images' or cr.images_allowed)
    )
  ) and exists (
    select 1 from public.projects p join public.organization_memberships m on m.organization_id=p.organization_id
    where p.id::text=(storage.foldername(name))[1] and m.user_id=auth.uid() and m.status='active'
      and (m.role='admin' or exists (
        select 1 from public.respondents r where r.project_id=p.id and r.id::text=(storage.foldername(name))[2] and r.assigned_to=auth.uid()
      ))
  )
);
drop policy if exists aoi_research_storage_admin_delete on storage.objects;
create policy aoi_research_storage_admin_delete on storage.objects for delete to authenticated using (
  bucket_id in ('aoi-consent','aoi-sources','aoi-recordings','aoi-oral-images') and exists (
    select 1 from public.projects p join public.organization_memberships m on m.organization_id=p.organization_id
    where p.id::text=(storage.foldername(name))[1] and m.user_id=auth.uid() and m.status='active' and m.role='admin'
  )
);
drop policy if exists aoi_research_storage_owner_cleanup on storage.objects;
create policy aoi_research_storage_owner_cleanup on storage.objects for delete to authenticated using (
  bucket_id in ('aoi-consent','aoi-sources','aoi-recordings','aoi-oral-images')
  and owner_id = auth.uid()::text
  and not exists (
    select 1 from public.research_attachments a
    where a.bucket_id = storage.objects.bucket_id and a.object_path = storage.objects.name
  )
);

-- Explicit Data API grants. RLS remains the authorization boundary.
revoke all on public.research_segments, public.hypotheses, public.pmf_metric_definitions,
  public.respondents, public.respondent_contacts, public.consent_records, public.research_sessions,
  public.pmf_observations, public.product_events, public.value_exchange_observations,
  public.research_attachments, public.gate_snapshots, public.candidates, public.outreach_events,
  public.evidence_records, public.email_templates, public.email_deliveries, public.contact_preferences,
  public.import_jobs, public.audit_events from anon, authenticated;
grant select on public.organization_memberships, public.projects, public.profiles to authenticated;
grant select on public.research_segments, public.hypotheses, public.pmf_metric_definitions to authenticated;
grant select, insert, update on public.respondents, public.respondent_contacts, public.research_sessions,
  public.pmf_observations, public.product_events, public.value_exchange_observations to authenticated;
grant select, insert on public.consent_records to authenticated;
grant select, insert, update on public.research_attachments to authenticated;
grant select, insert on public.gate_snapshots to authenticated;
grant select, insert, update on public.candidates to authenticated;
grant select, insert on public.outreach_events to authenticated;
grant select, insert, update on public.evidence_records to authenticated;
grant select on public.email_templates, public.contact_preferences to authenticated;
grant select, insert on public.email_deliveries to authenticated;
grant select, insert, update on public.import_jobs to authenticated;
grant select, insert on public.audit_events to authenticated;

revoke all on function public.rpc_aoi_operations_snapshot() from public, anon;
revoke all on function public.rpc_aoi_upsert_candidate(jsonb) from public, anon;
revoke all on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) from public, anon;
revoke all on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) from public, anon;
revoke all on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) from public, anon;
revoke all on function public.rpc_aoi_import_candidates(jsonb,text,text) from public, anon;
revoke all on function public.rpc_aoi_save_research_record(text,jsonb) from public, anon;
revoke all on function public.rpc_aoi_review_research_record(text,uuid,text,text) from public, anon;
revoke all on function public.rpc_aoi_pmf_snapshot() from public, anon;
revoke all on function public.rpc_aoi_create_gate_snapshot(text,text,text) from public, anon;
revoke all on function public.sync_aoi_consent_status() from public, anon, authenticated;
revoke all on function public.enforce_aoi_assignee_membership() from public, anon, authenticated;
revoke all on function public.enforce_aoi_research_workflow() from public, anon, authenticated;
revoke all on function public.enforce_aoi_candidate_workflow() from public, anon, authenticated;
revoke all on function public.validate_aoi_observation_value() from public, anon, authenticated;
revoke all on function public.validate_aoi_session_respondent() from public, anon, authenticated;
revoke all on function public.validate_aoi_attachment_path() from public, anon, authenticated;
grant execute on function public.rpc_aoi_operations_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_candidate(jsonb) to authenticated;
grant execute on function public.rpc_aoi_log_outreach(uuid,text,text,text,text) to authenticated;
grant execute on function public.rpc_aoi_add_evidence(uuid,text,text,integer,text,text,text) to authenticated;
grant execute on function public.rpc_aoi_queue_email(uuid,text,text,text,timestamptz,uuid) to authenticated;
grant execute on function public.rpc_aoi_import_candidates(jsonb,text,text) to authenticated;
grant execute on function public.rpc_aoi_save_research_record(text,jsonb) to authenticated;
grant execute on function public.rpc_aoi_review_research_record(text,uuid,text,text) to authenticated;
grant execute on function public.rpc_aoi_pmf_snapshot() to authenticated;
grant execute on function public.rpc_aoi_create_gate_snapshot(text,text,text) to authenticated;

revoke execute on function public.is_org_member(uuid), public.is_org_admin(uuid), public.rpc_current_user_context(),
  public.rpc_admin_list_users(), public.rpc_admin_create_task(text,text,text,date,text,uuid,numeric,integer),
  public.rpc_aoi_demo_dashboard() from anon;

alter default privileges in schema public revoke execute on functions from public, anon;
