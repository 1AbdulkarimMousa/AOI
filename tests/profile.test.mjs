import assert from "node:assert/strict";
import test from "node:test";

const profile = await import("../src/js/profile.js").catch(() => ({}));

test("validates and normalizes editable work profile fields", () => {
  assert.equal(typeof profile.validateProfile, "function");
  const result = profile.validateProfile({
    displayName: "  Kayla Tillmon ",
    jobTitle: " Research Intern ",
    bio: " Evidence operations ",
    phone: " +1 555 0100 ",
    timezone: "America/New_York",
    locale: "en",
    avatarKey: "coral",
  });

  assert.equal(result.valid, true);
  assert.equal(result.value.displayName, "Kayla Tillmon");
  assert.equal(result.value.jobTitle, "Research Intern");
  assert.equal(result.value.bio, "Evidence operations");
});

test("rejects invalid names, bios, timezones, locales, and preset avatars", () => {
  assert.equal(typeof profile.validateProfile, "function");
  assert.equal(profile.validateProfile({ displayName: "A", timezone: "UTC", locale: "en", avatarKey: "coral" }).valid, false);
  assert.equal(profile.validateProfile({ displayName: "Valid Name", bio: "x".repeat(241), timezone: "UTC", locale: "en", avatarKey: "coral" }).valid, false);
  assert.equal(profile.validateProfile({ displayName: "Valid Name", timezone: "Not/AZone", locale: "en", avatarKey: "coral" }).valid, false);
  assert.equal(profile.validateProfile({ displayName: "Valid Name", timezone: "UTC", locale: "fr", avatarKey: "coral" }).valid, false);
  assert.equal(profile.validateProfile({ displayName: "Valid Name", timezone: "UTC", locale: "en", avatarKey: "unknown" }).valid, false);
});

test("resolves photos, presets, and initials in priority order", () => {
  assert.equal(typeof profile.resolveAvatar, "function");
  assert.deepEqual(profile.resolveAvatar({ displayName: "Kayla Tillmon", avatarUrl: "https://example.test/a.png", avatarKey: "teal" }), { kind: "photo", value: "https://example.test/a.png" });
  assert.deepEqual(profile.resolveAvatar({ displayName: "Kayla Tillmon", avatarKey: "teal" }), { kind: "preset", value: "teal" });
  assert.deepEqual(profile.resolveAvatar({ displayName: "Kayla Tillmon" }), { kind: "initials", value: "KT" });
});

test("accepts only small JPEG, PNG, and WebP profile photos", () => {
  assert.equal(typeof profile.validateAvatarFile, "function");
  assert.deepEqual(profile.validateAvatarFile({ name: "kayla.webp", type: "image/webp", size: 1024 }), { valid: true });
  assert.equal(profile.validateAvatarFile({ name: "kayla.gif", type: "image/gif", size: 1024 }).valid, false);
  assert.equal(profile.validateAvatarFile({ name: "kayla.png", type: "image/png", size: 3 * 1024 * 1024 + 1 }).valid, false);
});

test("reconciles ambiguous avatar profile updates before cleanup", async () => {
  assert.equal(typeof profile.reconcileUploadedAvatar, "function");
  const saved = { userId: "user-1", avatarPath: "org/user-1/avatar.webp" };

  assert.deepEqual(
    await profile.reconcileUploadedAvatar(saved.avatarPath, saved.userId, async () => saved),
    { resolved: true, profile: saved },
  );
  assert.deepEqual(
    await profile.reconcileUploadedAvatar(saved.avatarPath, saved.userId, async () => ({ ...saved, avatarPath: "org/user-1/old.webp" })),
    { resolved: true, profile: null },
  );
  assert.deepEqual(
    await profile.reconcileUploadedAvatar(saved.avatarPath, saved.userId, async () => { throw new Error("offline"); }),
    { resolved: false, profile: null },
  );
});
