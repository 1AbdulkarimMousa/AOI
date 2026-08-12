-- Durable, source-scoped collaboration and contextual work inbox.

create table public.work_inbox_items (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  recipient_role text,
  source_type text not null check (source_type in (
    'task', 'respondent', 'session', 'evidence', 'product_event', 'value_exchange', 'observation'
  )),
  source_id uuid not null,
  dedupe_key text not null,
  category text not null check (category in (
    'action', 'waiting', 'mention', 'following', 'resolved', 'system_attention'
  )),
  reason text not null,
  summary text not null,
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'critical')),
  due_at timestamptz,
  actor_id uuid references public.profiles(id) on delete set null,
  requester_id uuid references public.profiles(id) on delete set null,
  owner_id uuid references public.profiles(id) on delete set null,
  assignee_id uuid references public.profiles(id) on delete set null,
  read_at timestamptz,
  snoozed_until timestamptz,
  resolved_at timestamptz,
  deep_link text not null,
  source_actions jsonb not null default '[]'::jsonb check (jsonb_typeof(source_actions) = 'array'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, recipient_id, dedupe_key),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.work_comments (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  source_type text not null check (source_type in (
    'task', 'respondent', 'session', 'evidence', 'product_event', 'value_exchange', 'observation'
  )),
  source_id uuid not null,
  author_id uuid not null references public.profiles(id) on delete restrict,
  client_nonce uuid not null,
  body text not null check (length(trim(body)) > 0),
  current_revision integer not null default 1 check (current_revision > 0),
  edited_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (author_id, client_nonce),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.work_comment_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  comment_id uuid not null references public.work_comments(id) on delete cascade,
  revision integer not null check (revision > 0),
  body text not null check (length(trim(body)) > 0),
  change_reason text,
  editor_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (comment_id, revision),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.work_mentions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  comment_id uuid not null references public.work_comments(id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
  mentioned_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (comment_id, mentioned_user_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.work_followers (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  follower_id uuid not null references public.profiles(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id, project_id, source_type, source_id, follower_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create table public.work_handoffs (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  from_user_id uuid not null references public.profiles(id) on delete restrict,
  to_user_id uuid not null references public.profiles(id) on delete restrict,
  client_nonce uuid not null,
  reason text not null check (length(trim(reason)) >= 12),
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (from_user_id, client_nonce),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade
);

create index work_inbox_recipient_bucket_idx
  on public.work_inbox_items (recipient_id, project_id, category, resolved_at, due_at, created_at desc);
create index work_inbox_source_idx
  on public.work_inbox_items (organization_id, project_id, source_type, source_id);
create index work_comments_source_idx
  on public.work_comments (organization_id, project_id, source_type, source_id, created_at);
create index work_comment_revisions_source_idx
  on public.work_comment_revisions (organization_id, project_id, source_type, source_id, created_at);
create index work_mentions_recipient_idx
  on public.work_mentions (mentioned_user_id, project_id, created_at desc);
create index work_followers_recipient_idx
  on public.work_followers (follower_id, project_id, active, updated_at desc);
create index work_handoffs_recipient_idx
  on public.work_handoffs (to_user_id, project_id, resolved_at, created_at desc);

alter table public.work_inbox_items enable row level security;
alter table public.work_comments enable row level security;
alter table public.work_comment_revisions enable row level security;
alter table public.work_mentions enable row level security;
alter table public.work_followers enable row level security;
alter table public.work_handoffs enable row level security;

create or replace function public.aoi_can_access_work_source(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_type text,
  p_source_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.is_org_member(p_organization_id) and (
    (p_source_type = 'task' and exists (
      select 1 from public.tasks source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'respondent' and exists (
      select 1 from public.respondents source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'session' and exists (
      select 1 from public.research_sessions source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'evidence' and exists (
      select 1 from public.evidence_records source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'product_event' and exists (
      select 1 from public.product_events source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'value_exchange' and exists (
      select 1 from public.value_exchange_observations source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
    or (p_source_type = 'observation' and exists (
      select 1 from public.pmf_observations source
      where source.id = p_source_id and source.organization_id = p_organization_id
        and source.project_id = p_project_id
    ))
  );
$$;

create or replace function private.aoi_work_source_context(
  p_source_type text,
  p_source_id uuid
)
returns table (
  organization_id uuid,
  project_id uuid,
  title text,
  source_status text,
  assigned_to uuid,
  priority text,
  due_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select task.organization_id, task.project_id, task.title, task.status, task.assigned_to,
    task.priority, task.due_date::timestamptz
  from public.tasks task where p_source_type = 'task' and task.id = p_source_id
  union all
  select source.organization_id, source.project_id, source.external_id, source.workflow_status,
    source.assigned_to, 'medium', source.retention_review_at::timestamptz
  from public.respondents source where p_source_type = 'respondent' and source.id = p_source_id
  union all
  select source.organization_id, source.project_id, source.method, source.workflow_status,
    source.assigned_to, 'medium', source.session_date::timestamptz
  from public.research_sessions source where p_source_type = 'session' and source.id = p_source_id
  union all
  select source.organization_id, source.project_id, source.title, source.workflow_status,
    source.assigned_to, 'medium', null::timestamptz
  from public.evidence_records source where p_source_type = 'evidence' and source.id = p_source_id
  union all
  select source.organization_id, source.project_id, 'Product event ' || source.event_date,
    source.workflow_status, source.assigned_to, 'medium', source.event_date::timestamptz
  from public.product_events source where p_source_type = 'product_event' and source.id = p_source_id
  union all
  select source.organization_id, source.project_id, 'Value exchange ' || source.observed_at,
    source.workflow_status, source.assigned_to, 'medium', source.observed_at::timestamptz
  from public.value_exchange_observations source
  where p_source_type = 'value_exchange' and source.id = p_source_id
  union all
  select source.organization_id, source.project_id, definition.label, source.workflow_status,
    source.assigned_to, 'medium', null::timestamptz
  from public.pmf_observations source
  join public.pmf_metric_definitions definition on definition.id = source.definition_id
  where p_source_type = 'observation' and source.id = p_source_id;
$$;

create or replace function private.aoi_actor_can_access_work_source(
  p_actor_id uuid,
  p_organization_id uuid,
  p_project_id uuid,
  p_source_type text,
  p_source_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.aoi_work_source_context(p_source_type, p_source_id) source
    join public.projects project on project.id = source.project_id
      and project.organization_id = source.organization_id and project.status = 'active'
    join public.organization_memberships membership
      on membership.organization_id = source.organization_id
      and membership.user_id = p_actor_id and membership.status = 'active'
    join public.profiles profile on profile.id = membership.user_id
      and profile.status = 'active' and not profile.must_change_password
    where source.organization_id = p_organization_id and source.project_id = p_project_id
      and (
        membership.role = 'admin'
        or source.assigned_to = p_actor_id
        or (p_source_type <> 'task' and source.source_status in ('approved', 'archived'))
      )
  );
$$;

create or replace function private.aoi_work_source_link(p_source_type text, p_source_id uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_source_type = 'task'
    then 'workspace.html?view=today&tab=tasks&task=' || p_source_id
    else 'workspace.html?view=research&tab=collect&type=' || p_source_type || '&id=' || p_source_id
  end;
$$;

revoke all on function private.aoi_work_source_context(text, uuid) from public, anon, authenticated;
revoke all on function private.aoi_actor_can_access_work_source(uuid, uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.aoi_work_source_link(text, uuid) from public, anon, authenticated;

create policy work_inbox_recipient_read on public.work_inbox_items
for select to authenticated
using (
  recipient_id = (select auth.uid())
  and public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id)
);

create policy work_comments_source_read on public.work_comments
for select to authenticated
using (public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id));

create policy work_comment_revisions_source_read on public.work_comment_revisions
for select to authenticated
using (public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id));

create policy work_mentions_source_read on public.work_mentions
for select to authenticated
using (public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id));

create policy work_followers_source_read on public.work_followers
for select to authenticated
using (public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id));

create policy work_handoffs_source_read on public.work_handoffs
for select to authenticated
using (public.aoi_can_access_work_source(organization_id, project_id, source_type, source_id));

create or replace function private.prevent_work_comment_revision_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'WORK_COMMENT_REVISIONS_APPEND_ONLY';
end;
$$;

create or replace function private.prevent_work_collaboration_scope_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id
    or new.project_id is distinct from old.project_id
    or new.source_type is distinct from old.source_type
    or new.source_id is distinct from old.source_id then
    raise exception 'WORK_COLLABORATION_SCOPE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger prevent_work_comment_revision_mutation
before update or delete on public.work_comment_revisions
for each row execute function private.prevent_work_comment_revision_mutation();

create trigger prevent_work_inbox_scope_mutation
before update on public.work_inbox_items
for each row execute function private.prevent_work_collaboration_scope_mutation();
create trigger prevent_work_comment_scope_mutation
before update on public.work_comments
for each row execute function private.prevent_work_collaboration_scope_mutation();
create trigger prevent_work_mention_scope_mutation
before update on public.work_mentions
for each row execute function private.prevent_work_collaboration_scope_mutation();
create trigger prevent_work_follower_scope_mutation
before update on public.work_followers
for each row execute function private.prevent_work_collaboration_scope_mutation();
create trigger prevent_work_handoff_scope_mutation
before update on public.work_handoffs
for each row execute function private.prevent_work_collaboration_scope_mutation();

revoke all on function private.prevent_work_comment_revision_mutation() from public, anon, authenticated;
revoke all on function private.prevent_work_collaboration_scope_mutation() from public, anon, authenticated;

create or replace function private.refresh_aoi_work_inbox(p_project_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer := 0;
  v_count integer;
begin
  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role,
    source_type, source_id, dedupe_key, category, reason, summary,
    priority, due_at, owner_id, assignee_id, deep_link, source_actions
  )
  select
    task.organization_id, task.project_id, task.assigned_to, membership.role,
    'task', task.id, 'derived:assignee:task:' || task.id, 'action',
    case task.status when 'revision_requested' then 'Task revision requested'
      when 'blocked' then 'Assigned task is blocked' else 'Assigned task needs progress' end,
    task.title, task.priority, task.due_date::timestamptz, task.created_by, task.assigned_to,
    private.aoi_work_source_link('task', task.id),
    case when task.status = 'revision_requested' then '["resubmit"]'::jsonb
      else '["update_checkpoint"]'::jsonb end
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
    and membership.user_id = task.assigned_to and membership.status = 'active'
  join public.profiles profile on profile.id = membership.user_id
    and profile.status = 'active' and not profile.must_change_password
  where task.assigned_to is not null
    and task.status in ('assigned', 'in_progress', 'blocked', 'revision_requested')
    and (p_project_id is null or task.project_id = p_project_id)
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    recipient_role = excluded.recipient_role,
    reason = excluded.reason,
    summary = excluded.summary,
    priority = excluded.priority,
    due_at = excluded.due_at,
    owner_id = excluded.owner_id,
    assignee_id = excluded.assignee_id,
    read_at = case when public.work_inbox_items.resolved_at is not null then null else public.work_inbox_items.read_at end,
    resolved_at = null,
    source_actions = excluded.source_actions,
    updated_at = clock_timestamp();
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role,
    source_type, source_id, dedupe_key, category, reason, summary,
    priority, due_at, owner_id, assignee_id, deep_link, source_actions
  )
  select
    task.organization_id, task.project_id, membership.user_id, membership.role,
    'task', task.id, 'derived:review:task:' || task.id, 'action',
    'Submitted task requires administrator review', task.title, task.priority,
    task.due_date::timestamptz, task.created_by, task.assigned_to,
    private.aoi_work_source_link('task', task.id), '["approve","request_revision"]'::jsonb
  from public.tasks task
  join public.organization_memberships membership
    on membership.organization_id = task.organization_id
    and membership.role = 'admin' and membership.status = 'active'
  join public.profiles profile on profile.id = membership.user_id
    and profile.status = 'active' and not profile.must_change_password
  where task.status in ('submitted', 'resubmitted')
    and (p_project_id is null or task.project_id = p_project_id)
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    reason = excluded.reason,
    summary = excluded.summary,
    priority = excluded.priority,
    due_at = excluded.due_at,
    owner_id = excluded.owner_id,
    assignee_id = excluded.assignee_id,
    read_at = case when public.work_inbox_items.resolved_at is not null then null else public.work_inbox_items.read_at end,
    resolved_at = null,
    source_actions = excluded.source_actions,
    updated_at = clock_timestamp();
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  with research_sources as (
    select 'respondent'::text source_type, id source_id, organization_id, project_id,
      external_id title, workflow_status, assigned_to, retention_review_at::timestamptz due_at
    from public.respondents
    union all
    select 'session', id, organization_id, project_id, method, workflow_status, assigned_to,
      session_date::timestamptz from public.research_sessions
    union all
    select 'evidence', id, organization_id, project_id, title, workflow_status, assigned_to,
      null::timestamptz from public.evidence_records
    union all
    select 'product_event', id, organization_id, project_id, 'Product event ' || event_date,
      workflow_status, assigned_to, event_date::timestamptz from public.product_events
    union all
    select 'value_exchange', id, organization_id, project_id, 'Value exchange ' || observed_at,
      workflow_status, assigned_to, observed_at::timestamptz from public.value_exchange_observations
    union all
    select 'observation', observation.id, observation.organization_id, observation.project_id,
      definition.label, observation.workflow_status, observation.assigned_to, null::timestamptz
    from public.pmf_observations observation
    join public.pmf_metric_definitions definition on definition.id = observation.definition_id
  )
  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role,
    source_type, source_id, dedupe_key, category, reason, summary,
    priority, due_at, assignee_id, deep_link, source_actions
  )
  select
    source.organization_id, source.project_id, source.assigned_to, membership.role,
    source.source_type, source.source_id,
    'derived:assignee:' || source.source_type || ':' || source.source_id,
    'action', case source.workflow_status when 'revision_requested'
      then 'Research revision requested' else 'Research draft needs completion' end,
    source.title, 'medium', source.due_at, source.assigned_to,
    private.aoi_work_source_link(source.source_type, source.source_id),
    case source.workflow_status when 'revision_requested' then '["resubmit"]'::jsonb
      else '["edit","submit"]'::jsonb end
  from research_sources source
  join public.organization_memberships membership
    on membership.organization_id = source.organization_id
    and membership.user_id = source.assigned_to and membership.status = 'active'
  join public.profiles profile on profile.id = membership.user_id
    and profile.status = 'active' and not profile.must_change_password
  where source.workflow_status in ('draft', 'revision_requested')
    and (p_project_id is null or source.project_id = p_project_id)
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    recipient_role = excluded.recipient_role,
    reason = excluded.reason,
    summary = excluded.summary,
    due_at = excluded.due_at,
    assignee_id = excluded.assignee_id,
    read_at = case when public.work_inbox_items.resolved_at is not null then null else public.work_inbox_items.read_at end,
    resolved_at = null,
    source_actions = excluded.source_actions,
    updated_at = clock_timestamp();
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  with research_sources as (
    select 'respondent'::text source_type, id source_id, organization_id, project_id,
      external_id title, workflow_status, assigned_to from public.respondents
    union all select 'session', id, organization_id, project_id, method, workflow_status, assigned_to
      from public.research_sessions
    union all select 'evidence', id, organization_id, project_id, title, workflow_status, assigned_to
      from public.evidence_records
    union all select 'product_event', id, organization_id, project_id, 'Product event ' || event_date,
      workflow_status, assigned_to from public.product_events
    union all select 'value_exchange', id, organization_id, project_id, 'Value exchange ' || observed_at,
      workflow_status, assigned_to from public.value_exchange_observations
    union all select 'observation', observation.id, observation.organization_id, observation.project_id,
      definition.label, observation.workflow_status, observation.assigned_to
      from public.pmf_observations observation
      join public.pmf_metric_definitions definition on definition.id = observation.definition_id
  )
  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role,
    source_type, source_id, dedupe_key, category, reason, summary,
    priority, assignee_id, deep_link, source_actions
  )
  select
    source.organization_id, source.project_id, membership.user_id, membership.role,
    source.source_type, source.source_id,
    'derived:review:' || source.source_type || ':' || source.source_id,
    'action', 'Submitted research requires administrator review', source.title,
    'medium', source.assigned_to,
    private.aoi_work_source_link(source.source_type, source.source_id),
    '["approve","request_revision"]'::jsonb
  from research_sources source
  join public.organization_memberships membership
    on membership.organization_id = source.organization_id
    and membership.role = 'admin' and membership.status = 'active'
  join public.profiles profile on profile.id = membership.user_id
    and profile.status = 'active' and not profile.must_change_password
  where source.workflow_status = 'submitted'
    and (p_project_id is null or source.project_id = p_project_id)
  on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
    reason = excluded.reason,
    summary = excluded.summary,
    assignee_id = excluded.assignee_id,
    read_at = case when public.work_inbox_items.resolved_at is not null then null else public.work_inbox_items.read_at end,
    resolved_at = null,
    source_actions = excluded.source_actions,
    updated_at = clock_timestamp();
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  update public.work_inbox_items item
  set resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  where item.resolved_at is null
    and item.dedupe_key like 'derived:%'
    and (p_project_id is null or item.project_id = p_project_id)
    and not exists (
      select 1
      from private.aoi_work_source_context(item.source_type, item.source_id) source
      join public.organization_memberships membership
        on membership.organization_id = item.organization_id
        and membership.user_id = item.recipient_id and membership.status = 'active'
      where source.organization_id = item.organization_id and source.project_id = item.project_id
        and (
          (item.dedupe_key like 'derived:assignee:%'
            and source.assigned_to = item.recipient_id
            and ((item.source_type = 'task' and source.source_status in ('assigned', 'in_progress', 'blocked', 'revision_requested'))
              or (item.source_type <> 'task' and source.source_status in ('draft', 'revision_requested'))))
          or (item.dedupe_key like 'derived:review:%'
            and membership.role = 'admin'
            and ((item.source_type = 'task' and source.source_status in ('submitted', 'resubmitted'))
              or (item.source_type <> 'task' and source.source_status = 'submitted')))
        )
    );
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  update public.work_handoffs handoff
  set resolved_at = clock_timestamp()
  where handoff.resolved_at is null
    and (p_project_id is null or handoff.project_id = p_project_id)
    and not exists (
      select 1 from private.aoi_work_source_context(handoff.source_type, handoff.source_id) source
      where source.organization_id = handoff.organization_id and source.project_id = handoff.project_id
        and ((handoff.source_type = 'task' and source.source_status not in ('completed', 'cancelled'))
          or (handoff.source_type <> 'task' and source.source_status not in ('approved', 'archived')))
    );
  get diagnostics v_count = row_count;
  v_changed := v_changed + v_count;

  update public.work_inbox_items item
  set resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  from public.work_handoffs handoff
  where item.resolved_at is null and item.dedupe_key = 'handoff:' || handoff.id
    and handoff.resolved_at is not null;
  get diagnostics v_count = row_count;
  return v_changed + v_count;
end;
$$;

revoke all on function private.refresh_aoi_work_inbox(uuid) from public, anon, authenticated;

create or replace function public.rpc_aoi_inbox_snapshot(
  p_bucket text default 'needs_action',
  p_project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project_id uuid;
begin
  if p_bucket not in ('needs_action', 'waiting', 'mentioned', 'following', 'recently_resolved', 'system_attention') then
    raise exception 'INBOX_BUCKET_INVALID';
  end if;

  select project.id into v_project_id
  from public.projects project
  where (p_project_id is null or project.id = p_project_id)
    and project.status = 'active'
    and public.is_org_member(project.organization_id)
  order by project.created_at, project.id
  limit 1;
  if v_project_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  perform private.refresh_aoi_work_inbox(v_project_id);

  return jsonb_build_object(
    'bucket', p_bucket,
    'projectId', v_project_id,
    'counts', jsonb_build_object(
      'needsAction', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.category = 'action' and item.resolved_at is null
          and (item.snoozed_until is null or item.snoozed_until <= now())
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          )),
      'waiting', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.category = 'waiting' and item.resolved_at is null
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          )),
      'mentioned', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.category = 'mention' and item.resolved_at is null
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          )),
      'following', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.category = 'following' and item.resolved_at is null
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          )),
      'recentlyResolved', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.resolved_at >= now() - interval '30 days'
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          )),
      'systemAttention', (select count(*) from public.work_inbox_items item
        where item.recipient_id = v_actor_id and item.project_id = v_project_id
          and item.category = 'system_attention' and item.resolved_at is null
          and private.aoi_actor_can_access_work_source(
            v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
          ))
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id,
        'category', item.category,
        'reason', item.reason,
        'summary', item.summary,
        'priority', item.priority,
        'dueAt', item.due_at,
        'sourceType', item.source_type,
        'sourceId', item.source_id,
        'readAt', item.read_at,
        'resolvedAt', item.resolved_at,
        'deepLink', item.deep_link,
        'sourceActions', item.source_actions,
        'createdAt', item.created_at
      ) order by
        case item.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
        item.due_at nulls last, item.created_at desc, item.id)
      from public.work_inbox_items item
      where item.recipient_id = v_actor_id and item.project_id = v_project_id
        and private.aoi_actor_can_access_work_source(
          v_actor_id, item.organization_id, item.project_id, item.source_type, item.source_id
        )
        and case p_bucket
          when 'needs_action' then item.category = 'action' and item.resolved_at is null
            and (item.snoozed_until is null or item.snoozed_until <= now())
          when 'waiting' then item.category = 'waiting' and item.resolved_at is null
          when 'mentioned' then item.category = 'mention' and item.resolved_at is null
          when 'following' then item.category = 'following' and item.resolved_at is null
          when 'recently_resolved' then item.resolved_at >= now() - interval '30 days'
          when 'system_attention' then item.category = 'system_attention' and item.resolved_at is null
        end
    ), '[]'::jsonb),
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.rpc_aoi_mark_inbox_read(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.work_inbox_items%rowtype;
begin
  select item.* into v_item from public.work_inbox_items item
  where item.id = p_item_id and item.recipient_id = (select auth.uid())
  for update;
  if v_item.id is null or not private.aoi_actor_can_access_work_source(
    (select auth.uid()), v_item.organization_id, v_item.project_id, v_item.source_type, v_item.source_id
  ) then raise exception 'INBOX_ITEM_NOT_FOUND'; end if;

  update public.work_inbox_items set read_at = coalesce(read_at, clock_timestamp()), updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  return jsonb_build_object('id', v_item.id, 'readAt', v_item.read_at);
end;
$$;

create or replace function public.rpc_aoi_create_work_comment(
  p_source_type text,
  p_source_id uuid,
  p_body text,
  p_client_nonce uuid,
  p_mentioned_user_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_source record;
  v_comment public.work_comments%rowtype;
  v_mentioned_user_id uuid;
  v_mention_id uuid;
  v_recipient_role text;
begin
  if p_client_nonce is null then raise exception 'WORK_CLIENT_NONCE_REQUIRED'; end if;
  if length(trim(coalesce(p_body, ''))) = 0 then raise exception 'WORK_COMMENT_BODY_REQUIRED'; end if;

  select * into v_source from private.aoi_work_source_context(p_source_type, p_source_id);
  if v_source.organization_id is null or not private.aoi_actor_can_access_work_source(
    v_actor_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
  ) then raise exception 'WORK_SOURCE_ACCESS_REQUIRED'; end if;

  select comment.* into v_comment from public.work_comments comment
  where comment.author_id = v_actor_id and comment.client_nonce = p_client_nonce;
  if v_comment.id is not null then
    if v_comment.source_type <> p_source_type or v_comment.source_id <> p_source_id
      or v_comment.body <> trim(p_body) then raise exception 'WORK_CLIENT_NONCE_CONFLICT'; end if;
    return jsonb_build_object('id', v_comment.id, 'revision', v_comment.current_revision, 'replayed', true);
  end if;

  insert into public.work_comments (
    organization_id, project_id, source_type, source_id, author_id, client_nonce, body
  ) values (
    v_source.organization_id, v_source.project_id, p_source_type, p_source_id,
    v_actor_id, p_client_nonce, trim(p_body)
  ) returning * into v_comment;

  insert into public.work_comment_revisions (
    organization_id, project_id, source_type, source_id,
    comment_id, revision, body, editor_id
  ) values (
    v_source.organization_id, v_source.project_id, p_source_type, p_source_id,
    v_comment.id, 1, v_comment.body, v_actor_id
  );

  for v_mentioned_user_id in select distinct unnest(coalesce(p_mentioned_user_ids, '{}'::uuid[])) loop
    if not private.aoi_actor_can_access_work_source(
      v_mentioned_user_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
    ) then raise exception 'WORK_RECIPIENT_MEMBERSHIP_REQUIRED'; end if;

    select membership.role into v_recipient_role
    from public.organization_memberships membership
    where membership.organization_id = v_source.organization_id
      and membership.user_id = v_mentioned_user_id and membership.status = 'active';

    insert into public.work_mentions (
      organization_id, project_id, source_type, source_id,
      comment_id, mentioned_user_id, mentioned_by
    ) values (
      v_source.organization_id, v_source.project_id, p_source_type, p_source_id,
      v_comment.id, v_mentioned_user_id, v_actor_id
    ) returning id into v_mention_id;

    insert into public.work_inbox_items (
      organization_id, project_id, recipient_id, recipient_role,
      source_type, source_id, dedupe_key, category, reason, summary,
      priority, actor_id, requester_id, assignee_id, deep_link, source_actions
    ) values (
      v_source.organization_id, v_source.project_id, v_mentioned_user_id, v_recipient_role,
      p_source_type, p_source_id, 'mention:' || v_comment.id || ':' || v_mentioned_user_id,
      'mention', 'Mentioned in a contextual comment', left(v_comment.body, 240),
      coalesce(v_source.priority, 'medium'), v_actor_id, v_actor_id, v_source.assigned_to,
      private.aoi_work_source_link(p_source_type, p_source_id), '[]'::jsonb
    ) on conflict (organization_id, project_id, recipient_id, dedupe_key) do nothing;
  end loop;

  return jsonb_build_object('id', v_comment.id, 'revision', 1, 'replayed', false);
end;
$$;

create or replace function public.rpc_aoi_revise_work_comment(
  p_comment_id uuid,
  p_body text,
  p_change_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_comment public.work_comments%rowtype;
  v_revision integer;
begin
  if length(trim(coalesce(p_body, ''))) = 0 then raise exception 'WORK_COMMENT_BODY_REQUIRED'; end if;
  if length(trim(coalesce(p_change_reason, ''))) < 3 then raise exception 'WORK_COMMENT_CHANGE_REASON_REQUIRED'; end if;

  select comment.* into v_comment from public.work_comments comment where comment.id = p_comment_id for update;
  if v_comment.id is null or not private.aoi_actor_can_access_work_source(
    v_actor_id, v_comment.organization_id, v_comment.project_id, v_comment.source_type, v_comment.source_id
  ) then raise exception 'WORK_COMMENT_NOT_FOUND'; end if;
  if v_comment.author_id <> v_actor_id and not public.is_org_admin(v_comment.organization_id) then
    raise exception 'WORK_COMMENT_EDIT_FORBIDDEN';
  end if;

  v_revision := v_comment.current_revision + 1;
  update public.work_comments
  set body = trim(p_body), current_revision = v_revision, edited_at = clock_timestamp()
  where id = v_comment.id;
  insert into public.work_comment_revisions (
    organization_id, project_id, source_type, source_id,
    comment_id, revision, body, change_reason, editor_id
  ) values (
    v_comment.organization_id, v_comment.project_id, v_comment.source_type, v_comment.source_id,
    v_comment.id, v_revision, trim(p_body), trim(p_change_reason), v_actor_id
  );
  return jsonb_build_object('id', v_comment.id, 'revision', v_revision);
end;
$$;

create or replace function public.rpc_aoi_follow_work_source(
  p_source_type text,
  p_source_id uuid,
  p_follow boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_source record;
  v_recipient_role text;
begin
  select * into v_source from private.aoi_work_source_context(p_source_type, p_source_id);
  if v_source.organization_id is null or not private.aoi_actor_can_access_work_source(
    v_actor_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
  ) then raise exception 'WORK_SOURCE_ACCESS_REQUIRED'; end if;

  select membership.role into v_recipient_role
  from public.organization_memberships membership
  where membership.organization_id = v_source.organization_id
    and membership.user_id = v_actor_id and membership.status = 'active';

  insert into public.work_followers (
    organization_id, project_id, source_type, source_id, follower_id, active
  ) values (
    v_source.organization_id, v_source.project_id, p_source_type, p_source_id, v_actor_id, coalesce(p_follow, false)
  ) on conflict (organization_id, project_id, source_type, source_id, follower_id) do update set
    active = excluded.active, updated_at = clock_timestamp();

  if coalesce(p_follow, false) then
    insert into public.work_inbox_items (
      organization_id, project_id, recipient_id, recipient_role,
      source_type, source_id, dedupe_key, category, reason, summary,
      priority, assignee_id, deep_link, source_actions
    ) values (
      v_source.organization_id, v_source.project_id, v_actor_id, v_recipient_role,
      p_source_type, p_source_id, 'following:' || p_source_type || ':' || p_source_id,
      'following', 'Following source updates', v_source.title,
      coalesce(v_source.priority, 'medium'), v_source.assigned_to,
      private.aoi_work_source_link(p_source_type, p_source_id), '[]'::jsonb
    ) on conflict (organization_id, project_id, recipient_id, dedupe_key) do update set
      summary = excluded.summary, read_at = public.work_inbox_items.read_at,
      resolved_at = null, updated_at = clock_timestamp();
  else
    update public.work_inbox_items set resolved_at = coalesce(resolved_at, clock_timestamp()), updated_at = clock_timestamp()
    where organization_id = v_source.organization_id and project_id = v_source.project_id
      and recipient_id = v_actor_id and dedupe_key = 'following:' || p_source_type || ':' || p_source_id;
  end if;

  return jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'following', coalesce(p_follow, false));
end;
$$;

create or replace function public.rpc_aoi_handoff_work(
  p_source_type text,
  p_source_id uuid,
  p_to_user_id uuid,
  p_reason text,
  p_client_nonce uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_source record;
  v_handoff public.work_handoffs%rowtype;
  v_recipient_role text;
begin
  if p_client_nonce is null then raise exception 'WORK_CLIENT_NONCE_REQUIRED'; end if;
  if length(trim(coalesce(p_reason, ''))) < 12 then raise exception 'WORK_HANDOFF_REASON_REQUIRED'; end if;
  if p_to_user_id = v_actor_id then raise exception 'WORK_HANDOFF_RECIPIENT_INVALID'; end if;

  select * into v_source from private.aoi_work_source_context(p_source_type, p_source_id);
  if v_source.organization_id is null or not private.aoi_actor_can_access_work_source(
    v_actor_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
  ) then raise exception 'WORK_SOURCE_ACCESS_REQUIRED'; end if;

  select handoff.* into v_handoff from public.work_handoffs handoff
  where handoff.from_user_id = v_actor_id and handoff.client_nonce = p_client_nonce;
  if v_handoff.id is not null then
    if v_handoff.source_type <> p_source_type or v_handoff.source_id <> p_source_id
      or v_handoff.to_user_id <> p_to_user_id or v_handoff.reason <> trim(p_reason) then
      raise exception 'WORK_CLIENT_NONCE_CONFLICT';
    end if;
    return jsonb_build_object('id', v_handoff.id, 'replayed', true);
  end if;

  select membership.role into v_recipient_role
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
    and profile.status = 'active' and not profile.must_change_password
  where membership.organization_id = v_source.organization_id
    and membership.user_id = p_to_user_id and membership.status = 'active';
  if v_recipient_role is null or not private.aoi_actor_can_access_work_source(
    p_to_user_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
  ) then raise exception 'WORK_RECIPIENT_MEMBERSHIP_REQUIRED'; end if;

  insert into public.work_handoffs (
    organization_id, project_id, source_type, source_id,
    from_user_id, to_user_id, client_nonce, reason
  ) values (
    v_source.organization_id, v_source.project_id, p_source_type, p_source_id,
    v_actor_id, p_to_user_id, p_client_nonce, trim(p_reason)
  ) returning * into v_handoff;

  insert into public.work_inbox_items (
    organization_id, project_id, recipient_id, recipient_role,
    source_type, source_id, dedupe_key, category, reason, summary,
    priority, actor_id, requester_id, assignee_id, deep_link, source_actions
  ) values (
    v_source.organization_id, v_source.project_id, p_to_user_id, v_recipient_role,
    p_source_type, p_source_id, 'handoff:' || v_handoff.id, 'action',
    trim(p_reason), v_source.title, coalesce(v_source.priority, 'medium'),
    v_actor_id, v_actor_id, v_source.assigned_to,
    private.aoi_work_source_link(p_source_type, p_source_id), '[]'::jsonb
  );

  return jsonb_build_object('id', v_handoff.id, 'replayed', false);
end;
$$;

revoke all on public.work_inbox_items, public.work_comments, public.work_comment_revisions,
  public.work_mentions, public.work_followers, public.work_handoffs from public, anon, authenticated;
grant select on public.work_inbox_items, public.work_comments, public.work_comment_revisions,
  public.work_mentions, public.work_followers, public.work_handoffs to authenticated;
grant all on public.work_inbox_items, public.work_comments, public.work_comment_revisions,
  public.work_mentions, public.work_followers, public.work_handoffs to service_role;

revoke all on function public.aoi_can_access_work_source(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.aoi_can_access_work_source(uuid, uuid, text, uuid) to authenticated, service_role;

revoke all on function public.rpc_aoi_inbox_snapshot(text, uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_mark_inbox_read(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_create_work_comment(text, uuid, text, uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.rpc_aoi_revise_work_comment(uuid, text, text) from public, anon, authenticated;
revoke all on function public.rpc_aoi_follow_work_source(text, uuid, boolean) from public, anon, authenticated;
revoke all on function public.rpc_aoi_handoff_work(text, uuid, uuid, text, uuid) from public, anon, authenticated;

grant execute on function public.rpc_aoi_inbox_snapshot(text, uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_mark_inbox_read(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_create_work_comment(text, uuid, text, uuid, uuid[]) to authenticated, service_role;
grant execute on function public.rpc_aoi_revise_work_comment(uuid, text, text) to authenticated, service_role;
grant execute on function public.rpc_aoi_follow_work_source(text, uuid, boolean) to authenticated, service_role;
grant execute on function public.rpc_aoi_handoff_work(text, uuid, uuid, text, uuid) to authenticated, service_role;

select private.refresh_aoi_work_inbox(null);

comment on table public.work_inbox_items is 'Durable recipient-specific projection of actionable source state; source workflows remain authoritative.';
comment on table public.work_comment_revisions is 'Append-only contextual comment revision history.';
comment on function public.rpc_aoi_inbox_snapshot(text, uuid) is 'Refreshes deterministic source projections and returns one authorized inbox bucket.';
