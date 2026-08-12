import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { resolveWorkspaceRoute } from "../src/js/crm.js";

const root = new URL("../", import.meta.url);

test("canonicalizes project tabs and stable record parameters", () => {
  const cases = [
    ["overview", {}, { projectTab: "overview", projectRecordType: null, projectRecordId: null, normalize: false }],
    ["milestones", { milestone: "m-1" }, { projectTab: "milestones", projectRecordType: "milestone", projectRecordId: "m-1", normalize: false }],
    ["blockers", { blocker: "b-1" }, { projectTab: "blockers", projectRecordType: "blocker", projectRecordId: "b-1", normalize: false }],
    ["risks", { risk: "r-1" }, { projectTab: "risks", projectRecordType: "risk", projectRecordId: "r-1", normalize: false }],
    ["decisions", { decision: "d-1" }, { projectTab: "decisions", projectRecordType: "decision", projectRecordId: "d-1", normalize: false }],
  ];
  for (const [tab, recordParams, expected] of cases) {
    const route = resolveWorkspaceRoute({ view: "projects", tab, project: "p-1", ...recordParams });
    assert.equal(route.view, "projects");
    assert.equal(route.projectId, "p-1");
    for (const [key, value] of Object.entries(expected)) assert.equal(route[key], value, `${tab}:${key}`);
  }

  const invalid = resolveWorkspaceRoute({ view: "projects", tab: "unknown", project: "p-1", milestone: "m-1", decision: "d-1" });
  assert.equal(invalid.projectTab, "overview");
  assert.equal(invalid.projectRecordId, null);
  assert.equal(invalid.normalize, true);
});

test("wires exact project RPC names and parameters", async () => {
  const api = await readFile(new URL("src/js/api.js", root), "utf8");
  assert.match(api, /loadProjectContext\(\)[\s\S]*rpc\("rpc_aoi_project_context"\)/);
  assert.match(api, /selectProjectContext\(projectId\)[\s\S]*rpc\("rpc_aoi_select_project",\s*\{ p_project_id: projectId \}\)/);
  assert.match(api, /loadProjectSnapshot\(projectId\)[\s\S]*rpc\("rpc_aoi_project_snapshot",\s*\{ p_project_id: projectId \}\)/);
  assert.match(api, /loadProjectRecordDetail\(recordType, recordId\)[\s\S]*p_record_type: recordType[\s\S]*p_record_id: recordId/);
  assert.match(api, /saveProjectRecord\(recordType, payload, recordId = null, expectedUpdatedAt = null, clientNonce = null\)[\s\S]*rpc\("rpc_aoi_save_project_record"[\s\S]*p_client_nonce: clientNonce/);
  assert.match(api, /transitionProjectRecord\(recordType, recordId, action, note, expectedUpdatedAt, clientNonce = null\)[\s\S]*rpc\("rpc_aoi_transition_project_record"[\s\S]*p_client_nonce: clientNonce/);
  assert.match(api, /adminSaveProject\(payload, projectId = null, expectedUpdatedAt = null\)[\s\S]*rpc\("rpc_aoi_admin_save_project"[\s\S]*p_payload: payload[\s\S]*p_project_id: projectId/);
  assert.match(api, /setProjectMember\(projectId, userId, active, responsibility, expectedUpdatedAt = null\)[\s\S]*rpc\("rpc_aoi_admin_set_project_member"[\s\S]*p_responsibility: responsibility/);
  assert.match(api, /transitionProject\(projectId, action, note, expectedUpdatedAt\)[\s\S]*rpc\("rpc_aoi_transition_project"[\s\S]*p_action: action/);
});

test("workspace loads and switches project context independently from dashboard", async () => {
  const [workspace, template, projectsTemplate, inbox] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/projects-template.js", root), "utf8"),
    readFile(new URL("src/js/inbox-template.js", root), "utf8"),
  ]);

  assert.match(workspace, /projectContext/);
  assert.match(workspace, /refreshProjectContext/);
  assert.match(workspace, /refreshProjectSnapshot/);
  assert.match(workspace, /confirmProjectSwitch/);
  assert.match(workspace, /projectDirty/);
  assert.match(workspace, /projectConflictDraft/);
  assert.match(workspace, /onProjectSwitcherChange/);
  assert.match(workspace, /reloadStaleProjectRecord\(\)[\s\S]*projectConflictDraft[\s\S]*loadProjectRecordDetail[\s\S]*projectRecordDraft = localDraft/);
  assert.match(workspace, /selectProjectContext/);
  assert.match(workspace, /selectProjectContext\(projectId\)[\s\S]*projectContext = mergeProjectSelection[\s\S]*Project selected[\s\S]*reconciliation/i);
  assert.doesNotMatch(workspace, /The project could not be selected/);
  const refreshInbox = workspace.slice(workspace.indexOf("async refreshInbox("), workspace.indexOf("async setInboxBucket("));
  assert.match(refreshInbox, /return true;/);
  assert.match(refreshInbox, /catch \(reason\)[\s\S]*return false;/);
  assert.match(workspace, /openInboxSource\(item\)[\s\S]*projectSourceTypes/);
  assert.match(workspace, /projectReturnFocus/);
  assert.match(workspace, /scopePreviewProject/);
  assert.match(template, /projectsTemplate/);
  assert.match(projectsTemplate, /aria-label="Project sections"/);
  assert.match(projectsTemplate, /aria-controls="project-panel-overview"/);
  assert.match(projectsTemplate, /id="project-panel-overview"[\s\S]*role="tabpanel"/);
  assert.match(projectsTemplate, /:tabindex="projectTab==='overview'\?0:-1"/);
  assert.match(projectsTemplate, /@keydown="onProjectTabKeydown/);
  assert.match(template, /<select[^>]+projectSwitcherValue/);
  assert.match(template, /onProjectSwitcherChange/);
  assert.match(workspace, /\{ id: "projects", label: "Projects" \}/);
  assert.match(inbox, /projectSourceLabel/);
});

test("project workspace uses selected-context permissions and real inline administration", async () => {
  const [workspace, template] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/projects-template.js", root), "utf8"),
  ]);
  assert.match(workspace, /get activeProjectRole\(\)/);
  assert.match(workspace, /get activeProjectIsOwner\(\)/);
  assert.match(workspace, /activeProjectAccess\(this\.projectContext/);
  assert.match(workspace, /syncAccessToProjectContext/);
  assert.match(template, /activeProjectRole==='admin'/);
  assert.doesNotMatch(template, /access\.role==='admin'/);
  assert.match(template, /projectAdminMode/);
  assert.match(template, /saveAdminProject/);
  assert.match(template, /saveProjectMember/);
  assert.match(template, /transitionActiveProject/);
  assert.match(template, /Project membership/);
  assert.doesNotMatch(workspace, /Project configuration is read-only|Project creation requires/);
});

test("project details expose loading, unavailable, dirty-exit, supersession, and complete snapshot contracts", async () => {
  const [workspace, template] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/projects-template.js", root), "utf8"),
  ]);
  assert.match(workspace, /projectDetailLoading/);
  assert.match(template, /:disabled="projectDetailLoading \|\| !canEditSelectedProjectRecord"/);
  assert.match(template, /@keydown\.escape\.stop="requestCloseProjectRecord\(\)"/);
  assert.match(template, /requestCloseProjectRecord\(\)/);
  assert.match(workspace, /async requestCloseProjectRecord/);
  assert.match(workspace, /projectUnavailable/);
  assert.match(workspace, /normalizeUnavailableProjectRoute/);
  assert.match(template, /Record unavailable/);
  assert.match(template, /Replacement approved decision ID/);
  assert.match(workspace, /projectSupersedeDecisionId/);
  for (const field of ["Decision statement", "Alternatives", "Rationale", "Expected impact", "Snapshot evidence", "Provenance", "Limitations"]) assert.match(template, new RegExp(field));
});

test("project context retry and dashboard consistency follow the selected context contract", async () => {
  const [workspace, template, api] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/projects-template.js", root), "utf8"),
    readFile(new URL("src/js/api.js", root), "utf8"),
  ]);
  assert.match(template, /projectSwitcherValue\s*\?\s*refreshProjectSnapshot\(\)\s*:\s*refreshProjectContext\(\)/);
  assert.match(api, /export async function loadDashboard\(\)/);
  assert.doesNotMatch(api, /loadDashboard\([^)]/);
  assert.match(workspace, /access[\s\S]*organizationName[\s\S]*activeProjectRole/);
});

test("project CSS provides restrained desktop and 390/320 mobile contracts", async () => {
  const css = await readFile(new URL("src/css/aoi.css", root), "utf8");
  assert.match(css, /\.project-workspace/);
  assert.match(css, /\.project-register-detail\s*{[\s\S]*grid-template-columns:/);
  assert.match(css, /\.project-detail-pane/);
  assert.match(css, /\.project-register-row[\s\S]*min-height:\s*44px/);
  assert.match(css, /:root\[data-theme="dark"\][\s\S]*\.project-/);
  assert.match(css, /@media \(max-width:\s*390px\)[\s\S]*\.project-register-detail/);
  assert.match(css, /@media \(max-width:\s*320px\)[\s\S]*\.project-/);
  const projectCss = css.match(/\/\* Project operating core \*\/[\s\S]*?\/\* Public landing page \*\//)?.[0] || "";
  assert.doesNotMatch(projectCss, /linear-gradient|radial-gradient|backdrop-filter|border-(?:left|right):\s*[2-9]px/);
});
