import assert from "node:assert/strict";
import test from "node:test";

const chat = await import("../src/js/chat.js").catch(() => ({}));

test("merges paginated and realtime messages without duplicates", () => {
  assert.equal(typeof chat.mergeMessages, "function");
  const current = [
    { id: "m2", createdAt: "2026-08-04T10:02:00.000Z", body: "Second" },
    { id: "m3", createdAt: "2026-08-04T10:03:00.000Z", body: "Third" },
  ];
  const incoming = [
    { id: "m1", createdAt: "2026-08-04T10:01:00.000Z", body: "First" },
    { id: "m2", createdAt: "2026-08-04T10:02:00.000Z", body: "Second, edited", editedAt: "2026-08-04T10:04:00.000Z" },
  ];

  assert.deepEqual(chat.mergeMessages(current, incoming).map((message) => [message.id, message.body]), [
    ["m1", "First"],
    ["m2", "Second, edited"],
    ["m3", "Third"],
  ]);
});

test("validates useful text while rejecting empty and oversized messages", () => {
  assert.equal(typeof chat.validateMessage, "function");
  assert.deepEqual(chat.validateMessage("  status updated  "), { valid: true, body: "status updated" });
  assert.equal(chat.validateMessage("   ").valid, false);
  assert.equal(chat.validateMessage("x".repeat(4001)).valid, false);
});

test("accepts safe chat files and rejects executables and oversized files", () => {
  assert.equal(typeof chat.validateChatFile, "function");
  assert.deepEqual(chat.validateChatFile({ name: "brief.pdf", type: "application/pdf", size: 1024 }), { valid: true });
  assert.equal(chat.validateChatFile({ name: "payload.exe", type: "application/octet-stream", size: 1024 }).valid, false);
  assert.equal(chat.validateChatFile({ name: "large.png", type: "image/png", size: 10 * 1024 * 1024 + 1 }).valid, false);
});

test("computes durable unread totals and excludes muted conversations", () => {
  assert.equal(typeof chat.totalUnread, "function");
  assert.equal(chat.totalUnread([
    { unreadCount: 3, muted: false },
    { unreadCount: 7, muted: true },
    { unreadCount: 2, muted: false },
  ]), 5);
});

test("clears unread state only after persistence succeeds", async () => {
  assert.equal(typeof chat.persistReadState, "function");
  const conversations = [
    { id: "team", unreadCount: 3 },
    { id: "direct", unreadCount: 2 },
  ];
  const calls = [];
  const updated = await chat.persistReadState(conversations, "team", "message-3", async (...args) => calls.push(args));

  assert.deepEqual(calls, [["team", "message-3"]]);
  assert.deepEqual(updated.map(({ id, unreadCount }) => [id, unreadCount]), [["team", 0], ["direct", 2]]);
  await assert.rejects(
    chat.persistReadState(conversations, "team", "message-3", async () => { throw new Error("offline"); }),
    /offline/,
  );
  assert.equal(conversations[0].unreadCount, 3);
});

test("builds synthetic preview chat for both workspace roles", () => {
  assert.equal(typeof chat.previewChat, "function");
  const preview = chat.previewChat("preview-admin", "AOI Administrator");
  assert.equal(preview.conversations[0].kind, "team");
  assert.ok(preview.conversations.some((conversation) => conversation.kind === "direct"));
  assert.ok(preview.messages[preview.conversations[0].id].length >= 2);
});
