import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

import {
  buildCollectIndex,
  conversionReadiness,
  gamificationLevel,
  prefillResearchForm,
  restoreResearchDrafts,
} from "../src/js/collect.js";

test("builds one collected-data index across every research record type", () => {
  const records = buildCollectIndex({
    respondents: [{
      id: "respondent-1",
      respondentCode: "CON-2026-0001",
      recruitmentCode: "PR-001",
      externalIds: ["KOL-77"],
      segmentName: "Families with Children",
      ownerName: "Wen Tang",
      workflowStatus: "approved",
      consentStatus: "granted",
      updatedAt: "2026-08-05T10:00:00Z",
    }],
    sessions: [{
      id: "session-1",
      respondentId: "respondent-1",
      respondentCode: "CON-2026-0001",
      method: "JTBD interview",
      workflowStatus: "submitted",
      ownerName: "Wen Tang",
      sessionDate: "2026-08-05",
    }],
    evidence: [{
      id: "evidence-1",
      respondentId: "respondent-1",
      respondentCode: "CON-2026-0001",
      title: "Parent described a recurring visibility gap",
      stance: "supporting",
      strength: 3,
      workflowStatus: "revision_requested",
      ownerName: "Wen Tang",
      updatedAt: "2026-08-05T12:00:00Z",
    }],
    productEvents: [],
    valueExchange: [],
    observations: [],
  });

  assert.deepEqual(records.map(({ recordType, id }) => ({ recordType, id })), [
    { recordType: "evidence", id: "evidence-1" },
    { recordType: "session", id: "session-1" },
    { recordType: "respondent", id: "respondent-1" },
  ]);
  assert.equal(records[0].respondentCode, "CON-2026-0001");
  assert.equal(records[2].identityTrail, "PR-001 · KOL-77");
});

test("requires screening, segment, and granted consent before conversion", () => {
  assert.deepEqual(conversionReadiness({
    status: "new",
    segment: "",
    consentStatus: "pending",
    respondentId: "",
  }), {
    ready: false,
    reasons: ["Complete screening.", "Choose a segment.", "Record granted consent."],
  });

  assert.deepEqual(conversionReadiness({
    status: "scheduled",
    segment: "Families with Children",
    consentStatus: "granted",
    respondentId: "",
  }), { ready: true, reasons: [] });

  assert.deepEqual(conversionReadiness({ respondentId: "respondent-1" }), {
    ready: false,
    reasons: ["This prospect is already connected to a respondent."],
  });
});

test("derives stable personal levels from persisted XP", () => {
  assert.deepEqual(gamificationLevel(0), { level: 1, currentXp: 0, levelFloor: 0, nextLevelXp: 250, progress: 0 });
  assert.deepEqual(gamificationLevel(375), { level: 2, currentXp: 375, levelFloor: 250, nextLevelXp: 600, progress: 36 });
  assert.deepEqual(gamificationLevel(1500), { level: 5, currentXp: 1500, levelFloor: 1500, nextLevelXp: 2500, progress: 0 });
  assert.deepEqual(gamificationLevel(7000), { level: 8, currentXp: 7000, levelFloor: 6000, nextLevelXp: null, progress: 100, maxLevel: true });
});

test("prefills follow-on collection from the connected respondent", () => {
  const form = prefillResearchForm({ method: "JTBD interview", respondentId: "", segmentCode: "" }, {
    id: "respondent-1",
    segmentCode: "families",
  });
  assert.deepEqual(form, {
    method: "JTBD interview",
    respondentId: "respondent-1",
    segmentCode: "families",
  });
});

test("restores only recognized autosaved research form fields", () => {
  const defaults = {
    respondent: { segmentCode: "families", notes: "" },
    evidence: { respondentId: "", title: "", strength: 2 },
  };
  assert.deepEqual(restoreResearchDrafts(defaults, {
    respondent: { notes: "Screening context", injected: "ignored" },
    evidence: { title: "Draft finding", strength: 3 },
    unknown: { title: "ignored" },
  }), {
    respondent: { segmentCode: "families", notes: "Screening context" },
    evidence: { respondentId: "", title: "Draft finding", strength: 3 },
  });
});

test("ships scoped identity, conversion, collect, automation, and gamification contracts", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260805160000_connect_collect_gamification.sql", import.meta.url), "utf8");
  for (const table of [
    "contact_external_identities",
    "gamification_events",
    "gamification_badges",
    "gamification_badge_awards",
    "gamification_team_goals",
  ]) {
    assert.match(migration, new RegExp(`create table(?: if not exists)? public\\.${table}\\b`, "i"), table);
  }
  for (const rpc of [
    "rpc_aoi_convert_recruitment_to_respondent",
    "rpc_aoi_collect_snapshot",
    "rpc_aoi_collect_record_detail",
    "rpc_aoi_gamification_summary",
  ]) {
    assert.match(migration, new RegExp(`function public\\.${rpc}\\b`, "i"), rpc);
  }
  assert.match(migration, /foreign key \(organization_id, project_id, crm_contact_id\)/i);
  assert.match(migration, /unique \(project_id, namespace, external_id\)/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /respondent\.organization_id = contact_external_identities\.organization_id/i);
  assert.match(migration, /respondent\.project_id = contact_external_identities\.project_id/i);
  assert.match(migration, /grant execute on function public\.rpc_aoi_collect_snapshot\(\) to authenticated/i);
  assert.match(migration, /insert into public\.gamification_events/i);
});

test("exposes conversion and collected-data browsing in the application", async () => {
  const [api, tracker, trackerTemplate, workspace, pmfTemplate] = await Promise.all([
    readFile(new URL("../src/js/api.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/pmf-template.js", import.meta.url), "utf8"),
  ]);

  assert.match(api, /rpc_aoi_convert_recruitment_to_respondent/);
  assert.match(api, /rpc_aoi_collect_snapshot/);
  assert.match(api, /rpc_aoi_collect_record_detail/);
  assert.match(api, /rpc_aoi_gamification_summary/);
  assert.match(tracker, /convertToRespondent/);
  assert.match(trackerTemplate, /Convert to respondent/);
  assert.match(workspace, /collectRecords/);
  assert.match(workspace, /openCollectRecord/);
  assert.match(workspace, /persistResearchDrafts/);
  assert.match(pmfTemplate, /Collected data/);
  assert.match(pmfTemplate, /Respondent profile/);
  assert.match(pmfTemplate, /Personal progress/);
  assert.doesNotMatch(pmfTemplate, /Weekly contribution board/);
});

test("uses the supplied Ambiloop and HUGE Dental co-brand assets", async () => {
  const template = await readFile(new URL("../src/js/workspace-template.js", import.meta.url), "utf8");
  await Promise.all([
    access(new URL("../public/ambiloop-logo.png", import.meta.url)),
    access(new URL("../public/huge-dental-logo.png", import.meta.url)),
  ]);
  assert.match(template, /ambiloop-logo\.png/);
  assert.match(template, /huge-dental-logo\.png/);
  assert.match(template, /co-brand-lockup/);
});

test("hardens cooperative progress without an exposed security definer", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260805161000_harden_collect_gamification.sql", import.meta.url), "utf8");
  assert.match(migration, /alter function public\.rpc_aoi_gamification_summary\(\) security invoker/i);
  assert.match(migration, /workflow_status = 'approved'/i);
  assert.match(migration, /gamification_events_actor_id_idx/i);
  assert.match(migration, /gamification_badge_awards_user_id_idx/i);
  assert.doesNotMatch(migration, /security definer[\s\S]*rpc_aoi_gamification_summary/i);
});

test("repairs the Collect snapshot against the deployed evidence schema", async () => {
  const [foundation, hotfix] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260805160000_connect_collect_gamification.sql", import.meta.url), "utf8"),
    readFile(new URL("../supabase/migrations/20260805162000_repair_collect_snapshot_runtime.sql", import.meta.url), "utf8"),
  ]);
  assert.match(foundation, /'title', evidence\.title/i);
  assert.doesNotMatch(foundation, /evidence\.evidence_title/i);
  assert.match(hotfix, /rpc_aoi_collect_snapshot/i);
  assert.match(hotfix, /evidence\.evidence_title/i);
  assert.match(hotfix, /evidence\.title/i);
});

test("keeps Collect identity reads behind respondent and recruitment RLS", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260805163000_repair_collect_identity_access.sql", import.meta.url), "utf8");
  assert.match(migration, /create policy contact_external_identities_read/i);
  assert.match(migration, /from public\.respondents respondent/i);
  assert.doesNotMatch(migration, /from public\.crm_contacts contact/i);
  assert.match(migration, /grant select on public\.participant_recruitment to authenticated/i);
  assert.doesNotMatch(migration, /grant select on public\.crm_contacts/i);
});

test("keeps Collect data namespaced and browser state session-scoped", async () => {
  const [api, workspace, template, tracker] = await Promise.all([
    readFile(new URL("../src/js/api.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
  ]);
  assert.match(api, /collect:\s*collect\.data/);
  assert.doesNotMatch(api, /\.\.\.collect\.data/);
  assert.match(workspace, /data\.collect\?\.respondents/);
  assert.match(workspace, /sessionStorage/);
  assert.match(workspace, /collectDetailRequest/);
  assert.match(tracker, /converted\.respondentId/);
  assert.doesNotMatch(template, /bonusXp/);
  assert.doesNotMatch(template, /360\+|340\+/);
});

test("hardens conversion identity, consent, and reward transitions", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260805164000_harden_conversion_integrity.sql", import.meta.url), "utf8");
  assert.match(migration, /CONTACT_IDENTITY_AMBIGUOUS/);
  assert.match(migration, /PARTICIPANT_LINK_IMMUTABLE/);
  assert.match(migration, /recontact_allowed[^;]*false/is);
  assert.match(migration, /source_reference/);
  assert.match(migration, /'respondents', new\.respondent_id/i);
});
