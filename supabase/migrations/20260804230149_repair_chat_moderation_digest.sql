-- Qualify pgcrypto under the RPC's intentionally empty search path.
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
      'bodySha256', pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_message.body, 'UTF8'), 'sha256'), 'hex'),
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

revoke all on function public.rpc_aoi_chat_moderate(uuid,text,text) from public, anon;
grant execute on function public.rpc_aoi_chat_moderate(uuid,text,text) to authenticated;
