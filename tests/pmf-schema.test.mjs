import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationsUrl = new URL("../supabase/migrations/", import.meta.url);

async function currentSchema() {
  const names = (await readdir(migrationsUrl)).filter((name) => name.endsWith(".sql")).sort();
  const files = await Promise.all(names.map((name) => readFile(new URL(name, migrationsUrl), "utf8")));
  return files.join("\n");
}

test("defines the normalized PMF collection and decision tables", async () => {
  const sql = await currentSchema();
  for (const table of [
    "research_segments",
    "respondents",
    "respondent_contacts",
    "consent_records",
    "research_sessions",
    "product_events",
    "value_exchange_observations",
    "hypotheses",
    "pmf_metric_definitions",
    "pmf_observations",
    "gate_snapshots",
    "research_attachments",
  ]) {
    assert.match(sql, new RegExp(`create table(?: if not exists)? public\\.${table}\\b`, "i"), table);
  }
});

test("defines persisted collection, review, import, and snapshot workflows", async () => {
  const sql = await currentSchema();
  for (const rpc of [
    "rpc_aoi_save_research_record",
    "rpc_aoi_review_research_record",
    "rpc_aoi_import_candidates",
    "rpc_aoi_pmf_snapshot",
  ]) {
    assert.match(sql, new RegExp(`function public\\.${rpc}\\b`, "i"), rpc);
  }
});

test("contains assignment-aware policies and private storage buckets", async () => {
  const sql = await currentSchema();
  assert.match(sql, /workflow_status\s*=\s*'approved'/i);
  assert.match(sql, /assigned_to\s*=\s*auth\.uid\(\)/i);
  assert.match(sql, /insert into storage\.buckets/i);
  assert.match(sql, /aoi-consent/);
  assert.match(sql, /aoi-recordings/);
  assert.match(sql, /aoi-oral-images/);
});

test("repairs ambiguous deployed RPC identifiers", async () => {
  const sql = await currentSchema();
  assert.match(sql, /v_project_id/);
  assert.match(sql, /p_candidate_id/);
  assert.match(sql, /p_rows jsonb/);
});

test("enforces review, consent, import, and private-media boundaries", async () => {
  const sql = await currentSchema();
  assert.match(sql, /ADMIN_REVIEW_REQUIRED/);
  assert.match(sql, /SUBMITTED_RECORD_LOCKED/);
  assert.match(sql, /workflow_status=case when v_status='archived' then 'approved' else 'submitted' end/);
  assert.match(sql, /file_format in \('csv', 'json', 'tsv', 'xlsx'\)/);
  assert.match(sql, /newer\.version > cr\.version/);
  assert.match(sql, /aoi_research_storage_owner_cleanup/);
  assert.match(sql, /email_deliveries_admin_insert/);
  assert.match(sql, /import_admin_update/);
  assert.match(sql, /function private\.sync_aoi_consent_status\(\)[\s\S]*security definer set search_path = ''/i);
  assert.match(sql, /drop function if exists public\.sync_aoi_consent_status\(\)/i);
  assert.match(sql, /grant select, insert on public\.organization_memberships to service_role/i);
  assert.match(sql, /rpc_aoi_append_consent_version/i);
  assert.match(sql, /OBSERVATION_PROVENANCE_REQUIRED/);
  assert.match(sql, /observation\.workflow_status = 'approved'/);
  assert.match(sql, /revoke insert on public\.gate_snapshots from authenticated/);
  assert.match(sql, /private\.assign_aoi_consent_version/);
});
