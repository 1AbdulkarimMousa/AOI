import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships a connected CRM persistence contract", async () => {
  const [migration, api, template, controller] = await Promise.all([
    readFile(new URL("supabase/migrations/20260804122136_crm_workspace.sql", root), "utf8"),
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
  ]);

  assert.match(migration, /create table if not exists public\.crm_contacts/);
  assert.match(migration, /create table if not exists public\.crm_activity/);
  assert.match(migration, /crm_contact_id uuid references public\.crm_contacts/);
  assert.match(migration, /alter table public\.crm_contacts enable row level security/);
  assert.match(migration, /rpc_aoi_crm_snapshot/);
  assert.match(migration, /rpc_aoi_upsert_crm_contact/);
  assert.match(migration, /rpc_aoi_log_crm_activity/);
  assert.match(api, /rpc\("rpc_aoi_crm_snapshot"\)/);
  assert.match(api, /rpc\("rpc_aoi_upsert_crm_contact"/);
  assert.match(api, /rpc\("rpc_aoi_log_crm_activity"/);
  assert.match(template, /Today queue/);
  assert.match(template, /Contact CRM/);
  assert.match(template, /Profile completeness/);
  assert.match(controller, /buildTodayQueue/);
  assert.match(controller, /rewardForAction/);
});
