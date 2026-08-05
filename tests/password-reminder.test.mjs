import assert from "node:assert/strict";
import test from "node:test";

const reminder = await import("../src/js/password-reminder.js").catch(() => null);

test("shows a password reminder immediately until the user changes or snoozes it", () => {
  assert.ok(reminder, "Password reminder helper must exist");
  const now = new Date("2026-08-05T12:00:00.000Z");
  assert.equal(reminder.shouldShowPasswordReminder({ seeded: true, now }), true);
  assert.equal(reminder.shouldShowPasswordReminder({ seeded: false, now }), false);
  assert.equal(reminder.shouldShowPasswordReminder({ seeded: true, changedAt: now.toISOString(), now }), false);
  assert.equal(reminder.shouldShowPasswordReminder({ seeded: true, snoozedUntil: "2026-08-06T12:00:00.000Z", now }), false);
  assert.equal(reminder.shouldShowPasswordReminder({ seeded: true, snoozedUntil: "2026-08-04T12:00:00.000Z", now }), true);
});

test("calculates a seven-day reminder snooze and validates replacement passwords", () => {
  assert.ok(reminder, "Password reminder helper must exist");
  const now = new Date("2026-08-05T12:00:00.000Z");
  assert.equal(reminder.snoozeUntil(now).toISOString(), "2026-08-12T12:00:00.000Z");
  assert.equal(reminder.isStrongPassword("123456"), false);
  assert.equal(reminder.isStrongPassword("a-longer-password-123"), true);
});
