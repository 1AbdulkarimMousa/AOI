import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  briefingProgress,
  briefingRoleCopy,
  briefingSourceDestination,
  createBriefingState,
  createPreviewBriefing,
} from "../src/js/briefing.js";

const root = new URL("../", import.meta.url);

test("normalizes bounded briefing data without inventing unsupported values", () => {
  const state = createBriefingState({
    scope: "team",
    summary: { pendingReviews: "3", approvedEvidence: 7 },
    attention: Array.from({ length: 14 }, (_, index) => ({ id: `a-${index}` })),
    signals: [{ id: "signal", evidenceCount: 4, strength: "3.25", changePercent: 99 }],
    samplePlan: [{ id: "sample", actual: null, target: 20, derivationStatus: "unsupported" }],
  });

  assert.equal(state.scope, "team");
  assert.equal(state.summary.pendingReviews, 3);
  assert.equal(state.summary.approvedEvidence, 7);
  assert.equal(state.attention.length, 12);
  assert.deepEqual(state.signals[0], { id: "signal", evidenceCount: 4, strength: 3.25 });
  assert.equal(state.samplePlan[0].actual, null);
  assert.equal(state.samplePlan[0].derivationStatus, "unsupported");
});

test("clamps visual progress while preserving unsupported sample state", () => {
  assert.equal(briefingProgress({ actual: 24, target: 20 }), 100);
  assert.equal(briefingProgress({ actual: -3, target: 20 }), 0);
  assert.equal(briefingProgress({ actual: null, target: 20 }), null);
  assert.equal(briefingProgress({ actual: 3, target: 0 }), null);
});

test("derives role copy from distinct attention rows", () => {
  assert.deepEqual(briefingRoleCopy("admin", { pendingReviews: 2, blockedWork: 1, overdueTasks: 3 }, 4), {
    eyebrow: "Administrator briefing",
    heading: "4 items need a decision or follow-up",
    body: "2 pending reviews, 1 blocked item, and 3 overdue tasks across this project.",
  });
  assert.deepEqual(briefingRoleCopy("intern", { pendingReviews: 0, blockedWork: 0, overdueTasks: 0 }, 0), {
    eyebrow: "Your briefing",
    heading: "Your assigned work is clear",
    body: "No assigned reviews, blockers, or overdue tasks need attention right now.",
  });
});

test("maps briefing records to exact owning workflows", () => {
  assert.deepEqual(briefingSourceDestination({ sourceType: "task", sourceId: "task-1" }), { view: "today", tab: "tasks", task: "task-1" });
  assert.deepEqual(briefingSourceDestination({ sourceType: "decision", sourceId: "decision-1" }), { view: "projects", tab: "decisions", decision: "decision-1" });
  assert.deepEqual(briefingSourceDestination({ sourceType: "risk", sourceId: "risk-1" }), { view: "projects", tab: "risks", risk: "risk-1" });
  assert.deepEqual(briefingSourceDestination({ sourceType: "survey_submission", sourceId: "response-1", assetId: "survey-1" }), { view: "research", tab: "surveys", response: "response-1", assetId: "survey-1" });
  assert.deepEqual(briefingSourceDestination({ sourceType: "evidence", sourceId: "evidence-1" }), { view: "research", tab: "collect", type: "evidence", id: "evidence-1" });
  assert.deepEqual(briefingSourceDestination({ sourceType: "pmf_layer", sourceId: "H2" }), { view: "research", tab: "analyze", layer: "H2" });
});

test("creates useful role-scoped synthetic briefing previews", () => {
  const dashboard = {
    project: { id: "preview-project", code: "SYN-01", name: "Synthetic evidence study" },
    tasks: [
      { id: "mine", title: "Resolve synthetic evidence gap", ownerName: "Morgan Example", status: "blocked", priority: "high", dueDate: "2026-08-10" },
      { id: "other", title: "Review synthetic submission", ownerName: "Avery Example", status: "submitted", priority: "high", dueDate: "2026-08-10" },
    ],
    evidence: [{ id: "e-1", pmfLayer: "H1", topic: "Visible next actions", stance: "supporting", strength: 3, workflowStatus: "approved" }],
    samplePlan: [{ id: "s-1", label: "Synthetic interviews", actual: 4, target: 8, pmfLayer: "H1", accent: "orange" }],
    generatedAt: "2026-08-13T08:00:00Z",
  };

  const admin = createPreviewBriefing(dashboard, "admin", "Avery Example");
  const intern = createPreviewBriefing(dashboard, "intern", "Morgan Example");
  assert.equal(admin.scope, "team");
  assert.equal(admin.attention.length, 2);
  assert.equal(intern.scope, "personal");
  assert.deepEqual(intern.attention.map((item) => item.sourceId), ["mine"]);
  assert.equal(intern.preview, true);

  const repairedIdentity = createPreviewBriefing({ ...dashboard, tasks: [{ id: "legacy", title: "Synthetic assigned review", ownerName: "Legacy Person", status: "submitted" }] }, "intern", "Morgan Example");
  assert.equal(repairedIdentity.attention.length, 1);
  assert.equal(repairedIdentity.attention[0].category, "follow_up");
  assert.notEqual(repairedIdentity.attention[0].sourceId, "legacy");
});

test("wires an action-first briefing without legacy seeded dashboard claims", async () => {
  const [api, workspace, template] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
  ]);

  assert.match(api, /rpc_aoi_today_briefing/);
  assert.match(workspace, /briefingState/);
  assert.match(workspace, /refreshBriefing/);
  assert.match(workspace, /briefingPreviewMode/);
  assert.match(template, /briefingState\.preview/);
  assert.match(workspace, /taskDetailReady/);
  assert.match(workspace, /data: emptyDashboard\(\)/);
  assert.match(template, /class="briefing-workspace"/);
  assert.match(template, /briefingLoading/);
  assert.match(template, /briefingError/);
  assert.match(template, /briefingProgress\(item\)/);
  const briefing = template.match(/<div x-show="view==='today' && todayTab==='briefing'" class="briefing-workspace">([\s\S]*?)<div x-show="view==='today' && todayTab==='tasks'">/)?.[1] || "";
  assert.ok(briefing);
  assert.doesNotMatch(briefing, /legacy-briefing-context/);
  assert.doesNotMatch(briefing, /Personal mission/);
  assert.doesNotMatch(briefing, /metric in data\.metrics/);
  assert.doesNotMatch(briefing, /layer\.confidence/);
  assert.doesNotMatch(briefing, /signal\.changePercent/);
});
