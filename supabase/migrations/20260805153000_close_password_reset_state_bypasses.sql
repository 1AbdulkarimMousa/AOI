-- Prevent stale JWTs and concurrent lifecycle changes from clearing reset state.

create or replace function private.admin_restore_password_state(
  p_organization_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid,
  p_previous jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_expected integer;
  v_restored integer := 0;
  v_row_count integer;
begin
  if not exists (
    select 1 from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.user_id
    where membership.organization_id = p_organization_id and membership.user_id = p_actor_id
      and membership.role = 'admin' and membership.status = 'active'
      and profile.status = 'active' and not profile.must_change_password
  ) then raise exception 'ADMIN_REQUIRED'; end if;

  update public.profiles
  set status = p_previous->>'profileStatus',
      must_change_password = coalesce((p_previous->>'mustChangePassword')::boolean, false),
      password_reminder_seeded_at = nullif(p_previous->>'passwordReminderSeededAt', '')::timestamptz,
      password_reminder_snoozed_until = nullif(p_previous->>'passwordReminderSnoozedUntil', '')::timestamptz,
      updated_at = clock_timestamp()
  where id = p_target_user_id and status = 'password_change_required' and must_change_password;
  get diagnostics v_row_count = row_count;
  if v_row_count <> 1 then raise exception 'PASSWORD_RESET_STATE_CHANGED'; end if;

  if jsonb_typeof(p_previous->'membershipStatuses') = 'object' then
    v_expected := jsonb_object_length(p_previous->'membershipStatuses');
    for v_item in select key, value from jsonb_each_text(p_previous->'membershipStatuses') loop
      update public.organization_memberships
      set status = v_item.value, updated_at = clock_timestamp()
      where organization_id = v_item.key::uuid and user_id = p_target_user_id and status = 'password_change_required';
      get diagnostics v_row_count = row_count;
      v_restored := v_restored + v_row_count;
    end loop;
  else
    v_expected := 1;
    update public.organization_memberships
    set status = p_previous->>'membershipStatus', updated_at = clock_timestamp()
    where organization_id = p_organization_id and user_id = p_target_user_id and status = 'password_change_required';
    get diagnostics v_restored = row_count;
  end if;
  if v_restored <> v_expected then raise exception 'PASSWORD_RESET_STATE_CHANGED'; end if;
end;
$$;

revoke all on function public.rpc_mark_password_changed() from public, anon, authenticated;
