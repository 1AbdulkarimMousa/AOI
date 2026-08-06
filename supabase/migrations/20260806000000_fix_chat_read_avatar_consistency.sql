-- Keep peer avatar reads behind a definer boundary and avoid read-state refresh loops.
create or replace function public.aoi_profile_avatar_read_authorized(
  p_organization_id text,
  p_profile_id text,
  p_object_path text
)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.aoi_profile_avatar_authorized(p_organization_id, p_profile_id)
    and exists (
      select 1 from public.profiles profile
      where profile.id::text = p_profile_id
        and profile.avatar_path = p_object_path
    );
$$;

revoke all on function public.aoi_profile_avatar_read_authorized(text,text,text) from public, anon;
grant execute on function public.aoi_profile_avatar_read_authorized(text,text,text) to authenticated;

drop policy if exists aoi_avatar_member_read on storage.objects;
create policy aoi_avatar_member_read on storage.objects
for select to authenticated using (
  bucket_id = 'aoi-avatars'
  and array_length(storage.foldername(name), 1) = 2
  and public.aoi_profile_avatar_authorized(
    (storage.foldername(name))[1], (storage.foldername(name))[2]
  )
  and (
    (storage.foldername(name))[2] = auth.uid()::text
    or public.aoi_profile_avatar_read_authorized(
      (storage.foldername(name))[1], (storage.foldername(name))[2], name
    )
  )
);

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
      last_read_message_id = v_message.id,
      last_read_at = v_message.created_at
    where member.conversation_id = p_conversation_id
      and member.user_id = auth.uid()
      and (member.last_read_at is null or v_message.created_at > member.last_read_at);
  end if;
  return jsonb_build_object(
    'conversationId', p_conversation_id,
    'lastReadMessageId', v_message.id,
    'lastReadAt', v_message.created_at
  );
end;
$$;
