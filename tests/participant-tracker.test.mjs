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

test("embeds recruitment as a CRM tab without removing the Contacts view", async () => {
  const [crmTemplate, workspace, workspaceTemplate, app] = await Promise.all([
    readFile(new URL("../src/js/crm-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/workspace-template.js", import.meta.url), "utf8"),
    readFile(new URL("../src/js/app.js", import.meta.url), "utf8"),
  ]);
  assert.match(crmTemplate, /crmTab==='contacts'/);
  assert.match(crmTemplate, /crmTab==='recruitment'/);
  assert.match(crmTemplate, /participantTrackerEmbedTemplate/);
  assert.match(workspace, /requestedTab = searchParams\.get\("tab"\)/);
  assert.match(workspace, /setCrmTab\(tab\)/);
  assert.match(workspaceTemplate, /crmTemplateWithRecruitment/);
  assert.match(app, /registerParticipantTracker\(Alpine\)/);
});
