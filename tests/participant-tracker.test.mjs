import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const seedData = await import("../scripts/participant-seed-data.mjs").catch(() => null);

test("defines the three supplied people as unscreened recruitment prospects", () => {
  assert.ok(seedData, "Participant seed data must exist");
  assert.deepEqual(seedData.PARTICIPANT_PROSPECTS.map(({ name, email, source, timeZone }) => ({ name, email, source, timeZone })), [
    { name: "Dereck Musiala", email: "derekmusiala9@gmail.com", source: "Facebook", timeZone: "" },
    { name: "Alvaro Gomes", email: "alvarogomes922@gmail.com", source: "Facebook", timeZone: "Eastern Time Zone" },
    { name: "Oliver Lucas", email: "olicas1914@gmail.com", source: "Facebook", timeZone: "" },
  ]);
  assert.equal(seedData.PARTICIPANT_PROSPECTS.every((prospect) => prospect.status === "new"), true);
  assert.equal(seedData.PARTICIPANT_PROSPECTS.every((prospect) => prospect.consentStatus === "pending"), true);
  assert.equal(seedData.PARTICIPANT_PROSPECTS.every((prospect) => prospect.interviewDate === null), true);
});

test("does not seed respondent or interview evidence records", () => {
  assert.ok(seedData, "Participant seed data must exist");
  const plan = seedData.buildParticipantSeedPlan({
    organizationId: "11111111-1111-4111-8111-111111111111",
    projectId: "22222222-2222-4222-8222-222222222222",
    ownerId: "33333333-3333-4333-8333-333333333333",
  });
  assert.equal(plan.prospects.length, 3);
  assert.equal(plan.prospects.every((prospect) => prospect.respondent_id === null), true);
  assert.equal(Object.hasOwn(plan, "sessions"), false);
  assert.equal(Object.hasOwn(plan, "evidence"), false);
  assert.equal(Object.hasOwn(plan, "consentRecords"), false);
});

test("ships a protected tracker page, RPC contract, and Vite entry", async () => {
  const [page, template, controller, api, migration, vite] = await Promise.all([
    readFile(new URL("../Participant_Recruitment_Tracker.html", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/api.js", import.meta.url), "utf8"),
    readFile(new URL("../supabase/migrations/20260805130000_participant_recruitment_tracker.sql", import.meta.url), "utf8"),
    readFile(new URL("../vite.config.js", import.meta.url), "utf8"),
  ]);
  assert.match(page, /data-page="participant-tracker"/);
  assert.match(template, /Participant Recruitment Tracker/);
  assert.match(controller, /registerParticipantTracker/);
  assert.match(api, /rpc_aoi_participant_tracker_snapshot/);
  assert.match(api, /rpc_aoi_upsert_participant_recruitment/);
  assert.match(migration, /participant_recruitment/);
  assert.match(migration, /crm_contact_id/);
  assert.match(migration, /is_org_admin/);
  assert.match(vite, /participantTracker/);
});

test("embeds recruitment as a Relationships tab without removing the Contacts view", async () => {
  const [crmTemplate, workspace, workspaceTemplate, app] = await Promise.all([
    readFile(new URL("../src/js/crm-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/app.js", import.meta.url), "utf8"),
  ]);
  assert.match(crmTemplate, /relationshipsTab==='contacts'/);
  assert.match(crmTemplate, /relationshipsTab==='recruitment'/);
  assert.match(crmTemplate, /participantTrackerEmbedTemplate/);
  assert.match(workspace, /requestedTab = searchParams\.get\("tab"\)/);
  assert.match(workspace, /setRelationshipsTab\(tab\)/);
  assert.match(workspaceTemplate, /crmTemplateWithRecruitment/);
  assert.match(app, /registerParticipantTracker\(Alpine\)/);
});

test("exposes the shared add prospect flow in CRM Recruitment", async () => {
  const template = await readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8");

  assert.match(template, /participant-embedded-heading[\s\S]*@click="openNew\(\)"[\s\S]*\+ Add a prospect/);
});

test("shows the relationship introduction only on the Contacts tab", async () => {
  const crmTemplate = await readFile(new URL("../src/js/crm-template.js", import.meta.url), "utf8");

  assert.match(crmTemplate, /<section x-show="relationshipsTab==='contacts'" class="page-intro crm-intro">/);
});

test("returns standalone tracker users to Relationships Recruitment", async () => {
  const controller = await readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8");

  assert.match(controller, /workspace\.html\?view=relationships&tab=recruitment/);
});

test("defaults new prospect follow-up to the current date", async () => {
  const controller = await readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8");

  assert.match(controller, /nextActionDue:\s*localDateValue\(\)/);
  assert.doesNotMatch(controller, /nextActionDue:\s*"2026-08-06"/);
});

test("keeps keyboard focus inside the prospect drawer and restores it on close", async () => {
  const [template, controller] = await Promise.all([
    readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
  ]);

  assert.match(template, /@keydown\.escape\.window="editorOpen && closeEditor\(\)"/);
  assert.match(template, /x-ref="participantEditor"[\s\S]*@keydown\.tab="trapEditorFocus\(\$event\)"/);
  assert.match(controller, /this\.\$refs\.participantEditor\?\.focus\(\)/);
  assert.match(controller, /this\.editorTrigger\?\.focus\(\)/);
});

test("embedded recruitment inherits preview context instead of authenticating independently", async () => {
  const [template, controller] = await Promise.all([
    readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
  ]);

  assert.match(template, /participantTrackerPage\(\{ embedded: true, preview, access, items:/);
  assert.doesNotMatch(template, /x-init="embedded=true; init\(\)"/);
  assert.match(controller, /previewContext/);
  assert.match(controller, /if \(this\.embedded && this\.previewContext\)/);
});

test("recruitment rows and stage choices expose governed keyboard behavior", async () => {
  const [template, controller] = await Promise.all([
    readFile(new URL("../src/js/participant-tracker-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/participant-tracker.js", import.meta.url), "utf8"),
  ]);

  assert.match(template, /class="participant-row"[\s\S]*tabindex="0"[\s\S]*@keydown\.enter\.self/);
  assert.match(template, /Recruitment stage[\s\S]*availableStatuses\(form\)/);
  assert.match(controller, /screening:\s*\["screening", "scheduled", "completed", "declined"\]/);
  assert.match(controller, /no_response:\s*\["no_response"\]/);
  assert.match(controller, /delete payload\.crmContactId/);
  assert.match(controller, /delete payload\.respondentId/);
  assert.match(controller, /if \(this\.preview\)[\s\S]*Preview only: respondent conversion is disabled/);
});

test("embedded recruitment remounts when project context changes", async () => {
  const workspace = await readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8");
  assert.match(workspace, /remountRecruitment\(\)/);
  assert.match(workspace, /changeProject[\s\S]*remountRecruitment\(\)/);
});
