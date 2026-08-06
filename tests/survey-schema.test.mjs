import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationsUrl = new URL("../supabase/migrations/", import.meta.url);

async function currentSchema() {
  const names = (await readdir(migrationsUrl)).filter((name) => name.endsWith(".sql")).sort();
  return (await Promise.all(names.map((name) => readFile(new URL(name, migrationsUrl), "utf8")))).join("\n");
}

test("defines the complete versioned survey persistence model", async () => {
  const sql = await currentSchema();
  for (const table of [
    "survey_assets",
    "survey_drafts",
    "survey_versions",
    "survey_links",
    "survey_invitations",
    "survey_submissions",
    "survey_answers",
    "survey_answer_revisions",
    "survey_reviews",
    "survey_text_codes",
    "survey_promotions",
    "survey_aggregate_snapshots",
    "survey_transfer_jobs",
  ]) {
    assert.match(sql, new RegExp(`create table(?: if not exists)? public\\.${table}\\b`, "i"), table);
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, "i"), `${table} RLS`);
  }
});

test("exposes authenticated survey workflows through scoped RPCs", async () => {
  const sql = await currentSchema();
  for (const rpc of [
    "rpc_aoi_survey_library",
    "rpc_aoi_create_survey",
    "rpc_aoi_create_survey_invitation",
    "rpc_aoi_save_survey_draft",
    "rpc_aoi_submit_survey_version",
    "rpc_aoi_review_survey_version",
    "rpc_aoi_publish_survey",
    "rpc_aoi_review_survey_submission",
    "rpc_aoi_promote_survey_answer",
    "rpc_aoi_survey_analysis",
  ]) {
    assert.match(sql, new RegExp(`function public\\.${rpc}\\b`, "i"), rpc);
  }
  assert.match(sql, /SURVEY_DRAFT_STALE/i);
  assert.match(sql, /SURVEY_ADMIN_APPROVAL_REQUIRED/i);
  assert.match(sql, /definition_hash/i);
  assert.match(sql, /digest\s*\(/i);
});

test("denies anonymous table access and provisions private survey uploads", async () => {
  const sql = await currentSchema();

  assert.match(sql, /revoke all on public\.survey_assets[\s\S]*from anon/i);
  assert.match(sql, /revoke all on public\.survey_submissions[\s\S]*from anon/i);
  assert.match(sql, /aoi-survey-uploads/);
  assert.match(sql, /survey_uploads_no_direct_anon/i);
  assert.match(sql, /approved_at/i);
  assert.match(sql, /response_status in \('in_progress','submitted','in_review','approved','revision_requested','rejected','excluded'\)/i);
});

test("uses null-safe assignment checks in privileged survey functions", async () => {
  const sql = await currentSchema();

  assert.doesNotMatch(sql, /auth\.uid\(\) not in \(v_asset\.owner_id,v_asset\.assigned_to\)/i);
  assert.match(sql, /auth\.uid\(\) <> v_asset\.owner_id and auth\.uid\(\) is distinct from v_asset\.assigned_to/i);
  assert.match(sql, /auth\.uid\(\) is distinct from v_submission\.assigned_to/i);
});

test("resolves survey token crypto from controlled schemas", async () => {
  const sql = await currentSchema();

  assert.match(sql, /alter function public\.rpc_aoi_public_survey_load\(text\)[\s\S]{0,80}set search_path = pg_catalog, extensions/i);
  assert.match(sql, /alter function public\.rpc_aoi_create_survey_link\(uuid,text,text,text,jsonb\)[\s\S]{0,80}set search_path = pg_catalog, extensions/i);
});

test("initializes survey RLS identities once per statement", async () => {
  const sql = await currentSchema();

  assert.match(sql, /asset\.owner_id=\(select auth\.uid\(\)\)/i);
  assert.match(sql, /submission\.assigned_to=\(select auth\.uid\(\)\)/i);
  assert.match(sql, /reviewer_id=\(select auth\.uid\(\)\)/i);
});

test("hardens public sessions, revisions, invitations, and idempotency", async () => {
  const sql = await currentSchema();

  assert.match(sql, /SURVEY_INVITATION_REQUIRED/);
  assert.match(sql, /insert into public\.survey_answer_revisions/i);
  assert.match(sql, /link\.link_status='active'/i);
  assert.match(sql, /v_submission\.idempotency_key=p_idempotency_key/i);
  assert.match(sql, /function public\.rpc_aoi_public_survey_replay\b/i);
  assert.match(sql, /SURVEY_RESPONSE_CAPACITY_REACHED/);
  assert.match(sql, /create unique index[\s\S]*survey_promotions_answer_unique/i);
  assert.match(sql, /SURVEY_REVISION_RESUMED/);
  assert.match(sql, /jsonb_build_object\('accepted',true,'locale',v_submission\.locale,'versionId',v_submission\.version_id/i);
  assert.match(sql, /v_asset\.lifecycle_status<>'published'/i);
});
