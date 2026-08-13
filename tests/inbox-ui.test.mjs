import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { createInboxState, inboxBucketLabel, inboxRoleCopy, projectSourceLabel, unreadInboxCount } from "../src/js/inbox.js";

const root = new URL("../", import.meta.url);

test("creates a durable role-adaptive inbox state", () => {
  assert.deepEqual(createInboxState(), {
    bucket: "needs_action",
    projectId: null,
    counts: { needsAction: 0, waiting: 0, mentioned: 0, following: 0, recentlyResolved: 0, systemAttention: 0 },
    items: [],
    generatedAt: null,
  });
  assert.equal(inboxBucketLabel("recently_resolved"), "Recently resolved");
  assert.match(inboxRoleCopy({ role: "admin", isOwner: true }).heading, /governance/i);
  assert.match(inboxRoleCopy({ role: "admin", isOwner: false }).heading, /review/i);
  assert.match(inboxRoleCopy({ role: "intern" }).heading, /assigned/i);
  assert.equal(unreadInboxCount({ items: [{ readAt: null }, { readAt: "2026-08-12" }] }), 1);
  assert.equal(projectSourceLabel("project_milestone"), "Project milestone");
  assert.equal(projectSourceLabel("project_decision"), "Project decision");
  assert.equal(projectSourceLabel("milestone"), "Project milestone");
  assert.equal(projectSourceLabel("decision"), "Project decision");
});

test("wires the persisted inbox into Today and replaces fake notifications", async () => {
  const [api, workspace, template, inboxTemplate] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/inbox-template.js", root), "utf8"),
  ]);

  assert.match(api, /rpc_aoi_inbox_snapshot/);
  assert.match(api, /rpc_aoi_mark_inbox_read/);
  assert.match(api, /rpc_aoi_create_work_comment/);
  assert.match(api, /rpc_aoi_follow_work_source/);
  assert.match(api, /rpc_aoi_handoff_work/);
  assert.match(api, /rpc_aoi_inbox_item_detail/);
  assert.match(api, /rpc_aoi_revise_work_comment/);
  assert.match(workspace, /refreshInbox/);
  assert.match(workspace, /openInboxItem/);
  assert.match(workspace, /this\.collectRecords\.find/);
  assert.match(workspace, /inboxReturnFocus/);
  assert.match(workspace, /focus\?\.\(\)/);
  assert.match(workspace, /openRequestedTask/);
  assert.match(workspace, /openRequestedCollectRecord/);
  assert.match(workspace, /createCollaborationState/);
  assert.match(template, /inboxTemplate/);
  assert.doesNotMatch(template, /Evidence review ready|notificationsRead/);
  assert.match(inboxTemplate, /Needs action/);
  assert.match(inboxTemplate, /Waiting on others/);
  assert.match(inboxTemplate, /Mentioned/);
  assert.match(inboxTemplate, /Following/);
  assert.match(inboxTemplate, /Recently resolved/);
  assert.match(inboxTemplate, /System attention/);
  assert.match(inboxTemplate, /role="status"/);
  assert.match(inboxTemplate, /aria-live="polite"/);
  assert.match(inboxTemplate, /:aria-pressed="inbox\.bucket===/);
  assert.match(inboxTemplate, /closeInboxItem\(\)/);
  assert.match(inboxTemplate, /submitCollaborationComment\(\)/);
  assert.match(inboxTemplate, /toggleCollaborationFollow\(\)/);
  assert.match(inboxTemplate, /submitCollaborationHandoff\(\)/);
  assert.match(inboxTemplate, /eligibleCollaborators/);
  assert.match(inboxTemplate, /collaboration\.comments/);
  assert.doesNotMatch(inboxTemplate, /Handoff recipient ID|Authorized team member UUID/);
});
