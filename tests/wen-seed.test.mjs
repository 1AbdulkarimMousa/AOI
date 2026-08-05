import assert from "node:assert/strict";
import test from "node:test";

const seedModule = await import("../scripts/intern-seed-data.mjs").catch(() => null);

test("defines Wen as an active consumer research intern", () => {
  assert.ok(seedModule, "Intern seed module must exist");
  assert.deepEqual(seedModule.WEN_ACCOUNT, {
    email: "wxt116@gmail.com",
    displayName: "Wen Tang",
    role: "intern",
  });
});

test("preserves all supplied Wen EOD dates without inventing source URLs", () => {
  assert.ok(seedModule, "Intern seed module must exist");
  const briefs = seedModule.buildInternSeedPlan({
    organizationId: "11111111-1111-4111-8111-111111111111",
    projectId: "22222222-2222-4222-8222-222222222222",
    userId: "33333333-3333-4333-8333-333333333333",
  }).eodBriefs;
  assert.deepEqual(briefs.map((brief) => brief.brief_date), [
    "2026-07-29",
    "2026-07-30",
    "2026-07-31",
    "2026-08-03",
    "2026-08-04",
  ]);
  assert.equal(briefs.every((brief) => brief.workflow_status === "submitted"), true);
  assert.equal(briefs.every((brief) => brief.evidence_links.length === 0), true);
  assert.equal(briefs.every((brief) => /URL|URLs\/files not provided/.test(brief.evidence_gathered)), true);
  assert.equal(briefs.every((brief) => brief.tomorrow_priorities.length === 3), true);
});

test("seeds Wen planning work without claiming participant evidence", () => {
  assert.ok(seedModule, "Intern seed module must exist");
  const plan = seedModule.buildInternSeedPlan({
    organizationId: "11111111-1111-4111-8111-111111111111",
    projectId: "22222222-2222-4222-8222-222222222222",
    userId: "33333333-3333-4333-8333-333333333333",
  });

  assert.equal(plan.tasks.length >= 8, true);
  assert.equal(new Set(plan.tasks.map((task) => task.acceptance_criteria.match(/Seed key: ([^\n]+)/)?.[1])).size, plan.tasks.length);
  assert.equal(plan.tasks.every((task) => task.acceptance_criteria.includes("Seed key: wen-pmf-")), true);
  assert.equal(plan.tasks.every((task) => task.assigned_to === "33333333-3333-4333-8333-333333333333"), true);
  assert.equal(plan.eodBriefs.every((brief) => brief.author_id === "33333333-3333-4333-8333-333333333333"), true);

  for (const forbidden of ["respondents", "contacts", "sessions", "evidence", "observations", "productEvents", "valueExchange"]) {
    assert.equal(Object.hasOwn(plan, forbidden), false, `${forbidden} must not be seeded`);
  }
});
