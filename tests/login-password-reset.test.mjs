import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const flow = await import("../src/js/login-flow.js").catch(() => null);
const auth = await readFile(new URL("../src/js/auth.js", import.meta.url), "utf8");
const login = await readFile(new URL("../src/js/login.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20260805150000_repair_password_reset_flow.sql", import.meta.url), "utf8").catch(() => "");

test("recognizes Supabase recovery callbacks in query strings and URL fragments", () => {
  assert.ok(flow, "Login flow helpers must exist");
  assert.equal(flow.isPasswordRecoveryUrl("https://example.test/login.html#access_token=x&type=recovery"), true);
  assert.equal(flow.isPasswordRecoveryUrl("https://example.test/login.html?type=recovery"), true);
  assert.equal(flow.isPasswordRecoveryUrl("https://example.test/login.html#access_token=x&type=signup"), false);
});

test("login exposes both recovery email and password completion paths", () => {
  assert.match(auth, /resetPasswordForEmail/);
  assert.match(auth, /return await requireWorkspaceAccess\(\)/);
  assert.match(login, /requestPasswordReset/);
  assert.match(login, /isPasswordRecoveryUrl/);
});

test("password completion repairs legacy active temporary accounts", () => {
  assert.match(migration, /membership\.status in \('active', 'password_change_required'\)/i);
  assert.match(migration, /profile\.status in \('active', 'password_change_required'\)/i);
  assert.match(migration, /must_change_password = false/i);
  assert.match(migration, /status = 'password_change_required'/i);
});
