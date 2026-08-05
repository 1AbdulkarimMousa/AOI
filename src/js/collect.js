const COLLECT_TYPES = [
  ["evidence", "evidence"],
  ["sessions", "session"],
  ["productEvents", "product_event"],
  ["valueExchange", "value_exchange"],
  ["observations", "observation"],
  ["respondents", "respondent"],
];

const LEVEL_THRESHOLDS = [0, 250, 600, 1000, 1500, 2500, 4000, 6000];

function recordDate(record) {
  return record.updatedAt || record.createdAt || record.observedAt || record.eventDate || record.sessionDate || "";
}

function recordTitle(recordType, record) {
  if (recordType === "respondent") return record.respondentCode || record.externalId || "Respondent";
  if (recordType === "session") return record.method || "Research session";
  if (recordType === "evidence") return record.title || "Evidence record";
  if (recordType === "product_event") return record.triggerType || "Product event";
  if (recordType === "value_exchange") return record.commitmentType || "Value exchange";
  return record.metricLabel || record.label || "PMF observation";
}

export function buildCollectIndex(snapshot = {}) {
  return COLLECT_TYPES.flatMap(([key, recordType]) => (snapshot[key] || []).map((record) => {
    const identityTrail = [record.recruitmentCode, ...(record.externalIds || [])].filter(Boolean).join(" · ");
    return {
      ...record,
      recordType,
      title: recordTitle(recordType, record),
      respondentCode: record.respondentCode || record.externalId || "",
      identityTrail,
      recordDate: recordDate(record),
    };
  }));
}

export function filterCollectRecords(records, { type = "all", status = "all", query = "" } = {}) {
  const value = query.trim().toLowerCase();
  return records.filter((record) => {
    const matchesType = type === "all" || record.recordType === type;
    const matchesStatus = status === "all" || record.workflowStatus === status;
    const matchesQuery = !value || [
      record.title,
      record.respondentCode,
      record.recruitmentCode,
      record.identityTrail,
      record.segmentName,
      record.ownerName,
    ].some((field) => String(field || "").toLowerCase().includes(value));
    return matchesType && matchesStatus && matchesQuery;
  });
}

export function conversionReadiness(record = {}) {
  if (record.respondentId) {
    return { ready: false, reasons: ["This prospect is already connected to a respondent."] };
  }
  const reasons = [];
  if (!["screening", "scheduled", "completed"].includes(record.status)) reasons.push("Complete screening.");
  if (!record.segment) reasons.push("Choose a segment.");
  if (record.consentStatus !== "granted") reasons.push("Record granted consent.");
  return { ready: reasons.length === 0, reasons };
}

export function gamificationLevel(xp = 0) {
  const currentXp = Math.max(0, Number(xp) || 0);
  let thresholdIndex = LEVEL_THRESHOLDS.findLastIndex((threshold) => currentXp >= threshold);
  if (thresholdIndex < 0) thresholdIndex = 0;
  const levelFloor = LEVEL_THRESHOLDS[thresholdIndex];
  const nextLevelXp = LEVEL_THRESHOLDS[thresholdIndex + 1] ?? null;
  if (nextLevelXp === null) {
    return { level: thresholdIndex + 1, currentXp, levelFloor, nextLevelXp, progress: 100, maxLevel: true };
  }
  const span = Math.max(1, nextLevelXp - levelFloor);
  return {
    level: thresholdIndex + 1,
    currentXp,
    levelFloor,
    nextLevelXp,
    progress: Math.round(((currentXp - levelFloor) / span) * 100),
  };
}

export function prefillResearchForm(form, respondent) {
  if (!respondent?.id) return { ...form };
  return {
    ...form,
    respondentId: respondent.id,
    segmentCode: respondent.segmentCode || form.segmentCode,
  };
}

export function restoreResearchDrafts(defaults, stored) {
  if (!stored || typeof stored !== "object") return structuredClone(defaults);
  return Object.fromEntries(Object.entries(defaults).map(([recordType, defaultForm]) => {
    const savedForm = stored[recordType];
    if (!savedForm || typeof savedForm !== "object") return [recordType, { ...defaultForm }];
    const recognized = Object.fromEntries(Object.keys(defaultForm)
      .filter((key) => Object.hasOwn(savedForm, key))
      .map((key) => [key, savedForm[key]]));
    return [recordType, { ...defaultForm, ...recognized }];
  }));
}
