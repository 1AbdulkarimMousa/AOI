import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const projects = await import("../src/js/projects.js").catch(() => ({}));
const createProjectRecordDraft = projects.createProjectRecordDraft || (() => ({}));
const activeProjectAccess = projects.activeProjectAccess || (() => ({}));
const ensureProjectMutationNonce = projects.ensureProjectMutationNonce || (() => null);
const filterProjectRecords = projects.filterProjectRecords || (() => []);
const hydrateProjectRecordDraft = projects.hydrateProjectRecordDraft || (() => ({}));
const isProjectRecordEditable = projects.isProjectRecordEditable || (() => false);
const mergeProjectSelection = projects.mergeProjectSelection || (() => ({}));
const normalizeProjectDetail = projects.normalizeProjectDetail || (() => ({}));
const normalizeProjectSnapshot = projects.normalizeProjectSnapshot || (() => ({}));
const projectRecordActions = projects.projectRecordActions || (() => []);
const riskScorePresentation = projects.riskScorePresentation || (() => ({}));
const serializeProjectRecord = projects.serializeProjectRecord || (() => ({}));
const sortProjectRecords = projects.sortProjectRecords || (() => []);
const projectTabNavigation = projects.projectTabNavigation || (() => null);

test("exports testable project domain helpers", () => {
  for (const name of ["activeProjectAccess", "createProjectRecordDraft", "ensureProjectMutationNonce", "filterProjectRecords", "hydrateProjectRecordDraft", "isProjectRecordEditable", "mergeProjectSelection", "normalizeProjectDetail", "normalizeProjectSnapshot", "projectRecordActions", "projectTabNavigation", "riskScorePresentation", "serializeProjectRecord", "sortProjectRecords"]) {
    assert.equal(typeof projects[name], "function", name);
  }
});

test("normalizes the mixed RPC snapshot and detail shapes", () => {
  const snapshot = normalizeProjectSnapshot({
    project: { id: "p1", managerId: "u1", plannedFinish: "2026-09-25", updatedAt: "stamp-p" },
    members: [{ userId: "u1", displayName: "Ada Admin" }, { userId: "u2", displayName: "Ian Intern" }],
    milestones: [{ id: "m1", title: "Review", intended_outcome: "Approved packet", owner_id: "u2", planned_finish: "2026-08-20", progress_percent: 60, acceptance_criteria: "Signed", next_action: "Submit", next_action_due: "2026-08-18", updated_at: "stamp-m" }],
    blockers: [], risks: [], decisions: [], activity: [{ id: "h1", actor_id: "u1", action: "approve", created_at: "2026-08-12" }],
  });
  assert.deepEqual(Object.fromEntries(Object.entries(snapshot.milestones[0]).filter(([key]) => !key.includes("_"))), {
    id: "m1", title: "Review", outcome: "Approved packet", ownerId: "u2", ownerName: "Ian Intern", plannedDate: "2026-08-20", progress: 60, acceptanceCriteria: "Signed", nextAction: "Submit", dueDate: "2026-08-18", updatedAt: "stamp-m",
  });
  assert.equal(snapshot.project.managerName, "Ada Admin");
  assert.equal(snapshot.activity[0].actorName, "Ada Admin");

  const detail = normalizeProjectDetail("decision", {
    record: { id: "d1", title: "Choose", expected_impact: "Traceable result", owner_id: "u2", updated_at: "stamp-d" },
    history: [{ id: "h2", actor_id: "u1", created_at: "2026-08-12" }],
    evidence: [
      { id: "link-1", evidence_id: "e1", stance: "supporting", relevance_note: "Direct", title: "Observed benefit", provenance: "Approved interview", limitations: "Small sample" },
      { id: "link-2", evidenceId: "e2", stance: "contradicting", relevance_note: "Limitation", title: "Workflow concern", provenance: "Approved observation", limitations: "One clinic" },
    ],
    snapshots: [{ id: "s1", version: 1, snapshot_data: { title: "Approved choice", statement: "Choose A", alternatives: ["Choose B"], rationale: "Best evidence", expectedImpact: "Faster learning", evidence: [{ sourceId: "e1", stance: "supporting", title: "Observed benefit", provenance: { sourceType: "evidence" }, limitations: "Small sample" }] } }],
  }, snapshot.members);
  assert.equal(detail.expectedImpact, "Traceable result");
  assert.equal(detail.ownerName, "Ian Intern");
  assert.equal(detail.evidence.supporting[0].relevanceNote, "Direct");
  assert.equal(detail.evidence.contradicting[0].relevanceNote, "Limitation");
  assert.deepEqual(detail.evidenceLinks, [
    { evidenceId: "e1", stance: "supporting", relevanceNote: "Direct" },
    { evidenceId: "e2", stance: "contradicting", relevanceNote: "Limitation" },
  ]);
  assert.equal(detail.snapshots[0].version, 1);
  assert.equal(detail.snapshots[0].content.statement, "Choose A");
  assert.equal(detail.snapshots[0].evidence.supporting[0].title, "Observed benefit");
});

test("editing an existing decision preserves loaded evidence links unless intentionally changed", () => {
  const detail = normalizeProjectDetail("decision", {
    record: { id: "d1", title: "Choose", statement: "Use the reviewed path" },
    evidence: [{ evidence_id: "e1", stance: "supporting", relevance_note: "Direct" }],
  });
  const hydratedDraft = { ...createProjectRecordDraft("decision"), ...detail };
  const preserved = serializeProjectRecord("decision", { ...hydratedDraft, rationale: "Clarified wording" }, "p1");
  assert.deepEqual(preserved.evidenceLinks, [{ evidenceId: "e1", stance: "supporting", relevanceNote: "Direct" }]);

  const unknownLinks = serializeProjectRecord("decision", { title: "Legacy", statement: "Keep links", rationale: "No detail loaded" }, "p1");
  assert.equal(Object.hasOwn(unknownLinks, "evidenceLinks"), false, "an absent link field must not become a destructive empty array");
  assert.deepEqual(serializeProjectRecord("decision", { ...hydratedDraft, evidenceLinks: [] }, "p1").evidenceLinks, [], "an explicit removal remains intentional");
});

test("an existing decision summary never hydrates an implicit destructive empty evidence list", () => {
  const summaryDraft = hydrateProjectRecordDraft("decision", { id: "d1", title: "Existing decision" }, { ownerId: "u1" });
  assert.equal(Object.hasOwn(summaryDraft, "evidenceLinks"), false);
  const detailedDraft = hydrateProjectRecordDraft("decision", { id: "d1", title: "Existing decision", evidenceLinks: [] }, { ownerId: "u1" });
  assert.deepEqual(detailedDraft.evidenceLinks, []);
  assert.deepEqual(hydrateProjectRecordDraft("decision", null, { ownerId: "u1" }).evidenceLinks, []);
});

test("serializes project drafts to the fixed RPC payload", () => {
  assert.deepEqual(serializeProjectRecord("milestone", {
    title: "Review", outcome: "Approved packet", ownerId: "u2", plannedDate: "2026-08-20", progress: 60, acceptanceCriteria: "Signed", nextAction: "Submit", dueDate: "2026-08-18",
  }, "p1"), {
    projectId: "p1", title: "Review", intendedOutcome: "Approved packet", ownerId: "u2", plannedFinish: "2026-08-20", progressPercent: 60, acceptanceCriteria: "Signed", nextAction: "Submit", nextActionDue: "2026-08-18",
  });
  assert.deepEqual(serializeProjectRecord("risk", { statement: "Bias", ownerId: "u2", probability: 4, impact: 3, trigger: "Skew", mitigation: "Broaden", nextAction: "Recruit", dueDate: "2026-08-18", reviewDate: "2026-08-20" }, "p1"), {
    projectId: "p1", statement: "Bias", ownerId: "u2", probability: 4, impact: 3, triggerCondition: "Skew", mitigation: "Broaden", nextAction: "Recruit", nextActionDue: "2026-08-18", reviewDate: "2026-08-20",
  });
});

test("creates typed project record drafts with accountable defaults", () => {
  assert.deepEqual(createProjectRecordDraft("milestone", { ownerId: "member-1" }), {
    title: "",
    outcome: "",
    ownerId: "member-1",
    plannedDate: "",
    progress: 0,
    acceptanceCriteria: "",
    nextAction: "",
    dueDate: "",
    status: "draft",
  });
  assert.deepEqual(createProjectRecordDraft("risk", { ownerId: "member-1" }), {
    statement: "",
    ownerId: "member-1",
    probability: 1,
    impact: 1,
    trigger: "",
    mitigation: "",
    nextAction: "",
    dueDate: "",
    reviewDate: "",
    acceptanceRationale: "",
    status: "identified",
  });
});

test("presents server risk scores with non-color labels", () => {
  assert.deepEqual(riskScorePresentation(3), { label: "Low", tone: "teal" });
  assert.deepEqual(riskScorePresentation(9), { label: "Moderate", tone: "blue" });
  assert.deepEqual(riskScorePresentation(16), { label: "High", tone: "orange" });
  assert.deepEqual(riskScorePresentation(25), { label: "Critical", tone: "rose" });
  assert.deepEqual(riskScorePresentation(null), { label: "Not scored", tone: "muted" });
});

test("limits lifecycle actions by record type, role, and state", () => {
  assert.deepEqual(projectRecordActions("milestone", "draft", "admin"), ["activate", "cancel"]);
  assert.deepEqual(projectRecordActions("milestone", "active", "intern"), ["submit", "block"]);
  assert.deepEqual(projectRecordActions("milestone", "blocked", "intern"), ["unblock"]);
  assert.deepEqual(projectRecordActions("milestone", "submitted", "admin"), ["revise", "approve"]);
  assert.deepEqual(projectRecordActions("blocker", "acknowledged", "intern"), ["start_resolving", "resolve", "escalate"]);
  assert.deepEqual(projectRecordActions("decision", "submitted", "intern"), []);
  assert.deepEqual(projectRecordActions("decision", "submitted", "admin"), ["request_revision", "reject", "approve"]);
  assert.deepEqual(projectRecordActions("decision", "approved", "admin"), ["supersede"]);
  assert.deepEqual(projectRecordActions("risk", "monitoring", "admin"), ["accept", "close"]);
  for (const status of ["submitted", "approved", "completed", "resolved", "accepted", "closed"]) {
    assert.equal(isProjectRecordEditable("milestone", status, "admin", "u1", "u1"), false, status);
  }
  assert.equal(isProjectRecordEditable("milestone", "active", "intern", "u1", "u1"), true);
  assert.equal(isProjectRecordEditable("milestone", "active", "intern", "u2", "u1"), false);
  assert.equal(isProjectRecordEditable("blocker", "resolving", "intern", "u2", "u1"), true);
});

test("derives project permissions from the selected organization rather than global access", () => {
  const context = {
    selectedOrganizationId: "o2",
    role: "admin",
    isOwner: true,
    organizations: [
      { id: "o1", name: "Owned Org", role: "admin", isOwner: true },
      { id: "o2", name: "Intern Org", role: "intern", isOwner: false },
    ],
  };
  assert.deepEqual(activeProjectAccess(context), { organizationId: "o2", organizationName: "Intern Org", role: "intern", isOwner: false });
  assert.deepEqual(activeProjectAccess({ ...context, selectedOrganizationId: "o1" }), { organizationId: "o1", organizationName: "Owned Org", role: "admin", isOwner: true });
});

test("retains one durable client nonce for the same uncertain mutation", () => {
  let calls = 0;
  const crypto = { randomUUID: () => `nonce-${++calls}` };
  const pending = {};
  assert.equal(ensureProjectMutationNonce(pending, "create:milestone", crypto), "nonce-1");
  assert.equal(ensureProjectMutationNonce(pending, "create:milestone", crypto), "nonce-1");
  assert.equal(ensureProjectMutationNonce(pending, "transition:m1:submit", crypto), "nonce-2");
  assert.equal(calls, 2);
});

test("supports roving project tab navigation", () => {
  const tabs = ["overview", "milestones", "blockers", "decisions"];
  assert.equal(projectTabNavigation(tabs, "overview", "ArrowRight"), "milestones");
  assert.equal(projectTabNavigation(tabs, "overview", "ArrowLeft"), "decisions");
  assert.equal(projectTabNavigation(tabs, "blockers", "Home"), "overview");
  assert.equal(projectTabNavigation(tabs, "milestones", "End"), "decisions");
  assert.equal(projectTabNavigation(tabs, "milestones", "Enter"), null);
});

test("merges a selected project without dropping authorized switcher options", () => {
  const context = { selectedProjectId: "p1", selectedOrganizationId: "o1", organizations: [{ id: "o1", projects: [{ id: "p1" }, { id: "p2" }] }] };
  assert.deepEqual(mergeProjectSelection(context, { selectedProjectId: "p2", selectedOrganizationId: "o1" }), { ...context, selectedProjectId: "p2" });
});

test("filters and sorts project registers without mutating the snapshot", () => {
  const records = [
    { id: "2", title: "Later", ownerId: "member-2", status: "active", dueDate: "2026-08-20", score: 4 },
    { id: "1", title: "Urgent", ownerId: "member-1", status: "blocked", dueDate: "2026-08-13", score: 20 },
    { id: "3", title: "Review", ownerId: "member-1", status: "active", dueDate: "2026-08-12", score: 10 },
  ];
  assert.deepEqual(filterProjectRecords(records, { ownerId: "member-1", status: "active" }).map((item) => item.id), ["3"]);
  assert.deepEqual(sortProjectRecords(records, "dueDate").map((item) => item.id), ["3", "1", "2"]);
  assert.deepEqual(sortProjectRecords(records, "riskScore").map((item) => item.id), ["1", "3", "2"]);
  assert.equal(records[0].id, "2");
});

test("project template is a register and detail pane, not modal-first CRUD", async () => {
  const template = await readFile(new URL("src/js/projects-template.js", root), "utf8");
  for (const label of ["Overview", "Milestones", "Blockers & Risks", "Decisions"]) assert.match(template, new RegExp(label));
  for (const state of ["projectLoading", "projectError", "projectStale", "projectSnapshot"]) assert.match(template, new RegExp(state));
  assert.match(template, /project-register/);
  assert.match(template, /project-detail-pane/);
  assert.match(template, /startProjectRecord/);
  assert.match(template, /Create project/);
  assert.match(template, /Configure project/);
  assert.match(template, /Decision evidence links/);
  for (const field of ["Planned finish", "Progress percent", "Next action due", "Blocking party", "Expected resolution", "Impact", "Review date"]) assert.match(template, new RegExp(field));
  assert.match(template, /Review history/);
  assert.match(template, /saveProjectRecord/);
  assert.match(template, /transitionProjectRecord/);
  assert.match(template, /activeProjectRole==='admin'/);
  assert.match(template, /\['blockers','risks'\]\.includes\(projectTab\)/);
  assert.match(template, /Supporting evidence[\s\S]*Contradictory evidence/);
  assert.match(template, /Immutable approved snapshot/);
  assert.match(template, /projectSnapshot\.members/);
  assert.doesNotMatch(template, /modal-backdrop|aria-modal="true"/);
});
