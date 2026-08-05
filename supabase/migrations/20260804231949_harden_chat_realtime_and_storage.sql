-- Preserve existing private-schema helpers and close realtime/storage privacy gaps.
grant usage on schema private to authenticated;
alter table public.chat_message_reactions add column if not exists removed_at timestamptz;
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
        where reaction.message_id = p_message.id and reaction.removed_at is null
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

  update public.chat_message_reactions reaction
  set removed_at = case when reaction.removed_at is null then clock_timestamp() else null end
  where reaction.message_id = v_message.id and reaction.user_id = auth.uid() and reaction.reaction = p_reaction
  returning reaction.removed_at is null into v_added;
  if not found then
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
create or replace function public.rpc_aoi_chat_message_by_nonce(
  p_conversation_id uuid,
  p_client_nonce uuid
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context from private.aoi_chat_context();
  if v_context.organization_id is null
    or not public.aoi_chat_is_participant(p_conversation_id, v_context.organization_id)
  then raise exception 'CHAT_CONVERSATION_FORBIDDEN'; end if;
  select private.aoi_chat_message_json(message) into v_result
  from public.chat_messages message
  where message.organization_id = v_context.organization_id
    and message.conversation_id = p_conversation_id
    and message.sender_id = auth.uid()
    and message.client_nonce = p_client_nonce;
  return v_result;
end;
$$;
revoke all on function public.rpc_aoi_chat_message_by_nonce(uuid,uuid) from public, anon;
grant execute on function public.rpc_aoi_chat_message_by_nonce(uuid,uuid) to authenticated;
grant select on public.chat_moderation_events to authenticated;
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
    or exists (
      select 1 from public.profiles profile
      where profile.id::text = (storage.foldername(name))[2]
        and profile.avatar_path = name
    )
  )
);
drop policy if exists aoi_chat_attachment_own_delete on storage.objects;
drop policy if exists aoi_chat_attachment_owner_or_admin_delete on storage.objects;
create policy aoi_chat_attachment_owner_or_admin_delete on storage.objects
for delete to authenticated using (
  bucket_id = 'aoi-chat'
  and (
    public.aoi_chat_storage_authorized(
      (storage.foldername(name))[1], (storage.foldername(name))[2], (storage.foldername(name))[3], true
    )
    or exists (
      select 1
      from public.organization_memberships membership
      join public.chat_conversations conversation on conversation.organization_id = membership.organization_id
      where membership.organization_id::text = (storage.foldername(name))[1]
        and conversation.id::text = (storage.foldername(name))[2]
        and membership.user_id = auth.uid()
        and membership.role = 'admin'
        and membership.status = 'active'
    )
  )
);
