const ANSWER_TYPES = new Set([
  "short_text", "long_text", "number", "email", "phone", "url", "date", "time",
  "single_choice", "multiple_choice", "dropdown", "yes_no", "rating", "nps",
  "likert", "matrix_single", "matrix_multiple", "ranking", "upload", "signature",
  "consent", "calculated", "hidden",
]);

function id(prefix) {
  return `${prefix}-${globalThis.crypto.randomUUID()}`;
}

export function cloneSurveyDefinition(value) {
  return JSON.parse(JSON.stringify(value));
}

export function createSurveyDefinition() {
  return {
    schemaVersion: 1,
    locales: ["en", "zh-CN"],
    defaultLocale: "en",
    title: { en: "Untitled survey", zh: "未命名问卷" },
    description: { en: "", zh: "" },
    settings: {
      presentation: "sections",
      showProgress: true,
      allowReview: true,
      randomizeSections: false,
    },
    theme: { accent: "orange", density: "comfortable", logoUrl: "" },
    scoring: { enabled: false, bands: [] },
    quotas: [],
    completion: { message: { en: "Thank you for your response.", zh: "感谢您的参与。" }, redirectUrl: "" },
    blocks: [{
      id: id("section"),
      type: "section",
      title: { en: "Section 1", zh: "第一部分" },
      description: { en: "", zh: "" },
      blocks: [],
    }],
  };
}

export function createSurveyQuestion(type = "short_text") {
  if (!ANSWER_TYPES.has(type)) throw new Error("SURVEY_QUESTION_TYPE_INVALID");
  const options = ["single_choice", "multiple_choice", "dropdown", "ranking"].includes(type)
    ? [
        { id: id("option"), label: { en: "Option 1", zh: "选项一" }, score: 0 },
        { id: id("option"), label: { en: "Option 2", zh: "选项二" }, score: 0 },
      ]
    : type === "yes_no"
      ? [
          { id: "yes", label: { en: "Yes", zh: "是" }, score: 1 },
          { id: "no", label: { en: "No", zh: "否" }, score: 0 },
        ]
      : [];
  const isMatrix = ["matrix_single", "matrix_multiple"].includes(type);
  return {
    id: id("question"),
    type,
    title: { en: "Untitled question", zh: "未命名问题" },
    description: { en: "", zh: "" },
    required: type === "consent",
    options,
    rows: isMatrix ? [
      { id: id("row"), label: { en: "Row 1", zh: "第一行" } },
      { id: id("row"), label: { en: "Row 2", zh: "第二行" } },
    ] : [],
    columns: isMatrix ? [
      { id: id("column"), label: { en: "Column 1", zh: "第一列" } },
      { id: id("column"), label: { en: "Column 2", zh: "第二列" } },
    ] : [],
    validation: type === "nps" ? { min: 0, max: 10 } : ["rating", "likert"].includes(type) ? { min: 1, max: 5 } : {},
    visibility: null,
    scoring: { weight: 1 },
    randomizeOptions: false,
    pmfMapping: { layer: "", metricCode: "" },
  };
}

export function surveyQuestions(definition) {
  const questions = [];
  const visit = (blocks = []) => {
    for (const block of blocks) {
      if (ANSWER_TYPES.has(block.type)) questions.push(block);
      if (Array.isArray(block.blocks)) visit(block.blocks);
    }
  };
  visit(definition?.blocks);
  return questions;
}

function conditions(rule) {
  if (!rule || typeof rule !== "object") return [];
  return [...(Array.isArray(rule.all) ? rule.all : []), ...(Array.isArray(rule.any) ? rule.any : [])];
}

function answered(value) {
  return value !== undefined && value !== null && value !== "" && (!Array.isArray(value) || value.length > 0);
}

function conditionMatches(condition, answers) {
  const actual = answers[condition.questionId];
  switch (condition.operator) {
    case "answered": return answered(actual);
    case "not_answered": return !answered(actual);
    case "equals": return Array.isArray(actual) ? actual.includes(condition.value) : actual === condition.value;
    case "not_equals": return Array.isArray(actual) ? !actual.includes(condition.value) : actual !== condition.value;
    case "contains": return String(actual ?? "").toLowerCase().includes(String(condition.value ?? "").toLowerCase());
    case "greater_than": return Number(actual) > Number(condition.value);
    case "less_than": return Number(actual) < Number(condition.value);
    case "at_least": return Number(actual) >= Number(condition.value);
    case "at_most": return Number(actual) <= Number(condition.value);
    default: return false;
  }
}

export function ruleMatches(rule, answers = {}) {
  if (!rule) return true;
  const all = Array.isArray(rule.all) ? rule.all : [];
  const any = Array.isArray(rule.any) ? rule.any : [];
  return all.every((condition) => conditionMatches(condition, answers))
    && (!any.length || any.some((condition) => conditionMatches(condition, answers)));
}

export function evaluateVisibility(definition, answers = {}) {
  const questions = surveyQuestions(definition);
  let visible = new Set(questions.filter((question) => !question.visibility).map((question) => question.id));
  for (let iteration = 0; iteration <= questions.length; iteration += 1) {
    const scopedAnswers = Object.fromEntries(Object.entries(answers).filter(([questionId]) => visible.has(questionId)));
    const next = new Set(questions.filter((question) => !question.visibility || ruleMatches(question.visibility, scopedAnswers)).map((question) => question.id));
    if (next.size === visible.size && [...next].every((questionId) => visible.has(questionId))) break;
    visible = next;
  }
  return questions.filter((question) => visible.has(question.id)).map((question) => question.id);
}

export function renderPipedText(value, definition, answers = {}, locale = "en") {
  const questions = new Map(surveyQuestions(definition).map((question) => [question.id, question]));
  const language = locale === "zh-CN" ? "zh" : "en";
  return String(value || "").replace(/\{\{([a-zA-Z0-9_-]+)\}\}/g, (_match, questionId) => {
    if (!Object.hasOwn(answers, questionId) || !questions.has(questionId)) return "";
    const question = questions.get(questionId);
    const answer = answers[questionId];
    const values = Array.isArray(answer) ? answer : [answer];
    return values.map((item) => {
      const option = (question.options || []).find((candidate) => candidate.id === item);
      return option ? option.label?.[language] || option.label?.en || "" : String(item ?? "");
    }).join(", ");
  });
}

function translationErrors(value, path, errors) {
  if (!String(value?.en || "").trim()) errors.push({ code: "TRANSLATION_REQUIRED", path: `${path}.en` });
  if (!String(value?.zh || "").trim()) errors.push({ code: "TRANSLATION_REQUIRED", path: `${path}.zh` });
}

function findCycles(questions, dependencies = (question) => conditions(question.visibility).map((condition) => condition.questionId)) {
  const ids = new Set(questions.map((question) => question.id));
  const graph = new Map(questions.map((question) => [
    question.id,
    dependencies(question).filter((questionId) => ids.has(questionId)),
  ]));
  const visiting = new Set();
  const visited = new Set();
  const cycles = new Set();

  const visit = (questionId) => {
    if (visiting.has(questionId)) {
      cycles.add(questionId);
      return;
    }
    if (visited.has(questionId)) return;
    visiting.add(questionId);
    for (const dependency of graph.get(questionId) || []) visit(dependency);
    visiting.delete(questionId);
    visited.add(questionId);
  };
  for (const question of questions) visit(question.id);
  return cycles;
}

export function validateSurveyDefinition(definition) {
  const errors = [];
  if (definition?.schemaVersion !== 1) errors.push({ code: "SCHEMA_VERSION_UNSUPPORTED", path: "schemaVersion" });
  translationErrors(definition?.title, "title", errors);
  const questions = surveyQuestions(definition);
  const ids = new Set();
  for (const [index, question] of questions.entries()) {
    const path = `questions.${index}`;
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(question.id || "")) errors.push({ code: "QUESTION_ID_INVALID", path: `${path}.id` });
    if (!question.id || ids.has(question.id)) errors.push({ code: "QUESTION_ID_DUPLICATE", path: `${path}.id` });
    ids.add(question.id);
    if (!ANSWER_TYPES.has(question.type)) errors.push({ code: "QUESTION_TYPE_INVALID", path: `${path}.type` });
    translationErrors(question.title, `${path}.title`, errors);
    if (["single_choice", "multiple_choice", "dropdown", "ranking"].includes(question.type)) {
      if (!Array.isArray(question.options) || question.options.length < 2) errors.push({ code: "QUESTION_OPTIONS_REQUIRED", path: `${path}.options` });
      for (const [optionIndex, option] of (question.options || []).entries()) {
        if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(option.id || "")) errors.push({ code: "OPTION_ID_INVALID", path: `${path}.options.${optionIndex}.id` });
        translationErrors(option.label, `${path}.options.${optionIndex}.label`, errors);
      }
    }
  }
  for (const question of questions) {
    for (const condition of conditions(question.visibility)) {
      if (!ids.has(condition.questionId)) errors.push({ code: "BRANCH_TARGET_MISSING", path: `${question.id}.visibility` });
      if (condition.questionId === question.id) errors.push({ code: "BRANCH_SELF_REFERENCE", path: `${question.id}.visibility` });
    }
    if (question.type === "calculated") {
      if (!["sum", "average", "minimum", "maximum", "product", "difference"].includes(question.calculation?.operator)) errors.push({ code: "CALCULATION_INVALID", path: `${question.id}.calculation` });
      for (const questionId of question.calculation?.questionIds || []) {
        if (!ids.has(questionId) || questionId === question.id) errors.push({ code: "CALCULATION_REFERENCE_INVALID", path: `${question.id}.calculation` });
      }
    }
  }
  for (const questionId of findCycles(questions)) errors.push({ code: "BRANCH_CYCLE", path: `${questionId}.visibility` });
  for (const questionId of findCycles(questions, (question) => question.calculation?.questionIds || [])) errors.push({ code: "CALCULATION_CYCLE", path: `${questionId}.calculation` });
  return { valid: errors.length === 0, errors };
}

function validateQuestion(question, value) {
  if (question.type === "consent" && question.required && value !== true) return "Consent is required to continue.";
  if (!answered(value)) return question.required ? "This question is required." : null;
  const { min, max, minLength, maxLength, pattern } = question.validation || {};
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) {
    if (!Number.isFinite(Number(value))) return "Enter a valid number.";
    if (min !== undefined && Number(value) < Number(min) || max !== undefined && Number(value) > Number(max)) {
      return `Enter a value from ${min ?? "the minimum"} to ${max ?? "the maximum"}.`;
    }
  }
  if (minLength !== undefined && String(value).length < minLength) return `Enter at least ${minLength} characters.`;
  if (maxLength !== undefined && String(value).length > maxLength) return `Enter no more than ${maxLength} characters.`;
  if (pattern) {
    try {
      if (!new RegExp(pattern).test(String(value))) return "Enter a value in the requested format.";
    } catch {
      return "This question has an invalid validation pattern.";
    }
  }
  if (question.type === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value))) return "Enter a valid email address.";
  if (question.type === "url") {
    try { new URL(String(value)); } catch { return "Enter a valid URL."; }
  }
  const optionIds = new Set((question.options || []).map((option) => option.id));
  if (["single_choice", "dropdown"].includes(question.type) && !optionIds.has(value)) return "Choose one of the available options.";
  if (["multiple_choice", "ranking"].includes(question.type) && (!Array.isArray(value) || value.some((item) => !optionIds.has(item)))) return "Choose only available options.";
  return null;
}

export function validateSurveyAnswers(definition, answers = {}) {
  const visible = new Set(evaluateVisibility(definition, answers));
  const errors = {};
  for (const question of surveyQuestions(definition)) {
    if (!visible.has(question.id)) continue;
    const error = validateQuestion(question, answers[question.id]);
    if (error) errors[question.id] = error;
  }
  return { valid: Object.keys(errors).length === 0, errors };
}

function questionScore(question, value) {
  if (!answered(value)) return 0;
  const weight = Number(question.scoring?.weight ?? 1);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type)) {
    return Number((question.options || []).find((option) => option.id === value)?.score || 0) * weight;
  }
  if (["multiple_choice", "ranking"].includes(question.type)) {
    return value.reduce((sum, optionId) => sum + Number((question.options || []).find((option) => option.id === optionId)?.score || 0), 0) * weight;
  }
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) return Number(value) * weight;
  return 0;
}

export function calculateSurveyFields(definition, answers = {}) {
  const result = { ...answers };
  const calculated = new Map(surveyQuestions(definition).filter((item) => item.type === "calculated" && item.calculation).map((question) => [question.id, question]));
  const resolving = new Set();
  const resolve = (questionId) => {
    if (!calculated.has(questionId)) return Number(result[questionId]);
    if (resolving.has(questionId)) throw new Error("SURVEY_CALCULATION_CYCLE");
    resolving.add(questionId);
    const question = calculated.get(questionId);
    const values = (question.calculation.questionIds || []).map(resolve).filter(Number.isFinite);
    const operator = question.calculation.operator;
    if (operator === "sum") result[question.id] = values.reduce((sum, value) => sum + value, 0);
    else if (operator === "average") result[question.id] = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
    else if (operator === "minimum") result[question.id] = values.length ? Math.min(...values) : 0;
    else if (operator === "maximum") result[question.id] = values.length ? Math.max(...values) : 0;
    else if (operator === "product") result[question.id] = values.reduce((total, value) => total * value, values.length ? 1 : 0);
    else if (operator === "difference") result[question.id] = values.slice(1).reduce((total, value) => total - value, values[0] || 0);
    else throw new Error("SURVEY_CALCULATION_OPERATOR_INVALID");
    resolving.delete(questionId);
    return Number(result[question.id]);
  };
  for (const questionId of calculated.keys()) resolve(questionId);
  return result;
}

function questionMaximum(question) {
  const weight = Number(question.scoring?.weight ?? 1);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type)) return Math.max(0, ...(question.options || []).map((option) => Number(option.score || 0))) * weight;
  if (["multiple_choice", "ranking"].includes(question.type)) return (question.options || []).reduce((sum, option) => sum + Math.max(0, Number(option.score || 0)), 0) * weight;
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) return Number(question.validation?.max || 0) * weight;
  return 0;
}

export function calculateSurveyScore(definition, answers = {}) {
  if (!definition?.scoring?.enabled) return { total: 0, maximum: 0, percent: 0 };
  const visible = new Set(evaluateVisibility(definition, answers));
  const questions = surveyQuestions(definition).filter((question) => visible.has(question.id));
  const total = questions.reduce((sum, question) => sum + questionScore(question, answers[question.id]), 0);
  const maximum = questions.reduce((sum, question) => sum + questionMaximum(question), 0);
  return { total, maximum, percent: maximum ? Math.round(total / maximum * 100) : 0 };
}

function seededRandom(seed) {
  let value = 2166136261;
  for (const character of String(seed)) {
    value ^= character.charCodeAt(0);
    value = Math.imul(value, 16777619);
  }
  return () => {
    value += 0x6D2B79F5;
    let next = value;
    next = Math.imul(next ^ next >>> 15, next | 1);
    next ^= next + Math.imul(next ^ next >>> 7, next | 61);
    return ((next ^ next >>> 14) >>> 0) / 4294967296;
  };
}

export function deterministicOrder(items, seed) {
  const result = [...items];
  const random = seededRandom(seed);
  for (let index = result.length - 1; index > 0; index -= 1) {
    const target = Math.floor(random() * (index + 1));
    [result[index], result[target]] = [result[target], result[index]];
  }
  return result;
}
