import assert from "node:assert/strict";
import test from "node:test";

const seedModule = await import("../scripts/kayla-seed-data.mjs").catch(() => null);
const seedUtils = await import("../scripts/seed-utils.mjs").catch(() => null);

test("defines Kayla's intern account seed", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  assert.deepEqual(seedModule.KAYLA_ACCOUNT, {
    email: "ktillmon@smith.edu",
    displayName: "Kayla Tillmon",
    role: "intern",
  });
});

test("attempts every terminal cleanup step when one fails", async () => {
  assert.ok(seedUtils, "Seed cleanup utilities must exist");
  const calls = [];
  const result = await seedUtils.runCleanupSteps([
    { name: "auth", run: async () => { calls.push("auth"); throw new Error("ban failed"); } },
    { name: "membership", run: async () => { calls.push("membership"); return "disabled"; } },
    { name: "profile", run: async () => { calls.push("profile"); return "disabled"; } },
  ]);

  assert.deepEqual(calls, ["auth", "membership", "profile"]);
  assert.deepEqual(result.values, { membership: "disabled", profile: "disabled" });
  assert.deepEqual(result.errors.map(({ name, error }) => [name, error.message]), [["auth", "ban failed"]]);
});

test("defines stable historical tasks and cancels unfinished work", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  const tasks = seedModule.KAYLA_TASKS;

  assert.equal(tasks.length, 8);
  assert.deepEqual(tasks.map((task) => task.status), [
    "completed",
    "submitted",
    "cancelled",
    "cancelled",
    "cancelled",
    "cancelled",
    "cancelled",
    "cancelled",
  ]);
  assert.deepEqual(tasks.map((task) => task.progress), [100, 100, 45, 55, 70, 0, 0, 0]);
  assert.equal(new Set(tasks.map((task) => task.seedKey)).size, 8);
  assert.equal(new Set(tasks.map((task) => task.id)).size, 8);
  assert.equal(tasks.every((task) => /^[0-9a-f-]{36}$/.test(task.id)), true);
  assert.equal(tasks.every((task) => task.seedKey.startsWith("kayla-pmf-")), true);
  assert.deepEqual(seedModule.KAYLA_UNFINISHED_TASK_STATUSES, [
    "draft",
    "assigned",
    "in_progress",
    "blocked",
    "revision_requested",
    "resubmitted",
  ]);
});

test("defines the three supplied July EOD briefs without inventing evidence URLs", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  const briefs = seedModule.KAYLA_EOD_BRIEFS;
  assert.ok(briefs, "Kayla EOD seed data must exist");

  assert.deepEqual(briefs.map((brief) => brief.briefDate), ["2026-07-29", "2026-07-30", "2026-07-31"]);
  assert.equal(briefs.every((brief) => brief.workflowStatus === "submitted"), true);
  assert.equal(briefs.every((brief) => brief.projectStatus === "on_track"), true);
  assert.equal(briefs.every((brief) => brief.evidenceLinks.length === 0), true);
  assert.equal(briefs.every((brief) => brief.evidenceGathered.includes("URL not provided")), true);
  assert.equal(briefs.every((brief) => brief.tomorrowPriorities.length === 3), true);
});

test("defines Kayla's effective withdrawal lifecycle", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  assert.deepEqual(seedModule.KAYLA_ACCOUNT_LIFECYCLE, {
    profileStatus: "disabled",
    membershipStatus: "disabled",
    authBanDuration: "876000h",
    effectiveAt: "2026-08-04T02:19:00-04:00",
  });
  assert.ok(seedModule.KAYLA_ACTIVITY_EVENTS, "Kayla activity seed data must exist");
  assert.equal(seedModule.KAYLA_ACTIVITY_EVENTS.length, 1);
  assert.equal(seedModule.KAYLA_ACTIVITY_EVENTS[0].id, "32000000-0000-4000-8000-000000000001");
  assert.equal(seedModule.KAYLA_ACTIVITY_EVENTS[0].eventType, "withdrawal");
});

test("defines the five canonical professional segments", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  assert.deepEqual(
    seedModule.KAYLA_PROFESSIONAL_SEGMENTS.map(({ code, name }) => ({ code, name })),
    [
      { code: "pediatric-dentist", name: "Pediatric Dentist - Family/Caregiver-Supported Care" },
      { code: "orthodontist", name: "Orthodontist - Long-Term Treatment Monitoring" },
      { code: "implant-dentist", name: "Periodontist - Periodontal/Implant Maintenance" },
      { code: "cosmetic-dentist", name: "General Dentist - High-Value Restorative/Cosmetic Care" },
      { code: "hygienist", name: "Dental Hygienist - Preventive Education and Home-Care Behavior" },
    ],
  );
});

test("keeps the professional recruitment allocation internally consistent", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  const totals = seedModule.KAYLA_PROFESSIONAL_SEGMENTS.reduce(
    (sum, segment) => ({
      min: sum.min + segment.targetMin,
      max: sum.max + segment.targetMax,
      planned: sum.planned + segment.targetPlanned,
    }),
    { min: 0, max: 0, planned: 0 },
  );

  assert.deepEqual(totals, { min: 31, max: 35, planned: 34 });
});

test("builds operational history without research-evidence writes", () => {
  assert.ok(seedModule, "Kayla seed module must exist");
  const plan = seedModule.buildKaylaSeedPlan({
    organizationId: "11111111-1111-4111-8111-111111111111",
    projectId: "22222222-2222-4222-8222-222222222222",
    userId: "33333333-3333-4333-8333-333333333333",
  });

  assert.deepEqual(Object.keys(plan).sort(), ["activities", "eodBriefs", "lifecycle", "samplePlan", "segments", "tasks"]);
  assert.equal(plan.tasks.every((task) => task.assigned_to === "33333333-3333-4333-8333-333333333333"), true);
  assert.equal(plan.tasks.every((task) => task.acceptance_criteria.includes("Seed key: kayla-pmf-")), true);
  assert.equal(plan.eodBriefs.every((brief) => brief.author_id === "33333333-3333-4333-8333-333333333333"), true);
  assert.equal(plan.eodBriefs.every((brief) => brief.evidence_links.length === 0), true);

  for (const forbidden of [
    "respondents",
    "consentRecords",
    "sessions",
    "evidence",
    "observations",
    "productEvents",
    "valueExchange",
    "gateSnapshots",
  ]) {
    assert.equal(Object.hasOwn(plan, forbidden), false, `${forbidden} must not be seeded`);
  }
});
