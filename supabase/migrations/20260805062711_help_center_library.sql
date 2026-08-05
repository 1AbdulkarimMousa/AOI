-- Bilingual, structured internal Help Center content.

create table if not exists public.help_center_articles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  slug text not null,
  category text not null,
  pmf_layer text,
  audience text[] not null default '{admin,intern}'::text[],
  sequence integer not null default 0,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  featured boolean not null default false,
  reading_minutes integer not null default 3 check (reading_minutes > 0),
  title jsonb not null default '{}'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  tags text[] not null default '{}'::text[],
  body jsonb not null default '{}'::jsonb,
  version integer not null default 1 check (version > 0),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, slug)
);

alter table public.help_center_articles enable row level security;

drop policy if exists help_center_member_read on public.help_center_articles;
create policy help_center_member_read on public.help_center_articles
  for select to authenticated
  using (public.is_org_member(organization_id) and (status = 'published' or public.is_org_admin(organization_id)));

drop policy if exists help_center_admin_write on public.help_center_articles;
create policy help_center_admin_write on public.help_center_articles
  for all to authenticated
  using (public.is_org_admin(organization_id))
  with check (public.is_org_admin(organization_id));

create or replace function public.rpc_aoi_help_center_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_is_admin boolean;
begin
  select membership.organization_id, public.is_org_admin(membership.organization_id)
  into v_org_id, v_is_admin
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = (select auth.uid()) and membership.status = 'active'
  limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;
  return jsonb_build_object('articles', coalesce((select jsonb_agg(jsonb_build_object(
    'id', article.id, 'slug', article.slug, 'category', article.category, 'pmfLayer', article.pmf_layer,
    'audience', article.audience, 'sequence', article.sequence, 'status', article.status,
    'featured', article.featured, 'readingMinutes', article.reading_minutes, 'title', article.title,
    'summary', article.summary, 'tags', article.tags, 'body', article.body, 'version', article.version,
    'updatedAt', article.updated_at
  ) order by article.sequence, article.slug) from public.help_center_articles article
    where article.organization_id = v_org_id and (article.status = 'published' or v_is_admin)), '[]'::jsonb));
end;
$$;

create or replace function public.rpc_aoi_help_center_upsert_article(p_article jsonb, p_expected_version integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_org_id uuid;
  v_id uuid;
  v_saved public.help_center_articles%rowtype;
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  where membership.user_id = (select auth.uid()) and membership.status = 'active' and membership.role = 'admin'
  limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  v_id := nullif(p_article->>'id', '')::uuid;
  if v_id is null then
    insert into public.help_center_articles (organization_id, slug, category, pmf_layer, audience, sequence, status, featured, reading_minutes, title, summary, tags, body, version, created_by, updated_by)
    values (v_org_id, trim(p_article->>'slug'), coalesce(p_article->>'category', 'method'), nullif(p_article->>'pmfLayer', ''), coalesce(array(select jsonb_array_elements_text(coalesce(p_article->'audience', '[]'::jsonb))), '{admin,intern}'::text[]), coalesce((p_article->>'sequence')::integer, 99), coalesce(p_article->>'status', 'draft'), coalesce((p_article->>'featured')::boolean, false), greatest(1, coalesce((p_article->>'readingMinutes')::integer, 3)), coalesce(p_article->'title', '{}'::jsonb), coalesce(p_article->'summary', '{}'::jsonb), coalesce(array(select jsonb_array_elements_text(coalesce(p_article->'tags', '[]'::jsonb))), '{}'::text[]), coalesce(p_article->'body', '{}'::jsonb), 1, (select auth.uid()), (select auth.uid())) returning * into v_saved;
  else
    update public.help_center_articles article set
      category = coalesce(nullif(p_article->>'category', ''), article.category), pmf_layer = nullif(p_article->>'pmfLayer', ''),
      audience = coalesce(array(select jsonb_array_elements_text(coalesce(p_article->'audience', '[]'::jsonb))), article.audience), sequence = coalesce((p_article->>'sequence')::integer, article.sequence),
      status = coalesce(nullif(p_article->>'status', ''), article.status), featured = coalesce((p_article->>'featured')::boolean, article.featured),
      reading_minutes = greatest(1, coalesce((p_article->>'readingMinutes')::integer, article.reading_minutes)), title = coalesce(p_article->'title', article.title),
      summary = coalesce(p_article->'summary', article.summary), tags = coalesce(array(select jsonb_array_elements_text(coalesce(p_article->'tags', '[]'::jsonb))), article.tags),
      body = coalesce(p_article->'body', article.body), version = article.version + 1, updated_by = (select auth.uid()), updated_at = clock_timestamp()
    where article.id = v_id and article.organization_id = v_org_id and (p_expected_version is null or article.version = p_expected_version)
    returning * into v_saved;
    if v_saved.id is null then raise exception 'HELP_ARTICLE_STALE_OR_MISSING'; end if;
  end if;
  return jsonb_build_object('id', v_saved.id, 'slug', v_saved.slug, 'category', v_saved.category, 'pmfLayer', v_saved.pmf_layer, 'audience', v_saved.audience, 'sequence', v_saved.sequence, 'status', v_saved.status, 'featured', v_saved.featured, 'readingMinutes', v_saved.reading_minutes, 'title', v_saved.title, 'summary', v_saved.summary, 'tags', v_saved.tags, 'body', v_saved.body, 'version', v_saved.version, 'updatedAt', v_saved.updated_at);
end;
$$;

create or replace function public.rpc_aoi_help_center_set_status(p_article_id uuid, p_status text, p_expected_version integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org_id uuid; v_saved public.help_center_articles%rowtype;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership where membership.user_id = (select auth.uid()) and membership.status = 'active' and membership.role = 'admin' limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  if p_status not in ('draft','published','archived') then raise exception 'HELP_STATUS_INVALID'; end if;
  update public.help_center_articles set status = p_status, version = version + 1, updated_by = (select auth.uid()), updated_at = clock_timestamp() where id = p_article_id and organization_id = v_org_id and (p_expected_version is null or version = p_expected_version) returning * into v_saved;
  if v_saved.id is null then raise exception 'HELP_ARTICLE_STALE_OR_MISSING'; end if;
  return jsonb_build_object('id', v_saved.id, 'slug', v_saved.slug, 'status', v_saved.status, 'version', v_saved.version, 'updatedAt', v_saved.updated_at);
end;
$$;

create or replace function public.rpc_aoi_help_center_reorder(p_order jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org_id uuid; v_item jsonb;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership where membership.user_id = (select auth.uid()) and membership.status = 'active' and membership.role = 'admin' limit 1;
  if v_org_id is null then raise exception 'ADMIN_REQUIRED'; end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_order, '[]'::jsonb)) loop
    update public.help_center_articles set sequence = (v_item->>'sequence')::integer, updated_by = (select auth.uid()), updated_at = clock_timestamp() where organization_id = v_org_id and id = (v_item->>'id')::uuid;
  end loop;
  return jsonb_build_object('saved', true);
end;
$$;

revoke all on function public.rpc_aoi_help_center_snapshot() from public, anon;
revoke all on function public.rpc_aoi_help_center_upsert_article(jsonb, integer) from public, anon;
revoke all on function public.rpc_aoi_help_center_set_status(uuid, text, integer) from public, anon;
revoke all on function public.rpc_aoi_help_center_reorder(jsonb) from public, anon;
grant execute on function public.rpc_aoi_help_center_snapshot() to authenticated;
grant execute on function public.rpc_aoi_help_center_upsert_article(jsonb, integer) to authenticated;
grant execute on function public.rpc_aoi_help_center_set_status(uuid, text, integer) to authenticated;
grant execute on function public.rpc_aoi_help_center_reorder(jsonb) to authenticated;
-- Project-scoped bilingual PMF Help Center.

create table if not exists public.help_center_articles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  slug text not null,
  category text not null,
  pmf_layer text check (pmf_layer is null or pmf_layer in ('H1', 'H2', 'H3', 'H4', 'H5')),
  audience text[] not null default array['admin', 'intern']::text[],
  sequence integer not null default 100 check (sequence >= 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  featured boolean not null default false,
  title_en text not null,
  title_zh text not null,
  summary_en text not null,
  summary_zh text not null,
  tags text[] not null default '{}'::text[],
  body_en jsonb not null,
  body_zh jsonb not null,
  version integer not null default 1 check (version > 0),
  published_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, slug),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  check (audience <@ array['admin', 'intern']::text[] and cardinality(audience) > 0),
  check (jsonb_typeof(body_en) = 'array' and jsonb_array_length(body_en) > 0),
  check (jsonb_typeof(body_zh) = 'array' and jsonb_array_length(body_zh) > 0)
);

create index if not exists help_center_articles_scope_idx
  on public.help_center_articles (organization_id, project_id, status, sequence, updated_at desc);

alter table public.help_center_articles enable row level security;
revoke all on public.help_center_articles from anon, authenticated;
grant select on public.help_center_articles to authenticated;

drop policy if exists help_center_published_member_read on public.help_center_articles;
create policy help_center_published_member_read on public.help_center_articles
for select to authenticated
using (
  public.is_org_member(organization_id)
  and (status = 'published' or public.is_org_admin(organization_id))
);

create or replace function public.help_center_article_json(p_article public.help_center_articles)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_article.id, 'slug', p_article.slug, 'category', p_article.category,
    'pmfLayer', p_article.pmf_layer, 'audience', to_jsonb(p_article.audience),
    'sequence', p_article.sequence, 'status', p_article.status, 'featured', p_article.featured,
    'title', jsonb_build_object('en', p_article.title_en, 'zh', p_article.title_zh),
    'summary', jsonb_build_object('en', p_article.summary_en, 'zh', p_article.summary_zh),
    'tags', to_jsonb(p_article.tags),
    'body', jsonb_build_object('en', p_article.body_en, 'zh', p_article.body_zh),
    'readingMinutes', greatest(3, jsonb_array_length(p_article.body_en)),
    'version', p_article.version, 'publishedAt', p_article.published_at, 'updatedAt', p_article.updated_at
  );
$$;

create or replace function public.assert_help_center_payload(p_article jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_locale text;
  v_body jsonb;
  v_block jsonb;
begin
  if jsonb_typeof(p_article) <> 'object' then raise exception 'HELP_ARTICLE_INVALID'; end if;
  if coalesce(trim(p_article->>'slug'), '') !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'HELP_ARTICLE_SLUG_INVALID'; end if;
  if coalesce(trim(p_article->>'category'), '') = '' then raise exception 'HELP_ARTICLE_CATEGORY_REQUIRED'; end if;
  if nullif(p_article->>'pmfLayer', '') is not null and p_article->>'pmfLayer' not in ('H1', 'H2', 'H3', 'H4', 'H5') then raise exception 'HELP_ARTICLE_PMF_LAYER_INVALID'; end if;
  if coalesce(trim(p_article#>>'{title,en}'), '') = '' or coalesce(trim(p_article#>>'{title,zh}'), '') = ''
    or coalesce(trim(p_article#>>'{summary,en}'), '') = '' or coalesce(trim(p_article#>>'{summary,zh}'), '') = '' then
    raise exception 'HELP_ARTICLE_BILINGUAL_COPY_REQUIRED';
  end if;
  if p_article::text ~* '<\/?[a-z][^>]*>' then raise exception 'HELP_ARTICLE_HTML_FORBIDDEN'; end if;

  foreach v_locale in array array['en', 'zh'] loop
    v_body := p_article#>array['body', v_locale];
    if jsonb_typeof(v_body) <> 'array' or jsonb_array_length(v_body) = 0 then raise exception 'HELP_ARTICLE_BODY_REQUIRED'; end if;
    for v_block in select value from jsonb_array_elements(v_body) loop
      if jsonb_typeof(v_block) <> 'object'
        or coalesce(v_block->>'type', '') not in ('intro', 'callout', 'steps', 'checklist', 'table', 'do_dont', 'example', 'faq', 'related_article') then
        raise exception 'HELP_ARTICLE_BLOCK_INVALID';
      end if;
      if v_block->>'type' in ('intro', 'example') and coalesce(trim(v_block->>'text'), '') = '' then raise exception 'HELP_ARTICLE_BLOCK_INVALID'; end if;
      if v_block->>'type' = 'callout' and (coalesce(trim(v_block->>'title'), '') = '' or coalesce(trim(v_block->>'text'), '') = '') then raise exception 'HELP_ARTICLE_BLOCK_INVALID'; end if;
      if v_block->>'type' in ('steps', 'checklist') and jsonb_typeof(v_block->'items') <> 'array' then raise exception 'HELP_ARTICLE_BLOCK_INVALID'; end if;
      if v_block->>'type' = 'table' and (jsonb_typeof(v_block->'columns') <> 'array' or jsonb_typeof(v_block->'rows') <> 'array') then raise exception 'HELP_ARTICLE_BLOCK_INVALID'; end if;
      if v_block->>'type' = 'do_dont' and (jsonb_typeof(v_block->'do') <> 'array' or jsonb_typeof(v_block->'avoid') <> 'array') then raise exception 'HELP_ARTICLE_BLOCK_INVALID'; end if;
    end loop;
  end loop;
end;
$$;

create or replace function public.rpc_aoi_help_center_snapshot()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_role text;
  v_project_name text;
begin
  select membership.organization_id, membership.role into v_org_id, v_role
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.status = 'active' and caller.status = 'active'
    and membership.role in ('admin', 'intern')
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at limit 1;
  if v_org_id is null then raise exception 'WORKSPACE_ACCESS_REQUIRED'; end if;

  select project.id, project.name into v_project_id, v_project_name from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  return jsonb_build_object(
    'projectId', v_project_id, 'projectName', v_project_name, 'role', v_role,
    'articles', coalesce((
      select jsonb_agg(public.help_center_article_json(article) order by article.sequence, article.title_en)
      from public.help_center_articles article
      where article.organization_id = v_org_id and article.project_id = v_project_id
        and (article.status = 'published' or v_role = 'admin')
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_aoi_upsert_help_article(p_article jsonb, p_expected_version integer default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_id uuid := nullif(p_article->>'id', '')::uuid;
  v_existing public.help_center_articles%rowtype;
  v_saved public.help_center_articles%rowtype;
  v_audience text[];
  v_tags text[];
begin
  select membership.organization_id into v_org_id
  from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.role = 'admin'
    and membership.status = 'active' and caller.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null or not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;

  perform public.assert_help_center_payload(p_article);
  v_audience := coalesce(array(select jsonb_array_elements_text(p_article->'audience')), array['admin', 'intern']::text[]);
  v_tags := coalesce(array(select jsonb_array_elements_text(p_article->'tags')), '{}'::text[]);
  if cardinality(v_audience) = 0 or not (v_audience <@ array['admin', 'intern']::text[]) then raise exception 'HELP_ARTICLE_AUDIENCE_INVALID'; end if;

  if v_id is not null then
    select article.* into v_existing from public.help_center_articles article
    where article.id = v_id and article.organization_id = v_org_id and article.project_id = v_project_id for update;
    if v_existing.id is null then raise exception 'HELP_ARTICLE_NOT_FOUND'; end if;
    if p_expected_version is null or v_existing.version <> p_expected_version then raise exception 'HELP_ARTICLE_STALE_WRITE'; end if;

    update public.help_center_articles article set
      slug = trim(p_article->>'slug'), category = trim(p_article->>'category'), pmf_layer = nullif(p_article->>'pmfLayer', ''),
      audience = v_audience, sequence = greatest(coalesce((p_article->>'sequence')::integer, article.sequence), 0),
      featured = coalesce((p_article->>'featured')::boolean, false),
      title_en = trim(p_article#>>'{title,en}'), title_zh = trim(p_article#>>'{title,zh}'),
      summary_en = trim(p_article#>>'{summary,en}'), summary_zh = trim(p_article#>>'{summary,zh}'),
      tags = v_tags, body_en = p_article#>'{body,en}', body_zh = p_article#>'{body,zh}',
      version = article.version + 1, updated_by = auth.uid(), updated_at = clock_timestamp()
    where article.id = v_id returning article.* into v_saved;
  else
    insert into public.help_center_articles (
      organization_id, project_id, slug, category, pmf_layer, audience, sequence, status, featured,
      title_en, title_zh, summary_en, summary_zh, tags, body_en, body_zh, created_by, updated_by
    ) values (
      v_org_id, v_project_id, trim(p_article->>'slug'), trim(p_article->>'category'), nullif(p_article->>'pmfLayer', ''),
      v_audience, greatest(coalesce((p_article->>'sequence')::integer, 100), 0), 'draft', coalesce((p_article->>'featured')::boolean, false),
      trim(p_article#>>'{title,en}'), trim(p_article#>>'{title,zh}'), trim(p_article#>>'{summary,en}'), trim(p_article#>>'{summary,zh}'),
      v_tags, p_article#>'{body,en}', p_article#>'{body,zh}', auth.uid(), auth.uid()
    ) returning * into v_saved;
  end if;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'help_center_article', v_saved.id,
    case when v_existing.id is null then 'created' else 'updated' end,
    jsonb_build_object('projectId', v_project_id, 'slug', v_saved.slug, 'version', v_saved.version));
  return public.help_center_article_json(v_saved);
exception
  when unique_violation then raise exception 'HELP_ARTICLE_SLUG_EXISTS';
end;
$$;

create or replace function public.rpc_aoi_set_help_article_status(p_article_id uuid, p_status text, p_expected_version integer)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_saved public.help_center_articles%rowtype;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.role = 'admin'
    and membership.status = 'active' and caller.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null or not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_status not in ('draft', 'published', 'archived') then raise exception 'HELP_ARTICLE_STATUS_INVALID'; end if;

  update public.help_center_articles article set
    status = p_status,
    published_at = case when p_status = 'published' then coalesce(article.published_at, clock_timestamp()) else article.published_at end,
    version = article.version + 1, updated_by = auth.uid(), updated_at = clock_timestamp()
  where article.id = p_article_id and article.organization_id = v_org_id and article.version = p_expected_version
  returning article.* into v_saved;
  if v_saved.id is null then
    if exists (select 1 from public.help_center_articles article where article.id = p_article_id and article.organization_id = v_org_id)
      then raise exception 'HELP_ARTICLE_STALE_WRITE';
      else raise exception 'HELP_ARTICLE_NOT_FOUND';
    end if;
  end if;

  insert into public.audit_events (organization_id, actor_id, entity_type, entity_id, action, metadata)
  values (v_org_id, auth.uid(), 'help_center_article', v_saved.id, p_status,
    jsonb_build_object('projectId', v_saved.project_id, 'slug', v_saved.slug, 'version', v_saved.version));
  return public.help_center_article_json(v_saved);
end;
$$;

create or replace function public.rpc_aoi_reorder_help_articles(p_article_ids uuid[], p_expected_versions jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_id uuid;
  v_id uuid;
  v_position integer := 0;
  v_expected integer;
begin
  select membership.organization_id into v_org_id from public.organization_memberships membership
  join public.profiles caller on caller.id = membership.user_id
  where membership.user_id = auth.uid() and membership.role = 'admin'
    and membership.status = 'active' and caller.status = 'active'
  order by membership.joined_at limit 1;
  if v_org_id is null or not public.is_org_admin(v_org_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select project.id into v_project_id from public.projects project
  where project.organization_id = v_org_id and project.status = 'active'
  order by project.created_at limit 1;
  if v_project_id is null then raise exception 'ACTIVE_PROJECT_REQUIRED'; end if;
  if coalesce(cardinality(p_article_ids), 0) = 0 or cardinality(p_article_ids) <> (select count(distinct item) from unnest(p_article_ids) item) then
    raise exception 'HELP_ARTICLE_ORDER_INVALID';
  end if;

  foreach v_id in array p_article_ids loop
    v_expected := nullif(p_expected_versions->>v_id::text, '')::integer;
    if v_expected is null then raise exception 'HELP_ARTICLE_STALE_WRITE'; end if;
    v_position := v_position + 1;
    update public.help_center_articles article set
      sequence = v_position, version = article.version + 1, updated_by = auth.uid(), updated_at = clock_timestamp()
    where article.id = v_id and article.organization_id = v_org_id and article.project_id = v_project_id and article.version = v_expected;
    if not found then raise exception 'HELP_ARTICLE_STALE_WRITE'; end if;
  end loop;

  insert into public.audit_events (organization_id, actor_id, entity_type, action, metadata)
  values (v_org_id, auth.uid(), 'help_center_article', 'reordered', jsonb_build_object('projectId', v_project_id, 'articleIds', p_article_ids));
  return public.rpc_aoi_help_center_snapshot();
end;
$$;

revoke all on function public.help_center_article_json(public.help_center_articles) from public, anon, authenticated;
revoke all on function public.assert_help_center_payload(jsonb) from public, anon, authenticated;
revoke all on function public.rpc_aoi_help_center_snapshot() from public, anon;
revoke all on function public.rpc_aoi_upsert_help_article(jsonb,integer) from public, anon;
revoke all on function public.rpc_aoi_set_help_article_status(uuid,text,integer) from public, anon;
revoke all on function public.rpc_aoi_reorder_help_articles(uuid[],jsonb) from public, anon;
grant execute on function public.rpc_aoi_help_center_snapshot() to authenticated;
grant execute on function public.rpc_aoi_upsert_help_article(jsonb,integer) to authenticated;
grant execute on function public.rpc_aoi_set_help_article_status(uuid,text,integer) to authenticated;
grant execute on function public.rpc_aoi_reorder_help_articles(uuid[],jsonb) to authenticated;

-- Curated standards and instructions. Seed content is methodology, never respondent evidence.
insert into public.help_center_articles (
  organization_id, project_id, slug, category, pmf_layer, audience, sequence, status, featured,
  title_en, title_zh, summary_en, summary_zh, tags, body_en, body_zh, published_at
)
select
  project.organization_id, project.id, seed.slug, seed.category, seed.pmf_layer,
  array['admin', 'intern']::text[], seed.sequence, 'published', seed.featured,
  seed.title_en, seed.title_zh, seed.summary_en, seed.summary_zh, seed.tags,
  jsonb_build_array(
    jsonb_build_object('type', 'intro', 'text', seed.summary_en),
    jsonb_build_object('type', 'steps', 'title', 'How to do it', 'items', to_jsonb(seed.steps_en)),
    jsonb_build_object('type', 'callout', 'tone', seed.tone, 'title', 'Operating standard', 'text', seed.callout_en)
  ),
  jsonb_build_array(
    jsonb_build_object('type', 'intro', 'text', seed.summary_zh),
    jsonb_build_object('type', 'steps', 'title', '操作步骤', 'items', to_jsonb(seed.steps_zh)),
    jsonb_build_object('type', 'callout', 'tone', seed.tone, 'title', '操作标准', 'text', seed.callout_zh)
  ),
  now()
from public.projects project
cross join (values
  (
    'start-here-pmf-workflow', 'start', null::text, 1, true,
    'Start here: the PMF workflow', '从这里开始：PMF 工作流',
    'A short path from a weekly question to a defensible PMF decision.', '从每周问题到可辩护 PMF 决策的简明路径。',
    array['onboarding','workflow','start here']::text[], 'gold',
    array['Read the current weekly question and evidence standard.','Select the right segment and situation.','Capture source, behavior, limitation, and consent.','Review support and contradiction together.','Recommend one owned next action and move through the appropriate Gate.']::text[],
    array['阅读当前每周问题和证据标准。','选择正确的细分人群和具体情境。','记录来源、行为、局限和同意状态。','同时检查支持证据和反证。','提出一个有负责人的下一步行动并推进到相应闸门。']::text[],
    'Do not try to prove the team right. Build the smallest complete record that helps the team find out what is true.',
    '不要试图证明团队是对的。建立最小而完整的记录，帮助团队找出事实。'
  ),
  (
    'pmf-five-layers', 'method', null, 2, true,
    'The five PMF layers', '五个 PMF 层级',
    'Understand what each layer proves, what it does not prove, and when to advance.', '了解每一层要证明什么、不能证明什么，以及何时推进。',
    array['H1','H2','H3','H4','H5','framework']::text[], 'blue',
    array['H1 tests whether the need is real and consequential.','H2 locates failures in current solutions.','H3 tests whether Ambiloop completes the job better.','H4 tests repeat value after novelty fades.','H5 tests a real value exchange or commitment.']::text[],
    array['H1 验证需求是否真实且后果重要。','H2 寻找现有方案的失败点。','H3 验证 Ambiloop 是否更好地完成任务。','H4 验证新鲜感消失后的重复价值。','H5 验证真实价值交换或承诺。']::text[],
    'A product demo cannot prove need importance, and a positive price answer cannot prove repeat use.',
    '产品演示不能证明需求重要，积极的价格回答也不能证明持续使用。'
  ),
  (
    'weekly-question-to-plan', 'method', null, 3, false,
    'Turn a weekly question into a research plan', '把每周问题变成研究计划',
    'Define the hypothesis, evidence standard, sample, owner, and readout before fieldwork begins.', '在开始执行前定义假设、证据标准、样本、负责人和汇报方式。',
    array['weekly question','hypothesis','sample plan']::text[], 'orange',
    array['Write one testable question tied to one PMF layer.','State what would support and contradict the hypothesis.','Choose sources that can answer the question.','Set sample targets, timing, and owner.','Define the decision the evidence will unlock.']::text[],
    array['写一个连接单一 PMF 层级的可验证问题。','说明支持和反驳假设的结果。','选择能够回答问题的来源。','设定样本目标、时间和负责人。','明确证据将解锁的决策。']::text[],
    'Define the success rule before reviewing results. A plan or hypothesis is not collected evidence.',
    '查看结果前定义成功标准。计划或假设不是已收集的证据。'
  ),
  (
    'capture-a-session', 'collection', null, 4, false,
    'Capture a research session', '记录研究会话',
    'Record real behavior and the most recent incident before interpreting what it means.', '先记录真实行为和最近事件，再解释它意味着什么。',
    array['session','JTBD','current behavior']::text[], 'orange',
    array['Choose the segment, PMF layer, method, and date.','Write what the person does today.','Record a recent incident in verifiable detail.','Describe the current action or workaround.','State the unmet need and session limitations.']::text[],
    array['选择细分人群、PMF 层级、方法和日期。','记录当下真实行为。','详细记录可核对的最近事件。','描述当前行动或替代方案。','说明未满足需求和会话局限。']::text[],
    'Use neutral language. Keep observed or reported behavior separate from team interpretation.',
    '使用中性语言。将观察或自述行为与团队解释分开。'
  ),
  (
    'write-strong-evidence', 'evidence', null, 5, true,
    'Write evidence that can survive review', '写出经得起评审的证据',
    'A useful evidence record is precise, sourced, balanced, and honest about uncertainty.', '有用的证据记录应当准确、有来源、平衡，并诚实面对不确定性。',
    array['evidence','strength','limitations','counterevidence']::text[], 'red',
    array['Name the finding in one precise sentence.','Quote or summarize without adding meaning.','Mark supporting, contradicting, or neutral.','Match strength to the source behavior.','Add the limitation and decision relevance.']::text[],
    array['用一句准确的话命名发现。','引用或概括来源，不添加含义。','标记为支持、反驳或中性。','让强度与来源行为匹配。','补充局限和决策相关性。']::text[],
    'Never hide counterevidence. If evidence is mixed, the decision must say so.',
    '不要隐藏反证。如果证据混合，决策必须明确说明。'
  ),
  (
    'sample-plan-and-recruitment', 'collection', null, 6, false,
    'Build a sample plan without overclaiming', '建立样本计划，避免过度推断',
    'Use planned, minimum, maximum, actual, and completion fields consistently.', '一致使用计划数、最小数、最大数、实际数和完成率字段。',
    array['sample','recruitment','segments']::text[], 'gold',
    array['Name the PMF layer and sample category.','Define qualification and source.','Set useful minimum and maximum targets.','Record planned count and owner.','Update actual count only when underlying records exist.']::text[],
    array['写明 PMF 层级和样本类别。','定义资格标准和来源。','设定有用的最小和最大目标。','记录计划数量和负责人。','只在基础记录存在时更新实际数量。']::text[],
    'Call out geographic, referral, and convenience bias. Never count the same sample twice.',
    '明确地理、转介绍和便利抽样偏差。不要重复计算同一个样本。'
  ),
  (
    'product-and-price-testing', 'collection', 'H3', 7, false,
    'Run product-value and price tests', '执行产品价值和价格测试',
    'Measure the Capture, Compare, Understand, Act chain before asking whether a price feels acceptable.', '先衡量捕捉、对比、理解、行动链条，再询问用户是否接受价格。',
    array['H3','H5','price','product event']::text[], 'gold',
    array['Log the trigger and target user.','Record whether capture produced a valid image.','Record whether comparison was used and understood.','Record the value and resulting action.','Give real commitment more weight than stated intent.']::text[],
    array['记录触发因素和目标用户。','记录是否捕捉到有效图像。','记录是否使用并理解了对比。','记录获得的价值和后续行动。','真实承诺的权重高于口头意愿。']::text[],
    'A paid commitment is stronger evidence than a positive answer about a future purchase.',
    '真实付费承诺比对未来购买的积极回答更强。'
  ),
  (
    'repeatability-home-use', 'method', 'H4', 8, false,
    'Test repeatability, not novelty', '测试可重复性，而不是新鲜感',
    'Design home use around natural triggers, Week 1/2/4 reuse, repeated value, and friction.', '围绕自然触发、第 1/2/4 周复用、重复价值和阻力设计家庭使用。',
    array['H4','repeatability','home use']::text[], 'blue',
    array['Identify the natural return trigger.','Define expected value for Week 1, 2, and 4.','Log successful, failed, and abandoned events.','Ask what changed and what action followed.','Measure operation, cleaning, charging, connection, and time burden.']::text[],
    array['确定自然的再次使用触发因素。','定义第 1、2、4 周的预期价值。','记录成功、失败和放弃的事件。','询问发生了什么变化和后续行动。','衡量操作、清洁、充电、连接和时间负担。']::text[],
    'Repeated value needs a natural trigger and a reason to return after curiosity fades.',
    '重复价值需要自然触发，也需要在好奇心消失后再次返回的理由。'
  ),
  (
    'gate-decision-and-readout', 'method', null, 9, true,
    'Prepare a Gate decision and weekly readout', '准备闸门决策和每周汇报',
    'Turn the evidence balance into one honest decision, one implication, and one next action.', '把证据平衡转化为一个诚实决策、一个影响和一个下一步行动。',
    array['Gate','readout','decision']::text[], 'teal',
    array['State what we learned in plain language.','Explain why it matters to the PMF layer.','Show the strongest support and contradiction.','Name sample, methodology, and limitations.','Recommend Go, Revise, Stop, or Insufficient evidence with one next action.']::text[],
    array['用清晰语言说明我们学到了什么。','解释它为什么影响 PMF 层级。','展示最强支持和最强反证。','说明样本、方法和局限。','用一个下一步行动提出 Go、Revise、Stop 或证据不足。']::text[],
    'A Gate snapshot freezes an approved readout; it does not make weak evidence strong.',
    '闸门快照冻结已批准的汇报，但不会让薄弱证据变强。'
  ),
  (
    'data-handling-and-ai', 'security', null, 10, false,
    'Handle research data and AI responsibly', '负责任地处理研究数据和 AI',
    'Protect identifiers, consent, confidential materials, and the boundary between assistance and judgment.', '保护身份信息、同意记录、机密材料，并区分辅助工具和人的判断。',
    array['security','consent','AI','confidentiality']::text[], 'red',
    array['Use stable IDs instead of personal names in analysis.','Check consent before recordings, images, quotes, or recontact.','Keep confidential files in approved systems.','Separate facts, statements, assumptions, and interpretation.','Verify every AI-assisted source and conclusion independently.']::text[],
    array['在分析中使用稳定 ID，而不是个人姓名。','使用录音、图像、引文或再次联系前检查同意状态。','将机密文件保留在批准的系统内。','区分事实、陈述、假设和解释。','独立核验每个 AI 辅助的来源和结论。']::text[],
    'If consent, confidentiality, or authorization is unclear, pause and ask an administrator.',
    '如果同意、保密或授权不明确，请暂停操作并询问管理员。'
  )
) as seed(
  slug, category, pmf_layer, sequence, featured, title_en, title_zh, summary_en, summary_zh,
  tags, tone, steps_en, steps_zh, callout_en, callout_zh
)
where project.status = 'active'
  and not exists (
    select 1 from public.help_center_articles article
    where article.project_id = project.id and article.slug = seed.slug
  );
