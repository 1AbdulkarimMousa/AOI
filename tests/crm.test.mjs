import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import * as crm from "../src/js/crm.js";

const {
  buildTodayQueue,
  contactCompleteness,
  createContactDraft,
  nextTabFromKey,
  rewardForAction,
} = crm;

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
    createOutreach: false,
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

test("derives needs-action state without mutating contact snapshots", () => {
  const contacts = [
    { id: "complete-overdue", name: "Complete overdue", completeness: 100, nextActionDue: "2026-08-03" },
    { id: "complete-later", name: "Complete later", completeness: 100, nextActionDue: "2026-08-12" },
  ];

  const queue = buildTodayQueue(contacts, "2026-08-04");

  assert.equal(contacts[0].queueReason, undefined);
  assert.equal(queue.find((contact) => contact.id === "complete-overdue").queueReason, "Overdue");
});

test("moves relationship tabs with arrow, Home, and End keys", () => {
  const tabs = ["contacts", "recruitment", "outreach"];
  assert.equal(nextTabFromKey(tabs, "contacts", "ArrowRight"), "recruitment");
  assert.equal(nextTabFromKey(tabs, "contacts", "ArrowLeft"), "outreach");
  assert.equal(nextTabFromKey(tabs, "recruitment", "Home"), "contacts");
  assert.equal(nextTabFromKey(tabs, "recruitment", "End"), "outreach");
  assert.equal(nextTabFromKey(tabs, "contacts", "Enter"), null);
});

test("rewards verified CRM actions without ranking people", () => {
  assert.equal(rewardForAction("enrich", 25), 35);
  assert.equal(rewardForAction("outreach", 25), 45);
  assert.equal(rewardForAction("follow_up", 25), 55);
});

test("resolves canonical Relationships tabs and legacy CRM routes", () => {
  assert.equal(typeof crm.resolveWorkspaceRoute, "function");
  const recruitment = crm.resolveWorkspaceRoute({ view: "relationships", tab: "recruitment" });
  assert.equal(recruitment.view, "relationships");
  assert.equal(recruitment.relationshipsTab, "recruitment");
  assert.equal(recruitment.normalize, false);

  const evidence = crm.resolveWorkspaceRoute({ view: "relationships", tab: "outreach", section: "evidence" });
  assert.equal(evidence.relationshipsTab, "outreach");
  assert.equal(evidence.outreachSection, "evidence");
  assert.equal(evidence.normalize, false);

  const legacy = crm.resolveWorkspaceRoute({ view: "imports" });
  assert.equal(legacy.view, "relationships");
  assert.equal(legacy.relationshipsTab, "outreach");
  assert.equal(legacy.outreachSection, "imports");
  assert.equal(legacy.normalize, true);

  const invalid = crm.resolveWorkspaceRoute({ view: "relationships", tab: "unknown", section: "unknown" });
  assert.equal(invalid.relationshipsTab, "contacts");
  assert.equal(invalid.outreachSection, "pipeline");
  assert.equal(invalid.normalize, true);
});

test("wires Relationships outreach routing into the workspace controller", async () => {
  const workspace = await readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8");

  assert.match(workspace, /resolveWorkspaceRoute/);
  assert.match(workspace, /outreachSection:\s*"pipeline"/);
  assert.match(workspace, /setOutreachSection\(section\)/);
  assert.match(workspace, /relationshipsTab\s*=\s*route\.relationshipsTab/);
  assert.match(workspace, /outreachSection\s*=\s*route\.outreachSection/);
  assert.match(workspace, /replaceWorkspaceLocation\(replace = false, contactId = ""\)/);
  assert.match(workspace, /\["tab", "section"[\s\S]*url\.searchParams\.delete\(param\)/);
  assert.match(workspace, /openRequestedCrmContact\(contactId\)/);
  assert.equal((workspace.match(/openRequestedCrmContact\(requestedContactId\)/g) || []).length, 2);
  assert.match(workspace, /history\.replaceState/);
});
