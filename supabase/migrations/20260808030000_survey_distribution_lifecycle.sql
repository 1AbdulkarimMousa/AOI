-- Phase 5: authenticated survey link and invitation lifecycle controls.

create or replace function public.rpc_aoi_update_survey_link_status(p_link_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.survey_links;
begin
  if p_status not in ('active', 'paused', 'revoked') then raise exception 'SURVEY_LINK_STATUS_INVALID'; end if;
  select link.* into v_link
  from public.survey_links link
  where link.id = p_link_id and public.is_org_admin(link.organization_id)
  for update;
  if v_link.id is null then raise exception 'SURVEY_LINK_NOT_FOUND'; end if;
  if v_link.link_status in ('revoked', 'expired', 'exhausted') and p_status = 'active' then
    raise exception 'SURVEY_LINK_REACTIVATION_INVALID';
  end if;
  update public.survey_links
  set link_status = p_status,
      revoked_by = case when p_status = 'revoked' then auth.uid() else revoked_by end,
      revoked_at = case when p_status = 'revoked' then coalesce(revoked_at, now()) else revoked_at end
  where id = v_link.id
  returning * into v_link;
  insert into public.audit_events(organization_id, actor_id, entity_type, entity_id, action, metadata)
  values(v_link.organization_id, auth.uid(), 'survey_link', v_link.id, 'status_changed', jsonb_build_object('status', p_status));
  return jsonb_build_object('id', v_link.id, 'status', v_link.link_status);
end;
$$;

create or replace function public.rpc_aoi_revoke_survey_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.survey_invitations;
begin
  select invitation.* into v_invitation
  from public.survey_invitations invitation
  where invitation.id = p_invitation_id and public.is_org_admin(invitation.organization_id)
  for update;
  if v_invitation.id is null then raise exception 'SURVEY_INVITATION_NOT_FOUND'; end if;
  if v_invitation.invitation_status in ('completed', 'revoked') then raise exception 'SURVEY_INVITATION_LOCKED'; end if;
  update public.survey_invitations set invitation_status = 'revoked' where id = v_invitation.id returning * into v_invitation;
  insert into public.audit_events(organization_id, actor_id, entity_type, entity_id, action, metadata)
  values(v_invitation.organization_id, auth.uid(), 'survey_invitation', v_invitation.id, 'revoked', '{}'::jsonb);
  return jsonb_build_object('id', v_invitation.id, 'status', v_invitation.invitation_status);
end;
$$;

revoke all on function public.rpc_aoi_update_survey_link_status(uuid, text), public.rpc_aoi_revoke_survey_invitation(uuid) from public, anon;
grant execute on function public.rpc_aoi_update_survey_link_status(uuid, text), public.rpc_aoi_revoke_survey_invitation(uuid) to authenticated;
