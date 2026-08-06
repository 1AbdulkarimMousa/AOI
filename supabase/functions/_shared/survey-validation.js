const ANSWER_TYPES = new Set([
  "short_text", "long_text", "number", "email", "phone", "url", "date", "time",
  "single_choice", "multiple_choice", "dropdown", "yes_no", "rating", "nps",
  "likert", "matrix_single", "matrix_multiple", "ranking", "upload", "signature",
  "consent", "calculated", "hidden",
]);

function questions(definition) {
  const result = [];
  const visit = (blocks = []) => {
    for (const block of blocks) {
      if (ANSWER_TYPES.has(block.type)) result.push(block);
      if (Array.isArray(block.blocks)) visit(block.blocks);
    }
  };
  visit(definition?.blocks);
  return result;
}

function hasAnswer(value) {
  return value !== undefined && value !== null && value !== "" && (!Array.isArray(value) || value.length > 0);
}

function conditionMatches(condition, answers) {
  const value = answers[condition.questionId];
  switch (condition.operator) {
    case "answered": return hasAnswer(value);
    case "not_answered": return !hasAnswer(value);
    case "equals": return Array.isArray(value) ? value.includes(condition.value) : value === condition.value;
    case "not_equals": return Array.isArray(value) ? !value.includes(condition.value) : value !== condition.value;
    case "contains": return String(value ?? "").toLowerCase().includes(String(condition.value ?? "").toLowerCase());
    case "greater_than": return Number(value) > Number(condition.value);
    case "less_than": return Number(value) < Number(condition.value);
    case "at_least": return Number(value) >= Number(condition.value);
    case "at_most": return Number(value) <= Number(condition.value);
    default: return false;
  }
}

function ruleMatches(rule, answers) {
  if (!rule) return true;
  const all = Array.isArray(rule.all) ? rule.all : [];
  const any = Array.isArray(rule.any) ? rule.any : [];
  return all.every((condition) => conditionMatches(condition, answers)) && (!any.length || any.some((condition) => conditionMatches(condition, answers)));
}

function visibleIds(definition, answers) {
  const list = questions(definition);
  let visible = new Set(list.filter((question) => !question.visibility).map((question) => question.id));
  for (let iteration = 0; iteration <= list.length; iteration += 1) {
    const scoped = Object.fromEntries(Object.entries(answers).filter(([questionId]) => visible.has(questionId)));
    const next = new Set(list.filter((question) => !question.visibility || ruleMatches(question.visibility, scoped)).map((question) => question.id));
    if (next.size === visible.size && [...next].every((questionId) => visible.has(questionId))) break;
    visible = next;
  }
  return visible;
}

function validateValue(question, value, partial, submissionId) {
  if (!hasAnswer(value)) {
    if (!partial && question.required) return question.type === "consent" ? "Consent is required to continue." : "This question is required.";
    return null;
  }
  if (question.type === "consent" && question.required && value !== true) return "Consent is required to continue.";
  if (["short_text", "long_text", "email", "phone", "url", "date", "time", "signature"].includes(question.type) && typeof value !== "string") return "Enter a text value.";
  if (question.validation?.minLength !== undefined && String(value).length < Number(question.validation.minLength)) return "Enter more detail.";
  if (question.validation?.maxLength !== undefined && String(value).length > Number(question.validation.maxLength)) return "Shorten this answer.";
  if (question.validation?.pattern) {
    try { if (!new RegExp(question.validation.pattern).test(String(value))) return "Enter a value in the requested format."; } catch { return "This question has an invalid validation pattern."; }
  }
  if (question.type === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return "Enter a valid email address.";
  if (question.type === "url") {
    try { new URL(value); } catch { return "Enter a valid URL."; }
  }
  if (["number", "rating", "nps", "likert"].includes(question.type)) {
    if (!Number.isFinite(Number(value))) return "Enter a valid number.";
    if (question.validation?.min !== undefined && Number(value) < Number(question.validation.min) || question.validation?.max !== undefined && Number(value) > Number(question.validation.max)) return "Enter a value in the allowed range.";
  }
  const optionIds = new Set((question.options || []).map((option) => option.id));
  if (["single_choice", "dropdown", "yes_no"].includes(question.type) && !optionIds.has(value)) return "Choose an available option.";
  if (question.type === "multiple_choice" && (!Array.isArray(value) || value.some((item) => !optionIds.has(item)))) return "Choose only available options.";
  if (question.type === "ranking" && (!Array.isArray(value) || value.length !== optionIds.size || new Set(value).size !== optionIds.size || value.some((item) => !optionIds.has(item)))) return "Rank every available option once.";
  if (["matrix_single", "matrix_multiple"].includes(question.type)) {
    if (typeof value !== "object" || Array.isArray(value)) return "Complete the matrix with available choices.";
    const rowIds = new Set((question.rows || []).map((row) => row.id));
    const columnIds = new Set((question.columns || []).map((column) => column.id));
    if (!partial && question.required && [...rowIds].some((rowId) => !hasAnswer(value[rowId]))) return "Complete every required matrix row.";
    for (const [rowId, selection] of Object.entries(value)) {
      if (!rowIds.has(rowId)) return "Use only available matrix rows.";
      if (question.type === "matrix_single" && !columnIds.has(selection)) return "Use only available matrix columns.";
      if (question.type === "matrix_multiple" && (!Array.isArray(selection) || selection.some((columnId) => !columnIds.has(columnId)))) return "Use only available matrix columns.";
    }
  }
  if (question.type === "upload" && (typeof value !== "object" || typeof value.path !== "string" || typeof value.name !== "string" || !submissionId || !value.path.startsWith(`${submissionId}/${question.id}/`))) return "Upload an approved private file.";
  if (question.type === "consent" && typeof value !== "boolean") return "Choose whether you consent.";
  return null;
}

function calculateFields(definition, answers) {
  const result = { ...answers };
  const calculated = new Map(questions(definition).filter((item) => item.type === "calculated" && item.calculation).map((question) => [question.id, question]));
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

function scoreFor(question, value) {
  const weight = Number(question.scoring?.weight ?? 1);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type)) return Number((question.options || []).find((option) => option.id === value)?.score || 0) * weight;
  if (["multiple_choice", "ranking"].includes(question.type)) return value.reduce((sum, optionId) => sum + Number((question.options || []).find((option) => option.id === optionId)?.score || 0), 0) * weight;
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) return Number(value || 0) * weight;
  return 0;
}

function maximumFor(question) {
  const weight = Number(question.scoring?.weight ?? 1);
  if (["single_choice", "dropdown", "yes_no"].includes(question.type)) return Math.max(0, ...(question.options || []).map((option) => Number(option.score || 0))) * weight;
  if (["multiple_choice", "ranking"].includes(question.type)) return (question.options || []).reduce((sum, option) => sum + Math.max(0, Number(option.score || 0)), 0) * weight;
  if (["number", "rating", "nps", "likert", "calculated"].includes(question.type)) return Number(question.validation?.max || 0) * weight;
  return 0;
}

export function validateSurveyPayload(definition, suppliedAnswers = {}, { partial = false, submissionId = "" } = {}) {
  const list = questions(definition);
  const byId = new Map(list.map((question) => [question.id, question]));
  const errors = {};
  for (const questionId of Object.keys(suppliedAnswers)) {
    if (!byId.has(questionId)) errors[questionId] = "Unknown question.";
    else if (byId.get(questionId).type === "hidden") errors[questionId] = "This value is managed by the survey distribution.";
  }
  const visible = visibleIds(definition, suppliedAnswers);
  let answers;
  try {
    answers = calculateFields(definition, Object.fromEntries(Object.entries(suppliedAnswers).filter(([questionId]) => visible.has(questionId) && !["calculated", "hidden"].includes(byId.get(questionId)?.type))));
  } catch {
    errors._definition = "The survey calculation definition is invalid.";
    answers = Object.fromEntries(Object.entries(suppliedAnswers).filter(([questionId]) => visible.has(questionId) && !["calculated", "hidden"].includes(byId.get(questionId)?.type)));
  }
  for (const question of list) {
    if (!visible.has(question.id)) continue;
    if (question.type === "hidden") continue;
    const error = validateValue(question, answers[question.id], partial, submissionId);
    if (error) errors[question.id] = error;
  }
  const scoringQuestions = list.filter((question) => visible.has(question.id));
  const total = definition?.scoring?.enabled ? scoringQuestions.reduce((sum, question) => sum + scoreFor(question, answers[question.id]), 0) : 0;
  const maximum = definition?.scoring?.enabled ? scoringQuestions.reduce((sum, question) => sum + maximumFor(question), 0) : 0;
  return {
    valid: Object.keys(errors).length === 0,
    errors,
    answers,
    score: { total, maximum, percent: maximum ? Math.round(total / maximum * 100) : 0 },
  };
}
