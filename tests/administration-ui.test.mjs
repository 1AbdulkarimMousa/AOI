import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships a dedicated, admin-protected Administration entry", async () => {
  const [page, app, vite] = await Promise.all([
    readFile(new URL("administration.html", root), "utf8"),
    readFile(new URL("src/js/app.js", root), "utf8"),
    readFile(new URL("vite.config.js", root), "utf8"),
  ]);

  assert.match(page, /data-page="administration"/);
  assert.match(page, /data-expected-role="admin"/);
  assert.match(page, /id="administration-app"/);
  assert.match(app, /registerAdministration/);
  assert.match(vite, /administration:\s*resolve/);
});

test("keeps Administration reachable from the shared workspace", async () => {
  const [template, controller] = await Promise.all([
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
  ]);

  assert.match(template, /view==='administration'/);
  assert.match(controller, /workspace\.html.*view=administration/);
  assert.doesNotMatch(controller, /submitUser\(\)/);
});

test("provides people, work, data, archive, and guide workflows", async () => {
  const [template, controller, styles] = await Promise.all([
    readFile(new URL("src/js/administration-template.js", root), "utf8"),
    readFile(new URL("src/js/administration.js", root), "utf8"),
    readFile(new URL("src/css/aoi.css", root), "utf8"),
  ]);

  for (const label of ["Overview", "People", "Work & CRM", "Data", "Archive & Audit", "Guides"]) assert.match(template + controller, new RegExp(label.replace("&", "&amp;|&")));
  assert.match(template, /Add person/);
  assert.match(template, /Import/);
  assert.match(template, /Export/);
  assert.match(template, /Archive person/);
  assert.match(template, /role="dialog"/);
  assert.match(controller, /requireWorkspaceAccess/);
  assert.match(controller, /\['admin', 'intern'\]\.includes\(access\.role\)/);
  assert.match(controller, /acceptanceCriteria/);
  assert.match(controller, /trapDrawerFocus/);
  assert.match(styles, /\.administration-shell/);
  assert.match(styles, /@media \(max-width: 560px\)/);
});

test("adds a role-specific onboarding guide for interns", async () => {
  const template = await readFile(new URL("src/js/workspace-template.js", root), "utf8");
  assert.match(template, /Intern onboarding/);
  assert.match(template, /Secure your account/);
  assert.match(template, /File your EOD brief/);
  assert.match(template, /completeInternOnboarding/);
});

test("supports invite, temporary-password, archive, restore, and session revocation actions", async () => {
  const source = await readFile(new URL("supabase/functions/admin-create-user/index.ts", root), "utf8");

  assert.match(source, /inviteUserByEmail/);
  assert.match(source, /accessMethod/);
  assert.match(source, /rpc_admin_archive_user/);
  assert.match(source, /rpc_admin_restore_user/);
  assert.match(source, /ban_duration/);
  assert.match(source, /complete_password_change/);
  assert.match(source, /cleanupProvisioning/);
  assert.match(source, /action === "import"/);
});

test("creates secure one-time onboarding credentials without a shared fallback", async () => {
  const [source, template, controller] = await Promise.all([
    readFile(new URL("supabase/functions/admin-create-user/index.ts", root), "utf8"),
    readFile(new URL("src/js/administration-template.js", root), "utf8"),
    readFile(new URL("src/js/administration.js", root), "utf8"),
  ]);

  assert.doesNotMatch(source, /123456/);
  assert.match(source, /accessMethod === "temporary_password"\s*\? generateTemporaryPassword\(\)/);
  assert.match(source, /\.\.\.\(accessMethod === "temporary_password" \? \{ temporaryPassword: generatedPassword \} : \{\}\)/);
  assert.match(template, /I saved this one-time password/);
  assert.match(template, /finishPersonCreation/);
  assert.match(controller, /credentialAcknowledged/);
  assert.match(controller, /createdCredential/);
});

test("guards person detail races, includes password setup status, and reconciles partial archives", async () => {
  const [source, template, edge] = await Promise.all([
    readFile(new URL("src/js/administration.js", root), "utf8"),
    readFile(new URL("src/js/administration-template.js", root), "utf8"),
    readFile(new URL("supabase/functions/admin-create-user/index.ts", root), "utf8"),
  ]);

  assert.match(source, /personRequestId/);
  assert.match(source, /requestId !== this\.personRequestId/);
  assert.match(template, /value="password_change_required"/);
  assert.match(edge, /reconciliationRequired:\s*true/);
  assert.match(edge, /reconcile_own_password/);
  assert.match(edge, /banned_until/);
  assert.match(edge, /otherActiveError/);
  assert.match(source, /result\.reconciliationRequired/);
  assert.match(source, /await this\.refresh\(\)/);
});

test("exposes accessible administration tab state", async () => {
  const template = await readFile(new URL("src/js/administration-template.js", root), "utf8");

  assert.match(template, /class="administration-tabs"[^>]*role="tablist"/);
  assert.match(template, /role="tab"[^>]*:aria-selected="section===item\.id"/);
  assert.match(template, /class="admin-person-tabs"/);
  assert.match(await readFile(new URL("src/js/administration.js", root), "utf8"), /apply\("\.admin-person-tabs"/);
});

test("activates invitations and blocks temporary-password users until they choose a new password", async () => {
  const [auth, login, page] = await Promise.all([
    readFile(new URL("src/js/auth.js", root), "utf8"),
    readFile(new URL("src/js/login.js", root), "utf8"),
    readFile(new URL("login.html", root), "utf8"),
  ]);

  assert.doesNotMatch(auth, /rpc_accept_invitation/);
  assert.match(auth, /completePasswordChange\(password,\s*"",\s*passwordCallback\)/);
  assert.match(auth, /complete_password_change/);
  assert.match(login, /mustChangePassword/);
  assert.match(page, /Choose a new password/);
  assert.match(auth, /complete_password_change/);
});
