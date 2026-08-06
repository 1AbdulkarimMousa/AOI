-- Versioned bilingual survey authoring, distribution, response governance, and analysis.
-- Anonymous callers never receive table access; the survey-public Edge Function uses
-- service-role-only RPCs that resolve organization and project from a hashed link token.

create extension if not exists pgcrypto;

create table public.survey_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  asset_type text not null default 'survey' check (asset_type in ('template','survey')),
  source_asset_id uuid references public.survey_assets(id) on delete set null,
  title jsonb not null default '{"en":"Untitled survey","zh":"未命名问卷"}'::jsonb,
  description jsonb not null default '{"en":"","zh":""}'::jsonb,
  folder text,
  tags text[] not null default '{}',
  lifecycle_status text not null default 'draft'
    check (lifecycle_status in ('draft','awaiting_approval','approved','published','paused','closed','archived','rejected')),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  assigned_to uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id) references public.projects(organization_id, id) on delete cascade
);
create index survey_assets_library_idx on public.survey_assets (organization_id, project_id, lifecycle_status, updated_at desc);

create table public.survey_drafts (
  asset_id uuid primary key references public.survey_assets(id) on delete cascade,
  organization_id uuid not null,
  project_id uuid not null,
  base_version_id uuid,
  revision integer not null default 1 check (revision > 0),
  definition jsonb not null,
  validation_errors jsonb not null default '[]'::jsonb,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, asset_id),
  foreign key (organization_id, project_id, asset_id)
    references public.survey_assets(organization_id, project_id, id) on delete cascade
);

create table public.survey_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  asset_id uuid not null,
  version_number integer not null check (version_number > 0),
  version_status text not null default 'submitted'
    check (version_status in ('submitted','approved','rejected','published','retired')),
  definition jsonb not null,
  definition_hash bytea not null,
  validation_report jsonb not null default '{}'::jsonb,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  approved_at timestamptz,
  published_at timestamptz,
  unique (asset_id, version_number),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, asset_id)
    references public.survey_assets(organization_id, project_id, id) on delete cascade
);
alter table public.survey_drafts add constraint survey_drafts_base_version_fk
  foreign key (organization_id, project_id, base_version_id)
  references public.survey_versions(organization_id, project_id, id) on delete set null;

create table public.survey_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  asset_id uuid not null,
  version_id uuid not null,
  label text not null default 'Primary link',
  token_hash bytea not null unique,
  link_mode text not null default 'public' check (link_mode in ('public','invited','embed')),
  identity_mode text not null default 'anonymous' check (identity_mode in ('anonymous','pseudonymous','identified')),
  link_status text not null default 'active' check (link_status in ('active','paused','revoked','expired','exhausted')),
  opens_at timestamptz,
  closes_at timestamptz,
  max_responses integer check (max_responses is null or max_responses > 0),
  response_count integer not null default 0 check (response_count >= 0),
  allowed_origins text[] not null default '{}',
  settings jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, asset_id)
    references public.survey_assets(organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, version_id)
    references public.survey_versions(organization_id, project_id, id) on delete restrict
);
create index survey_links_asset_idx on public.survey_links (asset_id, link_status, created_at desc);

create table public.survey_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  link_id uuid not null,
  token_hash bytea not null unique,
  recipient_name text,
  recipient_email text,
  crm_contact_id uuid,
  invitation_status text not null default 'queued'
    check (invitation_status in ('queued','sent','delivered','opened','started','completed','bounced','revoked')),
  send_count integer not null default 0,
  last_sent_at timestamptz,
  reminder_due_at timestamptz,
  completed_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, link_id)
    references public.survey_links(organization_id, project_id, id) on delete cascade
);
create index survey_invitations_delivery_idx on public.survey_invitations (link_id, invitation_status, reminder_due_at);

create table public.survey_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  asset_id uuid not null,
  version_id uuid not null,
  link_id uuid not null,
  invitation_id uuid,
  respondent_id uuid,
  assigned_to uuid references public.profiles(id) on delete set null,
  resume_token_hash bytea not null,
  response_status text not null default 'in_progress'
    check (response_status in ('in_progress','submitted','in_review','approved','revision_requested','rejected','excluded')),
  locale text not null default 'en' check (locale in ('en','zh-CN')),
  consent_receipt jsonb not null default '{}'::jsonb,
  score_result jsonb not null default '{}'::jsonb,
  quality_flags jsonb not null default '[]'::jsonb,
  idempotency_key text,
  started_at timestamptz not null default now(),
  last_saved_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  approved_at timestamptz,
  retention_review_at date,
  legal_hold boolean not null default false,
  anonymized_at timestamptz,
  unique (link_id, idempotency_key),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, asset_id)
    references public.survey_assets(organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, version_id)
    references public.survey_versions(organization_id, project_id, id) on delete restrict,
  foreign key (organization_id, project_id, link_id)
    references public.survey_links(organization_id, project_id, id) on delete restrict,
  foreign key (organization_id, project_id, invitation_id)
    references public.survey_invitations(organization_id, project_id, id) on delete set null (invitation_id),
  foreign key (organization_id, project_id, respondent_id)
    references public.respondents(organization_id, project_id, id) on delete set null (respondent_id)
);
create index survey_submissions_review_idx on public.survey_submissions (organization_id, project_id, response_status, assigned_to, submitted_at desc);
create index survey_submissions_analysis_idx on public.survey_submissions (asset_id, version_id, response_status, submitted_at desc);

create table public.survey_answers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  submission_id uuid not null,
  question_id text not null,
  answer_value jsonb not null default 'null'::jsonb,
  display_snapshot jsonb not null default '{}'::jsonb,
  answer_revision integer not null default 1 check (answer_revision > 0),
  validated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (submission_id, question_id),
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id, submission_id)
    references public.survey_submissions(organization_id, project_id, id) on delete cascade
);
create index survey_answers_question_idx on public.survey_answers (submission_id, question_id);

create table public.survey_answer_revisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  answer_id uuid not null,
  revision integer not null,
  previous_value jsonb,
  new_value jsonb not null,
  change_reason text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (organization_id, project_id, answer_id)
    references public.survey_answers(organization_id, project_id, id) on delete cascade
);

create table public.survey_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  submission_id uuid not null,
  action text not null check (action in ('assigned','in_review','recommend_approve','recommend_reject','approve','request_revision','reject','exclude')),
  notes text,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (organization_id, project_id, submission_id)
    references public.survey_submissions(organization_id, project_id, id) on delete cascade
);
create index survey_reviews_submission_idx on public.survey_reviews (submission_id, created_at desc);

create table public.survey_text_codes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  answer_id uuid not null,
  code text not null,
  label text not null,
  notes text,
  agreement_status text not null default 'single_coded' check (agreement_status in ('single_coded','agreed','disputed')),
  coded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (answer_id, code, coded_by),
  foreign key (organization_id, project_id, answer_id)
    references public.survey_answers(organization_id, project_id, id) on delete cascade
);

create table public.survey_promotions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  submission_id uuid not null,
  answer_id uuid,
  target_type text not null check (target_type in ('pmf_observation','evidence_record','aggregate_finding')),
  target_id uuid not null,
  promoted_by uuid not null references public.profiles(id) on delete restrict,
  promoted_at timestamptz not null default now(),
  unique (submission_id, answer_id, target_type, target_id),
  foreign key (organization_id, project_id, submission_id)
    references public.survey_submissions(organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, answer_id)
    references public.survey_answers(organization_id, project_id, id) on delete set null (answer_id)
);

create table public.survey_aggregate_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  asset_id uuid not null,
  version_id uuid not null,
  filter_hash text not null default 'all',
  population text not null default 'approved' check (population in ('operational','approved')),
  response_count integer not null default 0,
  payload jsonb not null default '{}'::jsonb,
  computed_at timestamptz not null default now(),
  unique (version_id, population, filter_hash),
  foreign key (organization_id, project_id, asset_id)
    references public.survey_assets(organization_id, project_id, id) on delete cascade,
  foreign key (organization_id, project_id, version_id)
    references public.survey_versions(organization_id, project_id, id) on delete cascade
);

create table public.survey_transfer_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  transfer_type text not null check (transfer_type in ('definition_import','response_import','definition_export','response_export')),
  file_name text not null,
  file_format text not null check (file_format in ('aoi_json','csv','xlsx','pdf')),
  package_hash text,
  row_count integer not null default 0,
  rejected_count integer not null default 0,
  transfer_status text not null default 'previewed' check (transfer_status in ('previewed','committed','rejected','exported')),
  validation_report jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  unique (organization_id, project_id, id),
  foreign key (organization_id, project_id) references public.projects(organization_id, id) on delete cascade
);

alter table public.survey_assets enable row level security;
alter table public.survey_drafts enable row level security;
alter table public.survey_versions enable row level security;
alter table public.survey_links enable row level security;
alter table public.survey_invitations enable row level security;
alter table public.survey_submissions enable row level security;
alter table public.survey_answers enable row level security;
alter table public.survey_answer_revisions enable row level security;
alter table public.survey_reviews enable row level security;
alter table public.survey_text_codes enable row level security;
alter table public.survey_promotions enable row level security;
alter table public.survey_aggregate_snapshots enable row level security;
alter table public.survey_transfer_jobs enable row level security;

-- Internal reads remain tenant scoped. Mutations use RPCs so transitions are atomic and audited.
create policy survey_assets_member_read on public.survey_assets for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_drafts_assignee_read on public.survey_drafts for select to authenticated
  using (exists (select 1 from public.survey_assets asset where asset.id=asset_id and asset.organization_id=organization_id
    and (public.is_org_admin(organization_id) or asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));
create policy survey_versions_member_read on public.survey_versions for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_links_member_read on public.survey_links for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_invitations_assignee_read on public.survey_invitations for select to authenticated
  using (public.is_org_admin(organization_id) or exists (select 1 from public.survey_links link join public.survey_assets asset on asset.id=link.asset_id where link.id=link_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));
create policy survey_submissions_assignee_read on public.survey_submissions for select to authenticated
  using (public.is_org_admin(organization_id) or assigned_to=(select auth.uid()) or exists (select 1 from public.survey_assets asset where asset.id=asset_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))));
create policy survey_answers_submission_read on public.survey_answers for select to authenticated
  using (exists (select 1 from public.survey_submissions submission where submission.id=submission_id
    and (public.is_org_admin(organization_id) or submission.assigned_to=(select auth.uid()) or exists (select 1 from public.survey_assets asset where asset.id=submission.asset_id and (asset.owner_id=(select auth.uid()) or asset.assigned_to=(select auth.uid()))))));
create policy survey_answer_revisions_admin_read on public.survey_answer_revisions for select to authenticated
  using (public.is_org_admin(organization_id));
create policy survey_reviews_assignee_read on public.survey_reviews for select to authenticated
  using (public.is_org_admin(organization_id) or reviewer_id=(select auth.uid()));
create policy survey_text_codes_member_read on public.survey_text_codes for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_promotions_member_read on public.survey_promotions for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_aggregate_member_read on public.survey_aggregate_snapshots for select to authenticated
  using (public.is_org_member(organization_id));
create policy survey_transfer_creator_read on public.survey_transfer_jobs for select to authenticated
  using (public.is_org_admin(organization_id) or created_by=(select auth.uid()));

create or replace function private.aoi_survey_context()
returns table (organization_id uuid, project_id uuid, role_name text)
language sql stable security definer set search_path = '' as $$
  select membership.organization_id, project.id, membership.role
  from public.organization_memberships membership
  join public.profiles profile on profile.id=membership.user_id and profile.status='active' and not profile.must_change_password
  join lateral (
    select candidate.id from public.projects candidate
    where candidate.organization_id=membership.organization_id and candidate.status='active'
    order by candidate.created_at limit 1
  ) project on true
  where membership.user_id=(select auth.uid()) and membership.status='active'
  limit 1;
$$;

create or replace function private.validate_aoi_survey_definition(p_definition jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare v_errors jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_definition) <> 'object' then
    return jsonb_build_array(jsonb_build_object('code','DEFINITION_OBJECT_REQUIRED','path','definition'));
  end if;
  if coalesce((p_definition->>'schemaVersion')::integer,0) <> 1 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SCHEMA_VERSION_UNSUPPORTED','path','schemaVersion'));
  end if;
  if jsonb_typeof(p_definition->'blocks') <> 'array' or jsonb_array_length(p_definition->'blocks')=0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SURVEY_BLOCK_REQUIRED','path','blocks'));
  end if;
  if nullif(trim(p_definition#>>'{title,en}'),'') is null or nullif(trim(p_definition#>>'{title,zh}'),'') is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SURVEY_TRANSLATIONS_REQUIRED','path','title'));
  end if;
  return v_errors;
exception when others then
  return jsonb_build_array(jsonb_build_object('code','DEFINITION_INVALID','path','definition'));
end;
$$;

create or replace function public.rpc_aoi_survey_library()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_org uuid; v_project uuid;
begin
  select context.organization_id, context.project_id into v_org, v_project from private.aoi_survey_context() context;
  if v_org is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object(
    'assets', coalesce((select jsonb_agg(jsonb_build_object(
      'id',asset.id,'assetType',asset.asset_type,'title',asset.title,'description',asset.description,
      'status',asset.lifecycle_status,'ownerId',asset.owner_id,'assignedTo',asset.assigned_to,
      'tags',asset.tags,'updatedAt',asset.updated_at,
      'draftRevision',draft.revision,'publishedVersion',published.version_number,
      'responseCount',(select count(*) from public.survey_submissions response where response.asset_id=asset.id),
      'approvedCount',(select count(*) from public.survey_submissions response where response.asset_id=asset.id and response.response_status='approved')
    ) order by asset.updated_at desc)
      from public.survey_assets asset
      left join public.survey_drafts draft on draft.asset_id=asset.id
      left join lateral (select version.version_number from public.survey_versions version where version.asset_id=asset.id and version.version_status='published' order by version.version_number desc limit 1) published on true
      where asset.organization_id=v_org and asset.project_id=v_project and asset.archived_at is null), '[]'::jsonb),
    'reviewCount',(select count(*) from public.survey_submissions response where response.organization_id=v_org and response.project_id=v_project and response.response_status in ('submitted','in_review'))
  );
end;
$$;

create or replace function public.rpc_aoi_create_survey(
  p_title jsonb,
  p_asset_type text default 'survey',
  p_definition jsonb default null,
  p_source_asset_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_project uuid; v_asset public.survey_assets; v_definition jsonb;
begin
  select context.organization_id, context.project_id into v_org, v_project from private.aoi_survey_context() context;
  if v_org is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  if p_asset_type not in ('template','survey') then raise exception 'SURVEY_ASSET_TYPE_INVALID'; end if;
  if nullif(trim(p_title->>'en'),'') is null or nullif(trim(p_title->>'zh'),'') is null then raise exception 'SURVEY_TITLE_TRANSLATIONS_REQUIRED'; end if;
  v_definition := coalesce(p_definition, jsonb_build_object(
    'schemaVersion',1,'locales',jsonb_build_array('en','zh-CN'),'defaultLocale','en','title',p_title,
    'description',jsonb_build_object('en','','zh',''),'settings',jsonb_build_object('presentation','sections','showProgress',true,'allowReview',true),
    'theme',jsonb_build_object('accent','orange','density','comfortable'),
    'blocks',jsonb_build_array(jsonb_build_object('id','section-'||gen_random_uuid()::text,'type','section','title',jsonb_build_object('en','Section 1','zh','第一部分'),'description',jsonb_build_object('en','','zh',''),'blocks',jsonb_build_array())),
    'quotas',jsonb_build_array(),'scoring',jsonb_build_object('enabled',false,'bands',jsonb_build_array()),
    'completion',jsonb_build_object('message',jsonb_build_object('en','Thank you for your response.','zh','感谢您的参与。'),'redirectUrl','')
  ));
  if jsonb_array_length(private.validate_aoi_survey_definition(v_definition)) > 0 then raise exception 'SURVEY_DEFINITION_INVALID'; end if;
  insert into public.survey_assets (organization_id,project_id,asset_type,source_asset_id,title,owner_id,assigned_to,created_by)
  values (v_org,v_project,p_asset_type,p_source_asset_id,p_title,auth.uid(),auth.uid(),auth.uid()) returning * into v_asset;
  insert into public.survey_drafts (asset_id,organization_id,project_id,definition,updated_by)
  values (v_asset.id,v_org,v_project,v_definition,auth.uid());
  insert into public.audit_events (organization_id,actor_id,entity_type,entity_id,action,metadata)
  values (v_org,auth.uid(),'survey_asset',v_asset.id,'created',jsonb_build_object('asset_type',p_asset_type));
  return jsonb_build_object('id',v_asset.id,'revision',1,'definition',v_definition);
end;
$$;

create or replace function public.rpc_aoi_survey_workspace(p_asset_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid() <> v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  return jsonb_build_object(
    'asset',jsonb_build_object('id',v_asset.id,'assetType',v_asset.asset_type,'title',v_asset.title,'description',v_asset.description,'status',v_asset.lifecycle_status,'ownerId',v_asset.owner_id,'assignedTo',v_asset.assigned_to,'tags',v_asset.tags,'updatedAt',v_asset.updated_at),
    'draft',(select jsonb_build_object('revision',draft.revision,'definition',draft.definition,'validationErrors',draft.validation_errors,'updatedAt',draft.updated_at) from public.survey_drafts draft where draft.asset_id=p_asset_id),
    'versions',coalesce((select jsonb_agg(jsonb_build_object('id',version.id,'versionNumber',version.version_number,'status',version.version_status,'submittedAt',version.submitted_at,'reviewedAt',version.reviewed_at,'publishedAt',version.published_at,'reviewNotes',version.review_notes) order by version.version_number desc) from public.survey_versions version where version.asset_id=p_asset_id),'[]'::jsonb),
    'links',coalesce((select jsonb_agg(jsonb_build_object('id',link.id,'versionId',link.version_id,'label',link.label,'mode',link.link_mode,'identityMode',link.identity_mode,'status',link.link_status,'responseCount',link.response_count,'maxResponses',link.max_responses,'opensAt',link.opens_at,'closesAt',link.closes_at,'settings',link.settings) order by link.created_at desc) from public.survey_links link where link.asset_id=p_asset_id),'[]'::jsonb),
    'submissions',coalesce((select jsonb_agg(jsonb_build_object('id',response.id,'versionId',response.version_id,'linkId',response.link_id,'status',response.response_status,'locale',response.locale,'score',response.score_result,'qualityFlags',response.quality_flags,'assignedTo',response.assigned_to,'startedAt',response.started_at,'submittedAt',response.submitted_at,'approvedAt',response.approved_at,
      'answers',coalesce((select jsonb_object_agg(answer.question_id,answer.answer_value) from public.survey_answers answer where answer.submission_id=response.id),'{}'::jsonb)) order by response.started_at desc) from public.survey_submissions response where response.asset_id=p_asset_id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_save_survey_draft(p_asset_id uuid,p_definition jsonb,p_expected_revision integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_asset public.survey_assets; v_draft public.survey_drafts; v_errors jsonb;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id) for update;
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid() <> v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  select * into v_draft from public.survey_drafts draft where draft.asset_id=p_asset_id for update;
  if v_draft.revision <> p_expected_revision then raise exception 'SURVEY_DRAFT_STALE'; end if;
  v_errors := private.validate_aoi_survey_definition(p_definition);
  update public.survey_drafts set definition=p_definition,revision=revision+1,validation_errors=v_errors,updated_by=auth.uid(),updated_at=now()
    where asset_id=p_asset_id returning * into v_draft;
  update public.survey_assets set title=p_definition->'title',description=coalesce(p_definition->'description','{}'::jsonb),updated_at=now(),
    lifecycle_status=case when lifecycle_status in ('awaiting_approval','rejected') then 'draft' else lifecycle_status end where id=p_asset_id;
  return jsonb_build_object('assetId',p_asset_id,'revision',v_draft.revision,'validationErrors',v_errors,'updatedAt',v_draft.updated_at);
end;
$$;

create or replace function public.rpc_aoi_submit_survey_version(p_asset_id uuid,p_expected_revision integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_asset public.survey_assets; v_draft public.survey_drafts; v_version public.survey_versions; v_errors jsonb; v_number integer;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id) for update;
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid() <> v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  select * into v_draft from public.survey_drafts draft where draft.asset_id=p_asset_id for update;
  if v_draft.revision <> p_expected_revision then raise exception 'SURVEY_DRAFT_STALE'; end if;
  v_errors := private.validate_aoi_survey_definition(v_draft.definition);
  if jsonb_array_length(v_errors)>0 then raise exception 'SURVEY_DEFINITION_INVALID'; end if;
  select coalesce(max(version_number),0)+1 into v_number from public.survey_versions where asset_id=p_asset_id;
  insert into public.survey_versions (organization_id,project_id,asset_id,version_number,definition,definition_hash,validation_report,submitted_by)
  values (v_asset.organization_id,v_asset.project_id,p_asset_id,v_number,v_draft.definition,digest(v_draft.definition::text,'sha256'),jsonb_build_object('valid',true,'errors',v_errors),auth.uid()) returning * into v_version;
  update public.survey_assets set lifecycle_status='awaiting_approval',updated_at=now() where id=p_asset_id;
  insert into public.audit_events (organization_id,actor_id,entity_type,entity_id,action,metadata)
  values (v_asset.organization_id,auth.uid(),'survey_version',v_version.id,'submitted',jsonb_build_object('version',v_number));
  return jsonb_build_object('id',v_version.id,'versionNumber',v_number,'status','submitted');
end;
$$;

create or replace function public.rpc_aoi_review_survey_version(p_version_id uuid,p_action text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_version public.survey_versions; v_status text;
begin
  select * into v_version from public.survey_versions version where version.id=p_version_id for update;
  if v_version.id is null then raise exception 'SURVEY_VERSION_NOT_FOUND'; end if;
  if not public.is_org_admin(v_version.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  if v_version.version_status <> 'submitted' then raise exception 'SURVEY_VERSION_NOT_SUBMITTED'; end if;
  if p_action not in ('approve','reject') then raise exception 'SURVEY_REVIEW_ACTION_INVALID'; end if;
  v_status := case when p_action='approve' then 'approved' else 'rejected' end;
  update public.survey_versions set version_status=v_status,reviewed_by=auth.uid(),reviewed_at=now(),review_notes=nullif(trim(p_notes),''),approved_at=case when p_action='approve' then now() else null end where id=p_version_id returning * into v_version;
  update public.survey_assets set lifecycle_status=case when p_action='approve' then 'approved' else 'rejected' end,updated_at=now() where id=v_version.asset_id;
  insert into public.audit_events (organization_id,actor_id,entity_type,entity_id,action,metadata)
  values (v_version.organization_id,auth.uid(),'survey_version',v_version.id,v_status,jsonb_build_object('notes',p_notes));
  return jsonb_build_object('id',v_version.id,'status',v_status,'reviewedAt',v_version.reviewed_at);
end;
$$;

create or replace function public.rpc_aoi_publish_survey(p_version_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_version public.survey_versions;
begin
  select * into v_version from public.survey_versions version where version.id=p_version_id for update;
  if v_version.id is null then raise exception 'SURVEY_VERSION_NOT_FOUND'; end if;
  if not public.is_org_admin(v_version.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  if v_version.version_status <> 'approved' then raise exception 'SURVEY_VERSION_APPROVAL_REQUIRED'; end if;
  update public.survey_versions set version_status='retired' where asset_id=v_version.asset_id and version_status='published';
  update public.survey_versions set version_status='published',published_at=now() where id=p_version_id returning * into v_version;
  update public.survey_assets set lifecycle_status='published',updated_at=now() where id=v_version.asset_id;
  return jsonb_build_object('id',v_version.id,'assetId',v_version.asset_id,'status','published','publishedAt',v_version.published_at);
end;
$$;

create or replace function public.rpc_aoi_create_survey_link(p_version_id uuid,p_label text default 'Primary link',p_mode text default 'public',p_identity_mode text default 'anonymous',p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_version public.survey_versions; v_asset public.survey_assets; v_link public.survey_links; v_token text;
begin
  select * into v_version from public.survey_versions version where version.id=p_version_id and version.version_status='published';
  if v_version.id is null then raise exception 'SURVEY_PUBLISHED_VERSION_REQUIRED'; end if;
  select * into v_asset from public.survey_assets where id=v_version.asset_id;
  if not public.is_org_admin(v_asset.organization_id) and auth.uid() <> v_asset.owner_id and auth.uid() is distinct from v_asset.assigned_to then raise exception 'SURVEY_ASSIGNMENT_REQUIRED'; end if;
  if p_mode not in ('public','invited','embed') or p_identity_mode not in ('anonymous','pseudonymous','identified') then raise exception 'SURVEY_LINK_SETTINGS_INVALID'; end if;
  v_token := encode(gen_random_bytes(24),'hex');
  insert into public.survey_links (organization_id,project_id,asset_id,version_id,label,token_hash,link_mode,identity_mode,opens_at,closes_at,max_responses,allowed_origins,settings,created_by)
  values (v_asset.organization_id,v_asset.project_id,v_asset.id,v_version.id,coalesce(nullif(trim(p_label),''),'Primary link'),digest(v_token,'sha256'),p_mode,p_identity_mode,
    nullif(p_settings->>'opensAt','')::timestamptz,nullif(p_settings->>'closesAt','')::timestamptz,nullif(p_settings->>'maxResponses','')::integer,
    coalesce(array(select jsonb_array_elements_text(coalesce(p_settings->'allowedOrigins','[]'::jsonb))),'{}'),p_settings,auth.uid()) returning * into v_link;
  return jsonb_build_object('id',v_link.id,'token',v_token,'mode',v_link.link_mode,'identityMode',v_link.identity_mode,'status',v_link.link_status);
end;
$$;

create or replace function public.rpc_aoi_review_survey_submission(p_submission_id uuid,p_action text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_status text;
begin
  select * into v_submission from public.survey_submissions response where response.id=p_submission_id and public.is_org_member(response.organization_id) for update;
  if v_submission.id is null then raise exception 'SURVEY_SUBMISSION_NOT_FOUND'; end if;
  if not public.is_org_admin(v_submission.organization_id) and auth.uid() is distinct from v_submission.assigned_to then raise exception 'SURVEY_REVIEW_ASSIGNMENT_REQUIRED'; end if;
  if p_action in ('approve','reject','exclude','request_revision') and not public.is_org_admin(v_submission.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  v_status := case p_action when 'start_review' then 'in_review' when 'approve' then 'approved' when 'request_revision' then 'revision_requested' when 'reject' then 'rejected' when 'exclude' then 'excluded' else null end;
  if v_status is null and p_action not in ('recommend_approve','recommend_reject') then raise exception 'SURVEY_REVIEW_ACTION_INVALID'; end if;
  if v_status is not null then
    update public.survey_submissions set response_status=v_status,reviewed_by=case when p_action in ('approve','reject','exclude','request_revision') then auth.uid() else reviewed_by end,
      reviewed_at=case when p_action in ('approve','reject','exclude','request_revision') then now() else reviewed_at end,
      approved_at=case when p_action='approve' then now() else approved_at end where id=p_submission_id returning * into v_submission;
  end if;
  insert into public.survey_reviews (organization_id,project_id,submission_id,action,notes,reviewer_id)
  values (v_submission.organization_id,v_submission.project_id,v_submission.id,case when p_action='start_review' then 'in_review' else p_action end,nullif(trim(p_notes),''),auth.uid());
  return jsonb_build_object('id',v_submission.id,'status',v_submission.response_status,'action',p_action);
end;
$$;

create or replace function public.rpc_aoi_promote_survey_answer(p_submission_id uuid,p_question_id text,p_metric_code text,p_segment_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_answer public.survey_answers; v_definition public.pmf_metric_definitions; v_segment public.research_segments; v_observation public.pmf_observations;
begin
  select * into v_submission from public.survey_submissions response where response.id=p_submission_id for update;
  if v_submission.id is null or v_submission.response_status<>'approved' then raise exception 'SURVEY_APPROVED_RESPONSE_REQUIRED'; end if;
  if not public.is_org_admin(v_submission.organization_id) then raise exception 'SURVEY_ADMIN_APPROVAL_REQUIRED'; end if;
  select * into v_answer from public.survey_answers answer where answer.submission_id=p_submission_id and answer.question_id=p_question_id;
  if v_answer.id is null then raise exception 'SURVEY_ANSWER_NOT_FOUND'; end if;
  select * into v_definition from public.pmf_metric_definitions definition where definition.organization_id=v_submission.organization_id and definition.project_id=v_submission.project_id and definition.code=p_metric_code and definition.active;
  if v_definition.id is null then raise exception 'SURVEY_PMF_METRIC_NOT_FOUND'; end if;
  select * into v_segment from public.research_segments segment where segment.organization_id=v_submission.organization_id and segment.project_id=v_submission.project_id and segment.code=p_segment_code and segment.active;
  if v_segment.id is null then raise exception 'SURVEY_SEGMENT_NOT_FOUND'; end if;
  insert into public.pmf_observations (organization_id,project_id,definition_id,respondent_id,segment_id,numeric_value,boolean_value,text_value,notes,workflow_status,assigned_to,created_by,submitted_at,reviewed_by,reviewed_at,review_notes)
  values (v_submission.organization_id,v_submission.project_id,v_definition.id,v_submission.respondent_id,v_segment.id,
    case when v_definition.value_type='numeric' then (v_answer.answer_value#>>'{}')::numeric else null end,
    case when v_definition.value_type='boolean' then (v_answer.answer_value#>>'{}')::boolean else null end,
    case when v_definition.value_type='text' then coalesce(v_answer.answer_value#>>'{}',v_answer.answer_value::text) else null end,
    'Promoted from approved survey response '||v_submission.id::text||', version '||v_submission.version_id::text||', question '||p_question_id,
    'approved',auth.uid(),auth.uid(),v_submission.submitted_at,auth.uid(),now(),'Approved survey promotion with preserved provenance') returning * into v_observation;
  insert into public.survey_promotions (organization_id,project_id,submission_id,answer_id,target_type,target_id,promoted_by)
  values (v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.id,'pmf_observation',v_observation.id,auth.uid());
  insert into public.audit_events (organization_id,actor_id,entity_type,entity_id,action,metadata)
  values (v_submission.organization_id,auth.uid(),'survey_submission',v_submission.id,'answer_promoted',jsonb_build_object('question_id',p_question_id,'metric_code',p_metric_code,'observation_id',v_observation.id));
  return jsonb_build_object('promotionType','pmf_observation','targetId',v_observation.id,'questionId',p_question_id,'metricCode',p_metric_code);
end;
$$;

create or replace function public.rpc_aoi_survey_analysis(p_asset_id uuid,p_population text default 'approved')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_asset public.survey_assets; v_allowed text[]; v_started integer; v_completed integer;
begin
  select * into v_asset from public.survey_assets asset where asset.id=p_asset_id and public.is_org_member(asset.organization_id);
  if v_asset.id is null then raise exception 'SURVEY_NOT_FOUND'; end if;
  if p_population not in ('approved','operational') then raise exception 'SURVEY_POPULATION_INVALID'; end if;
  v_allowed := case when p_population='approved' then array['approved'] else array['submitted','in_review','approved','revision_requested','rejected','excluded'] end;
  select count(*),count(*) filter (where response_status<>'in_progress') into v_started,v_completed from public.survey_submissions where asset_id=p_asset_id;
  return jsonb_build_object(
    'population',p_population,'starts',v_started,'completed',v_completed,
    'completionRate',case when v_started=0 then 0 else round(v_completed::numeric/v_started*100) end,
    'statusCounts',coalesce((select jsonb_object_agg(response_status,total) from (select response_status,count(*) total from public.survey_submissions where asset_id=p_asset_id group by response_status) status), '{}'::jsonb),
    'questions',coalesce((select jsonb_agg(jsonb_build_object('questionId',answer.question_id,'count',count(*),'values',jsonb_agg(answer.answer_value)))
      from public.survey_answers answer join public.survey_submissions response on response.id=answer.submission_id
      where response.asset_id=p_asset_id and response.response_status=any(v_allowed) group by answer.question_id), '[]'::jsonb),
    'qualityFlags',coalesce((select jsonb_agg(jsonb_build_object('submissionId',id,'flags',quality_flags)) from public.survey_submissions where asset_id=p_asset_id and jsonb_array_length(quality_flags)>0), '[]'::jsonb)
  );
end;
$$;

-- Public operations are callable only by service_role through the Edge Function.
create or replace function public.rpc_aoi_public_survey_load(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_link public.survey_links; v_version public.survey_versions; v_asset public.survey_assets;
begin
  select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256') and link.link_status='active'
    and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now())
    and (link.max_responses is null or link.response_count<link.max_responses);
  if v_link.id is null then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  select * into v_version from public.survey_versions where id=v_link.version_id and version_status='published';
  select * into v_asset from public.survey_assets where id=v_link.asset_id;
  if v_version.id is null then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  return jsonb_build_object('linkId',v_link.id,'versionId',v_version.id,'identityMode',v_link.identity_mode,'mode',v_link.link_mode,
    'definition',v_version.definition,'title',v_asset.title,'settings',v_link.settings);
end;
$$;

create or replace function public.rpc_aoi_public_survey_start(p_token text,p_locale text default 'en',p_consent jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_link public.survey_links; v_submission public.survey_submissions; v_resume text;
begin
  select * into v_link from public.survey_links link where link.token_hash=digest(p_token,'sha256') and link.link_status='active'
    and (link.opens_at is null or link.opens_at<=now()) and (link.closes_at is null or link.closes_at>now())
    and (link.max_responses is null or link.response_count<link.max_responses) for update;
  if v_link.id is null then raise exception 'SURVEY_LINK_UNAVAILABLE'; end if;
  v_resume := encode(gen_random_bytes(24),'hex');
  insert into public.survey_submissions (organization_id,project_id,asset_id,version_id,link_id,resume_token_hash,locale,consent_receipt,retention_review_at)
  values (v_link.organization_id,v_link.project_id,v_link.asset_id,v_link.version_id,v_link.id,digest(v_resume,'sha256'),case when p_locale='zh-CN' then 'zh-CN' else 'en' end,p_consent,current_date+interval '1 year') returning * into v_submission;
  return jsonb_build_object('submissionId',v_submission.id,'resumeToken',v_resume,'status','in_progress');
end;
$$;

create or replace function public.rpc_aoi_public_survey_save(p_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_answer record;
begin
  select response.* into v_submission from public.survey_submissions response join public.survey_links link on link.id=response.link_id
  where response.id=p_submission_id and response.response_status in ('in_progress','revision_requested')
    and response.resume_token_hash=digest(p_resume_token,'sha256') and link.token_hash=digest(p_token,'sha256') for update;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if jsonb_typeof(p_answers)<>'object' then raise exception 'SURVEY_ANSWERS_INVALID'; end if;
  for v_answer in select key,value from jsonb_each(p_answers) loop
    insert into public.survey_answers (organization_id,project_id,submission_id,question_id,answer_value,validated)
    values (v_submission.organization_id,v_submission.project_id,v_submission.id,v_answer.key,v_answer.value,true)
    on conflict (submission_id,question_id) do update set answer_value=excluded.answer_value,answer_revision=survey_answers.answer_revision+1,validated=true,updated_at=now();
  end loop;
  update public.survey_submissions set last_saved_at=now(),response_status='in_progress' where id=v_submission.id;
  return jsonb_build_object('submissionId',v_submission.id,'savedAt',now());
end;
$$;

create or replace function public.rpc_aoi_public_survey_submit(p_token text,p_submission_id uuid,p_resume_token text,p_answers jsonb,p_idempotency_key text,p_score jsonb default '{}'::jsonb,p_consent jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_submission public.survey_submissions; v_link public.survey_links;
begin
  if nullif(trim(p_idempotency_key),'') is null then raise exception 'SURVEY_IDEMPOTENCY_REQUIRED'; end if;
  select response.* into v_submission from public.survey_submissions response join public.survey_links link on link.id=response.link_id
  where response.id=p_submission_id and response.resume_token_hash=digest(p_resume_token,'sha256') and link.token_hash=digest(p_token,'sha256') for update;
  if v_submission.id is null then raise exception 'SURVEY_RESPONSE_UNAVAILABLE'; end if;
  if v_submission.response_status='submitted' and v_submission.idempotency_key=p_idempotency_key then
    return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at);
  end if;
  if v_submission.response_status not in ('in_progress','revision_requested') then raise exception 'SURVEY_RESPONSE_LOCKED'; end if;
  perform public.rpc_aoi_public_survey_save(p_token,p_submission_id,p_resume_token,p_answers);
  update public.survey_submissions set response_status='submitted',submitted_at=now(),last_saved_at=now(),idempotency_key=p_idempotency_key,
    score_result=p_score,consent_receipt=case when p_consent='{}'::jsonb then consent_receipt else p_consent end where id=v_submission.id returning * into v_submission;
  update public.survey_links set response_count=response_count+1,
    link_status=case when max_responses is not null and response_count+1>=max_responses then 'exhausted' else link_status end where id=v_submission.link_id returning * into v_link;
  return jsonb_build_object('submissionId',v_submission.id,'status','submitted','submittedAt',v_submission.submitted_at);
end;
$$;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('aoi-survey-uploads','aoi-survey-uploads',false,15728640,array['application/pdf','image/jpeg','image/png','text/plain','text/csv'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists survey_uploads_no_direct_anon on storage.objects;
create policy survey_uploads_no_direct_anon on storage.objects for select to anon using (false);

revoke all on public.survey_assets,public.survey_drafts,public.survey_versions,public.survey_links,public.survey_invitations,
  public.survey_submissions,public.survey_answers,public.survey_answer_revisions,public.survey_reviews,public.survey_text_codes,
  public.survey_promotions,public.survey_aggregate_snapshots,public.survey_transfer_jobs from anon,authenticated;
revoke all on public.survey_assets from anon;
revoke all on public.survey_submissions from anon;
grant select on public.survey_assets,public.survey_drafts,public.survey_versions,public.survey_links,public.survey_invitations,
  public.survey_submissions,public.survey_answers,public.survey_answer_revisions,public.survey_reviews,public.survey_text_codes,
  public.survey_promotions,public.survey_aggregate_snapshots,public.survey_transfer_jobs to authenticated;

revoke all on function public.rpc_aoi_survey_library(),public.rpc_aoi_create_survey(jsonb,text,jsonb,uuid),public.rpc_aoi_survey_workspace(uuid),
  public.rpc_aoi_save_survey_draft(uuid,jsonb,integer),public.rpc_aoi_submit_survey_version(uuid,integer),
  public.rpc_aoi_review_survey_version(uuid,text,text),public.rpc_aoi_publish_survey(uuid),
  public.rpc_aoi_create_survey_link(uuid,text,text,text,jsonb),public.rpc_aoi_review_survey_submission(uuid,text,text),
  public.rpc_aoi_promote_survey_answer(uuid,text,text,text),
  public.rpc_aoi_survey_analysis(uuid,text) from public,anon;
grant execute on function public.rpc_aoi_survey_library(),public.rpc_aoi_create_survey(jsonb,text,jsonb,uuid),public.rpc_aoi_survey_workspace(uuid),
  public.rpc_aoi_save_survey_draft(uuid,jsonb,integer),public.rpc_aoi_submit_survey_version(uuid,integer),
  public.rpc_aoi_review_survey_version(uuid,text,text),public.rpc_aoi_publish_survey(uuid),
  public.rpc_aoi_create_survey_link(uuid,text,text,text,jsonb),public.rpc_aoi_review_survey_submission(uuid,text,text),
  public.rpc_aoi_promote_survey_answer(uuid,text,text,text),
  public.rpc_aoi_survey_analysis(uuid,text) to authenticated;

revoke all on function public.rpc_aoi_public_survey_load(text),public.rpc_aoi_public_survey_start(text,text,jsonb),
  public.rpc_aoi_public_survey_save(text,uuid,text,jsonb),public.rpc_aoi_public_survey_submit(text,uuid,text,jsonb,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.rpc_aoi_public_survey_load(text),public.rpc_aoi_public_survey_start(text,text,jsonb),
  public.rpc_aoi_public_survey_save(text,uuid,text,jsonb),public.rpc_aoi_public_survey_submit(text,uuid,text,jsonb,text,jsonb,jsonb) to service_role;

revoke all on function private.aoi_survey_context(),private.validate_aoi_survey_definition(jsonb) from public,anon,authenticated;
