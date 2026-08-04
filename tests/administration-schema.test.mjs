import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = new URL("../supabase/migrations/20260804190000_administration_foundation.sql", import.meta.url);

test("defines staff profiles, onboarding, ownership, archival, and transfer history", async () => {
  const sql = await readFile(migration, "utf8");

  assert.match(sql, /create table public\.staff_profiles/i);
  assert.match(sql, /create table public\.staff_onboarding_steps/i);
  assert.match(sql, /create table public\.administration_transfer_jobs/i);
  assert.match(sql, /status in \('active', 'invited', 'password_change_required', 'disabled', 'archived'\)/i);
  assert.match(sql, /is_owner boolean not null default false/i);
  assert.match(sql, /departure_date date/i);
  assert.match(sql, /archive_reason text/i);
  assert.match(sql, /where is_owner/i);
});

test("enforces active profiles, owner controls, audit events, and archival handoff", async () => {
  const sql = await readFile(migration, "utf8");

  assert.match(sql, /profile\.status = 'active'/i);
  assert.match(sql, /create or replace function public\.is_org_owner/i);
  assert.match(sql, /LAST_ACTIVE_ADMIN/i);
  assert.match(sql, /OWNER_TRANSFER_REQUIRED/i);
  assert.match(sql, /OWNER_REQUIRED/i);
  assert.match(sql, /rpc_admin_archive_user/i);
  assert.match(sql, /p_replacement_user_id/i);
  assert.match(sql, /insert into public\.audit_events/i);
});

test("provides focused admin snapshots and permission-aware data transfer RPCs", async () => {
  const sql = await readFile(migration, "utf8");

  assert.match(sql, /rpc_admin_overview/i);
  assert.match(sql, /rpc_admin_people/i);
  assert.match(sql, /rpc_admin_person_detail/i);
  assert.match(sql, /rpc_admin_upsert_staff_profile/i);
  assert.match(sql, /rpc_admin_create_task_v2/i);
  assert.match(sql, /acceptance_criteria/i);
  assert.match(sql, /rpc_admin_export_data/i);
  assert.match(sql, /rpc_admin_import_data/i);
  assert.match(sql, /sync_candidate_to_crm/i);
  assert.match(sql, /candidate_crm_sync/i);
  assert.match(sql, /rpc_accept_invitation/i);
  assert.match(sql, /rpc_complete_password_change/i);
  assert.match(sql, /password_change_required/i);
  assert.match(sql, /rpc_update_onboarding_step/i);
  assert.match(sql, /onboarding_first_eod/i);
  assert.match(sql, /packageHash/i);
  assert.match(sql, /IMPORT_PREVIEW_REQUIRED/i);
  assert.match(sql, /FULL_RESTORE_OWNER_REQUIRED/i);
  assert.match(sql, /revoke all on function/i);
  assert.match(sql, /grant execute on function/i);
});
