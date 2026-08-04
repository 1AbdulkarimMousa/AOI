import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships a role-scoped daily EOD persistence contract", async () => {
  const migration = await readFile(new URL("supabase/migrations/20260804164524_daily_eod_briefs.sql", root), "utf8");

  assert.match(migration, /create table public\.daily_eod_briefs/);
  assert.match(migration, /unique \(project_id, author_id, brief_date\)/);
  assert.match(migration, /foreign key \(organization_id, project_id\)/);
  assert.match(migration, /workflow_status text not null default 'draft'/);
  assert.match(migration, /executive_owners text\[\]/);
  assert.match(migration, /tomorrow_priorities text\[\]/);
  assert.match(migration, /evidence_links jsonb/);
  assert.match(migration, /alter table public\.daily_eod_briefs enable row level security/);
  assert.match(migration, /daily_eod_own_read/);
  assert.match(migration, /daily_eod_admin_read/);
  assert.match(migration, /revoke all on public\.daily_eod_briefs from anon, authenticated/);
});

test("derives due state and mutations through authenticated RPCs", async () => {
  const migration = await readFile(new URL("supabase/migrations/20260804164524_daily_eod_briefs.sql", root), "utf8");

  assert.match(migration, /create or replace function public\.rpc_aoi_daily_eod_snapshot\(\)/);
  assert.match(migration, /create or replace function public\.rpc_aoi_save_daily_eod_brief\(\s*p_payload jsonb,\s*p_expected_updated_at timestamptz/);
  assert.match(migration, /create or replace function public\.rpc_aoi_admin_update_daily_eod_brief\(/);
  assert.match(migration, /create or replace function public\.rpc_aoi_daily_eod_reports\(/);
  assert.match(migration, /timezone\(v_timezone, clock_timestamp\(\)\)/);
  assert.match(migration, /extract\(isodow from v_brief_date\) between 1 and 5/);
  assert.match(migration, /time '17:00'/);
  assert.match(migration, /EOD_STALE_WRITE/);
  assert.match(migration, /EOD_ADMIN_EDIT_REASON_REQUIRED/);
  assert.match(migration, /caller\.status = 'active'/);
  assert.match(migration, /last_edit_reason = null/);
  assert.match(migration, /insert into public\.audit_events/);
  assert.match(migration, /revoke all on function public\.rpc_aoi_daily_eod_snapshot\(\) from public, anon/);
  assert.match(migration, /grant execute on function public\.rpc_aoi_daily_eod_snapshot\(\) to authenticated/);
});

test("limits report data by role and supports searchable history", async () => {
  const migration = await readFile(new URL("supabase/migrations/20260804164524_daily_eod_briefs.sql", root), "utf8");

  assert.match(migration, /v_role = 'admin' or brief\.author_id = auth\.uid\(\)/);
  assert.match(migration, /p_filters->>'search'/);
  assert.match(migration, /p_filters->>'fromDate'/);
  assert.match(migration, /p_filters->>'toDate'/);
  assert.match(migration, /'auditHistory'/);
  assert.match(migration, /'projectCode'/);
  assert.match(migration, /where brief\.organization_id = v_org_id/);
  assert.match(migration, /order by brief\.brief_date desc, brief\.updated_at desc/);
});
