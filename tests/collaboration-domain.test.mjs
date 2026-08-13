import assert from "node:assert/strict";
import test from "node:test";

const collaboration = await import("../src/js/collaboration.js").catch(() => ({}));

test("exports one collaboration behavior contract for project and Today", () => {
  for (const name of [
    "canonicalWorkSourceType",
    "collaborationFollowLabel",
    "collaborationRequestIsCurrent",
    "createCollaborationState",
    "eligibleCollaborationRecipients",
    "ensureCollaborationNonce",
    "normalizeCollaborationProjection",
  ]) assert.equal(typeof collaboration[name], "function", name);
});

test("normalizes full and compact collaboration projections", () => {
  const input = {
    source_type: "project_decision",
    source_id: "decision-1",
    comment_count: 4,
    is_following: true,
    comments: [
      { id: "c2", body: "Second", author_display_name: "Morgan Example", created_at: "2026-08-13T11:00:00Z", current_revision: 2, edited_at: "2026-08-13T11:30:00Z" },
      { id: "c1", body: "First", authorName: "Avery Example", createdAt: "2026-08-13T10:00:00Z", revisionCount: 1 },
    ],
    eligible_collaborators: [
      { user_id: "current", display_name: "Current Example", role: "admin", active: true },
      { user_id: "eligible", display_name: "Morgan Example", role: "intern", active: true },
      { user_id: "inactive", display_name: "Inactive Example", role: "intern", active: false },
    ],
  };
  const normalized = collaboration.normalizeCollaborationProjection(input, { currentUserId: "current", density: "compact" });
  assert.equal(normalized.sourceType, "decision");
  assert.equal(normalized.sourceId, "decision-1");
  assert.equal(normalized.commentCount, 4);
  assert.equal(normalized.isFollowing, true);
  assert.deepEqual(normalized.comments.map((comment) => comment.id), ["c1", "c2"]);
  assert.equal(normalized.comments[1].authorName, "Morgan Example");
  assert.equal(normalized.comments[1].revisionCount, 2);
  assert.deepEqual(normalized.eligibleCollaborators.map((member) => member.userId), ["eligible"]);
});

test("retains separate nonces per source and describes the next follow action", () => {
  let calls = 0;
  const crypto = { randomUUID: () => `nonce-${++calls}` };
  const drafts = {};
  assert.equal(collaboration.ensureCollaborationNonce(drafts, "decision:one", "commentNonce", crypto), "nonce-1");
  assert.equal(collaboration.ensureCollaborationNonce(drafts, "decision:one", "commentNonce", crypto), "nonce-1");
  assert.equal(collaboration.ensureCollaborationNonce(drafts, "risk:two", "commentNonce", crypto), "nonce-2");
  assert.equal(collaboration.collaborationFollowLabel(false), "Follow updates");
  assert.equal(collaboration.collaborationFollowLabel(true), "Unfollow updates");
});

test("shared state contains collaboration only and no source lifecycle mutation", () => {
  const state = collaboration.createCollaborationState?.() || {};
  assert.equal(Object.hasOwn(state, "submitCollaborationComment"), true);
  assert.equal(Object.hasOwn(state, "toggleCollaborationFollow"), true);
  assert.equal(Object.hasOwn(state, "submitCollaborationHandoff"), true);
  assert.equal(Object.hasOwn(state, "saveCommentRevision"), true);
  assert.equal(Object.hasOwn(state, "status"), false);
  assert.equal(Object.hasOwn(state, "updatedAt"), false);
});

test("rejects stale mutation completions after source navigation", () => {
  const request = { sequence: 3, key: "decision:one" };
  assert.equal(collaboration.collaborationRequestIsCurrent(request, 3, "decision:one"), true);
  assert.equal(collaboration.collaborationRequestIsCurrent(request, 4, "decision:one"), false);
  assert.equal(collaboration.collaborationRequestIsCurrent(request, 3, "risk:two"), false);
});
