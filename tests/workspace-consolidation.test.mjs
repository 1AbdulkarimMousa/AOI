import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import * as routes from "../src/js/crm.js";

const root = new URL("../", import.meta.url);
const resolveWorkspaceRoute = routes.resolveWorkspaceRoute || (() => ({}));

const defaults = {
  todayTab: "briefing",
  relationshipsTab: "contacts",
  outreachSection: "pipeline",
  researchTab: "collect",
  projectTab: "overview",
  projectId: null,
  projectRecordType: null,
  projectRecordId: null,
};

test("resolves canonical consolidated workspace tabs", () => {
  assert.equal(typeof routes.resolveWorkspaceRoute, "function");
  for (const tab of ["briefing", "tasks", "relationships", "momentum"]) {
    assert.deepEqual(resolveWorkspaceRoute({ view: "today", tab }), { view: "today", ...defaults, todayTab: tab, normalize: false });
  }
  for (const tab of ["contacts", "recruitment"]) {
    assert.deepEqual(resolveWorkspaceRoute({ view: "relationships", tab }), { view: "relationships", ...defaults, relationshipsTab: tab, normalize: false });
  }
  assert.deepEqual(resolveWorkspaceRoute({ view: "relationships", tab: "outreach", section: "evidence" }), {
    view: "relationships",
    ...defaults,
    relationshipsTab: "outreach",
    outreachSection: "evidence",
    normalize: false,
  });
  for (const tab of ["collect", "surveys", "analyze", "reports"]) {
    assert.deepEqual(resolveWorkspaceRoute({ view: "research", tab }), { view: "research", ...defaults, researchTab: tab, normalize: false });
  }
  for (const view of ["eod", "chat"]) {
    assert.deepEqual(resolveWorkspaceRoute({ view }), { view, ...defaults, normalize: false });
  }
  assert.deepEqual(resolveWorkspaceRoute({ view: "administration", tab: "people" }), {
    view: "administration", ...defaults, supportTab: "people", normalize: false,
  });
  assert.deepEqual(resolveWorkspaceRoute({ view: "projects", tab: "overview", project: "project-1" }), {
    view: "projects",
    ...defaults,
    projectId: "project-1",
    normalize: false,
  });
});

test("normalizes every legacy workspace destination", () => {
  const cases = [
    ["overview", { view: "today", todayTab: "briefing" }],
    ["work", { view: "today", todayTab: "tasks" }],
    ["team", { view: "today", todayTab: "momentum" }],
    ["crm", { view: "relationships", relationshipsTab: "contacts" }],
    ["outreach", { view: "relationships", relationshipsTab: "outreach", outreachSection: "pipeline" }],
    ["evidence", { view: "relationships", relationshipsTab: "outreach", outreachSection: "evidence" }],
    ["imports", { view: "relationships", relationshipsTab: "outreach", outreachSection: "imports" }],
    ["collect", { view: "research", researchTab: "collect" }],
    ["surveys", { view: "research", researchTab: "surveys" }],
    ["analyze", { view: "research", researchTab: "analyze" }],
    ["reports", { view: "research", researchTab: "reports" }],
    ["pmf", { view: "research", researchTab: "analyze" }],
    ["end-of-day", { view: "eod" }],
  ];

  for (const [view, expected] of cases) {
    const route = resolveWorkspaceRoute({ view });
    assert.equal(route.view, expected.view, view);
    for (const [key, value] of Object.entries(expected)) assert.equal(route[key], value, `${view}:${key}`);
    assert.equal(route.normalize, true, `${view}:normalize`);
  }

  const legacyOutreachEvidence = resolveWorkspaceRoute({ view: "outreach", section: "evidence" });
  assert.equal(legacyOutreachEvidence.outreachSection, "evidence");
  assert.equal(legacyOutreachEvidence.normalize, true);
});

test("rejects tabs and sections outside their owning workspace", () => {
  assert.deepEqual(resolveWorkspaceRoute({ view: "today", tab: "surveys", section: "evidence" }), {
    view: "today",
    ...defaults,
    normalize: true,
  });
  assert.deepEqual(resolveWorkspaceRoute({ view: "research", tab: "unknown", section: "imports" }), {
    view: "research",
    ...defaults,
    normalize: true,
  });
  assert.deepEqual(resolveWorkspaceRoute({ view: "relationships", tab: "contacts", section: "evidence" }), {
    view: "relationships",
    ...defaults,
    normalize: true,
  });
});

test("exposes shared operational and support destinations with local workflow tabs", async () => {
  const [controller, workspaceTemplate, crmTemplate, pmfTemplate, surveyTemplate] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
    readFile(new URL("src/js/pmf-template.js", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace-template.js", root), "utf8"),
  ]);
  const templates = workspaceTemplate + crmTemplate + pmfTemplate + surveyTemplate;

  assert.match(controller, /\{ id: "help-center", label: "Help Center" \}/);
  assert.match(controller, /\{ id: "administration", label: "Administration" \}/);
  assert.match(templates, /aria-label="Today sections"/);
  assert.match(templates, /aria-label="Relationship sections"/);
  assert.match(templates, /aria-label="Research sections"/);
  assert.match(templates, /view==='today'\s*&&\s*todayTab==='briefing'/);
  assert.match(templates, /view==='today'\s*&&\s*todayTab==='tasks'/);
  assert.match(templates, /view==='today'\s*&&\s*todayTab==='relationships'/);
  assert.match(templates, /view==='today'\s*&&\s*todayTab==='momentum'/);
  assert.match(templates, /view==='relationships'/);
  assert.match(templates, /view==='research'\s*&&\s*researchTab==='collect'/);
  assert.match(templates, /view==='research'\s*&&\s*researchTab==='surveys'/);
  assert.match(templates, /view==='research'\s*&&\s*researchTab==='analyze'/);
  assert.match(templates, /view==='research'\s*&&\s*researchTab==='reports'/);
  assert.match(controller, /url\.pathname\s*=\s*pageUrl\(import\.meta\.env\.BASE_URL, routeForRole\(access\.role\)\)/);
  assert.match(crmTemplate, /openCrmContact\(contact\)/);
});

test("uses canonical consolidated routes from utility and compatibility pages", async () => {
  const [administration, helpTemplate, tracker] = await Promise.all([
    readFile(new URL("src/js/administration.js", root), "utf8"),
    readFile(new URL("src/js/helpcenter-template.js", root), "utf8"),
    readFile(new URL("src/js/participant-tracker.js", root), "utf8"),
  ]);

  assert.match(administration, /\?view=today&tab=briefing/);
  assert.match(administration, /\?view=relationships&tab=contacts/);
  assert.match(administration, /\?view=research&tab=collect/);
  assert.match(administration, /\?view=chat/);
  assert.doesNotMatch(administration, /\?view=crm/);
  assert.match(helpTemplate, /\?view=research&tab=collect/);
  assert.match(helpTemplate, /\?view=research&tab=analyze/);
  assert.match(tracker, /\?view=relationships&tab=recruitment/);
  assert.match(tracker, /\?view=relationships&tab=contacts&contact=/);
  assert.doesNotMatch(tracker, /\?view=crm/);
});

test("renders shared support destinations once in the workspace navigation", async () => {
  const template = await readFile(new URL("src/js/workspace-template.js", root), "utf8");
  const navigation = template.match(/<nav class="primary-nav"[\s\S]*?<\/nav>/)?.[0] || "";

  assert.equal((navigation.match(/navigation\.filter\(item => \['help-center','administration'\]\.includes\(item\.id\)\)/g) || []).length, 0);
  assert.match(navigation, /x-for="item in navigation"/);
  assert.match(navigation, /item\.id\.slice\(0,1\)/);
});
