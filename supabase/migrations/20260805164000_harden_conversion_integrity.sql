-- Reject ambiguous identity matches, preserve connected links, retain consent
-- provenance, and award consent XP once per respondent rather than per version.

alter table public.consent_records add column if not exists source_reference text;

create or replace function private.protect_participant_identity_links()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.crm_contact_id is not null and new.crm_contact_id is distinct from old.crm_contact_id then
    raise exception 'PARTICIPANT_LINK_IMMUTABLE';
  end if;
  if old.respondent_id is not null and new.respondent_id is distinct from old.respondent_id then
    raise exception 'PARTICIPANT_LINK_IMMUTABLE';
  end if;
  if old.respondent_id is null and new.respondent_id is not null and not exists (
    select 1 from public.respondents respondent
    where respondent.id = new.respondent_id
      and respondent.participant_recruitment_id = old.id
      and respondent.organization_id = old.organization_id
      and respondent.project_id = old.project_id
      and respondent.crm_contact_id = new.crm_contact_id
  ) then
    raise exception 'PARTICIPANT_LINK_IMMUTABLE';
  end if;
  return new;
end;
$$;
revoke all on function private.protect_participant_identity_links() from public, anon, authenticated;
drop trigger if exists protect_participant_identity_links on public.participant_recruitment;
create trigger protect_participant_identity_links
before update of crm_contact_id, respondent_id on public.participant_recruitment
for each row execute function private.protect_participant_identity_links();

create or replace function private.source_recruitment_consent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_recruitment_id uuid;
begin
  select respondent.participant_recruitment_id into v_recruitment_id
  from public.respondents respondent where respondent.id = new.respondent_id;
  if v_recruitment_id is not null and new.version = 1 then
    new.source_reference := coalesce(new.source_reference, 'participant_recruitment:' || v_recruitment_id::text);
    new.recontact_allowed := false;
  end if;
  return new;
end;
$$;
revoke all on function private.source_recruitment_consent() from public, anon, authenticated;
drop trigger if exists source_recruitment_consent on public.consent_records;
create trigger source_recruitment_consent before insert on public.consent_records
for each row execute function private.source_recruitment_consent();

create or replace function private.reward_aoi_consent_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'granted' then
    perform private.award_aoi_gamification_event(
      new.organization_id, new.project_id, new.recorded_by, 'consent_granted', 20,
      'respondents', new.respondent_id,
      jsonb_build_object('respondentId', new.respondent_id, 'version', new.version)
    );
  end if;
  return new;
end;
$$;
revoke all on function private.reward_aoi_consent_grant() from public, anon, authenticated;

alter function public.rpc_aoi_convert_recruitment_to_respondent(uuid)
  rename to rpc_aoi_convert_recruitment_to_respondent_core;
revoke all on function public.rpc_aoi_convert_recruitment_to_respondent_core(uuid)
  from public, anon, authenticated;

create function public.rpc_aoi_convert_recruitment_to_respondent(p_recruitment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_recruitment public.participant_recruitment%rowtype;
  v_email_matches uuid[];
  v_phone_matches uuid[];
begin
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.user_id = v_actor_id and membership.role = 'admin' and membership.status = 'active'
  ) then raise exception 'ADMIN_CONVERSION_REQUIRED'; end if;

  select recruitment.* into v_recruitment
  from public.participant_recruitment recruitment
  where recruitment.id = p_recruitment_id
    and public.is_org_admin(recruitment.organization_id)
  for update;
  if v_recruitment.id is null then raise exception 'PARTICIPANT_NOT_FOUND'; end if;
  if v_recruitment.respondent_id is not null or v_recruitment.crm_contact_id is not null then
    return public.rpc_aoi_convert_recruitment_to_respondent_core(p_recruitment_id);
  end if;

  select coalesce(array_agg(contact.id order by contact.updated_at desc), '{}'::uuid[])
  into v_email_matches
  from public.crm_contacts contact
  where contact.organization_id = v_recruitment.organization_id
    and contact.project_id = v_recruitment.project_id
    and nullif(trim(v_recruitment.email), '') is not null
    and lower(contact.email) = lower(trim(v_recruitment.email));

  select coalesce(array_agg(contact.id order by contact.updated_at desc), '{}'::uuid[])
  into v_phone_matches
  from public.crm_contacts contact
  where contact.organization_id = v_recruitment.organization_id
    and contact.project_id = v_recruitment.project_id
    and nullif(regexp_replace(coalesce(v_recruitment.phone,''), '[^0-9]', '', 'g'), '') is not null
    and regexp_replace(coalesce(contact.phone,''), '[^0-9]', '', 'g') = regexp_replace(v_recruitment.phone, '[^0-9]', '', 'g');

  if cardinality(v_email_matches) > 1 or cardinality(v_phone_matches) > 1
    or (cardinality(v_email_matches) = 1 and cardinality(v_phone_matches) = 1
      and v_email_matches[1] <> v_phone_matches[1]) then
    raise exception 'CONTACT_IDENTITY_AMBIGUOUS';
  end if;

  return public.rpc_aoi_convert_recruitment_to_respondent_core(p_recruitment_id);
end;
$$;

revoke all on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) from public, anon;
grant execute on function public.rpc_aoi_convert_recruitment_to_respondent(uuid) to authenticated;
