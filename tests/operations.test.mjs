import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCandidateExport,
  buildRecommendations,
  parseCandidateImport,
} from "../src/js/operations.js";

test("parses workbook-shaped tabular data into candidate records", () => {
  const input = [
    "ID\tCategory\tHandle / Name\tPrimary Platform\tReach\tTier\tContact Readiness\tPMF Candidate\tOwner\tOutreach Status\tFirst Outreach\tNext Step Due",
    "1\tDental Professional\t@demo\tTikTok / Instagram\t100K\tMicro\tEmail ready\tYes\tKayla\tReady to Send\t2026-08-03\t2026-08-07",
  ].join("\n");

  const result = parseCandidateImport(input);

  assert.equal(result.errors.length, 0);
  assert.equal(result.rows.length, 1);
  assert.deepEqual(result.rows[0], {
    externalId: "1",
    category: "Dental Professional",
    name: "@demo",
    platforms: "TikTok / Instagram",
    reach: "100K",
    tier: "Micro",
    contactReadiness: "Email ready",
    contactChannel: "",
    contactDetail: "",
    sourceUrl: "",
    pmfCandidate: true,
    ownerName: "Kayla",
    outreachStatus: "Ready to Send",
    firstOutreach: "2026-08-03",
    nextStepDue: "2026-08-07",
  });
});

test("parses exported candidate JSON back into import rows", () => {
  const result = parseCandidateImport(JSON.stringify([{ externalId: "7", name: "@json", category: "Technology Reviewer", pmfCandidate: true }]));

  assert.equal(result.errors.length, 0);
  assert.equal(result.rows[0].name, "@json");
  assert.equal(result.rows[0].pmfCandidate, true);
});

test("rejects imports without a candidate name and reports the row", () => {
  const result = parseCandidateImport("ID\tCategory\tHandle / Name\n2\tMom & Family\t");

  assert.equal(result.rows.length, 0);
  assert.deepEqual(result.errors, ["Row 2: Handle / Name is required."]);
});

test("exports candidates as formula-safe CSV and JSON", () => {
  const candidates = [{
    externalId: "1",
    name: "=unsafe",
    category: "Dental Professional",
    outreachStatus: "Ready to Send",
  }];

  const exported = buildCandidateExport(candidates);

  assert.match(exported.csv, /^\uFEFFexternalId,category,name,platforms,reach,tier,contactReadiness,contactChannel,contactDetail,sourceUrl,pmfCandidate,ownerName,outreachStatus,firstOutreach,nextStepDue\r\n/);
  assert.match(exported.csv, /"'=unsafe"/);
  assert.deepEqual(JSON.parse(exported.json), candidates);
});

test("recommends transparent recovery actions from pipeline gaps", () => {
  const recommendations = buildRecommendations({
    totalCandidates: 70,
    contactReady: 61,
    contacted: 11,
    confirmed: 0,
    targetLow: 40,
    targetHigh: 50,
    planningTarget: 45,
    deadline: "2026-08-20",
    today: "2026-08-04",
    conversionRate: 0.4,
    categories: [
      { name: "Dental Professional", candidates: 49, contactReady: 48, confirmed: 0 },
      { name: "Mom & Family", candidates: 10, contactReady: 7, confirmed: 0 },
    ],
  });

  assert.equal(recommendations[0].type, "pipeline");
  assert.match(recommendations[0].reason, /113/);
  assert.match(recommendations[0].action, /43/);
  assert.equal(recommendations.some((item) => item.type === "category"), true);
});
