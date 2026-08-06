const ANSWER_TYPES = new Set([
  "short_text", "long_text", "number", "email", "phone", "url", "date", "time",
  "single_choice", "multiple_choice", "dropdown", "yes_no", "rating", "nps",
  "likert", "matrix_single", "matrix_multiple", "ranking", "upload", "signature",
  "consent", "calculated", "hidden",
]);
const CONTENT_TYPES = new Set(["content"]);

function id(prefix) {
  return `${prefix}-${globalThis.crypto.randomUUID()}`;
}

export function cloneSurveyDefinition(value) {
  return JSON.parse(JSON.stringify(value));
}

export function createSurveyDefinition({ locales = ["en", "zh-CN"] } = {}) {
  const includesChinese = locales.includes("zh-CN");
  return {
    schemaVersion: 1,
    locales: [...locales],
    defaultLocale: "en",
    title: { en: "Untitled survey", zh: includesChinese ? "未命名问卷" : "" },
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
    completion: { message: { en: "Thank you for your response.", zh: includesChinese ? "感谢您的参与。" : "" }, redirectUrl: "" },
    blocks: [{
      id: id("section"),
      type: "section",
      title: { en: "Section 1", zh: includesChinese ? "第一部分" : "" },
      description: { en: "", zh: "" },
      blocks: [],
    }],
  };
}

export function createSurveyQuestion(type = "short_text") {
  if (CONTENT_TYPES.has(type)) return {
    id: id("content"),
    type,
    title: { en: "Instruction", zh: "说明" },
    description: { en: "", zh: "" },
  };
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

export function surveyChoiceValues(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === "object") {
    if (Array.isArray(value.values)) return value.values;
    return value.value === undefined || value.value === "" ? [] : [value.value];
  }
  return value === undefined || value === null || value === "" ? [] : [value];
}

export function surveyOtherText(value) {
  return value && typeof value === "object" ? String(value.otherText || "") : "";
}

function conditions(rule) {
  if (!rule || typeof rule !== "object") return [];
  return [...(Array.isArray(rule.all) ? rule.all : []), ...(Array.isArray(rule.any) ? rule.any : [])];
}

function answered(value) {
  if (value && typeof value === "object" && (Object.hasOwn(value, "value") || Object.hasOwn(value, "values"))) return surveyChoiceValues(value).length > 0;
  return value !== undefined && value !== null && value !== "" && (!Array.isArray(value) || value.length > 0);
}

function conditionMatches(condition, answers) {
  const actual = answers[condition.questionId];
  const comparable = actual && typeof actual === "object" && (Object.hasOwn(actual, "value") || Object.hasOwn(actual, "values")) ? surveyChoiceValues(actual) : actual;
  switch (condition.operator) {
    case "answered": return answered(actual);
    case "not_answered": return !answered(actual);
    case "equals": return Array.isArray(comparable) ? comparable.includes(condition.value) : comparable === condition.value;
    case "not_equals": return Array.isArray(comparable) ? !comparable.includes(condition.value) : comparable !== condition.value;
    case "contains": return String(comparable ?? "").toLowerCase().includes(String(condition.value ?? "").toLowerCase());
    case "greater_than": return Number(comparable) > Number(condition.value);
    case "less_than": return Number(comparable) < Number(condition.value);
    case "at_least": return Number(comparable) >= Number(condition.value);
    case "at_most": return Number(comparable) <= Number(condition.value);
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
    const values = surveyChoiceValues(answer);
    const rendered = values.map((item) => {
      const option = (question.options || []).find((candidate) => candidate.id === item);
      return option ? option.label?.[language] || option.label?.en || "" : String(item ?? "");
    });
    if (question.other?.optionId && values.includes(question.other.optionId) && surveyOtherText(answer)) rendered.push(surveyOtherText(answer));
    return rendered.join(", ");
  });
}

function localeKeys(definition) {
  const configured = Array.isArray(definition?.locales) ? definition.locales : ["en", "zh-CN"];
  return configured.map((locale) => locale === "zh-CN" ? "zh" : locale).filter((locale) => ["en", "zh"].includes(locale));
}

function translationErrors(value, path, errors, languages) {
  for (const language of languages) {
    if (!String(value?.[language] || "").trim()) errors.push({ code: "TRANSLATION_REQUIRED", path: `${path}.${language}` });
  }
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
  const languages = localeKeys(definition);
  if (!languages.length || new Set(languages).size !== languages.length) errors.push({ code: "SURVEY_LOCALES_INVALID", path: "locales" });
  if (!definition?.locales?.includes(definition?.defaultLocale)) errors.push({ code: "DEFAULT_LOCALE_INVALID", path: "defaultLocale" });
  if (typeof definition?.settings?.showProgress !== "boolean" || typeof definition?.settings?.allowReview !== "boolean" || typeof definition?.settings?.randomizeSections !== "boolean") errors.push({ code: "SURVEY_SETTING_INVALID", path: "settings" });
  if (definition?.completion?.redirectUrl) {
    try {
      const redirect = new URL(definition.completion.redirectUrl);
      if (!["http:", "https:"].includes(redirect.protocol)) throw new Error("unsafe");
    } catch { errors.push({ code: "COMPLETION_REDIRECT_INVALID", path: "completion.redirectUrl" }); }
  }
  translationErrors(definition?.title, "title", errors, languages);
  for (const [sectionIndex, section] of (definition?.blocks || []).entries()) {
    translationErrors(section.title, `sections.${sectionIndex}.title`, errors, languages);
    for (const [blockIndex, block] of (section.blocks || []).entries()) {
      if (CONTENT_TYPES.has(block.type)) translationErrors(block.title, `sections.${sectionIndex}.blocks.${blockIndex}.title`, errors, languages);
    }
  }
  const questions = surveyQuestions(definition);
  const ids = new Set();
  for (const [index, question] of questions.entries()) {
    const path = `questions.${index}`;
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(question.id || "")) errors.push({ code: "QUESTION_ID_INVALID", path: `${path}.id` });
    if (!question.id || ids.has(question.id)) errors.push({ code: "QUESTION_ID_DUPLICATE", path: `${path}.id` });
    ids.add(question.id);
    if (!ANSWER_TYPES.has(question.type)) errors.push({ code: "QUESTION_TYPE_INVALID", path: `${path}.type` });
    translationErrors(question.title, `${path}.title`, errors, languages);
    if (["single_choice", "multiple_choice", "dropdown", "yes_no", "ranking"].includes(question.type)) {
      if (!Array.isArray(question.options) || question.options.length < 2) errors.push({ code: "QUESTION_OPTIONS_REQUIRED", path: `${path}.options` });
      const optionIds = new Set();
      for (const [optionIndex, option] of (question.options || []).entries()) {
        if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(option.id || "")) errors.push({ code: "OPTION_ID_INVALID", path: `${path}.options.${optionIndex}.id` });
        if (optionIds.has(option.id)) errors.push({ code: "OPTION_ID_DUPLICATE", path: `${path}.options.${optionIndex}.id` });
        optionIds.add(option.id);
        translationErrors(option.label, `${path}.options.${optionIndex}.label`, errors, languages);
      }
      const exclusiveIds = question.validation?.exclusiveOptionIds || [];
      if (exclusiveIds.some((optionId) => !optionIds.has(optionId))) errors.push({ code: "EXCLUSIVE_OPTION_INVALID", path: `${path}.validation.exclusiveOptionIds` });
      if (question.other && !optionIds.has(question.other.optionId)) errors.push({ code: "OTHER_OPTION_INVALID", path: `${path}.other.optionId` });
      if (question.type === "ranking" && question.other) errors.push({ code: "OTHER_OPTION_UNSUPPORTED", path: `${path}.other` });
      if (question.other?.label) translationErrors(question.other.label, `${path}.other.label`, errors, languages);
      if (question.validation?.minSelections !== undefined && question.validation?.maxSelections !== undefined && Number(question.validation.minSelections) > Number(question.validation.maxSelections)) errors.push({ code: "SELECTION_RANGE_INVALID", path: `${path}.validation` });
    }
    if (["rating", "nps", "likert"].includes(question.type)) {
      if (question.scaleLabels?.min) translationErrors(question.scaleLabels.min, `${path}.scaleLabels.min`, errors, languages);
      if (question.scaleLabels?.max) translationErrors(question.scaleLabels.max, `${path}.scaleLabels.max`, errors, languages);
    }
    if (["matrix_single", "matrix_multiple"].includes(question.type)) {
      for (const dimension of ["rows", "columns"]) {
        const values = question[dimension] || [];
        if (!values.length) errors.push({ code: "MATRIX_DIMENSIONS_REQUIRED", path: `${path}.${dimension}` });
        const dimensionIds = new Set();
        for (const [dimensionIndex, value] of values.entries()) {
          const code = dimension === "rows" ? "MATRIX_ROW_DUPLICATE" : "MATRIX_COLUMN_DUPLICATE";
          if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(value.id || "") || dimensionIds.has(value.id)) errors.push({ code, path: `${path}.${dimension}.${dimensionIndex}.id` });
          dimensionIds.add(value.id);
          translationErrors(value.label, `${path}.${dimension}.${dimensionIndex}.label`, errors, languages);
        }
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

function validateQuestion(question, value, { submissionId = "" } = {}) {
  if (question.type === "consent" && question.required && value !== true) return "Consent is required to continue.";
  if (!answered(value)) return question.required ? "This question is required." : null;
  const { min, max, minLength, maxLength, pattern } = question.validation || {};
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) {
    if (!Number.isFinite(Number(value))) return "Enter a valid number.";
    if (min !== undefined && Number(value) < Number(min) || max !== undefined && Number(value) > Number(max)) {
      return `Enter a value from ${min ?? "the minimum"} to ${max ?? "the maximum"}.`;
    }
    if (question.validation?.integer && !Number.isInteger(Number(value))) return "Enter a whole number.";
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
  const choiceValues = surveyChoiceValues(value);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type) && (choiceValues.length !== 1 || !optionIds.has(choiceValues[0]))) return "Choose one of the available options.";
  if (["multiple_choice", "ranking"].includes(question.type) && (!Array.isArray(value) && !(value && Array.isArray(value.values)) || choiceValues.some((item) => !optionIds.has(item)) || new Set(choiceValues).size !== choiceValues.length)) return "Choose only available options.";
  if (question.type === "multiple_choice") {
    const minimum = question.validation?.minSelections;
    const maximum = question.validation?.maxSelections;
    if (minimum !== undefined && choiceValues.length < Number(minimum)) return `Choose at least ${minimum} option(s).`;
    if (maximum !== undefined && choiceValues.length > Number(maximum)) return `Choose up to ${maximum} option(s).`;
    if ((question.validation?.exclusiveOptionIds || []).some((optionId) => choiceValues.includes(optionId)) && choiceValues.length > 1) return "That option cannot be combined with another choice.";
  }
  if (question.other?.optionId && choiceValues.includes(question.other.optionId) && question.other.required && !surveyOtherText(value).trim()) return "Please specify your Other answer.";
  if (question.type === "ranking" && (choiceValues.length !== optionIds.size || new Set(choiceValues).size !== optionIds.size)) return "Rank every available option once.";
  if (["matrix_single", "matrix_multiple"].includes(question.type)) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return "Complete the matrix with available choices.";
    const rowIds = new Set((question.rows || []).map((row) => row.id));
    const columnIds = new Set((question.columns || []).map((column) => column.id));
    if (question.required && [...rowIds].some((rowId) => !answered(value[rowId]))) return "Complete every required matrix row.";
    for (const [rowId, selection] of Object.entries(value)) {
      if (!rowIds.has(rowId)) return "Use only available matrix rows.";
      if (question.type === "matrix_single" && !columnIds.has(selection)) return "Use only available matrix columns.";
      if (question.type === "matrix_multiple" && (!Array.isArray(selection) || new Set(selection).size !== selection.length || selection.some((columnId) => !columnIds.has(columnId)))) return "Use only available matrix columns.";
    }
  }
  if (question.type === "upload" && (!value || typeof value !== "object" || typeof value.path !== "string" || typeof value.name !== "string" || !submissionId || !value.path.startsWith(`${submissionId}/${question.id}/`))) return "Upload an approved private file.";
  return null;
}

export function validateSurveyAnswers(definition, answers = {}, options = {}) {
  const visible = new Set(evaluateVisibility(definition, answers));
  const errors = {};
  const byId = new Map(surveyQuestions(definition).map((question) => [question.id, question]));
  if (options.rejectUnknown) {
    for (const questionId of Object.keys(answers)) {
      if (!byId.has(questionId)) errors[questionId] = "Unknown question.";
      else if (byId.get(questionId).type === "hidden") errors[questionId] = "This value is managed by the survey distribution.";
    }
  }
  for (const question of surveyQuestions(definition)) {
    if (!visible.has(question.id)) continue;
    if (question.type === "hidden") continue;
    const error = validateQuestion(question, answers[question.id], options);
    if (error) errors[question.id] = error;
  }
  return { valid: Object.keys(errors).length === 0, errors };
}

function questionScore(question, value) {
  if (!answered(value)) return 0;
  const weight = Number(question.scoring?.weight ?? 1);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type)) {
    return Number((question.options || []).find((option) => option.id === surveyChoiceValues(value)[0])?.score || 0) * weight;
  }
  if (["multiple_choice", "ranking"].includes(question.type)) {
    return surveyChoiceValues(value).reduce((sum, optionId) => sum + Number((question.options || []).find((option) => option.id === optionId)?.score || 0), 0) * weight;
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
