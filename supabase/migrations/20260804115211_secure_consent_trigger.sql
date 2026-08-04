-- Keep the narrowly privileged consent synchronizer outside the exposed schema.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.sync_aoi_consent_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_current public.consent_records%rowtype;
begin
  select c.* into v_current from public.consent_records c
  where c.respondent_id = new.respondent_id
  order by c.version desc limit 1;

  update public.respondents r
  set consent_status = v_current.status, updated_at = now()
  where r.id = v_current.respondent_id
    and r.organization_id = v_current.organization_id
    and r.project_id = v_current.project_id;

  if v_current.status <> 'granted' then
    update public.research_attachments a set status = 'withdrawn'
    where a.respondent_id = v_current.respondent_id and a.status = 'active'
      and a.bucket_id in ('aoi-recordings', 'aoi-oral-images');
  end if;
  return new;
end; $$;

revoke all on function private.sync_aoi_consent_status() from public, anon, authenticated;

drop trigger if exists sync_aoi_consent_status on public.consent_records;
create trigger sync_aoi_consent_status after insert on public.consent_records
  for each row execute function private.sync_aoi_consent_status();

drop function if exists public.sync_aoi_consent_status();

-- Projects created after April 2026 do not auto-grant Data API table access.
grant select, insert on public.organization_memberships to service_role;
grant select, insert on public.profiles to service_role;
