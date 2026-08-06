import assert from "node:assert/strict";
import test from "node:test";

import {
  calculateSurveyScore,
  calculateSurveyFields,
  cloneSurveyDefinition,
  createSurveyDefinition,
  createSurveyQuestion,
  deterministicOrder,
  evaluateVisibility,
  renderPipedText,
  surveyQuestions,
  validateSurveyAnswers,
  validateSurveyDefinition,
} from "../src/js/surveys/domain.js";
import {
  buildResponseCsv,
  exportSurveyPackage,
  importSurveyPackage,
} from "../src/js/surveys/import-export.js";

function publishedDefinition() {
  const definition = {
    ...createSurveyDefinition(),
    title: { en: "Concept test", zh: "概念测试" },
    blocks: [
      {
        id: "section-1",
        type: "section",
        title: { en: "Fit", zh: "匹配度" },
        blocks: [
          {
            id: "need",
            type: "single_choice",
            title: { en: "Do you have this need?", zh: "您有这个需求吗？" },
            required: true,
            options: [
              { id: "yes", label: { en: "Yes", zh: "是" }, score: 2 },
              { id: "no", label: { en: "No", zh: "否" }, score: 0 },
            ],
          },
          {
            id: "intensity",
            type: "rating",
            title: { en: "How strong is it?", zh: "需求有多强？" },
            required: true,
            validation: { min: 1, max: 5 },
            visibility: { all: [{ questionId: "need", operator: "equals", value: "yes" }] },
            scoring: { weight: 2 },
          },
        ],
      },
    ],
  };
  definition.scoring.enabled = true;
  return definition;
}

test("creates a bilingual versioned definition with a stable first section", () => {
  const draft = createSurveyDefinition();

  assert.equal(draft.schemaVersion, 1);
  assert.deepEqual(draft.locales, ["en", "zh-CN"]);
  assert.equal(draft.defaultLocale, "en");
  assert.equal(draft.blocks[0].type, "section");
  assert.ok(draft.blocks[0].id);
});

test("creates an English-only definition when requested", () => {
  const draft = createSurveyDefinition({ locales: ["en"] });

  assert.deepEqual(draft.locales, ["en"]);
  assert.equal(draft.defaultLocale, "en");
  assert.equal(validateSurveyDefinition(draft).valid, true);
});

test("validates definitions against their configured locales and ignores content blocks as answers", () => {
  const definition = createSurveyDefinition();
  definition.locales = ["en"];
  definition.title.zh = "";
  definition.blocks[0].title.zh = "";
  definition.blocks[0].blocks.push({
    id: "concept-copy",
    type: "content",
    title: { en: "Please read", zh: "" },
    description: { en: "A product concept.", zh: "" },
  });
  const question = createSurveyQuestion("short_text");
  question.title.zh = "";
  definition.blocks[0].blocks.push(question);

  assert.equal(validateSurveyDefinition(definition).valid, true);
  assert.deepEqual(surveyQuestions(definition).map((item) => item.id), [question.id]);
});

test("enforces choice limits, exclusive options, and required attached Other text", () => {
  const definition = publishedDefinition();
  const choices = {
    ...createSurveyQuestion("multiple_choice"),
    id: "confidence",
    title: { en: "What builds confidence?", zh: "什么能增强信心？" },
    required: true,
    options: [
      { id: "dentist", label: { en: "Dentist", zh: "牙医" }, score: 0 },
      { id: "reviews", label: { en: "Reviews", zh: "评价" }, score: 0 },
      { id: "none", label: { en: "None", zh: "无" }, score: 0 },
      { id: "other", label: { en: "Other", zh: "其他" }, score: 0 },
    ],
    validation: { maxSelections: 2, exclusiveOptionIds: ["none"] },
    other: { optionId: "other", required: true, label: { en: "Please specify", zh: "请说明" } },
  };
  definition.blocks[0].blocks.push(choices);

  assert.match(validateSurveyAnswers(definition, { need: "no", confidence: ["dentist", "reviews", "other"] }).errors.confidence, /up to 2/);
  assert.match(validateSurveyAnswers(definition, { need: "no", confidence: ["none", "reviews"] }).errors.confidence, /cannot be combined/);
  assert.match(validateSurveyAnswers(definition, { need: "no", confidence: { values: ["other"], otherText: "" } }).errors.confidence, /specify/i);
  assert.equal(validateSurveyAnswers(definition, { need: "no", confidence: { values: ["other"], otherText: "Clinical proof" } }).valid, true);
});

test("validates matrices, rankings, uploads, and managed fields with client-server parity", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks.push(
    { ...createSurveyQuestion("matrix_single"), id: "matrix", required: true, rows: [{ id: "r1", label: { en: "Row", zh: "行" } }], columns: [{ id: "c1", label: { en: "One", zh: "一" } }] },
    { ...createSurveyQuestion("ranking"), id: "rank", required: true, options: [{ id: "a", label: { en: "A", zh: "甲" } }, { id: "b", label: { en: "B", zh: "乙" } }] },
    { ...createSurveyQuestion("upload"), id: "file", required: true },
    { ...createSurveyQuestion("hidden"), id: "managed" },
  );

  const invalid = validateSurveyAnswers(definition, {
    need: "no", matrix: { r1: "missing" }, rank: ["a", "a"],
    file: { path: "another/file.pdf", name: "file.pdf" }, managed: "forged",
  }, { submissionId: "submission-1", rejectUnknown: true });

  for (const field of ["matrix", "rank", "file", "managed"]) assert.ok(invalid.errors[field], field);
  assert.equal(validateSurveyAnswers(definition, {
    need: "no", matrix: { r1: "c1" }, rank: ["a", "b"],
    file: { path: "submission-1/file/file.pdf", name: "file.pdf" },
  }, { submissionId: "submission-1", rejectUnknown: true }).valid, true);
});

test("rejects malformed matrix definitions and unsafe completion settings", () => {
  const definition = publishedDefinition();
  const matrix = { ...createSurveyQuestion("matrix_multiple"), id: "matrix" };
  matrix.rows[1].id = matrix.rows[0].id;
  matrix.columns[0].label.zh = "";
  definition.blocks[0].blocks.push(matrix);
  definition.defaultLocale = "fr";
  definition.settings.showProgress = "yes";
  definition.completion.redirectUrl = "javascript:alert(1)";

  const codes = new Set(validateSurveyDefinition(definition).errors.map((error) => error.code));
  for (const code of ["DEFAULT_LOCALE_INVALID", "SURVEY_SETTING_INVALID", "COMPLETION_REDIRECT_INVALID", "MATRIX_ROW_DUPLICATE", "TRANSLATION_REQUIRED"]) assert.equal(codes.has(code), true, code);
});

test("creates complete defaults for specialized question types", () => {
  const yesNo = createSurveyQuestion("yes_no");
  const matrix = createSurveyQuestion("matrix_single");
  const nps = createSurveyQuestion("nps");

  assert.deepEqual(yesNo.options.map((option) => option.label.en), ["Yes", "No"]);
  assert.equal(matrix.rows.length, 2);
  assert.equal(matrix.columns.length, 2);
  assert.deepEqual(nps.validation, { min: 0, max: 10 });
});

test("creates editable non-answer content blocks", () => {
  const content = createSurveyQuestion("content");

  assert.equal(content.type, "content");
  assert.ok(content.id.startsWith("content-"));
  assert.deepEqual(content.title, { en: "Instruction", zh: "说明" });
  assert.equal(Object.hasOwn(content, "required"), false);
});

test("clones reactive definition proxies without leaking references", () => {
  const source = publishedDefinition();
  const reactiveProxy = new Proxy(source, {});

  const clone = cloneSurveyDefinition(reactiveProxy);

  assert.deepEqual(clone, source);
  clone.title.en = "Changed";
  assert.equal(source.title.en, "Concept test");
});

test("validates bilingual content and rejects branch cycles", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks[0].visibility = {
    all: [{ questionId: "intensity", operator: "answered" }],
  };

  const result = validateSurveyDefinition(definition);

  assert.equal(result.valid, false);
  assert.equal(result.errors.some((error) => error.code === "BRANCH_CYCLE"), true);
  assert.equal(result.errors.some((error) => error.path.includes("title.zh")), false);
});

test("rejects unsafe question identifiers before CSV export", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks[0].id = "=unsafe,header";

  assert.equal(validateSurveyDefinition(definition).errors.some((error) => error.code === "QUESTION_ID_INVALID"), true);
});

test("shows conditional questions only when their declarative rule matches", () => {
  const definition = publishedDefinition();

  assert.deepEqual(evaluateVisibility(definition, { need: "no" }), ["need"]);
  assert.deepEqual(evaluateVisibility(definition, { need: "yes" }), ["need", "intensity"]);
});

test("pipes localized answer labels without evaluating arbitrary code", () => {
  const definition = publishedDefinition();

  assert.equal(renderPipedText("You chose {{need}}.", definition, { need: "yes" }, "en"), "You chose Yes.");
  assert.equal(renderPipedText("您的选择是 {{need}}。", definition, { need: "yes" }, "zh-CN"), "您的选择是 是。");
  assert.equal(renderPipedText("{{constructor}}", definition, {}, "en"), "");
});

test("does not require hidden questions and validates visible values", () => {
  const definition = publishedDefinition();

  assert.deepEqual(validateSurveyAnswers(definition, { need: "no" }), { valid: true, errors: {} });
  assert.deepEqual(validateSurveyAnswers(definition, { need: "yes" }), {
    valid: false,
    errors: { intensity: "This question is required." },
  });
  assert.equal(validateSurveyAnswers(definition, { need: "yes", intensity: 9 }).errors.intensity, "Enter a value from 1 to 5.");
});

test("requires affirmative consent and clears stale hidden branch answers", () => {
  const definition = publishedDefinition();
  const consent = { ...createSurveyQuestion("consent"), id: "consent" };
  const followUp = { ...createSurveyQuestion("short_text"), id: "follow-up", visibility: { all: [{ questionId: "intensity", operator: "equals", value: 5 }] } };
  definition.blocks[0].blocks.push(consent, followUp);

  assert.equal(validateSurveyAnswers(definition, { need: "no", intensity: 5, consent: false }).errors.consent, "Consent is required to continue.");
  assert.equal(evaluateVisibility(definition, { need: "no", intensity: 5, consent: true }).includes("follow-up"), false);
});

test("calculates transparent weighted scores", () => {
  const result = calculateSurveyScore(publishedDefinition(), { need: "yes", intensity: 4 });

  assert.deepEqual(result, { total: 10, maximum: 12, percent: 83 });
});

test("does not calculate authoritative scores when scoring is disabled", () => {
  const definition = publishedDefinition();
  definition.scoring.enabled = false;

  assert.deepEqual(calculateSurveyScore(definition, { need: "yes", intensity: 4 }), { total: 0, maximum: 0, percent: 0 });
});

test("evaluates calculated fields through a restricted operator contract", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks.push({
    ...createSurveyQuestion("calculated"),
    id: "total",
    calculation: { operator: "sum", questionIds: ["intensity", "bonus"] },
  });

  assert.deepEqual(calculateSurveyFields(definition, { intensity: 4, bonus: 2 }), { intensity: 4, bonus: 2, total: 6 });
  definition.blocks[0].blocks.at(-1).calculation.operator = "javascript";
  assert.throws(() => calculateSurveyFields(definition, { intensity: 4 }), /SURVEY_CALCULATION_OPERATOR_INVALID/);
});

test("resolves forward calculation dependencies and rejects cycles", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks.push(
    { ...createSurveyQuestion("calculated"), id: "total", calculation: { operator: "sum", questionIds: ["double", "bonus"] } },
    { ...createSurveyQuestion("calculated"), id: "double", calculation: { operator: "product", questionIds: ["intensity", "factor"] } },
  );

  assert.equal(calculateSurveyFields(definition, { intensity: 4, factor: 2, bonus: 1 }).total, 9);
  definition.blocks[0].blocks.at(-1).calculation.questionIds = ["total"];
  assert.throws(() => calculateSurveyFields(definition, { bonus: 1 }), /SURVEY_CALCULATION_CYCLE/);
});

test("randomizes deterministically without mutating the source", () => {
  const source = ["a", "b", "c", "d"];

  assert.deepEqual(deterministicOrder(source, "submission-42"), deterministicOrder(source, "submission-42"));
  assert.notDeepEqual(deterministicOrder(source, "submission-42"), deterministicOrder(source, "submission-43"));
  assert.deepEqual(source, ["a", "b", "c", "d"]);
});

test("round-trips a checksummed AOI survey package", async () => {
  const definition = publishedDefinition();
  const exported = await exportSurveyPackage({ definition, name: "Concept test" });
  const imported = await importSurveyPackage(exported);

  assert.equal(imported.name, "Concept test");
  assert.deepEqual(imported.definition, definition);
  await assert.rejects(() => importSurveyPackage(exported.replace("Concept test", "Changed")), /SURVEY_PACKAGE_CHECKSUM_INVALID/);
});

test("exports formula-safe wide response CSV with a bilingual codebook", () => {
  const exported = buildResponseCsv(publishedDefinition(), [{
    submissionId: "r1",
    status: "approved",
    answers: { need: "yes", intensity: "=2+2" },
  }]);

  assert.match(exported.wide, /^\uFEFFsubmissionId,status,need,intensity\r\n/);
  assert.match(exported.wide, /"'=2\+2"/);
  assert.match(exported.codebook, /Do you have this need\?/);
  assert.match(exported.codebook, /您有这个需求吗？/);
});

test("excludes direct identifiers from standard response and codebook exports", () => {
  const definition = publishedDefinition();
  definition.blocks[0].blocks[0].privacy = { classification: "direct_identifier" };

  const exported = buildResponseCsv(definition, [{ submissionId: "r1", status: "approved", answers: { need: "yes", intensity: 4 }, identifiers: { need: "Private" } }]);

  assert.doesNotMatch(exported.wide.split("\r\n")[0], /need/);
  assert.doesNotMatch(exported.codebook, /need/);
  assert.match(exported.wide, /intensity/);
});
