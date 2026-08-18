import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const flow = await import("../src/js/login-flow.js").catch(() => null);
const auth = await readFile(new URL("../src/js/auth.js", import.meta.url), "utf8");
const login = await readFile(new URL("../src/js/login.js", import.meta.url), "utf8");
const loginHtml = await readFile(new URL("../login.html", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20260805150000_repair_password_reset_flow.sql", import.meta.url), "utf8").catch(() => "");
const edge = await readFile(new URL("../supabase/functions/admin-create-user/index.ts", import.meta.url), "utf8");

test("recognizes Supabase recovery callbacks in query strings and URL fragments", () => {
  assert.ok(flow, "Login flow helpers must exist");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html#access_token=x&type=recovery"), "recovery");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html?type=recovery"), "recovery");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html#access_token=x&type=signup"), "signup");
});

test("keeps invite and signup callbacks in password establishment", () => {
  assert.ok(flow, "Login flow helpers must exist");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html#access_token=x&type=recovery"), "recovery");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html#access_token=x&type=invite"), "invite");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html?type=signup"), "signup");
  assert.equal(flow.passwordEstablishmentType("https://example.test/login.html#type=magiclink"), null);
});

test("activates invitations only through verified password completion", () => {
  assert.match(auth, /completePasswordChange\(password,\s*"",\s*passwordCallback\)/);
  assert.match(edge, /must_change_password:\s*true/);
  assert.match(edge, /profile\?\.status === "invited"[\s\S]*profile\.must_change_password === true/);
  assert.doesNotMatch(auth, /client\.rpc\("rpc_accept_invitation"\)/);
});

test("login exposes both recovery email and password completion paths", () => {
  assert.match(auth, /resetPasswordForEmail/);
  assert.match(auth, /return await requireWorkspaceAccess\(\)/);
  assert.match(login, /requestPasswordReset/);
  assert.match(login, /passwordEstablishmentType/);
  assert.match(login, /changePassword\(this\.newPassword, this\.currentPassword, this\.passwordCallback\)/);
});

test("owned login UI states the complete 14-character password policy", () => {
  assert.doesNotMatch(loginHtml, /minlength="12"|12 characters/);
  assert.match(loginHtml, /minlength="14"/);
  assert.match(loginHtml, /14 characters[^<]*(uppercase|upper case)[^<]*lowercase[^<]*digit[^<]*symbol/i);
});

test("password completion repairs legacy active temporary accounts", () => {
  assert.match(migration, /membership\.status in \('active', 'password_change_required'\)/i);
  assert.match(migration, /profile\.status in \('active', 'password_change_required'\)/i);
  assert.match(migration, /must_change_password = false/i);
  assert.match(migration, /status = 'password_change_required'/i);
});
