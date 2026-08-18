import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { csvCell } from "../src/js/core.js";
import { resolveWorkspaceRoute } from "../src/js/crm.js";
import { crmTemplate } from "../src/js/crm-template.js";
import { createDailyEodDraft, validateDailyEodFields } from "../src/js/daily-eod.js";
import { buildCandidateExport, parseCandidateImport } from "../src/js/operations.js";
import { buildLayerMatrices, validateResearchRecord } from "../src/js/pmf.js";

const root = new URL("../", import.meta.url);

test("hardens CSV cells when formulas follow whitespace or control prefixes", () => {
  assert.equal(csvCell("\t=IMPORTXML('bad')"), '"\'\t=IMPORTXML(\'bad\')"');
  assert.equal(csvCell("  +1"), '"\'  +1"');
  assert.equal(csvCell("safe"), '"safe"');
});

test("normalizes legacy workspace aliases without losing canonical EOD routes", () => {
  const pmf = resolveWorkspaceRoute({ view: "pmf" });
  assert.equal(pmf.view, "research");
  assert.equal(pmf.researchTab, "analyze");
  assert.equal(pmf.normalize, true);
  const research = resolveWorkspaceRoute({ view: "research", tab: "collect" });
  assert.equal(research.view, "research");
  assert.equal(research.researchTab, "collect");
  assert.equal(research.normalize, false);
  const eod = resolveWorkspaceRoute({ view: "daily-eod" });
  assert.equal(eod.view, "eod");
  assert.equal(eod.normalize, true);
});

test("selects the newest approved text observation by timestamp", () => {
  const matrices = buildLayerMatrices({
    segments: [{ code: "families", name: "Families" }],
    definitions: [{ id: "text", layer: "H1", dimension: "Need", label: "Latest need", valueType: "text" }],
    observations: [
      { definitionId: "text", segmentCode: "families", textValue: "Newest", workflowStatus: "approved", createdAt: "2026-08-06T12:00:00Z" },
      { definitionId: "text", segmentCode: "families", textValue: "Oldest", workflowStatus: "approved", createdAt: "2026-08-01T12:00:00Z" },
    ],
  });

  assert.equal(matrices.H1[0].values.families.display, "Newest");
});

test("rejects unsafe source protocols and mismatched respondent sessions", () => {
  const unsafe = validateResearchRecord("evidence", {
    pmfLayer: "H1",
    title: "Finding",
    evidenceText: "Observation",
    sourceLink: "javascript:alert(1)",
    limitations: "One respondent",
  }, "submitted");
  assert.deepEqual(unsafe, ["Use an http(s) source link."]);

  const mismatched = validateResearchRecord("observation", {
    definitionId: "metric",
    segmentCode: "families",
    numericValue: 3,
    respondentId: "respondent-a",
    sessionId: "session-b",
  }, "submitted", {
    definitions: [{ id: "metric", valueType: "numeric" }],
    sessions: [{ id: "session-b", respondentId: "respondent-b" }],
  });
  assert.deepEqual(mismatched, ["Choose a session belonging to the selected respondent."]);
});

test("rejects incompatible observation values for the selected metric type", () => {
  const errors = validateResearchRecord("observation", {
    definitionId: "metric",
    segmentCode: "families",
    numericValue: 3,
    textValue: "stale",
    respondentId: "respondent-a",
  }, "submitted", {
    definitions: [{ id: "metric", valueType: "numeric" }],
    sessions: [],
  });

  assert.deepEqual(errors, ["Clear values that do not match the selected metric type."]);
});

test("allows blank optional EOD evidence rows when one complete link remains", () => {
  const brief = createDailyEodDraft({
    engagementManagerId: "manager",
    personInChargeId: "owner",
    movedOutcome: "Outcome",
    evidenceGathered: "Evidence",
    deliverablesCompleted: "Deliverable",
    keyInsight: "Insight",
    currentBlocker: "None",
    blockerImpact: "None",
    proposedSolution: "None",
    executiveOwners: ["None"],
    executiveRequest: "None",
    tomorrowPriorities: ["One", "Two", "Three"],
    projectStatus: "on_track",
    evidenceLinks: [
      { sourceType: "crm", label: "CRM record", url: "https://example.com/crm" },
      { sourceType: "onedrive", label: "", url: "" },
    ],
  });

  assert.deepEqual(validateDailyEodFields(brief), {});
});

test("round-trips the complete candidate portability contract", () => {
  const candidate = {
    externalId: "7",
    source: "Discovery list",
    category: "Dental Professional",
    name: "Dr. Ada",
    platforms: "YouTube",
    reach: "100K",
    tier: "Macro",
    creatorType: "Dentist",
    contentFit: "Education",
    fitLevel: "High",
    contactReadiness: "Email ready",
    contactChannel: "Email",
    contactDetail: "ada@example.com",
    sourceUrl: "https://example.com/ada",
    pmfCandidate: true,
    pmfRationale: "Relevant practitioner",
    priorityScore: 91,
    priorityBand: "High",
    ownerName: "Kayla",
    outreachStatus: "Sent",
    interestLevel: "High",
    preferredCollaboration: "Interview / Product Testing",
    deckIntroduced: true,
    pmfAsked: true,
    firstOutreach: "2026-08-01",
    followUp1: "2026-08-05",
    followUp2: "2026-08-10",
    responseDate: "2026-08-06",
    nextStep: "Book interview",
    nextStepDue: "2026-08-08",
    notes: "Verified",
    sourceUpdatedOn: "2026-08-06",
  };

  const exported = buildCandidateExport([candidate]);
  const imported = parseCandidateImport(exported.csv);

  assert.deepEqual(imported.errors, []);
  assert.deepEqual(imported.rows[0], candidate);
});

test("wires local dates, preserved EOD state, briefing PMF routing, and mutation refreshes", async () => {
  const workspace = await readFile(new URL("src/js/workspace.js", root), "utf8");

  assert.match(workspace, /localDateValue/);
  assert.doesNotMatch(workspace, /function today\(\)[\s\S]*?toISOString\(\)\.slice\(0, 10\)/);
  assert.match(workspace, /dailyEod:\s*liveData\.dailyEod\s*\|\|\s*this\.data\.dailyEod/);
  assert.match(workspace, /matrixLayer\s*=\s*destination\.layer/);
  assert.match(workspace, /refreshMutationState/);
});

test("wires canonical history, direct EOD loading, and sequenced EOD requests", async () => {
  const workspace = await readFile(new URL("src/js/workspace.js", root), "utf8");

  assert.match(workspace, /popstate/);
  assert.match(workspace, /history\.pushState/);
  assert.match(workspace, /this\.view === "eod"[\s\S]*searchDailyEodReports/);
  assert.match(workspace, /dailyEodReportsSequence/);
  assert.match(workspace, /sequence !== this\.dailyEodReportsSequence/);
  assert.match(workspace, /reloadDailyEodConflict\(\)[\s\S]*catch \(reason\)/);
});

test("opens real role-correct task checkpoints instead of a toast-only action", async () => {
  const [workspace, template] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
  ]);

  assert.match(workspace, /taskCheckpointForm/);
  assert.match(workspace, /openTaskCheckpoint\(\)/);
  assert.match(workspace, /canUpdateSelectedTask/);
  assert.match(template, /openTaskCheckpoint\(\)/);
  assert.match(template, /taskCheckpointForm\.progress/);
  assert.match(template, /taskCheckpointForm\.note/);
  assert.match(template, /replace\("@click=\\"showToast\('Progress update'/);
});

test("wires the authoritative task lifecycle through detail, checkpoint, and admin review RPCs", async () => {
  const [api, workspace, template] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
  ]);

  assert.match(api, /export async function loadTaskDetail\(taskId\)[\s\S]*?rpc\("rpc_aoi_task_detail",\s*\{ p_task_id: taskId \}\)/);
  assert.match(api, /updateTaskCheckpoint\(taskId, progress, status = null, note = null, expectedUpdatedAt\)[\s\S]*?p_expected_updated_at: expectedUpdatedAt/);
  assert.match(api, /export async function reviewTask\(taskId, action, note, expectedUpdatedAt\)[\s\S]*?rpc\("rpc_aoi_review_task"[\s\S]*?p_expected_updated_at: expectedUpdatedAt/);

  assert.match(workspace, /async selectTask\(task, \{ preview = this\.preview \} = \{\}\)[\s\S]*?loadTaskDetail\(task\.id\)/);
  assert.match(workspace, /updateTaskCheckpoint\([\s\S]*?this\.selectedTask\.updatedAt/);
  assert.match(workspace, /reviewTask\(this\.selectedTask\.id, action, note, this\.selectedTask\.updatedAt\)/);
  assert.match(workspace, /TASK_STALE_WRITE[\s\S]*?taskCheckpointNotice/);
  assert.match(workspace, /checkpoint was saved, but the refreshed task could not be loaded/);
  assert.match(workspace, /review action was saved, but the refreshed task could not be loaded/);
  assert.match(workspace, /action === "request_revision"[\s\S]*?note\.length < 12/);

  const drawer = template.match(/const taskDrawerTemplate = String\.raw`([\s\S]*?)`;/)?.[1] || "";
  assert.match(drawer, /selectedTask\?\.acceptanceCriteria/);
  assert.match(drawer, /selectedTask\?\.estimatedHours/);
  assert.match(drawer, /selectedTask\?\.reviewNote/);
  assert.match(drawer, /selectedTask\?\.reviewHistory/);
  assert.match(drawer, /\['submitted','resubmitted'\]\.includes\(selectedTask\?\.status\)[\s\S]*?reviewSelectedTask\('request_revision'\)/);
  assert.match(drawer, /\['submitted','resubmitted'\]\.includes\(selectedTask\?\.status\)[\s\S]*?reviewSelectedTask\('approve'\)/);
  assert.match(drawer, /selectedTask\?\.status==='approved'[\s\S]*?reviewSelectedTask\('complete'\)/);
  assert.match(drawer, /taskCheckpointForm\.status==='resubmitted'/);
  assert.doesNotMatch(drawer, /option value="completed"/);
  assert.match(drawer, /taskCheckpointNotice[\s\S]*?role="alert"/);
});

test("wires respondent-scoped sessions, consent metadata, value clearing, and the Analyze CTA", async () => {
  const [workspace, template] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/pmf-template.js", root), "utf8"),
  ]);

  assert.match(workspace, /researchSessionsFor\(recordType\)/);
  assert.match(workspace, /syncResearchSession\(recordType\)/);
  assert.match(workspace, /syncObservationDefinition\(\)/);
  assert.match(template, /researchSessionsFor\('evidence'\)/);
  assert.match(template, /researchSessionsFor\('observation'\)/);
  assert.match(template, /researchForms\.evidence\.consentStatus/);
  assert.match(template, /Consent:/);
  assert.match(template, /@change="syncObservationDefinition\(\)"/);
  assert.match(template, /setResearchTab\('collect'\);startCollectionRecord\('observation'\)/);
  assert.match(template, /safeSourceUrl\(selectedCollectRecord\?\.sourceLink\)/);
});

test("names and focus-traps task, CRM, and candidate dialogs", async () => {
  const [workspace, workspaceTemplate, crmSource] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
  ]);
  const templates = workspaceTemplate + crmSource;

  assert.match(workspace, /trapDialogFocus\(event, selector\)/);
  for (const name of ["task-drawer-title", "candidate-drawer-title"]) {
    assert.equal((templates.match(new RegExp(name, "g")) || []).length >= 2, true);
  }
  assert.match(crmTemplate, /:aria-label="selectedCrmContact \? 'Contact record' : 'New contact intake'"/);
  assert.equal((templates.match(/trapDialogFocus\(\$event/g) || []).length, 3);
  assert.match(workspace, /candidateReturnFocus/);
  assert.match(workspace, /crmReturnFocus/);
  assert.match(workspace, /taskReturnFocus/);
});

test("enforces HTTP source links at the database boundary", async () => {
  const migration = await readFile(new URL("supabase/migrations/20260806080052_harden_external_urls_and_survey_runtime.sql", root), "utf8");

  for (const constraint of [
    "evidence_records_source_link_http",
    "pmf_observations_source_link_http",
    "crm_contacts_source_url_http",
    "candidates_source_url_http",
  ]) assert.match(migration, new RegExp(constraint));
  assert.equal((migration.match(/check \(.*\^https\?:\/\//g) || []).length, 4);
  assert.equal((migration.match(/\) not valid;/gi) || []).length, 4);
});
