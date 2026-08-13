import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("wires the daily EOD RPCs through the browser API", async () => {
  const api = await readFile(new URL("src/js/api.js", root), "utf8");

  assert.match(api, /rpc\("rpc_aoi_daily_eod_snapshot"\)/);
  assert.match(api, /rpc\("rpc_aoi_save_daily_eod_brief"/);
  assert.match(api, /rpc\("rpc_aoi_admin_update_daily_eod_brief"/);
  assert.match(api, /rpc\("rpc_aoi_daily_eod_reports"/);
});

test("ships the complete shared EOD form and administrator oversight", async () => {
  const [controller, shell, template] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/daily-eod-template.js", root), "utf8"),
  ]);

  assert.match(shell, /dailyEodTemplate/);
  assert.match(shell, /End-of-Day Brief/);
  assert.match(controller, /createDailyEodDraft/);
  assert.match(controller, /saveDailyEod/);
  assert.match(controller, /adminCompleteDailyEod/);
  assert.match(controller, /searchDailyEodReports/);
  assert.match(controller, /formatDailyEodTimestamp\(value, this\.locale, this\.dailyEod\.timezone/);
  assert.match(controller, /formatDailyEodTimestamp\(value\)\s*\{/);
  assert.match(controller, /scheduleDailyEodRefresh/);
  assert.match(controller, /visibilitychange/);
  assert.match(controller, /reloadDailyEodConflict/);
  assert.match(controller, /restoreDailyEodConflictDraft/);
  assert.match(controller, /dailyEodDraftScope/);
  assert.match(controller, /dailyEodRefreshSequence/);
  assert.match(controller, /scopeDate: this\.dailyEod\.serverDate/);
  assert.match(controller, /sequence !== this\.dailyEodRefreshSequence/);
  assert.match(controller, /if \(!this\.selectedDailyEod\) this\.dailyEodReturnFocus = document\.activeElement/);
  assert.match(controller, /aria-labelledby/);
  assert.match(controller, /eod-linked-evidence/);
  assert.match(template, /What Moved\?/);
  assert.match(template, /What&apos;s Blocked\?/);
  assert.match(template, /What Needs You\?/);
  assert.match(template, /What&apos;s On Tomorrow\?/);
  assert.match(template, /OneDrive/);
  assert.match(template, /Participant Tracker/);
  assert.match(template, /Missing today/);
  assert.match(template, /EOD report archive/);
  assert.match(template, /record\.projectCode/);
  assert.match(template, /Reload latest/);
  assert.match(template, /Restore my draft/);
  assert.match(template, /dailyEodLocked \|\| savingDailyEod/);
  assert.match(template, /Audit history/);
  assert.match(template, /access\.role==='admin'/);
  assert.match(template, /role="alert" tabindex="-1"/);
  assert.match(template, /aria-invalid/);
  assert.match(template, /aria-pressed/);
  assert.match(template, /<table/);
  assert.match(template, /Evidence unavailable in imported record/);
  assert.match(template, /lang="en"/);
});

test("styles the EOD form for focused desktop and stacked mobile use", async () => {
  const styles = await Promise.all([
    readFile(new URL("src/css/aoi.css", root), "utf8"),
    readFile(new URL("src/css/eod.css", root), "utf8"),
  ]).then((files) => files.join("\n"));

  assert.match(styles, /\.eod-layout/);
  assert.match(styles, /\.eod-form/);
  assert.match(styles, /\.eod-evidence-row/);
  assert.match(styles, /\.eod-oversight/);
  assert.match(styles, /\.eod-report-table/);
  assert.match(styles, /\.eod-drawer-notice[\s\S]*z-index:\s*110/);
  assert.match(styles, /\.eod-status-options input:focus-visible/);
  assert.match(styles, /@media \(max-width: 760px\)[\s\S]*\.eod-layout/);
  assert.match(styles, /\.eod-form input[\s\S]*font-size:\s*16px/);
  assert.match(styles, /@media \(max-width: 1180px\)[\s\S]*\.eod-layout/);
});

test("protects and recovers unsaved EOD work across navigation and project changes", async () => {
  const controller = await readFile(new URL("src/js/workspace.js", root), "utf8");
  assert.match(controller, /beforeunload/);
  assert.match(controller, /persistDailyEodRecovery/);
  assert.match(controller, /recoverDailyEodDraft/);
  assert.match(controller, /discardDailyEodRecovery/);
  assert.match(controller, /refreshDailyEod/);
  assert.match(controller, /dailyEodReportsLoaded = false/);
});
