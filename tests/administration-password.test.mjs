import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const passwordModule = await import("../src/js/administration-password.js").catch(() => null);

test("creates separate self-change and reset password drafts", () => {
  assert.ok(passwordModule, "Administration password helpers must exist");
  assert.deepEqual(passwordModule.createSelfPasswordDraft(), {
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
    showPasswords: false,
  });
  assert.deepEqual(passwordModule.createResetPasswordDraft(), {
    mode: "generated",
    temporaryPassword: "",
    confirmPassword: "",
    reason: "",
    showPasswords: false,
  });
});

test("validates self password changes before calling Auth", () => {
  assert.ok(passwordModule, "Administration password helpers must exist");
  assert.deepEqual(passwordModule.validateSelfPasswordChange({
    currentPassword: "",
    newPassword: "short",
    confirmPassword: "different",
  }), [
    "Enter your current password.",
    "New passwords must contain at least 14 characters with upper/lower case, a digit, and a symbol.",
    "New password confirmation does not match.",
  ]);
  assert.deepEqual(passwordModule.validateSelfPasswordChange({
    currentPassword: "ExistingPass123!",
    newPassword: "ExistingPass123!",
    confirmPassword: "ExistingPass123!",
  }), [
    "Choose a new password that differs from your current password.",
  ]);
  assert.deepEqual(passwordModule.validateSelfPasswordChange({
    currentPassword: "ExistingPass12345!",
    newPassword: "Replacement-Pass456!",
    confirmPassword: "Replacement-Pass456!",
  }), []);
});

test("validates generated and custom resets", () => {
  assert.ok(passwordModule, "Administration password helpers must exist");
  assert.deepEqual(passwordModule.validatePasswordReset({ mode: "generated", reason: "" }), ["Record why this password is being reset."]);
  assert.deepEqual(passwordModule.validatePasswordReset({
    mode: "custom",
    temporaryPassword: "short",
    confirmPassword: "different",
    reason: "Requested by user",
  }), [
    "Temporary passwords must contain at least 14 characters with upper/lower case, a digit, and a symbol.",
    "Temporary password confirmation does not match.",
  ]);
  assert.deepEqual(passwordModule.validatePasswordReset({ mode: "generated", reason: "Requested by user" }), []);
});

test("wires password management into the Administration drawer", async () => {
  const [template, controller, api, styles] = await Promise.all([
    readFile(new URL("src/js/administration-template.js", root), "utf8"),
    readFile(new URL("src/js/administration.js", root), "utf8"),
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/css/aoi.css", root), "utf8"),
  ]);

  assert.match(template, /Password & access/);
  assert.match(template, /Change my password/);
  assert.match(template, /Reset password/);
  assert.match(template, /Generate secure password/);
  assert.match(template, /Use custom temporary password/);
  assert.match(template, /autocomplete="current-password"/);
  assert.match(template, /autocomplete="new-password"/);
  assert.match(template, /password_change_required/);
  assert.match(template, /aria-pressed/);
  assert.match(controller, /changeOwnPassword/);
  assert.match(controller, /resetUserPassword/);
  assert.match(controller, /resetPasswordResult/);
  assert.match(controller, /profileStatus === "active"/);
  assert.match(controller, /Preview mode/);
  assert.match(api, /change_own_password/);
  assert.match(api, /reset_user_password/);
  assert.match(styles, /\.admin-security-section/);
  assert.match(styles, /@media \(max-width: 560px\)/);
  assert.doesNotMatch(styles, /\.admin-password-toggle[^}]*display:\s*flex\s*!important/);
});

test("secures self changes and administrator resets in the Edge Function", async () => {
  const [source, migration] = await Promise.all([
    readFile(new URL("supabase/functions/admin-create-user/index.ts", root), "utf8"),
    readFile(new URL("supabase/migrations/20260805151000_administration_password_management.sql", root), "utf8"),
  ]);

  assert.match(source, /change_own_password/);
  assert.match(source, /reset_user_password/);
  assert.match(source, /signInWithPassword/);
  assert.match(source, /crypto\.getRandomValues/);
  assert.match(source, /generatedPassword/);
  assert.match(source, /password\.length < 14/);
  assert.match(source, /isStrongPassword/);
  assert.match(source, /rpc_admin_prepare_password_reset/);
  assert.match(source, /rpc_admin_restore_password_state/);
  assert.match(source, /recoverySession/);
  assert.match(source, /currentPassword === password/);
  assert.match(migration, /password_changed_self/);
  assert.match(migration, /password_reset_by_admin/);
  assert.doesNotMatch(source, /metadata[^\n]*(currentPassword|newPassword|temporaryPassword|generatedPassword|password)/);
});

test("keeps password-state helpers private and service-role only", async () => {
  const sql = await readFile(new URL("supabase/migrations/20260805151000_administration_password_management.sql", root), "utf8");

  assert.match(sql, /create or replace function private\.admin_prepare_password_reset/i);
  assert.match(sql, /create or replace function private\.admin_restore_password_state/i);
  assert.match(sql, /create or replace function private\.admin_complete_self_password_change/i);
  assert.match(sql, /password_change_required/i);
  assert.match(sql, /insert into public\.audit_events/i);
  assert.match(sql, /grant usage on schema private to service_role/i);
  assert.match(sql, /revoke all on function private\./i);
  assert.match(sql, /grant execute on function private\.[\s\S]*to service_role/i);
  assert.doesNotMatch(sql, /grant execute on function private\.[\s\S]*to authenticated/i);
});

test("blocks every active organization until a reset password is replaced", async () => {
  const [hardening, finalHardening, timestampMigration, authSource, loginSource, repair] = await Promise.all([
    readFile(new URL("supabase/migrations/20260805152000_harden_administration_password_resets.sql", root), "utf8"),
    readFile(new URL("supabase/migrations/20260805153000_close_password_reset_state_bypasses.sql", root), "utf8"),
    readFile(new URL("supabase/migrations/20260805154000_record_password_change_timestamp.sql", root), "utf8"),
    readFile(new URL("src/js/auth.js", root), "utf8"),
    readFile(new URL("src/js/login.js", root), "utf8"),
    readFile(new URL("supabase/migrations/20260805150000_repair_password_reset_flow.sql", root), "utf8"),
  ]);
  const sql = `${hardening}\n${finalHardening}\n${timestampMigration}`;

  assert.match(sql, /is_owner[\s\S]*status in \('active', 'password_change_required'\)/i);
  assert.match(sql, /membershipStatuses/i);
  assert.match(sql, /jsonb_each_text/i);
  assert.match(sql, /where user_id = p_target_user_id and status = 'active'/i);
  assert.match(sql, /where user_id = v_user_id and status = 'password_change_required'/i);
  assert.match(sql, /create or replace function public\.rpc_mark_password_changed/i);
  assert.match(sql, /create or replace function public\.rpc_complete_password_change/i);
  assert.match(sql, /revoke all on function public\.rpc_mark_password_changed\(\) from public, anon, authenticated/i);
  assert.doesNotMatch(sql, /grant execute on function public\.rpc_mark_password_changed\(\) to authenticated/i);
  assert.match(sql, /PASSWORD_RESET_STATE_CHANGED/i);
  assert.match(sql, /status = 'password_change_required' and must_change_password/i);
  assert.doesNotMatch(authSource, /rpc_mark_password_changed/);
  assert.match(authSource, /mustChangePassword[\s\S]*completePasswordChange/);
  assert.match(authSource, /rpc_record_password_changed_at/);
  assert.match(loginSource, /currentPassword/);
  assert.match(sql, /create or replace function public\.rpc_record_password_changed_at/i);
  assert.match(sql, /where id = \(select auth\.uid\(\)\)[\s\S]*not must_change_password/i);
  assert.ok(repair.indexOf("organization_memberships_owner_check") < repair.indexOf("update public.profiles"));
});
