import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationsUrl = new URL("../supabase/migrations/", import.meta.url);

async function outreachMigration() {
  const names = await readdir(migrationsUrl);
  const name = names.find((entry) => entry === "20260804171635_shared_outreach_workspace.sql");
  assert.ok(name, "shared Outreach migration is missing");
  return readFile(new URL(name, migrationsUrl), "utf8");
}

function taggedJson(sql, tag) {
  const match = sql.match(new RegExp(`\\$${tag}\\$([\\s\\S]*?)\\$${tag}\\$`));
  assert.ok(match, `${tag} seed payload is missing`);
  return JSON.parse(match[1]);
}

test("seeds the complete operational Outreach dataset", async () => {
  const sql = await outreachMigration();
  const candidates = taggedJson(sql, "candidates");
  const plan = taggedJson(sql, "execution_plan");
  const templates = taggedJson(sql, "email_templates");

  assert.equal(candidates.length, 70);
  assert.deepEqual(candidates.map((candidate) => candidate.externalId), Array.from({ length: 70 }, (_, index) => String(index + 1)));
  assert.equal(candidates.filter((candidate) => candidate.outreachStatus === "Sent").length, 11);
  assert.equal(candidates.filter((candidate) => candidate.pmfCandidate).length, 32);
  assert.equal(candidates.filter((candidate) => candidate.contactReadiness === "Research needed").length, 9);
  assert.equal(candidates.filter((candidate) => candidate.contactReadiness !== "Research needed").length, 61);
  assert.equal(candidates.every((candidate) => candidate.fit), true);
  assert.equal(candidates.find((candidate) => candidate.externalId === "51").contactDetail, "bracesbybritt@gmail.com");
  assert.match(candidates.find((candidate) => candidate.externalId === "69").contactDetail, /matt\.evans@futurenet\.com/);
  assert.equal(candidates.find((candidate) => candidate.externalId === "69").contactReadiness, "Research needed");
  assert.equal(plan.length, 18);
  assert.equal(templates.length, 7);
  assert.match(sql, /external_id in \('1','2','3','4','5','6','7','8','9','10','11'\)/);
  assert.match(sql, /external_id = '12'[\s\S]*event\.status = 'Blocked'/);
});

test("makes the candidate pipeline shared while preserving administrator controls", async () => {
  const sql = await outreachMigration();

  assert.match(sql, /create policy candidates_workspace_read[\s\S]*public\.is_org_member\(organization_id\)/i);
  assert.match(sql, /create policy candidates_workspace_update[\s\S]*public\.is_org_member\(organization_id\)/i);
  assert.match(sql, /create policy candidates_workspace_insert[\s\S]*assigned_to = \(select auth\.uid\(\)\)[\s\S]*workflow_status = 'draft'/i);
  assert.match(sql, /create policy outreach_workspace_read[\s\S]*public\.is_org_member\(organization_id\)/i);
  assert.match(sql, /create policy outreach_workspace_insert[\s\S]*actor_id = \(select auth\.uid\(\)\)/i);
  assert.match(sql, /create policy evidence_workspace_read[\s\S]*public\.is_org_member\(organization_id\)/i);
  assert.match(sql, /create policy evidence_workspace_insert[\s\S]*workflow_status = 'draft'/i);
  assert.match(sql, /add column if not exists content_fit text/i);
  assert.match(sql, /create or replace function public\.enforce_aoi_candidate_assignee_membership\(\)/i);
  assert.match(sql, /create trigger enforce_aoi_assignee_membership[\s\S]*enforce_aoi_candidate_assignee_membership\(\)/i);
  assert.match(sql, /create or replace function public\.enforce_aoi_candidate_workflow\(\)[\s\S]*old\.organization_id is distinct from new\.organization_id[\s\S]*if public\.is_org_admin[\s\S]*old\.owner_id is distinct from new\.owner_id[\s\S]*CANDIDATE_WORKFLOW_IMMUTABLE/i);
  assert.match(sql, /enforce_aoi_candidate_workflow\(\)[\s\S]*old\.external_id is distinct from new\.external_id[\s\S]*old\.created_by is distinct from new\.created_by/i);
  assert.match(sql, /create or replace function public\.enforce_aoi_evidence_provenance\(\)[\s\S]*EVIDENCE_PROVENANCE_IMMUTABLE/i);
  assert.match(sql, /create trigger enforce_aoi_evidence_provenance[\s\S]*enforce_aoi_evidence_provenance\(\)/i);
  assert.match(sql, /candidates_created_by_fkey[\s\S]*foreign key \(created_by\)[\s\S]*on delete restrict/i);
  assert.match(sql, /evidence_records_candidate_id_fkey[\s\S]*foreign key \(candidate_id\)[\s\S]*on delete restrict/i);
  assert.match(sql, /evidence_records_recorded_by_fkey[\s\S]*foreign key \(recorded_by\)[\s\S]*on delete restrict/i);
  assert.match(sql, /evidence_records_respondent_id_fkey[\s\S]*foreign key \(respondent_id\)[\s\S]*on delete restrict/i);
  assert.match(sql, /evidence_records_session_id_fkey[\s\S]*foreign key \(session_id\)[\s\S]*on delete restrict/i);
  assert.match(sql, /create policy outreach_campaign_admin_write[\s\S]*public\.is_org_admin\(organization_id\)/i);
  assert.match(sql, /create policy outreach_plan_admin_write[\s\S]*public\.is_org_admin\(organization_id\)/i);
  assert.doesNotMatch(sql, /grant delete on public\.(candidates|outreach_events|evidence_records)/i);
  assert.match(sql, /if v_role = 'admin' and nullif\(p_candidate->>'ownerId'/i);
  assert.match(sql, /if not public\.is_org_admin\(v_org_id\) then raise exception 'ADMIN_REQUIRED'/i);
});

test("returns live campaign metrics and keeps the seed non-destructive", async () => {
  const sql = await outreachMigration();

  assert.match(sql, /create table public\.outreach_campaigns/i);
  assert.match(sql, /create table public\.outreach_plan_items/i);
  assert.match(sql, /'outreachSummary'/);
  assert.match(sql, /'categories'/);
  assert.match(sql, /candidate\.contact_readiness <> 'Research needed'/i);
  assert.match(sql, /candidate\.contact_readiness = 'Research needed'/i);
  assert.match(sql, /'executionPlan'/);
  assert.match(sql, /'scoringRules'/);
  assert.match(sql, /on conflict \(project_id, external_id\)[\s\S]*do update/i);
  assert.match(sql, /outreach_status = public\.candidates\.outreach_status/i);
  assert.match(sql, /notes = coalesce\(public\.candidates\.notes, excluded\.notes\)/i);
  assert.match(sql, /if v_owner_id is null then[\s\S]*membership\.status = 'active'[\s\S]*limit 1/i);
  assert.doesNotMatch(sql, /disable trigger enforce_aoi_assignee_membership/i);
  assert.doesNotMatch(sql, /OUTREACH_SEED_OWNER_REQUIRED/);
  assert.match(sql, /OUTREACH_SEED_IDENTITY_CONFLICT/i);
  assert.match(sql, /notes = case when p_candidate \? 'notes' then p_candidate->>'notes' else candidate\.notes end/i);
  assert.match(sql, /source_label = case when p_candidate \? 'source' then p_candidate->>'source' else candidate\.source_label end/i);
  assert.match(sql, /"statusOptions":\[[^\]]*"Sent"[^\]]*"Unreachable"/i);
  assert.doesNotMatch(sql, /email_templates_organization_name_unique/i);
  assert.doesNotMatch(sql, /delete from public\.(candidates|outreach_events|email_templates)/i);
});
