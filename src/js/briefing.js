const EMPTY_SUMMARY = Object.freeze({
  pendingReviews: 0,
  blockedWork: 0,
  overdueTasks: 0,
  overdueDeadlines: 0,
  approvedEvidence: 0,
  evidenceRespondents: 0,
  attentionCount: 0,
});

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function list(value, limit) {
  return (Array.isArray(value) ? value : []).slice(0, limit);
}

export function createBriefingState(input = {}) {
  return {
    scope: input.scope === "personal" ? "personal" : "team",
    project: input.project || null,
    summary: Object.fromEntries(Object.entries({ ...EMPTY_SUMMARY, ...(input.summary || {}) }).map(([key, value]) => [key, number(value)])),
    attention: list(input.attention, 12),
    deadlines: list(input.deadlines, 8),
    samplePlan: list(input.samplePlan, 12).map((item) => ({
      ...item,
      actual: item.derivationStatus === "derived" && item.actual != null ? number(item.actual) : null,
      target: number(item.target),
      derivationStatus: item.derivationStatus === "derived" ? "derived" : "unsupported",
    })),
    pmfChain: list(input.pmfChain, 5).map((item) => ({
      ...item,
      supportingCount: number(item.supportingCount),
      contradictingCount: number(item.contradictingCount),
      observationCount: number(item.observationCount),
      respondentCount: number(item.respondentCount),
    })),
    evidenceSummary: { ...(input.evidenceSummary || {}) },
    signals: list(input.signals, 8).map(({ changePercent: _changePercent, ...item }) => ({
      ...item,
      evidenceCount: number(item.evidenceCount),
      strength: number(item.strength),
    })),
    activity: list(input.activity, 12),
    generatedAt: input.generatedAt || null,
    timezone: input.timezone || "UTC",
    preview: Boolean(input.preview),
  };
}

export function briefingProgress(item = {}) {
  if (item.actual == null || number(item.target) <= 0) return null;
  return Math.min(100, Math.max(0, Math.round((number(item.actual) / number(item.target)) * 100)));
}

function countLabel(value, singular, plural = `${singular}s`) {
  return `${value} ${value === 1 ? singular : plural}`;
}

export function briefingRoleCopy(role, summary = {}, attentionCount = 0) {
  const pendingReviews = number(summary.pendingReviews);
  const blockedWork = number(summary.blockedWork);
  const overdueTasks = number(summary.overdueTasks);
  const total = number(attentionCount);
  if (role !== "admin" && total === 0) {
    return {
      eyebrow: "Your briefing",
      heading: "Your assigned work is clear",
      body: "No assigned reviews, blockers, or overdue tasks need attention right now.",
    };
  }
  const roleCopy = role === "admin" ? "Administrator briefing" : "Your briefing";
  return {
    eyebrow: roleCopy,
    heading: total === 0 ? "No decisions or follow-ups need attention" : `${total} ${total === 1 ? "item needs" : "items need"} a decision or follow-up`,
    body: `${countLabel(pendingReviews, "pending review")}, ${countLabel(blockedWork, "blocked item")}, and ${countLabel(overdueTasks, "overdue task")} ${role === "admin" ? "across this project" : "in your assigned work"}.`,
  };
}

export function briefingSourceDestination(item = {}) {
  const sourceType = String(item.sourceType || "").replace(/^project_/, "");
  const sourceId = item.sourceId || item.id || null;
  if (sourceType === "task") return { view: "today", tab: "tasks", task: sourceId };
  if (["milestone", "blocker", "risk", "decision"].includes(sourceType)) {
    return {
      view: "projects",
      tab: sourceType === "milestone" ? "milestones" : sourceType === "decision" ? "decisions" : sourceType === "risk" ? "risks" : "blockers",
      [sourceType]: sourceId,
    };
  }
  if (sourceType === "survey_version" || sourceType === "survey_submission") {
    return { view: "research", tab: "surveys", [sourceType === "survey_version" ? "version" : "response"]: sourceId, assetId: item.assetId || null };
  }
  if (sourceType === "pmf_layer") return { view: "research", tab: "analyze", layer: sourceId };
  const recordType = { session: "session", evidence: "evidence", respondent: "respondent", product_event: "product_event", value_exchange: "value_exchange", observation: "observation" }[sourceType];
  if (recordType) return { view: "research", tab: "collect", type: recordType, id: sourceId };
  if (sourceType === "crm_contact") return { view: "relationships", tab: "contacts", contact: sourceId };
  if (sourceType === "candidate") return { view: "relationships", tab: "outreach", section: "pipeline", candidate: sourceId };
  if (sourceType === "participant") return { view: "relationships", tab: "recruitment", participant: sourceId };
  return null;
}

export function briefingSampleDestination(item = {}) {
  if (item.derivationStatus !== "derived") return null;
  if (item.sourceKind === "approved_survey_submission" && item.surveyAssetId) return { view: "research", tab: "surveys", assetId: item.surveyAssetId };
  if (["approved_professional_respondent", "approved_consumer_session", "approved_product_event_respondent"].includes(item.sourceKind)) return { view: "research", tab: "collect" };
  return null;
}

export function createPreviewBriefing(dashboard = {}, role = "admin", displayName = "") {
  const tasks = dashboard.tasks || [];
  const assignedTasks = tasks.filter((task) => task.ownerName === displayName);
  const scopedTasks = role === "admin" ? tasks : (assignedTasks.length ? assignedTasks : [{
    id: "preview-personal-follow-up",
    title: "Confirm the next evidence handoff",
    objective: "Record the support needed before continuing assigned work.",
    ownerName: displayName,
    ownerInitials: displayName.split(/\s+/).map((part) => part[0]).join("").slice(0, 2),
    status: "revision_requested",
    priority: "high",
    dueDate: "2026-08-14",
  }]);
  const attention = scopedTasks
    .filter((task) => ["submitted", "resubmitted", "revision_requested", "blocked"].includes(task.status) || (task.dueDate && task.dueDate < "2026-08-13" && !["completed", "cancelled"].includes(task.status)))
    .map((task) => ({
      id: `preview-task-${task.id}`,
      sourceType: "task",
      sourceId: task.id,
      title: task.title,
      reason: task.status === "blocked" ? "Assigned task is blocked." : ["submitted", "resubmitted"].includes(task.status) ? "Submitted task is ready for review." : "Assigned task needs follow-up.",
      category: task.status === "blocked" ? "blocked" : ["submitted", "resubmitted"].includes(task.status) ? "review" : "follow_up",
      priority: task.priority || "medium",
      dueOn: task.dueDate || null,
    }));
  const evidence = (dashboard.evidence || []).filter((item) => item.workflowStatus === "approved");
  const groupedSignals = new Map();
  for (const item of evidence) {
    if (!item.topic) continue;
    const key = `${item.topic}:${item.stance}`;
    const current = groupedSignals.get(key) || { id: key, theme: item.topic, stance: item.stance, evidenceCount: 0, strength: 0 };
    current.evidenceCount += 1;
    current.strength += number(item.strength);
    groupedSignals.set(key, current);
  }
  const signals = [...groupedSignals.values()].map((item) => ({ ...item, strength: item.strength / item.evidenceCount }));
  return createBriefingState({
    scope: role === "admin" ? "team" : "personal",
    project: dashboard.project,
    summary: {
      attentionCount: attention.length,
      pendingReviews: scopedTasks.filter((task) => ["submitted", "resubmitted"].includes(task.status)).length,
      blockedWork: scopedTasks.filter((task) => task.status === "blocked").length,
      overdueTasks: scopedTasks.filter((task) => task.dueDate && task.dueDate < "2026-08-13" && !["completed", "cancelled"].includes(task.status)).length,
      approvedEvidence: evidence.length,
    },
    attention,
    samplePlan: dashboard.samplePlan || [],
    pmfChain: ["H1", "H2", "H3", "H4", "H5"].map((code, index) => ({
      id: `preview-${code}`,
      code,
      name: ["Need Truth", "Current Solution Gap", "Product Value", "Repeatability", "Value Exchange"][index],
      supportingCount: evidence.filter((item) => item.pmfLayer === code && item.stance === "supporting").length,
      contradictingCount: evidence.filter((item) => item.pmfLayer === code && item.stance === "contradicting").length,
    })),
    evidenceSummary: { approved: evidence.length },
    signals,
    activity: dashboard.activity || [],
    generatedAt: dashboard.generatedAt,
    preview: true,
  });
}
