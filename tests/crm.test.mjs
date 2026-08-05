import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import * as crm from "../src/js/crm.js";

const {
  buildTodayQueue,
  contactCompleteness,
  createContactDraft,
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

test("resolves canonical CRM tabs and legacy outreach routes", () => {
  assert.equal(typeof crm.resolveCrmWorkspaceRoute, "function");
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "crm", tab: "recruitment" }), {
    view: "crm",
    crmTab: "recruitment",
    outreachSection: "pipeline",
    normalize: false,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "crm", tab: "outreach", section: "evidence" }), {
    view: "crm",
    crmTab: "outreach",
    outreachSection: "evidence",
    normalize: false,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "imports" }), {
    view: "crm",
    crmTab: "outreach",
    outreachSection: "imports",
    normalize: true,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "outreach", section: "unknown" }), {
    view: "crm",
    crmTab: "outreach",
    outreachSection: "pipeline",
    normalize: true,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "crm", tab: "unknown", section: "unknown" }), {
    view: "crm",
    crmTab: "contacts",
    outreachSection: "pipeline",
    normalize: true,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: "crm", tab: "outreach" }), {
    view: "crm",
    crmTab: "outreach",
    outreachSection: "pipeline",
    normalize: true,
  });
  assert.deepEqual(crm.resolveCrmWorkspaceRoute({ view: null, tab: "outreach", defaultView: "overview" }), {
    view: "overview",
    crmTab: "contacts",
    outreachSection: "pipeline",
    normalize: true,
  });
});

test("wires CRM outreach routing into the workspace controller", async () => {
  const workspace = await readFile(new URL("../src/js/workspace.js", import.meta.url), "utf8");

  assert.match(workspace, /resolveCrmWorkspaceRoute/);
  assert.match(workspace, /outreachSection:\s*"pipeline"/);
  assert.match(workspace, /setOutreachSection\(section\)/);
  assert.match(workspace, /crmTab\s*=\s*route\.crmTab/);
  assert.match(workspace, /outreachSection\s*=\s*route\.outreachSection/);
  assert.match(workspace, /replaceWorkspaceLocation\(view\)/);
  assert.match(workspace, /searchParams\.delete\("tab"\)/);
  assert.match(workspace, /searchParams\.delete\("section"\)/);
  assert.match(workspace, /openRequestedCrmContact\(contactId\)/);
  assert.equal((workspace.match(/openRequestedCrmContact\(requestedContactId\)/g) || []).length, 2);
  assert.match(workspace, /history\.replaceState/);
});
