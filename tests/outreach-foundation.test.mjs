import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationsUrl = new URL("../supabase/migrations/", import.meta.url);

async function foundationMigration() {
  const names = await readdir(migrationsUrl);
  const name = names.find((entry) => entry.endsWith("_outreach_relationship_foundation.sql"));
  assert.ok(name, "Outreach relationship foundation migration is missing");
  return readFile(new URL(name, migrationsUrl), "utf8");
}

test("restores private PMF evidence visibility and separates Outreach research", async () => {
  const sql = await foundationMigration();

  assert.match(sql, /drop policy if exists evidence_workspace_read on public\.evidence_records/i);
  assert.match(sql, /create policy evidence_assignment_or_approved_read[\s\S]*assigned_to = \(select auth\.uid\(\)\)[\s\S]*workflow_status = 'approved'/i);
  assert.match(sql, /create table public\.outreach_research/i);
  assert.match(sql, /alter table public\.outreach_research enable row level security/i);
  assert.match(sql, /candidate_id is null[\s\S]*respondent_id is not null/i);
});

test("normalizes relationship, campaign, and operational workflow data", async () => {
  const sql = await foundationMigration();
  const tables = [
    "crm_contact_methods",
    "crm_communication_preferences",
    "outreach_stage_definitions",
    "outreach_campaign_memberships",
    "relationship_activities",
    "outreach_tasks",
    "outreach_meetings",
    "outreach_offers",
    "outreach_audit_events",
  ];

  for (const table of tables) {
    assert.match(sql, new RegExp(`create table public\\.${table}`, "i"), `${table} is missing`);
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, "i"), `${table} must enable RLS`);
  }
  assert.match(sql, /semantic_family text not null[\s\S]*'research'[\s\S]*'committed'[\s\S]*'closed'/i);
  assert.match(sql, /unique \(campaign_id, contact_id\)/i);
  assert.match(sql, /revoke all on public\.[\s\S]*from anon, authenticated/i);
});

test("backfills every candidate into one canonical CRM relationship", async () => {
  const sql = await foundationMigration();

  assert.match(sql, /create temporary table outreach_crm_backfill/i);
  assert.match(sql, /insert into public\.crm_contacts/i);
  assert.match(sql, /update public\.candidates candidate[\s\S]*crm_contact_id = mapping\.crm_id/i);
  assert.match(sql, /alter table public\.candidates alter column crm_contact_id set not null/i);
  assert.match(sql, /insert into public\.crm_contact_methods/i);
  assert.match(sql, /insert into public\.outreach_campaign_memberships/i);
  assert.match(sql, /candidates_relationship_scope_unique/i);
  assert.match(sql, /foreign key \(organization_id, project_id, contact_id, candidate_id\)/i);
});

test("unifies legacy activity history and trusts only server-authored audit events", async () => {
  const sql = await foundationMigration();

  assert.match(sql, /insert into public\.relationship_activities[\s\S]*from public\.crm_activity/i);
  assert.match(sql, /insert into public\.relationship_activities[\s\S]*from public\.outreach_events/i);
  assert.match(sql, /legacy_source/i);
  assert.match(sql, /revoke all on public\.outreach_audit_events from anon, authenticated/i);
  assert.match(sql, /revoke insert, update on public\.candidates from authenticated/i);
  assert.match(sql, /revoke insert on public\.outreach_events from authenticated/i);
  assert.match(sql, /revoke insert on public\.email_deliveries from authenticated/i);
  assert.match(sql, /create or replace function public\.rpc_aoi_log_outreach/i);
  assert.match(sql, /insert into public\.outreach_audit_events/i);
  assert.doesNotMatch(sql, /delete from public\.(crm_activity|outreach_events|audit_events)/i);
});

test("exposes optimistic relationship and append-only activity RPCs", async () => {
  const sql = await foundationMigration();

  assert.match(sql, /create function public\.rpc_aoi_save_relationship/i);
  assert.match(sql, /p_expected_updated_at timestamptz/i);
  assert.match(sql, /OUTREACH_STALE_WRITE/i);
  assert.match(sql, /create function public\.rpc_aoi_log_relationship_activity/i);
  assert.match(sql, /create function public\.rpc_aoi_outreach_foundation_snapshot/i);
  assert.match(sql, /candidate\.crm_contact_id = contact\.id/i);
  assert.match(sql, /grant execute on function public\.rpc_aoi_save_relationship/i);
  assert.match(sql, /revoke all on function public\.rpc_aoi_save_relationship[\s\S]*from public, anon/i);
  assert.match(sql, /createOutreach/i);
  assert.match(sql, /'createOutreach', coalesce\([\s\S]*v_candidate_id is not null/i);
  assert.match(sql, /OUTREACH_WRITE_NOT_ASSIGNED/i);
  assert.match(sql, /create trigger touch_relationship_version/i);
});

test("makes normalized communication preferences authoritative", async () => {
  const sql = await foundationMigration();

  assert.match(sql, /crm_communication_preferences_state_check/i);
  assert.match(sql, /insert into public\.crm_communication_preferences[\s\S]*from public\.contact_preferences/i);
  assert.match(sql, /create function public\.rpc_aoi_set_communication_preference/i);
  assert.match(sql, /create or replace function public\.rpc_aoi_queue_email/i);
  assert.match(sql, /preference\.consent_state in \('denied','withdrawn'\)/i);
  assert.match(sql, /not exists \([\s\S]*from public\.crm_communication_preferences[\s\S]*preference\.channel = 'email'/i);
  assert.match(sql, /from public\.crm_contact_methods method[\s\S]*method\.method_type = 'email'[\s\S]*lower\(method\.value\) = lower\(trim\(p_recipient\)\)/i);
  assert.match(sql, /'updatedAt', contact\.updated_at/i);
  assert.match(sql, /rpc_aoi_operations_snapshot_unversioned/i);
  assert.match(sql, /p_candidate->>'updatedAt'/i);
  assert.match(sql, /'updatedAt', v_contact\.updated_at/i);
  assert.match(sql, /ownerName/i);
  assert.match(sql, /OUTREACH_OWNER_AMBIGUOUS/i);
});
