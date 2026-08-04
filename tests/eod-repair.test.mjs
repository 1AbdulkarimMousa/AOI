import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationsUrl = new URL("../supabase/migrations/", import.meta.url);

async function repairMigration() {
  const names = await readdir(migrationsUrl);
  const name = names.find((entry) => entry.endsWith("_repair_daily_eod_controls.sql"));
  assert.ok(name, "daily EOD repair migration is missing");
  return readFile(new URL(name, migrationsUrl), "utf8");
}

test("repairs daily EOD scope, audit provenance, and concurrent creation", async () => {
  const sql = await repairMigration();

  assert.match(sql, /create table public\.daily_eod_audit_events/i);
  assert.match(sql, /alter table public\.daily_eod_audit_events enable row level security/i);
  assert.match(sql, /revoke all on public\.daily_eod_audit_events from anon, authenticated/i);
  assert.match(sql, /order by case membership\.role when 'admin' then 1 else 2 end, membership\.joined_at/i);
  assert.match(sql, /pg_advisory_xact_lock/i);
  assert.match(sql, /audit\.organization_id = brief\.organization_id/i);
  assert.match(sql, /insert into public\.daily_eod_audit_events/i);
  assert.match(sql, /'projectId'/i);
  assert.match(sql, /EOD_SCOPE_CHANGED/i);
  assert.match(sql, /not \(p_payload \? 'scopeDate'\).*not \(p_payload \? 'scopeProjectId'\)/i);
});

test("preserves first-submission lateness during later edits", async () => {
  const sql = await repairMigration();

  assert.match(sql, /create or replace function private\.preserve_daily_eod_lateness/i);
  assert.match(sql, /old\.submitted_at is not null[\s\S]*new\.is_late := old\.is_late/i);
  assert.match(sql, /create trigger preserve_daily_eod_lateness/i);
  assert.match(sql, /update public\.daily_eod_briefs brief[\s\S]*brief\.submitted_at >=/i);
  assert.doesNotMatch(sql, /brief\.is_late or v_local_now >=/i);
});
