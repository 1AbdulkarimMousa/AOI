import assert from "node:assert/strict";
import test from "node:test";

const seedModule = await import("../scripts/mike-outreach-seed-data.mjs").catch(() => null);

test("defines the nine supplied Mike outreach contacts", () => {
  assert.ok(seedModule, "Mike outreach seed module must exist");
  assert.equal(seedModule.MIKE_OUTREACH_CONTACTS.length, 9);
  assert.deepEqual(
    seedModule.MIKE_OUTREACH_CONTACTS.map(({ externalId, handle }) => [externalId, handle]),
    [
      ["12", "@dentist_emi"],
      ["13", "@dryazdan"],
      ["14", "@fitlittlehygienist"],
      ["15", "@justflossit"],
      ["16", "@drashleyizadi"],
      ["17", "@smilewithcallie"],
      ["18", "@iamdr_a"],
      ["19", "@jerry_rdh"],
      ["20", "@pediatric.dentist.mom"],
    ],
  );
});

test("preserves every supplied email and phone number", () => {
  assert.ok(seedModule, "Mike outreach seed module must exist");
  const byHandle = Object.fromEntries(seedModule.MIKE_OUTREACH_CONTACTS.map((contact) => [contact.handle, contact]));

  assert.deepEqual(byHandle["@dryazdan"].emails, ["doctoryazdan@gmail.com", "info@dryazdan.com"]);
  assert.equal(byHandle["@dryazdan"].phone, "949.644-6988");
  assert.deepEqual(byHandle["@jerry_rdh"].emails, ["JerryRDH@gmail.com", "dentistryhumor@gmail.com"]);
  assert.equal(byHandle["@drashleyizadi"].phone, "+14106661178");
  assert.equal(byHandle["@iamdr_a"].phone, "+1 212-223-7946");
  assert.equal(seedModule.MIKE_OUTREACH_CONTACTS.every((contact) => contact.emails.length >= 1), true);
});

test("records only explicitly reported outreach channels", () => {
  assert.ok(seedModule, "Mike outreach seed module must exist");
  const byHandle = Object.fromEntries(seedModule.MIKE_OUTREACH_CONTACTS.map((contact) => [contact.handle, contact]));

  assert.deepEqual(byHandle["@dentist_emi"].outreachChannels, ["Instagram", "Email"]);
  assert.deepEqual(byHandle["@dryazdan"].outreachChannels, ["Facebook", "Instagram", "Email", "Phone Call"]);
  assert.deepEqual(byHandle["@iamdr_a"].outreachChannels, ["Email", "Instagram", "Facebook", "Phone Call"]);
  assert.deepEqual(byHandle["@jerry_rdh"].outreachChannels, ["Instagram", "Facebook", "Email"]);
  assert.deepEqual(byHandle["@drashleyizadi"].outreachChannels, ["Instagram"]);
  assert.equal(seedModule.MIKE_OUTREACH_CONTACTS.filter((contact) => contact.outreachChannels.length > 0).length, 9);
});

test("builds idempotent candidate updates and channel-level events", () => {
  assert.ok(seedModule, "Mike outreach seed module must exist");
  const candidatesByExternalId = Object.fromEntries(
    seedModule.MIKE_OUTREACH_CONTACTS.map((contact, index) => [contact.externalId, {
      id: `candidate-${index + 1}`,
      external_id: contact.externalId,
      outreach_status: "Ready to Send",
      notes: contact.externalId === "16"
        ? "[Mike outreach seed 2026-08-05] Contact details were supplied, but no completed outreach channel was reported."
        : null,
    }]),
  );
  const plan = seedModule.buildMikeOutreachSeedPlan({
    organizationId: "11111111-1111-4111-8111-111111111111",
    projectId: "22222222-2222-4222-8222-222222222222",
    ownerId: "33333333-3333-4333-8333-333333333333",
    candidatesByExternalId,
  });

  assert.equal(plan.candidateUpdates.length, 9);
  assert.equal(plan.crmContacts.length, 9);
  assert.equal(plan.crmActivities.length, 9);
  assert.equal(plan.crmActivities.filter((activity) => activity.activity_type === "outreach").length, 9);
  assert.equal(plan.crmActivities.filter((activity) => activity.activity_type === "enrich").length, 0);
  assert.equal(plan.outreachEvents.length, 22);
  assert.equal(new Set(plan.outreachEvents.map((event) => event.id)).size, 22);
  assert.equal(plan.outreachEvents.every((event) => event.status === "Sent" && event.kind === "Initial"), true);
  assert.equal(plan.outreachEvents.every((event) => event.occurred_at.startsWith("2026-08-05T")), true);
  assert.equal(plan.candidateUpdates.filter((update) => update.values.outreach_status === "Sent").length, 9);

  const ashley = plan.candidateUpdates.find((update) => update.externalId === "16");
  assert.equal(ashley.values.outreach_status, "Sent");
  assert.match(ashley.values.notes, /Initial outreach reported via Instagram/);
  assert.doesNotMatch(ashley.values.notes, /no completed outreach channel was reported/);
  assert.match(ashley.values.contact_detail, /dr\.roham@valleydentalhealth\.com/);
  assert.match(ashley.values.contact_detail, /\+14106661178/);
  assert.deepEqual(plan.executionPlanUpdate, { planDate: "2026-08-05", minimumFirstTouches: 9 });
});
