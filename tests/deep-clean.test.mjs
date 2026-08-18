import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("removes unreachable legacy workspace surfaces and their controller state", async () => {
  const [template, workspace, styles] = await Promise.all([
    source("src/js/workspace-template.js"),
    source("src/js/workspace.js"),
    source("src/css/aoi.css"),
  ]);

  for (const value of ["legacy-research", "legacy-pmf", "eod-report-entry", "openPmfLayer", "selectedLayer", "samplePercent", "overallSample"]) {
    assert.doesNotMatch(`${template}\n${workspace}\n${styles}`, new RegExp(`\\b${value}\\b`));
  }
  assert.doesNotMatch(template, /\.replace\("@keydown\.window\.escape/);
});

test("removes declaration-only browser APIs and compatibility helpers", async () => {
  const [api, workspace, administration, participantTracker, surveyWorkspace, crm, dailyEod, loginFlow] = await Promise.all([
    source("src/js/api.js"),
    source("src/js/workspace.js"),
    source("src/js/administration.js"),
    source("src/js/participant-tracker.js"),
    source("src/js/surveys/workspace.js"),
    source("src/js/crm.js"),
    source("src/js/daily-eod.js"),
    source("src/js/login-flow.js"),
  ]);

  for (const name of ["queueEmail", "listAdminUsers", "loadCollectSnapshot", "loadGamificationSummary", "reorderHelpArticles"]) {
    assert.doesNotMatch(api, new RegExp(`\\b${name}\\b`));
  }
  for (const name of ["helpCenterUrl", "progressTone", "focusTasks", "candidateStats", "crmContactActivities"]) {
    assert.doesNotMatch(workspace, new RegExp(`\\b${name}\\b`));
  }
  assert.doesNotMatch(administration, /\bworkspaceUrl\b/);
  assert.doesNotMatch(participantTracker, /\bquickStatus\b/);
  assert.doesNotMatch(surveyWorkspace, /\bsurveyPreviewSectionIndex\b|\bsurveyValueBreakdown\b/);
  assert.doesNotMatch(crm, /\bCRM_LIFECYCLES\b|\bresolveCrmWorkspaceRoute\b/);
  assert.doesNotMatch(dailyEod, /\bvalidateDailyEodBrief\b/);
  assert.doesNotMatch(loginFlow, /\bisPasswordRecoveryUrl\b/);
});

test("keeps module-private helpers out of the exported surface", async () => {
  const modules = await Promise.all([
    source("src/js/auth.js"),
    source("src/js/chat.js"),
    source("src/js/pmf.js"),
    source("src/js/profile.js"),
    source("src/js/participant-tracker.js"),
    source("src/js/surveys/workspace.js"),
    source("scripts/intern-seed-data.mjs"),
    source("scripts/mike-outreach-seed-data.mjs"),
  ]);
  const combined = modules.join("\n");
  for (const name of ["WorkspaceMembershipError", "getSession", "completePasswordChange", "REACTION_EMOJI", "PMF_LAYERS", "AVATAR_KEYS", "allowedRecruitmentTransitions", "SURVEY_QUESTION_TYPES", "WEN_EOD_BRIEFS", "MIKE_OUTREACH_DATE"]) {
    const exported = new RegExp(`\\bexport\\s+(?:(?:async\\s+)?function|class|(?:const|let|var))\\s+${name}\\b|\\bexport\\s*\\{[^}]*\\b${name}\\b[^}]*\\}`);
    assert.doesNotMatch(combined, exported);
  }
});

test("removes obsolete starter assets and retired stack ignores", async () => {
  const [gitignore, readme] = await Promise.all([source(".gitignore"), source("README.md")]);
  for (const path of ["public/file.svg", "public/globe.svg", "public/window.svg", "public/og.png"]) {
    await assert.rejects(access(new URL(path, root)), { code: "ENOENT" });
  }
  assert.doesNotMatch(gitignore, /^\/\.pnp$|^\.pnp\.\*$|^\.yarn\/|^\/\.next\/$|^\/\.vinext\/$|^\/out\/$|^\.vercel$|^\/\.wrangler\/$/m);
  assert.match(readme, /embedded Administration workspace destination/i);
});
