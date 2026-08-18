const requiredTextFields = [
  ["movedOutcome", "Add the tangible outcome that moved today."],
  ["evidenceGathered", "Add the evidence gathered today."],
  ["deliverablesCompleted", "Add the deliverables completed today."],
  ["keyInsight", "Add the key insight or discovery."],
  ["currentBlocker", "Add the current blocker or enter None."],
  ["blockerImpact", "Add the blocker impact or enter None."],
  ["proposedSolution", "Add the proposed solution or enter None."],
  ["executiveRequest", "Add the executive request or enter None."],
];

export function createDailyEodDraft(values = {}) {
  return {
    id: null,
    engagementManagerId: "",
    personInChargeId: "",
    movedOutcome: "",
    evidenceGathered: "",
    deliverablesCompleted: "",
    keyInsight: "",
    currentBlocker: "",
    blockerImpact: "",
    proposedSolution: "",
    executiveOwners: [],
    executiveRequest: "",
    tomorrowPriorities: ["", "", ""],
    projectStatus: "on_track",
    evidenceLinks: [{ sourceType: "onedrive", label: "", url: "" }],
    workflowStatus: "draft",
    updatedAt: null,
    ...values,
    executiveOwners: [...(values.executiveOwners || [])],
    tomorrowPriorities: [0, 1, 2].map((index) => values.tomorrowPriorities?.[index] || ""),
    evidenceLinks: (values.evidenceLinks?.length ? values.evidenceLinks : [{ sourceType: "onedrive", label: "", url: "" }]).map((link) => ({ ...link })),
  };
}

export function validateDailyEodFields(brief) {
  const errors = {};
  if (!String(brief.engagementManagerId || "").trim()) errors.engagementManagerId = "Choose the Engagement Manager.";
  if (!String(brief.personInChargeId || "").trim()) errors.personInChargeId = "Choose the Person In Charge.";
  for (const [field, message] of requiredTextFields) {
    if (!String(brief[field] || "").trim()) errors[field] = message;
  }
  const owners = brief.executiveOwners || [];
  if (!owners.length || (owners.includes("None") && owners.length > 1)) errors.executiveOwners = "Choose executive support or None.";
  const priorities = brief.tomorrowPriorities || [];
  if (priorities.length !== 3 || priorities.some((priority) => !String(priority || "").trim())) errors.tomorrowPriorities = "Add exactly three priorities for tomorrow.";
  if (!["on_track", "at_risk", "off_track"].includes(brief.projectStatus)) errors.projectStatus = "Choose the project status.";
  const evidence = (brief.evidenceLinks || []).filter((link) => String(link.label || "").trim() || String(link.url || "").trim());
  const validEvidence = evidence.length > 0 && evidence.every((link) => {
    if (!String(link.label || "").trim()) return false;
    try {
      return ["http:", "https:"].includes(new URL(link.url).protocol);
    } catch {
      return false;
    }
  });
  if (!validEvidence) errors.evidenceLinks = "Add at least one labeled http(s) evidence link.";
  return errors;
}

export function createDailyEodDraftKey(userId, projectId, serverDate) {
  if (![userId, projectId, serverDate].every((value) => String(value || "").trim())) return "";
  return `aoi:eod-draft:${userId}:${projectId}:${serverDate}`;
}

export function readDailyEodDraft(storage, key) {
  if (!storage || !key) return null;
  try {
    const value = JSON.parse(storage.getItem(key));
    return value?.draft && value?.savedAt ? { ...value, draft: createDailyEodDraft(value.draft) } : null;
  } catch {
    return null;
  }
}

export function writeDailyEodDraft(storage, key, draft, savedAt = new Date().toISOString()) {
  if (!storage || !key) return;
  try {
    storage.setItem(key, JSON.stringify({ savedAt, draft: createDailyEodDraft(draft) }));
  } catch {
    return false;
  }
  return true;
}

export function isLegacyEvidenceException(brief) {
  return brief?.workflowStatus === "submitted"
    && brief?.legacyEvidenceMissing === true
    && !(brief.evidenceLinks || []).length;
}

export function toggleExecutiveOwner(selected, owner) {
  if (owner === "None") return ["None"];
  const current = (selected || []).filter((value) => value !== "None");
  return current.includes(owner) ? current.filter((value) => value !== owner) : [...current, owner];
}

export function filterDailyEodTeam(team, filter) {
  if (!filter || filter === "all") return team || [];
  if (filter === "missing") return (team || []).filter((member) => ["missing", "draft"].includes(member.workflowStatus));
  return (team || []).filter((member) => member.workflowStatus === filter);
}

export function dailyEodAttentionCount(snapshot, role, currentUserId = null) {
  const ownDue = ["due", "overdue"].includes(snapshot?.dueState) ? 1 : 0;
  if (role !== "admin") return ownDue;
  const teamAttention = (snapshot?.teamToday || []).filter((member) => {
    if (currentUserId && member.userId === currentUserId && ownDue) return false;
    return ["missing", "draft", "submitted"].includes(member.workflowStatus);
  }).length;
  return ownDue + teamAttention;
}

export function formatDailyEodTimestamp(value, locale = "en", timeZone = "UTC") {
  if (!value) return "";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "";
  return new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone,
    timeZoneName: "short",
  }).format(parsed);
}
