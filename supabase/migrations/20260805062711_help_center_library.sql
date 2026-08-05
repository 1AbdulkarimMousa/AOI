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
