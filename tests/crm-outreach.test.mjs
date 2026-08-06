import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("consolidates the complete Outreach suite under Relationships", async () => {
  const [crmTemplate, outreachTemplate, importTemplate, workspace, workspaceTemplate] = await Promise.all([
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
    readFile(new URL("src/js/outreach-template.js", root), "utf8").catch(() => ""),
    readFile(new URL("src/js/import-template.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
  ]);

  assert.match(crmTemplate, />Contacts<\/button>/);
  assert.match(crmTemplate, />Recruitment<\/button>/);
  assert.match(crmTemplate, />Outreach<\/button>/);
  assert.match(crmTemplate, /outreachTemplate/);
  assert.match(crmTemplate, /role="tablist"/);
  assert.match(crmTemplate, /role="tab"/);
  assert.match(crmTemplate, /:aria-selected="relationshipsTab==='outreach'"/);

  assert.match(outreachTemplate, /setOutreachSection\('pipeline'\)/);
  assert.match(outreachTemplate, /setOutreachSection\('evidence'\)/);
  assert.match(outreachTemplate, /setOutreachSection\('imports'\)/);
  assert.match(outreachTemplate, /KOL outreach command center/);
  assert.match(outreachTemplate, /Candidate pipeline/);
  assert.match(outreachTemplate, /Evidence & consent ledger/);
  assert.match(outreachTemplate, /Data portability/);
  assert.match(outreachTemplate, /commitImport\(\)/);
  assert.match(outreachTemplate, /exportCandidates\('csv'\)/);
  assert.match(outreachTemplate, /workbookImportTemplate/);

  assert.doesNotMatch(workspace, /\{ id: "(?:outreach|evidence|imports)"/);
  assert.doesNotMatch(workspaceTemplate, /view==='(?:outreach|evidence|imports)'/);
  assert.doesNotMatch(workspaceTemplate, /workbookImportTemplate/);
  assert.doesNotMatch(importTemplate, /view==='imports'/);
  assert.match(workspaceTemplate, /candidateEditorOpen/);
});

test("opens candidate and evidence actions in Relationships Outreach Pipeline", async () => {
  const [workspace, outreachTemplate] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/outreach-template.js", root), "utf8").catch(() => ""),
  ]);

  assert.match(workspace, /startNewCandidate\(\)[\s\S]*setOutreachSection\("pipeline"\)/);
  assert.match(outreachTemplate, /@click="setOutreachSection\('pipeline'\)"/);
  assert.match(workspace, /setOutreachSection\(section\)/);
  assert.match(workspace, /setView\(view\)[\s\S]*resolveWorkspaceRoute/);
});

test("mounts Recruitment on demand and preserves it after tab changes", async () => {
  const [crmTemplate, workspace] = await Promise.all([
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
  ]);

  assert.match(crmTemplate, /<template x-if="recruitmentMounted">/);
  assert.match(crmTemplate, /<section x-show="relationshipsTab==='recruitment'"/);
  assert.match(workspace, /recruitmentMounted:\s*false/);
  assert.match(workspace, /route\.relationshipsTab === "recruitment"/);
});
