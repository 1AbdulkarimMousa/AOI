-- Organization-scoped internal chat, safe member profiles, private media, and realtime access.

alter table public.profiles add column if not exists job_title text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists timezone text not null default 'UTC';
alter table public.profiles add column if not exists avatar_key text;
alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles
  add constraint profiles_display_name_length_check check (char_length(trim(display_name)) between 2 and 80),
  add constraint profiles_job_title_length_check check (job_title is null or char_length(job_title) <= 100),
  add constraint profiles_bio_length_check check (bio is null or char_length(bio) <= 240),
  add constraint profiles_phone_length_check check (phone is null or char_length(phone) <= 40),
  add constraint profiles_timezone_length_check check (char_length(timezone) between 1 and 100),
  add constraint profiles_avatar_key_check check (
    avatar_key is null or avatar_key in ('coral', 'teal', 'blue', 'purple', 'gold', 'slate', 'rose', 'sand')
  );
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
update public.profiles profile
set phone = staff.phone,
    timezone = staff.timezone
from public.staff_profiles staff
join public.organization_memberships membership
  on membership.organization_id = staff.organization_id and membership.user_id = staff.user_id
where profile.id = staff.user_id and membership.status = 'active';
create or replace function private.sync_aoi_profile_contact()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles profile
  set phone = new.phone,
      timezone = new.timezone,
      updated_at = clock_timestamp()
  where profile.id = new.user_id;
  return new;
end;
$$;
revoke all on function private.sync_aoi_profile_contact() from public, anon, authenticated;
drop trigger if exists sync_aoi_profile_contact on public.staff_profiles;
create trigger sync_aoi_profile_contact
after insert or update of phone, timezone on public.staff_profiles
for each row execute function private.sync_aoi_profile_contact();
create table public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('team', 'direct')),
  title text,
  direct_key text,
  created_by uuid references public.profiles(id) on delete set null,
  last_message_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, direct_key),
  unique (organization_id, id),
  constraint chat_conversations_shape_check check (
    (kind = 'team' and direct_key is null)
    or (kind = 'direct' and direct_key is not null and title is null)
  )
);
create unique index chat_conversations_one_team_per_org_idx
  on public.chat_conversations (organization_id) where kind = 'team';
create index chat_conversations_recent_idx
  on public.chat_conversations (organization_id, last_message_at desc nulls last, created_at desc);
create table public.chat_conversation_members (
  organization_id uuid not null,
  conversation_id uuid not null,
  user_id uuid not null,
  notification_level text not null default 'all' check (notification_level in ('all', 'mentions', 'muted')),
  last_read_message_id uuid,
  last_read_at timestamptz,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (conversation_id, user_id),
  unique (organization_id, conversation_id, user_id),
  constraint chat_members_conversation_scope_fk foreign key (organization_id, conversation_id)
    references public.chat_conversations (organization_id, id) on delete cascade,
  constraint chat_members_org_membership_fk foreign key (organization_id, user_id)
    references public.organization_memberships (organization_id, user_id) on delete restrict,
  constraint chat_members_dates_check check (left_at is null or left_at >= joined_at)
);
create index chat_members_user_idx
  on public.chat_conversation_members (user_id, organization_id, left_at, conversation_id);
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  conversation_id uuid not null,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  reply_to_id uuid,
  body text not null,
  client_nonce uuid,
  edited_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_vector tsvector generated always as (to_tsvector('simple', body)) stored,
  unique (conversation_id, id),
  unique (organization_id, conversation_id, id),
  constraint chat_messages_conversation_scope_fk foreign key (organization_id, conversation_id)
    references public.chat_conversations (organization_id, id) on delete cascade,
  constraint chat_messages_sender_membership_fk foreign key (organization_id, conversation_id, sender_id)
    references public.chat_conversation_members (organization_id, conversation_id, user_id) on delete restrict,
  constraint chat_messages_reply_scope_fk foreign key (conversation_id, reply_to_id)
    references public.chat_messages (conversation_id, id) on delete no action,
  constraint chat_messages_body_check check (
    (deleted_at is not null and body = '')
    or (deleted_at is null and char_length(trim(body)) between 0 and 4000)
  )
);
create unique index chat_messages_client_nonce_idx
  on public.chat_messages (conversation_id, sender_id, client_nonce) where client_nonce is not null;
create index chat_messages_conversation_created_idx
  on public.chat_messages (conversation_id, created_at desc, id desc);
create index chat_messages_search_idx on public.chat_messages using gin (search_vector);
alter table public.chat_conversation_members
  add constraint chat_members_last_read_scope_fk foreign key (conversation_id, last_read_message_id)
  references public.chat_messages (conversation_id, id) on delete set null (last_read_message_id);
create table public.chat_message_reactions (
  organization_id uuid not null,
  conversation_id uuid not null,
  message_id uuid not null,
  user_id uuid not null,
  reaction text not null check (reaction in ('thumbs_up', 'heart', 'celebrate', 'laugh', 'surprised', 'sad')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, reaction),
  constraint chat_reactions_message_scope_fk foreign key (organization_id, conversation_id, message_id)
    references public.chat_messages (organization_id, conversation_id, id) on delete cascade,
  constraint chat_reactions_member_scope_fk foreign key (organization_id, conversation_id, user_id)
    references public.chat_conversation_members (organization_id, conversation_id, user_id) on delete cascade
);
create index chat_reactions_conversation_idx
  on public.chat_message_reactions (conversation_id, message_id, reaction);
create table public.chat_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  conversation_id uuid not null,
  message_id uuid not null,
  uploader_id uuid not null references public.profiles(id) on delete restrict,
  bucket_id text not null default 'aoi-chat' check (bucket_id = 'aoi-chat'),
  object_path text not null unique,
  file_name text not null,
  mime_type text not null check (mime_type in (
    'image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/plain', 'text/csv',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  )),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint chat_attachments_message_scope_fk foreign key (organization_id, conversation_id, message_id)
    references public.chat_messages (organization_id, conversation_id, id) on delete cascade,
  constraint chat_attachments_member_scope_fk foreign key (organization_id, conversation_id, uploader_id)
    references public.chat_conversation_members (organization_id, conversation_id, user_id) on delete restrict
);
create index chat_attachments_message_idx
  on public.chat_attachments (message_id, created_at) where deleted_at is null;
create table public.chat_moderation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null,
  message_id uuid not null,
  moderator_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('remove')),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  constraint chat_moderation_message_scope_fk foreign key (organization_id, conversation_id, message_id)
    references public.chat_messages (organization_id, conversation_id, id) on delete restrict
);
create index chat_moderation_org_created_idx
  on public.chat_moderation_events (organization_id, created_at desc);
alter table public.chat_conversations enable row level security;
alter table public.chat_conversation_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_message_reactions enable row level security;
alter table public.chat_attachments enable row level security;
alter table public.chat_moderation_events enable row level security;
create or replace function public.aoi_chat_is_participant(
  target_conversation_id uuid,
  target_organization_id uuid
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.chat_conversation_members member
    join public.organization_memberships membership
      on membership.organization_id = member.organization_id and membership.user_id = member.user_id
    join public.profiles profile on profile.id = member.user_id
    join public.organizations organization on organization.id = member.organization_id
    where member.conversation_id = target_conversation_id
      and member.organization_id = target_organization_id
      and member.user_id = auth.uid()
      and member.left_at is null
      and membership.status = 'active'
      and profile.status = 'active'
      and organization.status = 'active'
  );
$$;
create or replace function public.aoi_chat_topic_authorized(p_topic text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_conversation_id uuid;
  v_organization_id uuid;
begin
  if p_topic is null or p_topic !~ '^chat:[0-9a-fA-F-]{36}$' then return false; end if;
  begin
    v_conversation_id := substring(p_topic from 6)::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  select conversation.organization_id into v_organization_id
  from public.chat_conversations conversation where conversation.id = v_conversation_id;
  return v_organization_id is not null
    and public.aoi_chat_is_participant(v_conversation_id, v_organization_id);
end;
$$;
create or replace function public.aoi_chat_storage_authorized(
  p_organization_id text,
  p_conversation_id text,
  p_uploader_id text,
  p_require_owner boolean default false
)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_organization_id uuid;
  v_conversation_id uuid;
  v_uploader_id uuid;
begin
  begin
    v_organization_id := p_organization_id::uuid;
    v_conversation_id := p_conversation_id::uuid;
    v_uploader_id := p_uploader_id::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if p_require_owner and v_uploader_id <> auth.uid() then return false; end if;
  return exists (
    select 1 from public.chat_conversations conversation
    where conversation.id = v_conversation_id and conversation.organization_id = v_organization_id
  ) and public.aoi_chat_is_participant(v_conversation_id, v_organization_id);
end;
$$;
create or replace function public.aoi_profile_avatar_authorized(
  p_organization_id text,
  p_profile_id text
)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_organization_id uuid;
  v_profile_id uuid;
begin
  begin
    v_organization_id := p_organization_id::uuid;
    v_profile_id := p_profile_id::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return exists (
    select 1
    from public.organization_memberships mine
    join public.organization_memberships peer on peer.organization_id = mine.organization_id
    join public.profiles mine_profile on mine_profile.id = mine.user_id
    join public.profiles peer_profile on peer_profile.id = peer.user_id
    join public.organizations organization on organization.id = mine.organization_id
    where mine.organization_id = v_organization_id
      and mine.user_id = auth.uid() and mine.status = 'active' and mine_profile.status = 'active'
      and peer.user_id = v_profile_id and peer.status = 'active' and peer_profile.status = 'active'
      and organization.status = 'active'
  );
end;
$$;
revoke all on function public.aoi_chat_is_participant(uuid,uuid) from public, anon;
revoke all on function public.aoi_chat_topic_authorized(text) from public, anon;
revoke all on function public.aoi_chat_storage_authorized(text,text,text,boolean) from public, anon;
revoke all on function public.aoi_profile_avatar_authorized(text,text) from public, anon;
grant execute on function public.aoi_chat_is_participant(uuid,uuid) to authenticated;
grant execute on function public.aoi_chat_topic_authorized(text) to authenticated;
grant execute on function public.aoi_chat_storage_authorized(text,text,text,boolean) to authenticated;
grant execute on function public.aoi_profile_avatar_authorized(text,text) to authenticated;
create policy chat_conversations_participant_read on public.chat_conversations
for select to authenticated
using (public.aoi_chat_is_participant(id, organization_id));
create policy chat_members_participant_read on public.chat_conversation_members
for select to authenticated
using (public.aoi_chat_is_participant(conversation_id, organization_id));
create policy chat_messages_participant_read on public.chat_messages
for select to authenticated
using (public.aoi_chat_is_participant(conversation_id, organization_id));
create policy chat_reactions_participant_read on public.chat_message_reactions
for select to authenticated
using (public.aoi_chat_is_participant(conversation_id, organization_id));
create policy chat_attachments_participant_read on public.chat_attachments
for select to authenticated
using (deleted_at is null and public.aoi_chat_is_participant(conversation_id, organization_id));
create policy chat_moderation_admin_read on public.chat_moderation_events
for select to authenticated
using (public.is_org_admin(organization_id));
drop policy if exists profiles_self_or_org_read on public.profiles;
drop policy if exists profiles_self_read on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_read on public.profiles
for select to authenticated
using (id = (select auth.uid()));
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
revoke all on public.chat_conversations from anon, authenticated;
revoke all on public.chat_conversation_members from anon, authenticated;
revoke all on public.chat_messages from anon, authenticated;
revoke all on public.chat_message_reactions from anon, authenticated;
revoke all on public.chat_attachments from anon, authenticated;
revoke all on public.chat_moderation_events from anon, authenticated;
grant select on public.chat_conversations to authenticated;
grant select on public.chat_conversation_members to authenticated;
grant select on public.chat_messages to authenticated;
grant select on public.chat_message_reactions to authenticated;
grant select on public.chat_attachments to authenticated;
insert into public.chat_conversations (organization_id, kind, title)
select organization.id, 'team', 'Team'
from public.organizations organization
on conflict (organization_id) where kind = 'team' do nothing;
insert into public.chat_conversation_members (organization_id, conversation_id, user_id)
select conversation.organization_id, conversation.id, membership.user_id
from public.chat_conversations conversation
join public.organization_memberships membership
  on membership.organization_id = conversation.organization_id and membership.status = 'active'
join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
where conversation.kind = 'team'
on conflict (conversation_id, user_id) do update set left_at = null;
create or replace function private.ensure_aoi_team_room()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.chat_conversations (organization_id, kind, title)
  values (new.id, 'team', 'Team')
  on conflict (organization_id) where kind = 'team' do nothing;
  return new;
end;
$$;
create or replace function private.sync_aoi_team_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_team_id uuid;
begin
  select conversation.id into v_team_id
  from public.chat_conversations conversation
  where conversation.organization_id = new.organization_id and conversation.kind = 'team';
  if v_team_id is null then
    insert into public.chat_conversations (organization_id, kind, title)
    values (new.organization_id, 'team', 'Team')
    on conflict (organization_id) where kind = 'team'
    do update set updated_at = public.chat_conversations.updated_at
    returning id into v_team_id;
  end if;
  if new.status = 'active' and exists (
    select 1 from public.profiles profile where profile.id = new.user_id and profile.status = 'active'
  ) then
    insert into public.chat_conversation_members (organization_id, conversation_id, user_id)
    values (new.organization_id, v_team_id, new.user_id)
    on conflict (conversation_id, user_id) do update set left_at = null;
  else
    update public.chat_conversation_members member set left_at = coalesce(member.left_at, clock_timestamp())
    where member.conversation_id = v_team_id and member.user_id = new.user_id;
  end if;
  return new;
end;
$$;
revoke all on function private.ensure_aoi_team_room() from public, anon, authenticated;
revoke all on function private.sync_aoi_team_membership() from public, anon, authenticated;
drop trigger if exists ensure_aoi_team_room on public.organizations;
create trigger ensure_aoi_team_room after insert on public.organizations
for each row execute function private.ensure_aoi_team_room();
drop trigger if exists sync_aoi_team_membership on public.organization_memberships;
create trigger sync_aoi_team_membership after insert or update of status on public.organization_memberships
for each row execute function private.sync_aoi_team_membership();
create or replace function private.aoi_chat_context()
returns table (organization_id uuid, role text)
language sql stable security definer set search_path = '' as $$
  select membership.organization_id, membership.role
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  join public.organizations organization on organization.id = membership.organization_id
  where membership.user_id = auth.uid()
    and membership.status = 'active'
    and profile.status = 'active'
    and organization.status = 'active'
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at, membership.organization_id
  limit 1;
$$;
create or replace function private.aoi_safe_profile(p_profile public.profiles)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'userId', p_profile.id,
    'displayName', p_profile.display_name,
    'jobTitle', p_profile.job_title,
    'bio', p_profile.bio,
    'phone', p_profile.phone,
    'timezone', p_profile.timezone,
    'locale', p_profile.locale,
    'avatarKey', p_profile.avatar_key,
    'avatarPath', p_profile.avatar_path
  );
$$;
create or replace function private.aoi_chat_profile(p_profile public.profiles)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'userId', p_profile.id,
    'displayName', p_profile.display_name,
    'jobTitle', p_profile.job_title,
    'avatarKey', p_profile.avatar_key,
    'avatarPath', p_profile.avatar_path
  );
$$;
create or replace function private.aoi_chat_message_json(p_message public.chat_messages)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p_message.id,
    'conversationId', p_message.conversation_id,
    'senderId', p_message.sender_id,
    'sender', private.aoi_chat_profile(profile),
    'replyToId', p_message.reply_to_id,
    'body', p_message.body,
    'clientNonce', p_message.client_nonce,
    'editedAt', p_message.edited_at,
    'deletedAt', p_message.deleted_at,
    'createdAt', p_message.created_at,
    'updatedAt', p_message.updated_at,
    'reactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reaction', grouped.reaction,
        'count', grouped.reaction_count,
        'reactedByMe', grouped.reacted_by_me
      ) order by grouped.reaction)
      from (
        select reaction.reaction, count(*) as reaction_count,
          bool_or(reaction.user_id = auth.uid()) as reacted_by_me
        from public.chat_message_reactions reaction
        where reaction.message_id = p_message.id
        group by reaction.reaction
      ) grouped
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', attachment.id,
        'bucketId', attachment.bucket_id,
        'objectPath', attachment.object_path,
        'fileName', attachment.file_name,
        'mimeType', attachment.mime_type,
        'sizeBytes', attachment.size_bytes
      ) order by attachment.created_at, attachment.id)
      from public.chat_attachments attachment
      where attachment.message_id = p_message.id and attachment.deleted_at is null
    ), '[]'::jsonb)
  )
  from public.profiles profile where profile.id = p_message.sender_id;
$$;
create or replace function private.aoi_chat_conversation_json(
  p_conversation public.chat_conversations,
  p_user_id uuid
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p_conversation.id,
    'kind', p_conversation.kind,
    'title', case when p_conversation.kind = 'team' then p_conversation.title else coalesce((
      select profile.display_name
      from public.chat_conversation_members member
      join public.profiles profile on profile.id = member.user_id
      where member.conversation_id = p_conversation.id and member.user_id <> p_user_id and member.left_at is null
      order by profile.display_name limit 1
    ), 'Direct message') end,
    'members', coalesce((
      select jsonb_agg(private.aoi_chat_profile(profile) order by profile.display_name)
      from public.chat_conversation_members member
      join public.profiles profile on profile.id = member.user_id
      where member.conversation_id = p_conversation.id and member.left_at is null and profile.status = 'active'
    ), '[]'::jsonb),
    'lastMessageAt', p_conversation.last_message_at,
    'lastMessage', (
      select private.aoi_chat_message_json(message)
      from public.chat_messages message
      where message.conversation_id = p_conversation.id
      order by message.created_at desc, message.id desc limit 1
    ),
    'unreadCount', (
      select count(*)
      from public.chat_messages message
      join public.chat_conversation_members mine
        on mine.conversation_id = p_conversation.id and mine.user_id = p_user_id
      where message.conversation_id = p_conversation.id
        and message.sender_id <> p_user_id
        and message.created_at > coalesce(mine.last_read_at, mine.joined_at)
    ),
    'muted', coalesce((
      select member.notification_level = 'muted'
      from public.chat_conversation_members member
      where member.conversation_id = p_conversation.id and member.user_id = p_user_id
    ), false),
    'archivedAt', p_conversation.archived_at,
    'createdAt', p_conversation.created_at,
    'updatedAt', p_conversation.updated_at
  );
$$;
revoke all on function private.aoi_chat_context() from public, anon, authenticated;
revoke all on function private.aoi_safe_profile(public.profiles) from public, anon, authenticated;
revoke all on function private.aoi_chat_profile(public.profiles) from public, anon, authenticated;
revoke all on function private.aoi_chat_message_json(public.chat_messages) from public, anon, authenticated;
revoke all on function private.aoi_chat_conversation_json(public.chat_conversations,uuid) from public, anon, authenticated;
create or replace function public.rpc_aoi_chat_bootstrap()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_caller public.profiles%rowtype;
  v_team_id uuid;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null then raise exception 'CHAT_ACCESS_REQUIRED'; end if;
  select profile.* into v_caller from public.profiles profile where profile.id = auth.uid();

  insert into public.chat_conversations (organization_id, kind, title, created_by)
  values (v_context.organization_id, 'team', 'Team', auth.uid())
  on conflict (organization_id) where kind = 'team'
  do update set updated_at = public.chat_conversations.updated_at
  returning id into v_team_id;

  insert into public.chat_conversation_members (organization_id, conversation_id, user_id)
  select v_context.organization_id, v_team_id, membership.user_id
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.organization_id = v_context.organization_id
    and membership.status = 'active' and profile.status = 'active'
  on conflict (conversation_id, user_id) do update set left_at = null;

  return jsonb_build_object(
    'currentUser', private.aoi_safe_profile(v_caller) || jsonb_build_object(
      'role', v_context.role,
      'organizationId', v_context.organization_id
    ),
    'members', coalesce((
      select jsonb_agg(
        private.aoi_chat_profile(profile) || jsonb_build_object('role', membership.role)
        order by case membership.role when 'admin' then 1 else 2 end, profile.display_name
      )
      from public.organization_memberships membership
      join public.profiles profile on profile.id = membership.user_id
      where membership.organization_id = v_context.organization_id
        and membership.status = 'active' and profile.status = 'active'
    ), '[]'::jsonb),
    'conversations', coalesce((
      select jsonb_agg(private.aoi_chat_conversation_json(conversation, auth.uid())
        order by conversation.last_message_at desc nulls last, conversation.created_at)
      from public.chat_conversation_members member
      join public.chat_conversations conversation on conversation.id = member.conversation_id
      where member.organization_id = v_context.organization_id
        and member.user_id = auth.uid() and member.left_at is null
        and conversation.archived_at is null
    ), '[]'::jsonb),
    'reactions', jsonb_build_array('thumbs_up', 'heart', 'celebrate', 'laugh', 'surprised', 'sad')
  );
end;
$$;
create or replace function public.rpc_aoi_chat_open_direct(p_member_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_conversation public.chat_conversations%rowtype;
  v_direct_key text;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null then raise exception 'CHAT_ACCESS_REQUIRED'; end if;
  if p_member_id is null or p_member_id = auth.uid() or not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = v_context.organization_id
      and membership.user_id = p_member_id
      and membership.status = 'active' and profile.status = 'active'
  ) then raise exception 'CHAT_DIRECT_MEMBER_INVALID'; end if;

  v_direct_key := least(auth.uid()::text, p_member_id::text) || ':' || greatest(auth.uid()::text, p_member_id::text);
  insert into public.chat_conversations (organization_id, kind, direct_key, created_by)
  values (v_context.organization_id, 'direct', v_direct_key, auth.uid())
  on conflict (organization_id, direct_key)
  do update set updated_at = public.chat_conversations.updated_at
  returning * into v_conversation;

  insert into public.chat_conversation_members (organization_id, conversation_id, user_id)
  values
    (v_context.organization_id, v_conversation.id, auth.uid()),
    (v_context.organization_id, v_conversation.id, p_member_id)
  on conflict (conversation_id, user_id) do update set left_at = null;

  return private.aoi_chat_conversation_json(v_conversation, auth.uid());
end;
$$;
create or replace function public.rpc_aoi_chat_messages(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_context record;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
  v_result jsonb;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null
    or not public.aoi_chat_is_participant(p_conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;

  with page as (
    select message.* from public.chat_messages message
    where message.organization_id = v_context.organization_id
      and message.conversation_id = p_conversation_id
      and (p_before is null or message.created_at < p_before)
    order by message.created_at desc, message.id desc limit v_limit
  )
  select coalesce(jsonb_agg(private.aoi_chat_message_json(message)
    order by message.created_at, message.id), '[]'::jsonb)
  into v_result from page message;
  return v_result;
end;
$$;
create or replace function public.rpc_aoi_chat_send(
  p_conversation_id uuid,
  p_body text,
  p_client_nonce uuid default null,
  p_reply_to_id uuid default null,
  p_attachments jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_body text := trim(coalesce(p_body, ''));
  v_message public.chat_messages%rowtype;
  v_attachment jsonb;
  v_path text;
  v_name text;
  v_mime text;
  v_size bigint;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null
    or not public.aoi_chat_is_participant(p_conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;
  if char_length(v_body) > 4000 then raise exception 'CHAT_MESSAGE_INVALID'; end if;
  if p_reply_to_id is not null and not exists (
    select 1 from public.chat_messages message
    where message.id = p_reply_to_id and message.conversation_id = p_conversation_id
  ) then raise exception 'CHAT_REPLY_INVALID'; end if;
  if jsonb_typeof(coalesce(p_attachments, '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) > 10
  then raise exception 'CHAT_ATTACHMENTS_INVALID'; end if;
  if char_length(v_body) = 0 and jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) = 0
  then raise exception 'CHAT_MESSAGE_INVALID'; end if;

  insert into public.chat_messages (
    organization_id, conversation_id, sender_id, reply_to_id, body, client_nonce
  ) values (
    v_context.organization_id, p_conversation_id, auth.uid(), p_reply_to_id, v_body, p_client_nonce
  )
  on conflict (conversation_id, sender_id, client_nonce) where client_nonce is not null
  do update set client_nonce = excluded.client_nonce
  returning * into v_message;

  for v_attachment in select value from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb)) loop
    v_path := nullif(trim(v_attachment->>'objectPath'), '');
    v_name := nullif(trim(v_attachment->>'fileName'), '');
    v_mime := nullif(lower(trim(v_attachment->>'mimeType')), '');
    begin
      v_size := (v_attachment->>'sizeBytes')::bigint;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'CHAT_ATTACHMENT_INVALID';
    end;
    if v_path is null or v_name is null or char_length(v_name) > 255
      or v_mime not in (
        'image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/plain', 'text/csv',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
      or v_size not between 1 and 10485760
      or position(v_context.organization_id::text || '/' || p_conversation_id::text || '/' || auth.uid()::text || '/' in v_path) <> 1
      or not exists (
        select 1 from storage.objects object
        where object.bucket_id = 'aoi-chat' and object.name = v_path
          and lower(coalesce(object.metadata->>'mimetype', '')) = v_mime
          and coalesce((object.metadata->>'size')::bigint, v_size) = v_size
      )
    then raise exception 'CHAT_ATTACHMENT_INVALID'; end if;

    insert into public.chat_attachments (
      organization_id, conversation_id, message_id, uploader_id,
      object_path, file_name, mime_type, size_bytes
    ) values (
      v_context.organization_id, p_conversation_id, v_message.id, auth.uid(),
      v_path, v_name, v_mime, v_size
    ) on conflict (object_path) do nothing;
  end loop;

  update public.chat_conversations conversation
  set last_message_at = greatest(coalesce(conversation.last_message_at, v_message.created_at), v_message.created_at),
      updated_at = clock_timestamp()
  where conversation.id = p_conversation_id;
  return private.aoi_chat_message_json(v_message);
end;
$$;
create or replace function public.rpc_aoi_chat_edit(p_message_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_body text := trim(coalesce(p_body, ''));
  v_message public.chat_messages%rowtype;
begin
  select * into v_context from private.aoi_chat_context();
  if char_length(v_body) not between 1 and 4000 then raise exception 'CHAT_MESSAGE_INVALID'; end if;
  update public.chat_messages message set
    body = v_body, edited_at = clock_timestamp(), updated_at = clock_timestamp()
  where message.id = p_message_id
    and message.organization_id = v_context.organization_id
    and message.sender_id = auth.uid()
    and message.deleted_at is null
  returning message.* into v_message;
  if v_message.id is null then raise exception 'CHAT_MESSAGE_EDIT_FORBIDDEN'; end if;
  return private.aoi_chat_message_json(v_message);
end;
$$;
create or replace function public.rpc_aoi_chat_delete(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_message public.chat_messages%rowtype;
begin
  select * into v_context from private.aoi_chat_context();
  update public.chat_messages message set
    body = '', deleted_at = clock_timestamp(), deleted_by = auth.uid(), updated_at = clock_timestamp()
  where message.id = p_message_id
    and message.organization_id = v_context.organization_id
    and message.sender_id = auth.uid()
    and message.deleted_at is null
  returning message.* into v_message;
  if v_message.id is null then raise exception 'CHAT_MESSAGE_DELETE_FORBIDDEN'; end if;
  update public.chat_attachments attachment set deleted_at = clock_timestamp()
  where attachment.message_id = v_message.id and attachment.deleted_at is null;
  return private.aoi_chat_message_json(v_message);
end;
$$;
create or replace function public.rpc_aoi_chat_moderate(
  p_message_id uuid,
  p_reason text,
  p_action text default 'remove'
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_message public.chat_messages%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null or v_context.role <> 'admin'
    or not public.is_org_admin(v_context.organization_id)
  then raise exception 'CHAT_ADMIN_REQUIRED'; end if;
  if p_action <> 'remove' or char_length(v_reason) not between 3 and 500
  then raise exception 'CHAT_MODERATION_INVALID'; end if;

  select message.* into v_message from public.chat_messages message
  where message.id = p_message_id and message.organization_id = v_context.organization_id
  for update;
  if v_message.id is null then raise exception 'CHAT_MESSAGE_NOT_FOUND'; end if;
  if v_message.deleted_at is not null then raise exception 'CHAT_MESSAGE_ALREADY_DELETED'; end if;

  insert into public.chat_moderation_events (
    organization_id, conversation_id, message_id, moderator_id, action, reason, details
  ) values (
    v_context.organization_id, v_message.conversation_id, v_message.id, auth.uid(), 'remove', v_reason,
    jsonb_build_object(
      'senderId', v_message.sender_id,
      'bodySha256', encode(digest(v_message.body, 'sha256'), 'hex'),
      'attachmentCount', (select count(*) from public.chat_attachments attachment where attachment.message_id = v_message.id)
    )
  );
  update public.chat_messages message set
    body = '', deleted_at = clock_timestamp(), deleted_by = auth.uid(), updated_at = clock_timestamp()
  where message.id = v_message.id returning message.* into v_message;
  update public.chat_attachments attachment set deleted_at = clock_timestamp()
  where attachment.message_id = v_message.id and attachment.deleted_at is null;
  return private.aoi_chat_message_json(v_message);
end;
$$;
create or replace function public.rpc_aoi_chat_toggle_reaction(p_message_id uuid, p_reaction text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_message public.chat_messages%rowtype;
  v_added boolean;
begin
  select * into v_context from private.aoi_chat_context();
  if p_reaction not in ('thumbs_up', 'heart', 'celebrate', 'laugh', 'surprised', 'sad')
  then raise exception 'CHAT_REACTION_INVALID'; end if;
  select message.* into v_message from public.chat_messages message
  where message.id = p_message_id and message.organization_id = v_context.organization_id
    and message.deleted_at is null;
  if v_message.id is null
    or not public.aoi_chat_is_participant(v_message.conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;

  delete from public.chat_message_reactions reaction
  where reaction.message_id = v_message.id and reaction.user_id = auth.uid() and reaction.reaction = p_reaction;
  if found then
    v_added := false;
  else
    insert into public.chat_message_reactions (
      organization_id, conversation_id, message_id, user_id, reaction
    ) values (
      v_context.organization_id, v_message.conversation_id, v_message.id, auth.uid(), p_reaction
    );
    v_added := true;
  end if;
  return jsonb_build_object('messageId', v_message.id, 'reaction', p_reaction, 'added', v_added);
end;
$$;
create or replace function public.rpc_aoi_chat_mark_read(
  p_conversation_id uuid,
  p_message_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_message public.chat_messages%rowtype;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null
    or not public.aoi_chat_is_participant(p_conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;
  if p_message_id is null then
    select message.* into v_message from public.chat_messages message
    where message.conversation_id = p_conversation_id
    order by message.created_at desc, message.id desc limit 1;
  else
    select message.* into v_message from public.chat_messages message
    where message.id = p_message_id and message.conversation_id = p_conversation_id;
    if v_message.id is null then raise exception 'CHAT_MESSAGE_NOT_FOUND'; end if;
  end if;
  if v_message.id is not null then
    update public.chat_conversation_members member set
      last_read_message_id = case
        when member.last_read_at is null or v_message.created_at >= member.last_read_at then v_message.id
        else member.last_read_message_id end,
      last_read_at = greatest(coalesce(member.last_read_at, v_message.created_at), v_message.created_at)
    where member.conversation_id = p_conversation_id and member.user_id = auth.uid();
  end if;
  return jsonb_build_object(
    'conversationId', p_conversation_id,
    'lastReadMessageId', v_message.id,
    'lastReadAt', v_message.created_at
  );
end;
$$;
create or replace function public.rpc_aoi_chat_search(
  p_query text,
  p_conversation_id uuid default null,
  p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_context record;
  v_query text := trim(coalesce(p_query, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
  v_result jsonb;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null or char_length(v_query) < 2 then raise exception 'CHAT_SEARCH_INVALID'; end if;
  if p_conversation_id is not null
    and not public.aoi_chat_is_participant(p_conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;

  select coalesce(jsonb_agg(private.aoi_chat_message_json(result.message)
    order by result.rank desc, (result.message).created_at desc), '[]'::jsonb)
  into v_result
  from (
    select message, 1::real as rank
    from public.chat_messages message
    where message.organization_id = v_context.organization_id
      and message.deleted_at is null
      and (p_conversation_id is null or message.conversation_id = p_conversation_id)
      and exists (
        select 1 from public.chat_conversation_members member
        where member.conversation_id = message.conversation_id
          and member.user_id = auth.uid() and member.left_at is null
      )
      and message.body ilike '%' || v_query || '%'
    order by rank desc, message.created_at desc limit v_limit
  ) result;
  return v_result;
end;
$$;
create or replace function public.rpc_aoi_update_profile(p_profile jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_context record;
  v_display_name text := trim(coalesce(p_profile->>'displayName', ''));
  v_job_title text := nullif(trim(p_profile->>'jobTitle'), '');
  v_bio text := nullif(trim(p_profile->>'bio'), '');
  v_phone text := nullif(trim(p_profile->>'phone'), '');
  v_timezone text := coalesce(nullif(trim(p_profile->>'timezone'), ''), 'UTC');
  v_locale text := coalesce(nullif(trim(p_profile->>'locale'), ''), 'en');
  v_avatar_key text := nullif(trim(p_profile->>'avatarKey'), '');
  v_avatar_path text := nullif(trim(p_profile->>'avatarPath'), '');
  v_saved public.profiles%rowtype;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null then raise exception 'PROFILE_ACCESS_REQUIRED'; end if;
  if char_length(v_display_name) not between 2 and 80
    or char_length(coalesce(v_job_title, '')) > 100
    or char_length(coalesce(v_bio, '')) > 240
    or char_length(coalesce(v_phone, '')) > 40
    or v_locale not in ('en', 'zh-CN')
    or (v_avatar_key is not null and v_avatar_key not in ('coral', 'teal', 'blue', 'purple', 'gold', 'slate', 'rose', 'sand'))
    or not exists (select 1 from pg_catalog.pg_timezone_names timezone where timezone.name = v_timezone)
  then raise exception 'PROFILE_INVALID'; end if;
  if v_avatar_path is not null and (
    position(v_context.organization_id::text || '/' || auth.uid()::text || '/' in v_avatar_path) <> 1
    or not exists (
      select 1 from storage.objects object
      where object.bucket_id = 'aoi-avatars' and object.name = v_avatar_path
        and lower(coalesce(object.metadata->>'mimetype', '')) in ('image/jpeg', 'image/png', 'image/webp')
        and coalesce((object.metadata->>'size')::bigint, 0) between 1 and 3145728
    )
  ) then raise exception 'PROFILE_AVATAR_INVALID'; end if;

  update public.profiles profile set
    display_name = v_display_name,
    job_title = v_job_title,
    bio = v_bio,
    phone = v_phone,
    timezone = v_timezone,
    locale = v_locale,
    avatar_key = v_avatar_key,
    avatar_path = v_avatar_path,
    updated_at = clock_timestamp()
  where profile.id = auth.uid() and profile.status = 'active'
  returning profile.* into v_saved;
  if v_saved.id is null then raise exception 'PROFILE_ACCESS_REQUIRED'; end if;
  update public.staff_profiles staff set
    phone = v_phone,
    timezone = v_timezone,
    updated_at = clock_timestamp()
  where staff.organization_id = v_context.organization_id and staff.user_id = auth.uid();
  return private.aoi_safe_profile(v_saved);
end;
$$;
create or replace function public.rpc_aoi_member_profile(p_member_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_context record;
  v_profile public.profiles%rowtype;
  v_role text;
begin
  select * into v_context from private.aoi_chat_context();
  select profile.* into v_profile
  from public.organization_memberships membership
  join public.profiles profile on profile.id = membership.user_id
  where membership.organization_id = v_context.organization_id
    and membership.user_id = p_member_id
    and membership.status = 'active' and profile.status = 'active';
  if v_profile.id is null then raise exception 'PROFILE_MEMBER_FORBIDDEN'; end if;
  select membership.role into v_role
  from public.organization_memberships membership
  where membership.organization_id = v_context.organization_id and membership.user_id = p_member_id;
  return private.aoi_safe_profile(v_profile) || jsonb_build_object('role', v_role);
end;
$$;
create or replace function public.rpc_current_user_context()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'loginIdentifier', profile.login_identifier,
    'locale', profile.locale,
    'mustChangePassword', profile.must_change_password,
    'jobTitle', profile.job_title,
    'bio', profile.bio,
    'phone', profile.phone,
    'timezone', profile.timezone,
    'avatarKey', profile.avatar_key,
    'avatarPath', profile.avatar_path,
    'role', membership.role,
    'isOwner', membership.is_owner,
    'organizationId', organization.id,
    'organizationName', organization.name,
    'projectId', project.id,
    'projectName', project.name
  )
  from public.profiles profile
  join public.organization_memberships membership
    on membership.user_id = profile.id and membership.status in ('active', 'password_change_required')
  join public.organizations organization
    on organization.id = membership.organization_id and organization.status = 'active'
  left join lateral (
    select project_row.id, project_row.name
    from public.projects project_row
    where project_row.organization_id = organization.id and project_row.status = 'active'
    order by project_row.created_at, project_row.id limit 1
  ) project on true
  where profile.id = auth.uid() and profile.status in ('active', 'password_change_required')
  order by case membership.role when 'admin' then 1 else 2 end, membership.joined_at
  limit 1;
$$;
revoke all on function public.rpc_aoi_chat_bootstrap() from public, anon;
revoke all on function public.rpc_aoi_chat_open_direct(uuid) from public, anon;
revoke all on function public.rpc_aoi_chat_messages(uuid,timestamptz,integer) from public, anon;
revoke all on function public.rpc_aoi_chat_send(uuid,text,uuid,uuid,jsonb) from public, anon;
revoke all on function public.rpc_aoi_chat_edit(uuid,text) from public, anon;
revoke all on function public.rpc_aoi_chat_delete(uuid) from public, anon;
revoke all on function public.rpc_aoi_chat_moderate(uuid,text,text) from public, anon;
revoke all on function public.rpc_aoi_chat_toggle_reaction(uuid,text) from public, anon;
revoke all on function public.rpc_aoi_chat_mark_read(uuid,uuid) from public, anon;
revoke all on function public.rpc_aoi_chat_search(text,uuid,integer) from public, anon;
revoke all on function public.rpc_aoi_update_profile(jsonb) from public, anon;
revoke all on function public.rpc_aoi_member_profile(uuid) from public, anon;
revoke all on function public.rpc_current_user_context() from public, anon;
grant execute on function public.rpc_aoi_chat_bootstrap() to authenticated;
grant execute on function public.rpc_aoi_chat_open_direct(uuid) to authenticated;
grant execute on function public.rpc_aoi_chat_messages(uuid,timestamptz,integer) to authenticated;
grant execute on function public.rpc_aoi_chat_send(uuid,text,uuid,uuid,jsonb) to authenticated;
grant execute on function public.rpc_aoi_chat_edit(uuid,text) to authenticated;
grant execute on function public.rpc_aoi_chat_delete(uuid) to authenticated;
grant execute on function public.rpc_aoi_chat_moderate(uuid,text,text) to authenticated;
grant execute on function public.rpc_aoi_chat_toggle_reaction(uuid,text) to authenticated;
grant execute on function public.rpc_aoi_chat_mark_read(uuid,uuid) to authenticated;
grant execute on function public.rpc_aoi_chat_search(text,uuid,integer) to authenticated;
grant execute on function public.rpc_aoi_update_profile(jsonb) to authenticated;
grant execute on function public.rpc_aoi_member_profile(uuid) to authenticated;
grant execute on function public.rpc_current_user_context() to authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'aoi-avatars', 'aoi-avatars', false, 3145728,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'aoi-chat', 'aoi-chat', false, 10485760,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/plain', 'text/csv',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists aoi_avatar_member_read on storage.objects;
create policy aoi_avatar_member_read on storage.objects
for select to authenticated using (
  bucket_id = 'aoi-avatars'
  and array_length(storage.foldername(name), 1) = 2
  and public.aoi_profile_avatar_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2]
  )
);
drop policy if exists aoi_avatar_own_insert on storage.objects;
create policy aoi_avatar_own_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'aoi-avatars'
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.aoi_profile_avatar_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2]
  )
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);
drop policy if exists aoi_avatar_own_update on storage.objects;
create policy aoi_avatar_own_update on storage.objects
for update to authenticated using (
  bucket_id = 'aoi-avatars' and (storage.foldername(name))[2] = auth.uid()::text
) with check (
  bucket_id = 'aoi-avatars'
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.aoi_profile_avatar_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2]
  )
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);
drop policy if exists aoi_avatar_own_delete on storage.objects;
create policy aoi_avatar_own_delete on storage.objects
for delete to authenticated using (
  bucket_id = 'aoi-avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.aoi_profile_avatar_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2]
  )
);
drop policy if exists aoi_chat_attachment_read on storage.objects;
create policy aoi_chat_attachment_read on storage.objects
for select to authenticated using (
  bucket_id = 'aoi-chat'
  and array_length(storage.foldername(name), 1) = 3
  and public.aoi_chat_storage_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2], (storage.foldername(name))[3], false
  )
  and (
    (
      (storage.foldername(name))[3] = auth.uid()::text
      and not exists (
        select 1 from public.chat_attachments attachment
        where attachment.object_path = name
      )
    )
    or exists (
      select 1 from public.chat_attachments attachment
      where attachment.object_path = name and attachment.deleted_at is null
    )
  )
);
drop policy if exists aoi_chat_attachment_own_insert on storage.objects;
create policy aoi_chat_attachment_own_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'aoi-chat'
  and array_length(storage.foldername(name), 1) = 3
  and public.aoi_chat_storage_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2], (storage.foldername(name))[3], true
  )
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt', 'csv', 'xls', 'xlsx', 'doc', 'docx')
);
drop policy if exists aoi_chat_attachment_own_update on storage.objects;
create policy aoi_chat_attachment_own_update on storage.objects
for update to authenticated using (
  bucket_id = 'aoi-chat' and (storage.foldername(name))[3] = auth.uid()::text
) with check (
  bucket_id = 'aoi-chat'
  and array_length(storage.foldername(name), 1) = 3
  and public.aoi_chat_storage_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2], (storage.foldername(name))[3], true
  )
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt', 'csv', 'xls', 'xlsx', 'doc', 'docx')
);
drop policy if exists aoi_chat_attachment_own_delete on storage.objects;
create policy aoi_chat_attachment_own_delete on storage.objects
for delete to authenticated using (
  bucket_id = 'aoi-chat'
  and public.aoi_chat_storage_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2], (storage.foldername(name))[3], true
  )
);
drop policy if exists aoi_chat_realtime_read on realtime.messages;
create policy aoi_chat_realtime_read on realtime.messages
for select to authenticated using (
  extension in ('presence', 'broadcast')
  and public.aoi_chat_topic_authorized((select realtime.topic()))
);
drop policy if exists aoi_chat_realtime_write on realtime.messages;
create policy aoi_chat_realtime_write on realtime.messages
for insert to authenticated with check (
  extension in ('presence', 'broadcast')
  and public.aoi_chat_topic_authorized((select realtime.topic()))
);
do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages'
    ) then
      alter publication supabase_realtime add table public.chat_messages;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_conversations'
    ) then
      alter publication supabase_realtime add table public.chat_conversations;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_conversation_members'
    ) then
      alter publication supabase_realtime add table public.chat_conversation_members;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_message_reactions'
    ) then
      alter publication supabase_realtime add table public.chat_message_reactions;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_attachments'
    ) then
      alter publication supabase_realtime add table public.chat_attachments;
    end if;
  end if;
end;
$$;
