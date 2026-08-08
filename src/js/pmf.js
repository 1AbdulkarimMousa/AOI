import { isSafeHttpUrl } from "./core.js";

export const PMF_LAYERS = [
  { code: "H1", name: "Need Truth" },
  { code: "H2", name: "Current Solution Gap" },
  { code: "H3", name: "Product Value" },
  { code: "H4", name: "Repeatability" },
  { code: "H5", name: "Value Exchange" },
];

function present(value) {
  return value !== undefined && value !== null && String(value).trim() !== "";
}

export function validateResearchRecord(type, record, workflowStatus = "draft", context = {}) {
  const errors = [];
  const submitting = workflowStatus === "submitted";

  if (type === "respondent") {
    if (!present(record.segmentCode)) errors.push("Choose a research segment.");
    if (!present(record.respondentType)) errors.push("Choose a respondent type.");
    if (submitting && record.consentStatus !== "granted") {
      errors.push("Consent must be granted before submission.");
    }
  }

  if (type === "session") {
    if (!present(record.respondentId)) errors.push("Choose a respondent.");
    if (!present(record.method)) errors.push("Choose a research method.");
    if (submitting && !present(record.unmetNeed)) errors.push("Record the unmet need before submission.");
  }

  if (type === "evidence") {
    if (!present(record.pmfLayer)) errors.push("Choose a PMF layer.");
    if (!present(record.title)) errors.push("Add an evidence title.");
    if (!present(record.evidenceText)) errors.push("Record the evidence or quote.");
    if (submitting && !present(record.sourceLink) && !present(record.sessionId)) {
      errors.push("Add a source link or session reference.");
    }
    if (submitting && !present(record.limitations)) {
      errors.push("Record the evidence limitations before submission.");
    }
    if (present(record.sourceLink) && !isSafeHttpUrl(record.sourceLink)) errors.push("Use an http(s) source link.");
  }

  if (type === "product_event") {
    if (!present(record.respondentId)) errors.push("Choose a product-test respondent.");
    if (!present(record.eventDate)) errors.push("Choose the event date.");
  }

  if (type === "value_exchange") {
    if (!present(record.respondentId)) errors.push("Choose a respondent.");
    if (!present(record.hardwarePrice)) errors.push("Record the tested hardware price.");
  }

  if (type === "observation") {
    if (!present(record.definitionId)) errors.push("Choose a matrix metric.");
    if (!present(record.segmentCode)) errors.push("Choose a research segment.");
    if (![record.numericValue, record.booleanValue, record.textValue].some(present)) {
      errors.push("Record an observation value.");
    }
    if (submitting && ![record.respondentId, record.sessionId, record.sourceLink].some(present)) {
      errors.push("Add a respondent, session, or source link before submission.");
    }
    if (present(record.sourceLink) && !isSafeHttpUrl(record.sourceLink)) errors.push("Use an http(s) source link.");
    const definition = (context.definitions || []).find((item) => item.id === record.definitionId);
    if (definition) {
      const valueFields = { numeric: "numericValue", boolean: "booleanValue", text: "textValue" };
      const incompatible = Object.entries(valueFields).some(([valueType, field]) => valueType !== definition.valueType && present(record[field]));
      if (incompatible) errors.push("Clear values that do not match the selected metric type.");
    }
  }

  if (["evidence", "observation"].includes(type) && present(record.sessionId)) {
    const session = (context.sessions || []).find((item) => item.id === record.sessionId);
    if (!session) errors.push("Choose a valid research session.");
    else if (present(record.respondentId) && session.respondentId !== record.respondentId) errors.push("Choose a session belonging to the selected respondent.");
  }

  return errors;
}

export function normalizeObservationValues(record, definition) {
  const normalized = { ...record };
  const valueFields = { numeric: "numericValue", boolean: "booleanValue", text: "textValue" };
  for (const [valueType, field] of Object.entries(valueFields)) {
    if (valueType !== definition?.valueType) normalized[field] = "";
  }
  return normalized;
}

function summarize(definition, observations, segmentCode, respondents = []) {
  const respondentById = new Map(respondents.map((respondent) => [respondent.id, respondent]));
  const values = observations.filter((item) => (
    item.definitionId === definition.id
    && item.segmentCode === segmentCode
    && item.workflowStatus === "approved"
    && (!item.respondentId || respondentById.get(item.respondentId)?.consentStatus === "granted")
  ));
  if (!values.length) return { display: "—", sampleSize: 0, value: null };

  if (definition.valueType === "boolean") {
    const trueCount = values.filter((item) => item.booleanValue === true).length;
    const value = (trueCount / values.length) * 100;
    return { display: `${Math.round(value)}%`, sampleSize: values.length, value };
  }

  if (definition.valueType === "numeric") {
    const numeric = values.map((item) => Number(item.numericValue)).filter(Number.isFinite);
    if (!numeric.length) return { display: "—", sampleSize: 0, value: null };
    const value = numeric.reduce((sum, item) => sum + item, 0) / numeric.length;
    return { display: value.toFixed(1), sampleSize: numeric.length, value };
  }

  const latest = values
    .map((item, index) => ({ item, index }))
    .filter(({ item }) => present(item.textValue))
    .sort((a, b) => {
      const timestampDifference = new Date(b.item.createdAt || 0).getTime() - new Date(a.item.createdAt || 0).getTime();
      return timestampDifference || a.index - b.index;
    })[0]?.item;
  return { display: latest?.textValue || "—", sampleSize: values.length, value: latest?.textValue || null };
}

export function buildLayerMatrices({ segments = [], definitions = [], observations = [], respondents = [] } = {}) {
  return Object.fromEntries(PMF_LAYERS.map((layer) => [
    layer.code,
    definitions.filter((definition) => definition.layer === layer.code).map((definition) => ({
      ...definition,
      values: Object.fromEntries(segments.map((segment) => [
        segment.code,
         summarize(definition, observations, segment.code, respondents),
      ])),
    })),
  ]));
}

export function buildPmfRecommendations({
  reviewQueue = [],
  samplePlan = [],
  evidence = [],
  respondents = [],
} = {}) {
  const recommendations = [];
  const respondentById = new Map(respondents.map((respondent) => [respondent.id, respondent]));

  if (reviewQueue.length) {
    recommendations.push({
      id: "review-backlog",
      type: "review",
      priority: reviewQueue.length >= 5 ? "critical" : "high",
      title: "Clear the evidence review queue",
      reason: `${reviewQueue.length} submitted record${reviewQueue.length === 1 ? " is" : "s are"} waiting for an administrator decision.`,
      action: "Review provenance, counterevidence, consent, and limitations before the next Gate decision.",
    });
  }

  samplePlan.filter((item) => Number(item.actual) < Number(item.target)).forEach((item) => {
    const gap = Number(item.target) - Number(item.actual);
    recommendations.push({
      id: `sample-${item.id || item.label}`,
      type: "sample",
      priority: gap >= Math.ceil(Number(item.target) / 2) ? "critical" : "high",
      title: `Close the ${item.label} sample gap`,
      reason: `${item.actual} approved samples are available against a target of ${item.target}.`,
      action: `Recruit and approve ${gap} additional qualified sample${gap === 1 ? "" : "s"}.`,
    });
  });

  PMF_LAYERS.forEach((layer) => {
    const approved = evidence.filter((item) => (
      item.pmfLayer === layer.code
      && item.workflowStatus === "approved"
      && (!item.respondentId || respondentById.get(item.respondentId)?.consentStatus === "granted")
    ));
    const contrary = approved.filter((item) => item.stance === "contradicting").length;
    if (approved.length >= 2 && contrary / approved.length >= 0.5) {
      recommendations.push({
        id: `contradiction-${layer.code}`,
        type: "contradiction",
        priority: "high",
        title: `Challenge the ${layer.name} hypothesis`,
        reason: `${contrary} of ${approved.length} approved records contradict the current hypothesis.`,
        action: "Narrow the segment or situation and collect targeted counterevidence before advancing.",
      });
    }
  });

  const consentRisks = respondents.filter((item) => ["withdrawn", "declined", "expired"].includes(item.consentStatus)).length;
  if (consentRisks) {
    recommendations.push({
      id: "consent-risk",
      type: "consent",
      priority: "critical",
      title: "Resolve consent restrictions",
      reason: `${consentRisks} respondent record${consentRisks === 1 ? " has" : "s have"} withdrawn, declined, or expired consent.`,
      action: "Exclude restricted material from current analysis and create a manual anonymization or purge task.",
    });
  }

  return recommendations;
}
