import assert from "node:assert/strict";
import test from "node:test";

import { validateSurveyPayload } from "../supabase/functions/_shared/survey-validation.js";

const definition = {
  schemaVersion: 1,
  scoring: { enabled: true },
  blocks: [{
    id: "section",
    type: "section",
    blocks: [
      { id: "need", type: "single_choice", required: true, options: [{ id: "yes", score: 2 }, { id: "no", score: 0 }] },
      { id: "rating", type: "rating", required: true, validation: { min: 1, max: 5 }, scoring: { weight: 2 }, visibility: { all: [{ questionId: "need", operator: "equals", value: "yes" }] } },
      { id: "consent", type: "consent", required: true },
    ],
  }],
};

test("allows incomplete autosaves but rejects unknown and mistyped answers", () => {
  assert.equal(validateSurveyPayload(definition, { need: "yes" }, { partial: true }).valid, true);
  assert.equal(validateSurveyPayload(definition, { unknown: "value" }, { partial: true }).errors.unknown, "Unknown question.");
  assert.equal(validateSurveyPayload(definition, { need: "maybe" }, { partial: true }).errors.need, "Choose an available option.");
});

test("enforces visible required fields and affirmative consent on submit", () => {
  const missing = validateSurveyPayload(definition, { need: "yes", consent: false });

  assert.equal(missing.errors.rating, "This question is required.");
  assert.equal(missing.errors.consent, "Consent is required to continue.");
  assert.equal(validateSurveyPayload(definition, { need: "no", consent: true }).valid, true);
});

test("drops stale hidden answers and computes the authoritative score", () => {
  const result = validateSurveyPayload(definition, { need: "no", rating: 5, consent: true });

  assert.deepEqual(result.answers, { need: "no", consent: true });
  assert.deepEqual(result.score, { total: 0, maximum: 2, percent: 0 });
});

test("accepts valid visible answers and ignores client score claims", () => {
  const result = validateSurveyPayload(definition, { need: "yes", rating: 4, consent: true });

  assert.equal(result.valid, true);
  assert.deepEqual(result.score, { total: 10, maximum: 12, percent: 83 });
});

test("validates structured, contact, and upload answers authoritatively", () => {
  const specialized = structuredClone(definition);
  specialized.blocks[0].blocks.push(
    { id: "email", type: "email", required: true, validation: {} },
    { id: "url", type: "url", required: true, validation: {} },
    { id: "matrix", type: "matrix_single", required: true, rows: [{ id: "r1" }, { id: "r2" }], columns: [{ id: "c1" }, { id: "c2" }] },
    { id: "rank", type: "ranking", required: true, options: [{ id: "a" }, { id: "b" }] },
    { id: "file", type: "upload", required: true },
    { id: "managed", type: "hidden", required: false },
  );
  const result = validateSurveyPayload(specialized, {
    need: "no", consent: true, email: "bad", url: "not-a-url", matrix: { r1: "c3" }, rank: ["a", "a"],
    file: { path: "another-response/file", name: "x.pdf" }, managed: "forged",
  }, { submissionId: "submission-1" });

  for (const field of ["email", "url", "matrix", "rank", "file", "managed"]) assert.ok(result.errors[field], field);
});

test("accepts complete matrices, rankings, and owned upload paths", () => {
  const specialized = structuredClone(definition);
  specialized.blocks[0].blocks.push(
    { id: "matrix", type: "matrix_single", required: true, rows: [{ id: "r1" }], columns: [{ id: "c1" }] },
    { id: "rank", type: "ranking", required: true, options: [{ id: "a" }, { id: "b" }] },
    { id: "file", type: "upload", required: true },
  );
  const result = validateSurveyPayload(specialized, {
    need: "no", consent: true, matrix: { r1: "c1" }, rank: ["a", "b"],
    file: { path: "submission-1/file/upload.pdf", name: "upload.pdf", type: "application/pdf", size: 10 },
  }, { submissionId: "submission-1" });

  assert.equal(result.valid, true);
});
