import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";

const migrationFiles = [
  "../supabase/migrations/202608050001_intern_workflow_controls.sql",
  "../src/js/api.js",
  "../src/js/workspace.js",
];

test("adds an assignment-validated task checkpoint contract", async () => {
  const [migration, api, workspace] = await Promise.all(migrationFiles.map((file) => readFile(new URL(file, import.meta.url), "utf8")));
  assert.match(migration, /rpc_aoi_update_task_checkpoint/);
  assert.match(migration, /assigned_to = \(select auth\.uid\(\)\)/);
  assert.match(migration, /activity_events/);
  assert.match(api, /updateTaskCheckpoint/);
  assert.match(workspace, /updateTaskCheckpoint/);
});

test("ships the Phase 4 workflow integrity migration", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260808010000_workflow_integrity.sql", import.meta.url), "utf8");
  assert.match(migration, /TASK_CHECKPOINT_NOTE_REQUIRED/);
  assert.match(migration, /TASK_COMPLETION_PROGRESS_REQUIRED/);
  assert.match(migration, /TASK_CHECKPOINT_LOCKED/);
  assert.match(migration, /TASK_TRANSITION_INVALID/);
  assert.match(migration, /consent_status = ''granted''/);
  assert.match(migration, /rpc_aoi_daily_eod_reports\(jsonb,integer,integer\)/);
  assert.match(migration, /brief\.project_id = v_project_id/);
  assert.match(migration, /GATE_SNAPSHOT_PATCH_FAILED/);
});

test("provisions the CRM outcome onboarding step", async () => {
  const migration = await readFile(new URL("../supabase/migrations/202608050001_intern_workflow_controls.sql", import.meta.url), "utf8");
  assert.match(migration, /log_crm_outcome/);
  assert.match(migration, /staff_onboarding_steps/);
  assert.match(migration, /rpc_update_onboarding_step/);
});
