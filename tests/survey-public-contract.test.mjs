import assert from "node:assert/strict";
import test from "node:test";

import * as surveyPublic from "../supabase/functions/_shared/survey-public.js";

const { decideSurveySubmitReplay } = surveyPublic;

test("continues a first submit after the replay RPC reports its exact miss", () => {
  const decision = decideSurveySubmitReplay({
    data: null,
    error: { message: "SURVEY_RESPONSE_UNAVAILABLE" },
  });

  assert.deepEqual(decision, { kind: "continue" });
});

test("returns a completed replay as a 200 response without continuing submission", () => {
  const data = {
    replayed: true,
    submissionId: "submission-1",
    status: "submitted",
    submittedAt: "2026-08-10T00:00:00Z",
  };

  assert.deepEqual(decideSurveySubmitReplay({ data, error: null }), {
    kind: "response",
    status: 200,
    payload: { data },
  });
});

test("keeps locked, identity, revoked, and non-exact errors terminal", () => {
  for (const message of [
    "SURVEY_RESPONSE_LOCKED",
    "SURVEY_INVITATION_REQUIRED",
    "SURVEY_LINK_UNAVAILABLE",
    "SURVEY_RESPONSE_UNAVAILABLE: identity mismatch",
  ]) {
    assert.deepEqual(
      decideSurveySubmitReplay({ data: null, error: { message } }),
      { kind: "error", message },
      message,
    );
  }
});

test("does not continue an unexpected empty replay response", () => {
  assert.deepEqual(
    decideSurveySubmitReplay({ data: null, error: null }),
    { kind: "error", message: "SURVEY_REPLAY_INVALID" },
  );
});

test("uses the exact allowed origin CORS contract and disables caching", () => {
  const origin = "https://survey.example.com";

  assert.deepEqual(surveyPublic.surveyCorsHeaders(origin), {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    Vary: "Origin",
  });
});
