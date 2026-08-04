import assert from "node:assert/strict";
import test from "node:test";

import {
  buildTodayQueue,
  contactCompleteness,
  createContactDraft,
  rewardForAction,
} from "../src/js/crm.js";

test("creates a short contact draft with safe defaults", () => {
  assert.deepEqual(createContactDraft("Kayla Tillmon"), {
    name: "",
    contactType: "KOL",
    organization: "",
    email: "",
    phone: "",
    primaryChannel: "Email",
    sourceUrl: "",
    tags: "",
    ownerName: "Kayla Tillmon",
    lifecycle: "new",
    nextAction: "",
    nextActionDue: "",
    notes: "",
  });
});

test("scores contact completeness from the fields needed for follow-up", () => {
  assert.equal(contactCompleteness({ name: "Dr. Ada", contactType: "Professional" }), 33);
  assert.equal(contactCompleteness({
    name: "Dr. Ada",
    contactType: "Professional",
    primaryChannel: "Email",
    sourceUrl: "https://example.com",
    nextAction: "Send intro",
    nextActionDue: "2026-08-08",
  }), 100);
});

test("puts overdue and due-today contacts before later work", () => {
  const queue = buildTodayQueue([
    { id: "later", name: "Later", nextActionDue: "2026-08-12", priorityScore: 99 },
    { id: "today", name: "Today", nextActionDue: "2026-08-04", priorityScore: 50 },
    { id: "overdue", name: "Overdue", nextActionDue: "2026-08-03", priorityScore: 10 },
  ], "2026-08-04");

  assert.deepEqual(queue.map((item) => item.id), ["overdue", "today", "later"]);
  assert.equal(queue[0].queueReason, "Overdue");
});

test("rewards verified CRM actions without ranking people", () => {
  assert.equal(rewardForAction("enrich", 25), 35);
  assert.equal(rewardForAction("outreach", 25), 45);
  assert.equal(rewardForAction("follow_up", 25), 55);
});
