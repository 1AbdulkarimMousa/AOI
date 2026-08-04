import assert from "node:assert/strict";
import test from "node:test";

import {
  buildLayerMatrices,
  buildPmfRecommendations,
  validateResearchRecord,
} from "../src/js/pmf.js";

const segments = [
  { code: "families", name: "Families with Children" },
  { code: "orthodontic", name: "Adult Orthodontic Patients" },
];

test("requires consent and a segment before a respondent can be submitted", () => {
  const result = validateResearchRecord("respondent", {
    externalId: "R-001",
    respondentType: "Consumer",
    segmentCode: "",
    consentStatus: "pending",
  }, "submitted");

  assert.deepEqual(result, [
    "Choose a research segment.",
    "Consent must be granted before submission.",
  ]);
});

test("requires provenance and limitations for submitted evidence", () => {
  const result = validateResearchRecord("evidence", {
    pmfLayer: "H1",
    stance: "supporting",
    strength: 3,
    title: "A recurring visibility problem",
    evidenceText: "Participant described a recent incident.",
    sourceLink: "",
    limitations: "",
  }, "submitted");

  assert.deepEqual(result, [
    "Add a source link or session reference.",
    "Record the evidence limitations before submission.",
  ]);
});

test("builds every PMF layer matrix by segment from approved observations", () => {
  const matrices = buildLayerMatrices({
    segments,
    definitions: [
      { id: "m1", code: "recent_change_rate", layer: "H1", dimension: "Frequency", label: "Recent change rate", valueType: "boolean" },
      { id: "m2", code: "capture_success", layer: "H3", dimension: "Capture", label: "Capture success", valueType: "boolean" },
      { id: "m3", code: "purchase_intent_259", layer: "H5", dimension: "Price Acceptance", label: "Purchase intent at $259", valueType: "numeric" },
    ],
    observations: [
      { definitionId: "m1", segmentCode: "families", booleanValue: true, workflowStatus: "approved" },
      { definitionId: "m1", segmentCode: "families", booleanValue: false, workflowStatus: "approved" },
      { definitionId: "m1", segmentCode: "families", booleanValue: true, workflowStatus: "draft" },
      { definitionId: "m2", segmentCode: "orthodontic", booleanValue: true, workflowStatus: "approved" },
      { definitionId: "m3", segmentCode: "families", numericValue: 4, workflowStatus: "approved" },
      { definitionId: "m3", segmentCode: "families", numericValue: 2, workflowStatus: "approved" },
    ],
  });

  assert.deepEqual(Object.keys(matrices), ["H1", "H2", "H3", "H4", "H5"]);
  assert.equal(matrices.H1[0].values.families.display, "50%");
  assert.equal(matrices.H1[0].values.families.sampleSize, 2);
  assert.equal(matrices.H3[0].values.orthodontic.display, "100%");
  assert.equal(matrices.H5[0].values.families.display, "3.0");
});

test("requires provenance before a matrix observation can be submitted", () => {
  const result = validateResearchRecord("observation", {
    definitionId: "m1",
    segmentCode: "families",
    booleanValue: true,
    respondentId: "",
    sessionId: "",
    sourceLink: "",
  }, "submitted");

  assert.deepEqual(result, ["Add a respondent, session, or source link before submission."]);
});

test("recommends action for review backlog, sample gaps, contradictions, and consent risk", () => {
  const recommendations = buildPmfRecommendations({
    reviewQueue: [{ id: "e1" }, { id: "e2" }],
    samplePlan: [{ id: "s1", label: "Implant maintenance", actual: 2, target: 8 }],
    evidence: [
      { pmfLayer: "H1", stance: "supporting", workflowStatus: "approved" },
      { pmfLayer: "H1", stance: "contradicting", workflowStatus: "approved" },
      { pmfLayer: "H1", stance: "contradicting", workflowStatus: "approved" },
    ],
    respondents: [{ id: "r1", consentStatus: "withdrawn" }],
  });

  assert.deepEqual(
    recommendations.map((item) => item.type),
    ["review", "sample", "contradiction", "consent"],
  );
  assert.match(recommendations[1].action, /6/);
});
