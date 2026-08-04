-- AOI / Ambiloop local test foundation
-- Synthetic seed data only. All base tables remain private behind RLS.

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  default_locale text not null default 'en' check (default_locale in ('en', 'zh-CN')),
  timezone text not null default 'America/New_York',
  status text not null default 'active' check (status in ('active', 'suspended', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  status text not null default 'active' check (status in ('planning', 'active', 'paused', 'complete', 'archived')),
  current_week integer not null default 1,
  start_date date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);
create index if not exists projects_organization_idx on public.projects (organization_id, status);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null,
  objective text,
  status text not null check (status in ('draft','assigned','in_progress','blocked','submitted','revision_requested','resubmitted','approved','completed','cancelled')),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  owner_name text not null,
  owner_initials text not null,
  due_date date,
  pmf_layer text,
  progress integer not null default 0 check (progress between 0 and 100),
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tasks_organization_project_idx on public.tasks (organization_id, project_id, status, due_date);

create table if not exists public.sample_plan_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  label text not null,
  pmf_layer text not null,
  actual integer not null default 0 check (actual >= 0),
  target integer not null check (target > 0),
  accent text not null default 'orange',
  created_at timestamptz not null default now()
);
create index if not exists sample_plan_organization_project_idx on public.sample_plan_items (organization_id, project_id);

create table if not exists public.pmf_layers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  code text not null,
  name text not null,
  sequence integer not null,
  confidence integer not null default 0 check (confidence between 0 and 100),
  status text not null check (status in ('validated','provisional','partial','contradicted','not_validated')),
  evidence_count integer not null default 0 check (evidence_count >= 0),
  counterevidence_count integer not null default 0 check (counterevidence_count >= 0),
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, code)
);
create index if not exists pmf_layers_organization_project_idx on public.pmf_layers (organization_id, project_id, sequence);

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  actor_name text not null,
  actor_initials text not null,
  action text not null,
  subject text not null,
  event_type text not null,
  occurred_at timestamptz not null default now()
);
create index if not exists activity_organization_project_idx on public.activity_events (organization_id, project_id, occurred_at desc);

create table if not exists public.research_signals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  theme text not null,
  stance text not null check (stance in ('supporting','contradicting')),
  evidence_count integer not null default 0,
  change_percent integer not null default 0,
  strength numeric(3,1) not null default 1.0 check (strength between 1 and 4),
  created_at timestamptz not null default now()
);
create index if not exists research_signals_organization_project_idx on public.research_signals (organization_id, project_id, stance);

create table if not exists public.team_progress (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  display_name text not null,
  initials text not null,
  role_label text not null,
  points integer not null default 0,
  weekly_points integer not null default 0,
  streak_days integer not null default 0,
  completed_tasks integer not null default 0,
  rank integer not null,
  created_at timestamptz not null default now(),
  unique (project_id, display_name)
);
create index if not exists team_progress_organization_project_idx on public.team_progress (organization_id, project_id, rank);

create table if not exists public.project_metrics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  metric_key text not null,
  label text not null,
  value numeric not null,
  target numeric,
  unit text not null default 'number',
  delta numeric,
  created_at timestamptz not null default now(),
  unique (project_id, metric_key)
);
create index if not exists project_metrics_organization_project_idx on public.project_metrics (organization_id, project_id, metric_key);

alter table public.organizations enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.sample_plan_items enable row level security;
alter table public.pmf_layers enable row level security;
alter table public.activity_events enable row level security;
alter table public.research_signals enable row level security;
alter table public.team_progress enable row level security;
alter table public.project_metrics enable row level security;

insert into public.organizations (id, slug, name, default_locale, timezone)
values ('11111111-1111-4111-8111-111111111111', 'aoi-technologics', 'HUGE DENTAL USA LLC / AOI Technologics', 'en', 'America/New_York')
on conflict (id) do update set name = excluded.name, updated_at = now();

insert into public.projects (id, organization_id, code, name, description, status, current_week, start_date, end_date)
values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'AOI-PMF-01',
  'Ambiloop U.S. PMF Validation',
  'Bilingual research operations, evidence traceability, and GTM validation.',
  'active', 4, '2026-07-13', '2026-09-25'
)
on conflict (id) do update set name = excluded.name, description = excluded.description, current_week = excluded.current_week, updated_at = now();

delete from public.tasks where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.tasks (organization_id, project_id, title, objective, status, priority, owner_name, owner_initials, due_date, pmf_layer, progress, points) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Synthesize pediatric dentist interviews','Convert eight conversations into traceable Need Truth evidence.','in_progress','high','Kayla Tillmon','KT','2026-08-04','Need Truth',68,180),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Review recruitment message v3','Approve language before the next clinician outreach wave.','submitted','critical','Ethan','ET','2026-08-03','Need Truth',100,120),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Log orthodontic solution-gap evidence','Add supporting and contradictory quotes with strength scores.','revision_requested','high','Wen Tang','WT','2026-08-03','Solution Gap',54,160),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Schedule implant-maintenance interviews','Book the remaining two qualified periodontists.','blocked','medium','Mike Revou Moses','MR','2026-08-05','Need Truth',40,140),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Prepare Week 4 evidence review','Summarize learning, limitations, and the recommended next action.','assigned','high','Zhen','ZH','2026-08-06','Product Value',12,220),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Validate concept-test survey logic','Check segment quotas, Gabor-Granger branching, and consent.','approved','medium','Administrator','AD','2026-08-02','Value Exchange',100,200);

delete from public.sample_plan_items where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.sample_plan_items (organization_id, project_id, label, pmf_layer, actual, target, accent) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Dental professionals','Need Truth',19,35,'orange'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Consumer interviews','Need Truth',24,40,'teal'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Concept-test responses','Product Value',86,200,'blue'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Product test users','Repeatability',8,32,'purple');

delete from public.pmf_layers where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.pmf_layers (organization_id, project_id, code, name, sequence, confidence, status, evidence_count, counterevidence_count, next_action) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H1','Need Truth',1,78,'provisional',54,8,'Close the pediatric dentist evidence gap'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H2','Current Solution Gap',2,64,'partial',41,12,'Verify switching readiness by segment'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H3','Product Value',3,46,'not_validated',28,7,'Complete the concept-test sample'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H4','Repeatability',4,22,'not_validated',11,4,'Begin four-week home-use cohort'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','H5','Value Exchange',5,18,'not_validated',7,3,'Launch price and commitment test');

delete from public.activity_events where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.activity_events (organization_id, project_id, actor_name, actor_initials, action, subject, event_type, occurred_at) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Ethan','ET','submitted','Recruitment message v3','review',now() - interval '18 minutes'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Kayla Tillmon','KT','logged 6 evidence records','Pediatric dentist interviews','evidence',now() - interval '1 hour'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Wen Tang','WT','received revision feedback','Orthodontic solution-gap evidence','revision',now() - interval '3 hours'),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Mike Revou Moses','MR','flagged a blocker','Implant-maintenance recruitment','blocked',now() - interval '5 hours');

delete from public.research_signals where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.research_signals (organization_id, project_id, theme, stance, evidence_count, change_percent, strength) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Caregiver visibility between visits','supporting',31,18,3.4),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Image-comparison confidence','supporting',24,12,3.1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Actionability without clinician context','contradicting',14,7,2.8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Routine-fit friction','contradicting',9,3,2.4);

delete from public.team_progress where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.team_progress (organization_id, project_id, display_name, initials, role_label, points, weekly_points, streak_days, completed_tasks, rank) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Kayla Tillmon','KT','Research Intern',1480,340,6,12,1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Wen Tang','WT','Research Intern',1320,280,4,11,2),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Mike Revou Moses','MR','Doctor BD Support',1180,220,3,9,3);

delete from public.project_metrics where project_id = '22222222-2222-4222-8222-222222222222';
insert into public.project_metrics (organization_id, project_id, metric_key, label, value, target, unit, delta) values
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','weekly_plan','Weekly plan',72,100,'percent',8),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','evidence_records','Evidence records',168,200,'number',24),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','pending_reviews','Pending reviews',3,0,'number',1),
('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','active_blockers','Active blockers',2,0,'number',-1);

create or replace function public.rpc_aoi_demo_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'organization', jsonb_build_object('id', o.id, 'name', o.name, 'slug', o.slug),
    'project', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'description', p.description, 'currentWeek', p.current_week, 'startDate', p.start_date, 'endDate', p.end_date),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', m.metric_key, 'label', m.label, 'value', m.value, 'target', m.target, 'unit', m.unit, 'delta', m.delta) order by case m.metric_key when 'weekly_plan' then 1 when 'evidence_records' then 2 when 'pending_reviews' then 3 when 'active_blockers' then 4 else 99 end) from public.project_metrics m where m.project_id = p.id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'objective', t.objective, 'status', t.status, 'priority', t.priority, 'ownerName', t.owner_name, 'ownerInitials', t.owner_initials, 'dueDate', t.due_date, 'pmfLayer', t.pmf_layer, 'progress', t.progress, 'points', t.points) order by t.due_date nulls last, t.priority desc) from public.tasks t where t.project_id = p.id), '[]'::jsonb),
    'samplePlan', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'pmfLayer', s.pmf_layer, 'actual', s.actual, 'target', s.target, 'accent', s.accent) order by case s.label when 'Dental professionals' then 1 when 'Consumer interviews' then 2 when 'Concept-test responses' then 3 when 'Product test users' then 4 else 99 end) from public.sample_plan_items s where s.project_id = p.id), '[]'::jsonb),
    'pmfLayers', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'code', l.code, 'name', l.name, 'sequence', l.sequence, 'confidence', l.confidence, 'status', l.status, 'evidenceCount', l.evidence_count, 'counterevidenceCount', l.counterevidence_count, 'nextAction', l.next_action) order by l.sequence) from public.pmf_layers l where l.project_id = p.id), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'actorName', a.actor_name, 'actorInitials', a.actor_initials, 'action', a.action, 'subject', a.subject, 'eventType', a.event_type, 'occurredAt', a.occurred_at) order by a.occurred_at desc) from public.activity_events a where a.project_id = p.id), '[]'::jsonb),
    'signals', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'theme', r.theme, 'stance', r.stance, 'evidenceCount', r.evidence_count, 'changePercent', r.change_percent, 'strength', r.strength) order by r.evidence_count desc) from public.research_signals r where r.project_id = p.id), '[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id', tp.id, 'displayName', tp.display_name, 'initials', tp.initials, 'roleLabel', tp.role_label, 'points', tp.points, 'weeklyPoints', tp.weekly_points, 'streakDays', tp.streak_days, 'completedTasks', tp.completed_tasks, 'rank', tp.rank) order by tp.rank) from public.team_progress tp where tp.project_id = p.id), '[]'::jsonb),
    'generatedAt', now()
  )
  from public.projects p
  join public.organizations o on o.id = p.organization_id
  where p.id = '22222222-2222-4222-8222-222222222222';
$$;

revoke all on function public.rpc_aoi_demo_dashboard() from public;
grant execute on function public.rpc_aoi_demo_dashboard() to anon, authenticated;

comment on function public.rpc_aoi_demo_dashboard() is 'Read-only synthetic dashboard payload for the AOI local test build.';
