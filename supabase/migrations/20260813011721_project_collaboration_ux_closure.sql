create or replace function private.aoi_work_collaboration_projection(
  p_actor_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_comment_limit integer default null,
  p_include_revisions boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source record;
  v_comments jsonb;
begin
  select * into v_source from private.aoi_work_source_context(p_source_type, p_source_id);
  if v_source.organization_id is null or not private.aoi_actor_can_access_work_source(
    p_actor_id, v_source.organization_id, v_source.project_id, p_source_type, p_source_id
  ) then raise exception 'WORK_SOURCE_ACCESS_REQUIRED'; end if;

  select coalesce(jsonb_agg(item.payload order by item.created_at, item.id), '[]'::jsonb)
  into v_comments
  from (
    select comment.id, comment.created_at, jsonb_build_object(
      'id', comment.id,
      'body', comment.body,
      'authorId', comment.author_id,
      'authorName', author.display_name,
      'authorRole', membership.role,
      'createdAt', comment.created_at,
      'editedAt', comment.edited_at,
      'revisionCount', comment.current_revision,
      'canRevise', comment.author_id = p_actor_id or public.is_org_admin(comment.organization_id),
      'revisions', case when p_include_revisions then coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', revision.id,
          'revision', revision.revision,
          'body', revision.body,
          'changeReason', revision.change_reason,
          'editorId', revision.editor_id,
          'editorName', editor.display_name,
          'createdAt', revision.created_at
        ) order by revision.revision)
        from public.work_comment_revisions revision
        join public.profiles editor on editor.id = revision.editor_id
        where revision.comment_id = comment.id
      ), '[]'::jsonb) else '[]'::jsonb end
    ) payload
    from public.work_comments comment
    join public.profiles author on author.id = comment.author_id
    left join public.organization_memberships membership
      on membership.organization_id = comment.organization_id
      and membership.user_id = comment.author_id
    where comment.organization_id = v_source.organization_id
      and comment.project_id = v_source.project_id
      and comment.source_type = p_source_type
      and comment.source_id = p_source_id
    order by comment.created_at desc, comment.id desc
    limit coalesce(p_comment_limit, 2147483647)
  ) item;

  return jsonb_build_object(
    'sourceType', p_source_type,
    'sourceId', p_source_id,
    'projectId', v_source.project_id,
    'commentCount', (select count(*) from public.work_comments comment
      where comment.organization_id = v_source.organization_id and comment.project_id = v_source.project_id
        and comment.source_type = p_source_type and comment.source_id = p_source_id),
    'comments', v_comments,
    'isFollowing', exists(select 1 from public.work_followers follower
      where follower.organization_id = v_source.organization_id and follower.project_id = v_source.project_id
        and follower.source_type = p_source_type and follower.source_id = p_source_id
        and follower.follower_id = p_actor_id and follower.active),
    'eligibleCollaborators', coalesce((select jsonb_agg(jsonb_build_object(
      'userId', membership.user_id,
      'displayName', profile.display_name,
      'role', membership.role,
      'active', true
    ) order by profile.display_name, membership.user_id)
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
        and profile.status = 'active' and not profile.must_change_password
      join auth.users auth_user on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
      where membership.organization_id = v_source.organization_id and membership.status = 'active'
        and private.aoi_actor_can_access_work_source(membership.user_id, v_source.organization_id,
          v_source.project_id, p_source_type, p_source_id)), '[]'::jsonb),
    'recentHandoff', (select jsonb_build_object(
      'id', handoff.id,
      'fromUserId', handoff.from_user_id,
      'fromDisplayName', sender.display_name,
      'toUserId', handoff.to_user_id,
      'toDisplayName', recipient.display_name,
      'reason', handoff.reason,
      'resolvedAt', handoff.resolved_at,
      'createdAt', handoff.created_at
    ) from public.work_handoffs handoff
      join public.profiles sender on sender.id = handoff.from_user_id
      join public.profiles recipient on recipient.id = handoff.to_user_id
      where handoff.organization_id = v_source.organization_id and handoff.project_id = v_source.project_id
        and handoff.source_type = p_source_type and handoff.source_id = p_source_id
      order by handoff.created_at desc, handoff.id desc limit 1)
  );
end;
$$;

revoke all on function private.aoi_work_collaboration_projection(uuid, text, uuid, integer, boolean) from public, anon, authenticated;

alter function public.rpc_aoi_project_record_detail(text, uuid) rename to rpc_aoi_project_record_detail_pre_collaboration;
alter function public.rpc_aoi_project_record_detail_pre_collaboration(text, uuid) set schema private;
revoke all on function private.rpc_aoi_project_record_detail_pre_collaboration(text, uuid) from public, anon, authenticated;

create function public.rpc_aoi_project_record_detail(p_record_type text, p_record_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
  v_collaboration jsonb;
begin
  v_payload := private.rpc_aoi_project_record_detail_pre_collaboration(p_record_type, p_record_id);
  v_collaboration := private.aoi_work_collaboration_projection((select auth.uid()), p_record_type, p_record_id, null, true);
  return (v_payload - 'comments') || jsonb_build_object('comments', v_collaboration->'comments', 'collaboration', v_collaboration);
end;
$$;

alter function public.rpc_aoi_project_snapshot(uuid) rename to rpc_aoi_project_snapshot_pre_collaboration;
alter function public.rpc_aoi_project_snapshot_pre_collaboration(uuid) set schema private;
revoke all on function private.rpc_aoi_project_snapshot_pre_collaboration(uuid) from public, anon, authenticated;

create function public.rpc_aoi_project_snapshot(p_project_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_payload jsonb;
  v_project_id uuid;
  v_organization_id uuid;
begin
  v_payload := private.rpc_aoi_project_snapshot_pre_collaboration(p_project_id);
  v_project_id := (v_payload->'project'->>'id')::uuid;
  v_organization_id := (v_payload->'project'->>'organizationId')::uuid;
  v_payload := jsonb_set(v_payload, '{members}', coalesce((select jsonb_agg(member || jsonb_build_object('updatedAt', project_member.updated_at))
    from jsonb_array_elements(v_payload->'members') member
    join public.project_members project_member on project_member.id = (member->>'id')::uuid), '[]'::jsonb));
  return v_payload || jsonb_build_object('eligibleOrganizationMembers', case when public.is_org_admin(v_organization_id) then coalesce((
    select jsonb_agg(jsonb_build_object(
      'userId', membership.user_id,
      'displayName', profile.display_name,
      'role', membership.role,
      'active', true,
      'projectMemberUpdatedAt', project_member.updated_at
    ) order by profile.display_name, membership.user_id)
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
      and profile.status = 'active' and not profile.must_change_password
    join auth.users auth_user on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
    left join public.project_members project_member on project_member.project_id = v_project_id and project_member.user_id = membership.user_id
    where membership.organization_id = v_organization_id and membership.status = 'active'
      and not exists (select 1 from public.project_members member
        where member.project_id = v_project_id and member.user_id = membership.user_id and member.active)
  ), '[]'::jsonb) else '[]'::jsonb end);
end;
$$;

create function public.rpc_aoi_inbox_item_detail(p_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_item public.work_inbox_items%rowtype;
  v_collaboration jsonb;
begin
  select item.* into v_item from public.work_inbox_items item
  where item.id = p_item_id and item.recipient_id = v_actor_id;
  if v_item.id is null or not private.aoi_actor_can_access_work_source(
    v_actor_id, v_item.organization_id, v_item.project_id, v_item.source_type, v_item.source_id
  ) then raise exception 'INBOX_ITEM_NOT_FOUND'; end if;
  v_collaboration := private.aoi_work_collaboration_projection(v_actor_id, v_item.source_type, v_item.source_id, 3, false);
  return jsonb_build_object(
    'id', v_item.id,
    'projectId', v_item.project_id,
    'category', v_item.category,
    'reason', v_item.reason,
    'summary', v_item.summary,
    'priority', v_item.priority,
    'dueAt', v_item.due_at,
    'sourceType', v_item.source_type,
    'sourceId', v_item.source_id,
    'readAt', v_item.read_at,
    'resolvedAt', v_item.resolved_at,
    'deepLink', v_item.deep_link,
    'sourceActions', v_item.source_actions,
    'createdAt', v_item.created_at,
    'collaboration', v_collaboration
  );
end;
$$;

create or replace function public.rpc_aoi_admin_set_project_member(
  p_project_id uuid,
  p_user_id uuid,
  p_active boolean,
  p_responsibility text,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_project public.projects%rowtype;
  v_member public.project_members%rowtype;
begin
  select project.* into v_project from public.projects project where project.id = p_project_id for update;
  if v_project.id is null or not public.is_org_admin(v_project.organization_id) then raise exception 'PROJECT_ADMIN_REQUIRED'; end if;
  if v_project.lifecycle_status = 'archived' then raise exception 'PROJECT_READ_ONLY'; end if;
  select member.* into v_member from public.project_members member where member.project_id = p_project_id and member.user_id = p_user_id for update;
  if p_active and length(trim(coalesce(p_responsibility, ''))) = 0 then raise exception 'PROJECT_MEMBER_RESPONSIBILITY_REQUIRED'; end if;
  if p_active and not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
      and profile.status = 'active' and not profile.must_change_password
    join auth.users auth_user on auth_user.id = profile.id and auth_user.email_confirmed_at is not null
    where membership.organization_id = v_project.organization_id
      and membership.user_id = p_user_id and membership.status = 'active'
  ) then raise exception 'PROJECT_MEMBER_ORGANIZATION_REQUIRED'; end if;
  if not p_active and exists (select 1 from public.organization_memberships membership where membership.organization_id = v_project.organization_id
    and membership.user_id = p_user_id and membership.is_owner) then raise exception 'PROJECT_OWNER_REMOVAL_FORBIDDEN'; end if;
  if not p_active and (
    exists (select 1 from public.project_milestones where project_id = p_project_id and owner_id = p_user_id and status not in ('completed','cancelled'))
    or exists (select 1 from public.project_blockers where project_id = p_project_id and resolution_owner_id = p_user_id and status <> 'resolved')
    or exists (select 1 from public.project_risks where project_id = p_project_id and owner_id = p_user_id and status not in ('accepted','closed'))
    or exists (select 1 from public.project_decisions where project_id = p_project_id and owner_id = p_user_id and status not in ('approved','rejected','superseded'))
  ) then raise exception 'PROJECT_MEMBER_HAS_OPEN_ASSIGNMENTS'; end if;
  if v_member.id is not null and p_expected_updated_at is null then raise exception 'PROJECT_MEMBER_EXPECTED_UPDATED_AT_REQUIRED'; end if;
  if v_member.id is not null and v_member.updated_at <> p_expected_updated_at then raise exception 'PROJECT_MEMBER_STALE_WRITE'; end if;
  insert into public.project_members (organization_id, project_id, user_id, responsibility, active, assigned_by, archived_at)
  values (v_project.organization_id, p_project_id, p_user_id, nullif(trim(p_responsibility), ''), p_active, v_actor_id,
    case when p_active then null else clock_timestamp() end)
  on conflict (project_id, user_id) do update set responsibility = excluded.responsibility, active = excluded.active,
    assigned_by = excluded.assigned_by, assigned_at = case when excluded.active and not project_members.active then clock_timestamp() else project_members.assigned_at end,
    archived_at = excluded.archived_at, updated_at = clock_timestamp()
  returning * into v_member;
  return to_jsonb(v_member);
end;
$$;

revoke all on function public.rpc_aoi_project_record_detail(text, uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_project_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_inbox_item_detail(uuid) from public, anon, authenticated;
revoke all on function public.rpc_aoi_admin_set_project_member(uuid, uuid, boolean, text, timestamptz) from public, anon, authenticated;
grant execute on function public.rpc_aoi_project_record_detail(text, uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_project_snapshot(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_inbox_item_detail(uuid) to authenticated, service_role;
grant execute on function public.rpc_aoi_admin_set_project_member(uuid, uuid, boolean, text, timestamptz) to authenticated, service_role;

comment on function public.rpc_aoi_inbox_item_detail(uuid) is 'Returns one recipient-authorized inbox item with compact contextual collaboration.';
