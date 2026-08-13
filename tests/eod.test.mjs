import assert from "node:assert/strict";
import test from "node:test";

import {
  createDailyEodDraft,
  createDailyEodDraftKey,
  dailyEodAttentionCount,
  filterDailyEodTeam,
  formatDailyEodTimestamp,
  isLegacyEvidenceException,
  readDailyEodDraft,
  toggleExecutiveOwner,
  validateDailyEodBrief,
  validateDailyEodFields,
  writeDailyEodDraft,
} from "../src/js/daily-eod.js";

function validBrief() {
  return {
    ...createDailyEodDraft({ engagementManagerId: "manager", personInChargeId: "owner" }),
    movedOutcome: "Completed the first interview synthesis.",
    evidenceGathered: "Six interview notes were normalized.",
    deliverablesCompleted: "Research summary and evidence log.",
    keyInsight: "Parents need a clearer next action.",
    currentBlocker: "None",
    blockerImpact: "None",
    proposedSolution: "None",
    executiveOwners: ["None"],
    executiveRequest: "None",
    tomorrowPriorities: ["Review synthesis", "Schedule interviews", "Update evidence log"],
    projectStatus: "on_track",
    evidenceLinks: [{ sourceType: "evidence_log", label: "Interview evidence", url: "https://example.com/evidence" }],
  };
}

test("creates a stable EOD draft with three priorities and one evidence row", () => {
  const draft = createDailyEodDraft({ engagementManagerId: "manager" });

  assert.equal(draft.engagementManagerId, "manager");
  assert.deepEqual(draft.tomorrowPriorities, ["", "", ""]);
  assert.deepEqual(draft.executiveOwners, []);
  assert.deepEqual(draft.evidenceLinks, [{ sourceType: "onedrive", label: "", url: "" }]);
});

test("requires every submitted EOD field and a valid evidence URL", () => {
  assert.deepEqual(validateDailyEodBrief(validBrief()), []);

  const invalid = validBrief();
  invalid.keyInsight = "";
  invalid.tomorrowPriorities[1] = "";
  invalid.evidenceLinks[0].url = "not-a-url";

  assert.deepEqual(validateDailyEodBrief(invalid), [
    "Add the key insight or discovery.",
    "Add exactly three priorities for tomorrow.",
    "Add at least one labeled http(s) evidence link.",
  ]);
});

test("keeps None mutually exclusive with named executive owners", () => {
  assert.deepEqual(toggleExecutiveOwner(["Eason", "Mike"], "None"), ["None"]);
  assert.deepEqual(toggleExecutiveOwner(["None"], "Zhenzhen"), ["Zhenzhen"]);
  assert.deepEqual(toggleExecutiveOwner(["Eason"], "Eason"), []);
});

test("filters admin oversight and counts only actionable EOD records", () => {
  const team = [
    { userId: "1", workflowStatus: "missing" },
    { userId: "2", workflowStatus: "draft" },
    { userId: "3", workflowStatus: "submitted" },
    { userId: "4", workflowStatus: "completed" },
  ];

  assert.deepEqual(filterDailyEodTeam(team, "missing").map((item) => item.userId), ["1", "2"]);
  assert.deepEqual(filterDailyEodTeam(team, "submitted").map((item) => item.userId), ["3"]);
  assert.equal(dailyEodAttentionCount({ dueState: "due", teamToday: team }, "admin"), 4);
  assert.equal(dailyEodAttentionCount({ dueState: "completed", teamToday: team }, "intern"), 0);
});

test("formats audit timestamps in the organization timezone", () => {
  assert.match(formatDailyEodTimestamp("2026-08-04T20:40:00.000Z", "en", "America/New_York"), /Aug 4, 2026, 4:40 PM EDT/);
});

test("maps validation errors to stable field identifiers", () => {
  const invalid = validBrief();
  invalid.movedOutcome = "";
  invalid.tomorrowPriorities[2] = "";
  invalid.evidenceLinks[0].url = "invalid";

  assert.deepEqual(validateDailyEodFields(invalid), {
    movedOutcome: "Add the tangible outcome that moved today.",
    tomorrowPriorities: "Add exactly three priorities for tomorrow.",
    evidenceLinks: "Add at least one labeled http(s) evidence link.",
  });
});

test("stores recovery drafts within one user, project, and server date", () => {
  const storage = new Map();
  const adapter = { getItem: (key) => storage.get(key) || null, setItem: (key, value) => storage.set(key, value), removeItem: (key) => storage.delete(key) };
  const key = createDailyEodDraftKey("user-1", "project-1", "2026-08-13");
  assert.equal(key, "aoi:eod-draft:user-1:project-1:2026-08-13");

  writeDailyEodDraft(adapter, key, validBrief(), "2026-08-13T17:00:00.000Z");
  assert.equal(readDailyEodDraft(adapter, key).draft.movedOutcome, "Completed the first interview synthesis.");
  assert.equal(readDailyEodDraft(adapter, createDailyEodDraftKey("user-1", "project-2", "2026-08-13")), null);
});

test("limits missing-evidence completion to explicit imported records", () => {
  assert.equal(isLegacyEvidenceException({ workflowStatus: "submitted", legacyEvidenceMissing: true, evidenceLinks: [] }), true);
  assert.equal(isLegacyEvidenceException({ workflowStatus: "draft", legacyEvidenceMissing: true, evidenceLinks: [] }), false);
  assert.equal(isLegacyEvidenceException({ workflowStatus: "submitted", legacyEvidenceMissing: false, evidenceLinks: [] }), false);
});
