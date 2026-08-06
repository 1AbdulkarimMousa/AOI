import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  WEN_CONSUMER_SURVEY_ASSET_ID,
  buildWenConsumerOralHealthSurvey,
  decideWenConsumerSurveySeed,
} from "../scripts/wen-consumer-survey-data.mjs";
import { evaluateVisibility, surveyQuestions, validateSurveyDefinition } from "../src/js/surveys/domain.js";
import { validateSurveyPayload } from "../supabase/functions/_shared/survey-validation.js";

test("defines Wen's English-only eight-part survey with 44 numbered questions", () => {
  const definition = buildWenConsumerOralHealthSurvey();
  const questions = surveyQuestions(definition);

  assert.match(WEN_CONSUMER_SURVEY_ASSET_ID, /^[0-9a-f-]{36}$/);
  assert.deepEqual(definition.locales, ["en"]);
  assert.equal(definition.metadata.author, "Wen Tang");
  assert.equal(definition.metadata.estimatedMinutes, 10);
  assert.equal(definition.blocks.length, 8);
  assert.equal(questions.length, 44);
  assert.deepEqual(questions.map((question) => question.number), Array.from({ length: 44 }, (_, index) => index + 1));
  assert.equal(validateSurveyDefinition(definition).valid, true);
});

test("models the supplied conditional, privacy, matrix, and selection-limit behavior", () => {
  const definition = buildWenConsumerOralHealthSurvey();
  const questions = new Map(surveyQuestions(definition).map((question) => [question.number, question]));

  assert.equal(questions.get(1).privacy.classification, "direct_identifier");
  assert.equal(questions.get(2).privacy.classification, "direct_identifier");
  assert.equal(questions.get(5).privacy.classification, "direct_identifier");
  assert.equal(questions.get(6).privacy.classification, "direct_identifier");
  assert.equal(questions.get(44).privacy.classification, "direct_identifier");
  assert.equal(questions.get(25).validation.maxSelections, 2);
  assert.equal(questions.get(41).validation.maxSelections, 3);
  assert.equal(questions.get(34).type, "matrix_single");
  assert.equal(questions.get(34).rows.length, 6);
  assert.deepEqual(questions.get(16).scaleLabels.min, { en: "Not at all confident" });
  assert.deepEqual(questions.get(16).scaleLabels.max, { en: "Completely confident" });

  const hiddenWithoutChildren = new Set(evaluateVisibility(definition, { q09_children_at_home: "no" }));
  const visibleWithChildren = new Set(evaluateVisibility(definition, { q09_children_at_home: "yes" }));
  assert.equal(hiddenWithoutChildren.has("q10_children_ages"), false);
  assert.equal(visibleWithChildren.has("q10_children_ages"), true);
  assert.equal(evaluateVisibility(definition, { q43_prototype_interest: "no" }).includes("q44_launch_email"), false);
  assert.equal(evaluateVisibility(definition, { q43_prototype_interest: "yes" }).includes("q44_launch_email"), true);
  assert.equal(evaluateVisibility(definition, { q24_camera_experience: "never_heard" }).includes("q25_camera_decision_factors"), false);
  assert.equal(evaluateVisibility(definition, { q24_camera_experience: "considered" }).includes("q25_camera_decision_factors"), true);
  assert.equal(evaluateVisibility(definition, { q24_camera_experience: "considered" }).includes("q26_camera_disappointment"), false);
  assert.equal(evaluateVisibility(definition, { q24_camera_experience: "bought" }).includes("q26_camera_disappointment"), true);
});

test("returns a fresh definition so seed callers cannot mutate the canonical survey", () => {
  const first = buildWenConsumerOralHealthSurvey();
  first.title.en = "Changed";

  assert.equal(buildWenConsumerOralHealthSurvey().title.en, "Consumer Oral Health Survey");
});

test("accepts a complete representative response through authoritative validation", () => {
  const definition = buildWenConsumerOralHealthSurvey();
  const questions = surveyQuestions(definition);
  const answers = {};
  for (let iteration = 0; iteration < questions.length; iteration += 1) {
    const visible = new Set(evaluateVisibility(definition, answers));
    let changed = false;
    for (const question of questions) {
      if (!question.required || !visible.has(question.id) || Object.hasOwn(answers, question.id)) continue;
      if (["single_choice", "dropdown", "yes_no"].includes(question.type)) answers[question.id] = question.options[0].id;
      else if (question.type === "multiple_choice") answers[question.id] = [question.options[0].id];
      else if (["rating", "nps", "likert", "number"].includes(question.type)) answers[question.id] = question.validation?.min ?? 1;
      else if (question.type === "email") answers[question.id] = "respondent@example.com";
      else if (question.type === "phone") answers[question.id] = "+1 555 010 0200";
      else if (question.type === "matrix_single") answers[question.id] = Object.fromEntries(question.rows.map((row) => [row.id, question.columns[0].id]));
      else answers[question.id] = "Representative response";
      changed = true;
    }
    if (!changed) break;
  }

  const result = validateSurveyPayload(definition, answers);
  assert.equal(result.valid, true, JSON.stringify(result.errors));
});

test("allows safe seed creation and no-op reruns but protects edited or active surveys", () => {
  const canonical = buildWenConsumerOralHealthSurvey();
  const ownerId = "33333333-3333-4333-8333-333333333333";
  const expected = { ownerId, organizationId: "11111111-1111-4111-8111-111111111111", projectId: "22222222-2222-4222-8222-222222222222" };
  const asset = { id: WEN_CONSUMER_SURVEY_ASSET_ID, owner_id: ownerId, assigned_to: ownerId, created_by: ownerId, organization_id: expected.organizationId, project_id: expected.projectId };

  assert.equal(decideWenConsumerSurveySeed({ asset: null, draft: null, versions: 0, submissions: 0 }, canonical, expected), "create");
  assert.equal(decideWenConsumerSurveySeed({ asset, draft: null, versions: 0, submissions: 0 }, canonical, expected), "repair_draft");
  assert.equal(decideWenConsumerSurveySeed({ asset, draft: { definition: canonical }, versions: 0, submissions: 0 }, canonical, expected), "noop");
  assert.equal(decideWenConsumerSurveySeed({ asset, draft: { definition: { ...canonical, title: { en: "Edited" } } }, versions: 0, submissions: 0 }, canonical, expected), "conflict");
  assert.equal(decideWenConsumerSurveySeed({ asset, draft: { definition: canonical }, versions: 1, submissions: 0 }, canonical, expected), "conflict");
  assert.equal(decideWenConsumerSurveySeed({ asset: { ...asset, owner_id: "someone-else" }, draft: { definition: canonical }, versions: 0, submissions: 0 }, canonical, expected), "conflict");
  assert.equal(decideWenConsumerSurveySeed({ asset: { ...asset, assigned_to: "someone-else" }, draft: { definition: canonical }, versions: 0, submissions: 0 }, canonical, expected), "conflict");
  assert.equal(decideWenConsumerSurveySeed({ asset: { ...asset, created_by: "someone-else" }, draft: { definition: canonical }, versions: 0, submissions: 0 }, canonical, expected), "conflict");
  assert.equal(decideWenConsumerSurveySeed({ asset: { ...asset, project_id: "another-project" }, draft: { definition: canonical }, versions: 0, submissions: 0 }, canonical, expected), "conflict");
});

test("ships a standalone survey seed that does not reset user passwords", async () => {
  const [packageSource, seedSource] = await Promise.all([
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../scripts/seed-wen-consumer-survey.mjs", import.meta.url), "utf8"),
  ]);

  assert.equal(JSON.parse(packageSource).scripts["seed:wen-survey"], "node scripts/seed-wen-consumer-survey.mjs");
  assert.match(seedSource, /WEN_ACCOUNT\.email/);
  assert.match(seedSource, /decideWenConsumerSurveySeed/);
  assert.doesNotMatch(seedSource, /updateUserById|password|AOI_RESET_ALL_PASSWORDS/);
});
