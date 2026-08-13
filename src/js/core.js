export function pageUrl(base, page) {
  const normalizedBase = `/${String(base || "/").replace(/^\/+|\/+$/g, "")}`;
  const prefix = normalizedBase === "/" ? "" : normalizedBase;
  return `${prefix}/${String(page).replace(/^\/+/, "")}`;
}

export function localDateValue(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function routeForRole(role) {
  if (role === "admin") return "workspace.html";
  if (role === "intern") return "interns.html";
  return "login.html";
}

export function csvCell(value) {
  let text = String(value ?? "");
  if (/^[\u0000-\u0020]*[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export function safeHttpUrl(value) {
  const text = String(value || "").trim();
  if (!text) return "";
  try {
    return ["http:", "https:"].includes(new URL(text).protocol) ? text : "";
  } catch {
    return "";
  }
}

export function isSafeHttpUrl(value) {
  return Boolean(safeHttpUrl(value));
}

export function initials(name) {
  return String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("") || "AO";
}

export function readableError(reason, fallback) {
  if (!(reason instanceof Error)) return fallback;
  const value = reason.message;
  if (value.includes("TASK_TITLE_REQUIRED")) return "Enter a task title with at least three characters.";
  if (value.includes("ADMIN_REQUIRED")) return "Your administrator access could not be verified.";
  if (value.includes("ASSIGNEE_INVALID")) return "Choose an active AOI user for this task.";
  if (value.includes("EOD_STALE_WRITE")) return "This EOD brief changed in another session. Reload it before saving.";
  if (value.includes("EOD_ADMIN_EDIT_REASON_REQUIRED")) return "Add a short reason for the administrator change.";
  if (value.includes("EOD_ALREADY_COMPLETED")) return "This EOD brief is complete and can now be changed only by an administrator.";
  if (value.includes("TASK_CHECKPOINT_NOTE_REQUIRED")) return "Add a checkpoint note before completing or resubmitting this task.";
  if (value.includes("TASK_COMPLETION_PROGRESS_REQUIRED")) return "Set progress to 100% before completing this task.";
  if (value.includes("TASK_CHECKPOINT_LOCKED")) return "This task is locked after submission or completion.";
  if (value.includes("TASK_RESUBMISSION_INVALID")) return "Only a task sent back for revision can be resubmitted.";
  if (value.includes("TASK_TRANSITION_INVALID")) return "That task state change is not allowed from the current status.";
  if (value.includes("EOD_NOT_REQUIRED_TODAY")) return "EOD briefs are required Monday through Friday.";
  if (value.includes("EOD_")) return "Check every required EOD field and try again.";
  if (value.toLowerCase().includes("invalid login")) return "The email or password is incorrect.";
  return value || fallback;
}

export function clamp(value, min = 0, max = 100) {
  return Math.min(max, Math.max(min, Number(value) || 0));
}

export function scopePreviewDashboard(dashboard, role, displayName) {
  const copy = structuredClone(dashboard);
  const currentEod = (copy.dailyEodReportItems || []).find((brief) => brief.authorName === displayName && brief.briefDate === copy.dailyEod?.serverDate) || null;
  if (copy.dailyEod) {
    copy.dailyEod.myBrief = currentEod;
    copy.dailyEod.dueState = ["submitted", "completed"].includes(currentEod?.workflowStatus) ? currentEod.workflowStatus : "due";
  }
  if (role === "intern") {
    copy.tasks = copy.tasks.filter((task) => task.ownerName === displayName);
    copy.candidates = (copy.candidates || []).filter((candidate) => candidate.ownerName === displayName);
    copy.crmContacts = (copy.crmContacts || []).filter((contact) => contact.ownerName === displayName);
    const candidateIds = new Set((copy.candidates || []).map((candidate) => candidate.id));
    copy.evidenceRecords = (copy.evidenceRecords || []).filter((record) => candidateIds.has(record.candidateId));
    copy.outreachEvents = (copy.outreachEvents || []).filter((event) => candidateIds.has(event.candidateId));
    const contactIds = new Set((copy.crmContacts || []).map((contact) => contact.id));
    copy.crmActivity = (copy.crmActivity || []).filter((activity) => contactIds.has(activity.contactId));
    copy.participantRecruitment = (copy.participantRecruitment || []).filter((item) => item.ownerName === displayName);
    const visibleResearch = (record) => record.workflowStatus === "approved" || record.assignedToName === displayName;
    copy.respondents = (copy.respondents || []).filter(visibleResearch);
    const respondentIds = new Set(copy.respondents.map((record) => record.id));
    copy.sessions = (copy.sessions || []).filter((record) => visibleResearch(record) && respondentIds.has(record.respondentId));
    copy.evidence = (copy.evidence || []).filter((record) => visibleResearch(record) && (!record.respondentId || respondentIds.has(record.respondentId)));
    copy.productEvents = (copy.productEvents || []).filter((record) => visibleResearch(record) && respondentIds.has(record.respondentId));
    copy.valueExchange = (copy.valueExchange || []).filter((record) => visibleResearch(record) && respondentIds.has(record.respondentId));
    copy.observations = (copy.observations || []).filter((record) => visibleResearch(record) && (!record.respondentId || respondentIds.has(record.respondentId)));
    copy.reviewQueue = (copy.reviewQueue || []).filter((record) => record.assignedToName === displayName);
    copy.dailyEodReportItems = (copy.dailyEodReportItems || []).filter((brief) => brief.authorName === displayName);
    if (copy.dailyEod) copy.dailyEod.teamToday = [];
  }
  return copy;
}
