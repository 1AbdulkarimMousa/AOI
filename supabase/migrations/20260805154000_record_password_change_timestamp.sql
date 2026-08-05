-- Persist voluntary password changes without granting access-state mutations.

create or replace function public.rpc_record_password_changed_at()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed_at timestamptz;
begin
  update public.profiles
  set password_changed_at = clock_timestamp(),
      password_reminder_snoozed_until = null,
      updated_at = clock_timestamp()
  where id = (select auth.uid()) and status = 'active' and not must_change_password
  returning password_changed_at into v_changed_at;
  if v_changed_at is null then raise exception 'ACTIVE_PROFILE_REQUIRED'; end if;
  return v_changed_at;
end;
$$;

revoke all on function public.rpc_record_password_changed_at() from public, anon;
grant execute on function public.rpc_record_password_changed_at() to authenticated;
