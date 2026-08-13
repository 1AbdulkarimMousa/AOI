const ACTIONS = Object.freeze({
  milestone: {
    intern: { active: ["submit", "block"], blocked: ["unblock"], revision_requested: ["submit"] },
    admin: { draft: ["activate", "cancel"], active: ["submit", "block", "cancel"], blocked: ["unblock", "cancel"], revision_requested: ["submit", "cancel"], submitted: ["revise", "approve"], approved: ["complete"] },
  },
  blocker: {
    intern: { open: ["acknowledge", "start_resolving", "resolve", "escalate"], acknowledged: ["start_resolving", "resolve", "escalate"], resolving: ["resolve", "escalate"], resolved: ["reopen"] },
    admin: { open: ["acknowledge", "start_resolving", "resolve", "escalate"], acknowledged: ["start_resolving", "resolve", "escalate"], resolving: ["resolve", "escalate"], resolved: ["reopen"] },
  },
  risk: {
    intern: { identified: ["assess"], assessing: ["mitigate"], mitigating: ["monitor"], monitoring: ["close"] },
    admin: { identified: ["assess", "accept"], assessing: ["mitigate", "accept"], mitigating: ["monitor", "accept"], monitoring: ["accept", "close"] },
  },
  decision: {
    intern: { draft: ["submit"], revision_requested: ["resubmit"] },
    admin: { draft: ["submit"], revision_requested: ["resubmit"], submitted: ["request_revision", "reject", "approve"], resubmitted: ["request_revision", "reject", "approve"], approved: ["supersede"] },
  },
});

export const PROJECT_TABS = Object.freeze(["overview", "milestones", "blockers", "risks", "decisions"]);
export const PROJECT_RECORD_PARAMS = Object.freeze({ milestones: "milestone", blockers: "blocker", risks: "risk", decisions: "decision" });

export function activeProjectAccess(context = {}) {
  const organization = (context.organizations || []).find((item) => item.id === context.selectedOrganizationId) || {};
  return {
    organizationId: context.selectedOrganizationId || organization.id || null,
    organizationName: organization.name || context.organizationName || "",
    role: organization.role || organization.organizationRole || organization.organization_role || context.role || "intern",
    isOwner: organization.isOwner ?? organization.is_owner ?? context.isOwner ?? false,
  };
}

export function ensureProjectMutationNonce(pending, key, crypto = globalThis.crypto) {
  pending[key] ||= crypto.randomUUID();
  return pending[key];
}

export function projectTabNavigation(tabs, current, key) {
  const index = tabs.indexOf(current);
  if (index < 0 || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(key)) return null;
  if (key === "Home") return tabs[0];
  if (key === "End") return tabs.at(-1);
  return tabs[(index + (key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length];
}

function memberMap(members = []) {
  return new Map(members.map((member) => [member.userId || member.user_id, member.displayName || member.display_name]));
}

function normalizeRecord(recordType, record = {}, members = []) {
  const names = memberMap(members);
  const ownerId = record.ownerId || record.owner_id || record.resolutionOwnerId || record.resolution_owner_id || "";
  const common = {
    ...record,
    ownerId,
    ownerName: record.ownerName || names.get(ownerId) || "",
    nextAction: record.nextAction ?? record.next_action ?? "",
    dueDate: record.dueDate ?? record.nextActionDue ?? record.next_action_due ?? "",
    updatedAt: record.updatedAt ?? record.updated_at ?? null,
  };
  if (recordType === "milestone") return {
    ...common,
    outcome: record.outcome ?? record.intendedOutcome ?? record.intended_outcome ?? "",
    plannedDate: record.plannedDate ?? record.plannedFinish ?? record.planned_finish ?? "",
    progress: Number(record.progress ?? record.progressPercent ?? record.progress_percent) || 0,
    acceptanceCriteria: record.acceptanceCriteria ?? record.acceptance_criteria ?? "",
  };
  if (recordType === "blocker") return {
    ...common,
    blockingParty: record.blockingParty ?? record.blocking_party ?? "",
    expectedResolutionDate: record.expectedResolutionDate ?? record.expected_resolution_date ?? "",
    blockedSince: record.blockedSince ?? record.blocked_since ?? record.created_at ?? "",
    escalated: record.escalated ?? Boolean(record.escalated_at),
  };
  if (recordType === "risk") return {
    ...common,
    trigger: record.trigger ?? record.triggerCondition ?? record.trigger_condition ?? "",
    reviewDate: record.reviewDate ?? record.review_date ?? "",
    acceptanceRationale: record.acceptanceRationale ?? record.acceptance_rationale ?? "",
  };
  return {
    ...common,
    decisionMakerId: record.decisionMakerId ?? record.decision_maker_id ?? "",
    decisionMakerName: record.decisionMakerName || names.get(record.decisionMakerId || record.decision_maker_id) || "",
    expectedImpact: record.expectedImpact ?? record.expected_impact ?? "",
  };
}

export function normalizeProjectSnapshot(snapshot = {}) {
  const members = (snapshot.members || []).map((member) => ({ ...member, updatedAt: member.updatedAt ?? member.updated_at ?? null }));
  const names = memberMap(members);
  const managerId = snapshot.project?.managerId || snapshot.project?.manager_id;
  return {
    ...snapshot,
    project: snapshot.project ? { ...snapshot.project, managerName: snapshot.project.managerName || names.get(managerId) || "" } : null,
    members,
    milestones: (snapshot.milestones || []).map((record) => normalizeRecord("milestone", record, members)),
    blockers: (snapshot.blockers || []).map((record) => normalizeRecord("blocker", record, members)),
    risks: (snapshot.risks || []).map((record) => normalizeRecord("risk", record, members)),
    decisions: (snapshot.decisions || []).map((record) => normalizeRecord("decision", record, members)),
    activity: (snapshot.activity || []).map((event) => ({ ...event, actorName: event.actorName || names.get(event.actor_id) || "AOI", occurredAt: event.occurredAt || event.created_at })),
    eligibleOrganizationMembers: (snapshot.eligibleOrganizationMembers || snapshot.eligible_organization_members || []).map((member) => ({
      userId: member.userId || member.user_id,
      displayName: member.displayName || member.display_name || "Unavailable member",
      role: member.role || "member",
      active: member.active !== false,
      projectMemberUpdatedAt: member.projectMemberUpdatedAt ?? member.project_member_updated_at ?? null,
    })),
  };
}

export function mergeProjectSelection(context = {}, selection = {}) {
  return { ...context, ...selection, organizations: context.organizations || [] };
}

export function normalizeProjectDetail(recordType, detail = {}, members = []) {
  const record = normalizeRecord(recordType, detail.record || detail, members);
  const names = memberMap(members);
  const rawEvidence = Array.isArray(detail.evidence)
    ? detail.evidence
    : [...(detail.evidence?.supporting || []), ...(detail.evidence?.contradicting || detail.evidence?.contradictory || [])];
  const evidence = rawEvidence.map((item) => ({
    ...item,
    evidenceId: item.evidenceId ?? item.evidence_id ?? item.sourceId ?? item.source_id ?? "",
    relevanceNote: item.relevanceNote ?? item.relevance_note ?? "",
  }));
  const snapshots = (detail.snapshots || []).map((snapshot) => {
    const content = snapshot.content || snapshot.snapshotData || snapshot.snapshot_data || snapshot;
    const snapshotEvidence = Array.isArray(content.evidence) ? content.evidence.map((item) => ({ ...item, evidenceId: item.evidenceId ?? item.sourceId ?? item.evidence_id ?? "" })) : [];
    return {
      ...snapshot,
      content,
      evidence: {
        supporting: snapshotEvidence.filter((item) => item.stance === "supporting"),
        contradicting: snapshotEvidence.filter((item) => ["contradicting", "contradictory"].includes(item.stance)),
      },
    };
  });
  return {
    ...record,
    history: (detail.history || []).map((entry) => ({ ...entry, actorName: entry.actorName || names.get(entry.actor_id) || "AOI", occurredAt: entry.occurredAt || entry.created_at })),
    comments: detail.comments || [],
    evidence: { supporting: evidence.filter((item) => item.stance === "supporting"), contradicting: evidence.filter((item) => ["contradicting", "contradictory"].includes(item.stance)) },
    evidenceLinks: evidence.map((item) => ({ evidenceId: item.evidenceId, stance: item.stance === "contradictory" ? "contradicting" : item.stance, relevanceNote: item.relevanceNote })),
    snapshots,
    collaboration: detail.collaboration || { comments: detail.comments || [], sourceType: recordType, sourceId: record.id },
  };
}

export function serializeProjectRecord(recordType, draft = {}, projectId) {
  const common = { projectId };
  if (recordType === "milestone") return { ...common, title: draft.title, intendedOutcome: draft.outcome, ownerId: draft.ownerId, plannedFinish: draft.plannedDate, progressPercent: Number(draft.progress) || 0, acceptanceCriteria: draft.acceptanceCriteria, nextAction: draft.nextAction, nextActionDue: draft.dueDate };
  if (recordType === "blocker") return { ...common, title: draft.title, description: draft.description, resolutionOwnerId: draft.ownerId || draft.resolutionOwnerId, blockingParty: draft.blockingParty, expectedResolutionDate: draft.expectedResolutionDate, impact: draft.impact, nextAction: draft.nextAction, nextActionDue: draft.dueDate };
  if (recordType === "risk") return { ...common, statement: draft.statement, ownerId: draft.ownerId, probability: Number(draft.probability), impact: Number(draft.impact), triggerCondition: draft.trigger, mitigation: draft.mitigation, nextAction: draft.nextAction, nextActionDue: draft.dueDate, reviewDate: draft.reviewDate };
  if (recordType === "decision") {
    const payload = { ...common, title: draft.title, statement: draft.statement, ownerId: draft.ownerId, decisionMakerId: draft.decisionMakerId, alternatives: Array.isArray(draft.alternatives) ? draft.alternatives : String(draft.alternatives || "").split(/[\n;]+/).map((value) => value.trim()).filter(Boolean), rationale: draft.rationale, expectedImpact: draft.expectedImpact };
    if (Object.hasOwn(draft, "evidenceLinks")) payload.evidenceLinks = draft.evidenceLinks;
    return payload;
  }
  return { ...common, ...draft };
}

export function createProjectRecordDraft(recordType, defaults = {}) {
  const ownerId = defaults.ownerId || "";
  const drafts = {
    project: { name: "", code: "", objective: "", sponsorName: "", managerId: ownerId, plannedStart: "", plannedFinish: "", health: "on_track", status: "planning" },
    milestone: { title: "", outcome: "", ownerId, plannedDate: "", progress: 0, acceptanceCriteria: "", nextAction: "", dueDate: "", status: "draft" },
    blocker: { title: "", description: "", resolutionOwnerId: ownerId, ownerId, blockingParty: "", expectedResolutionDate: "", impact: "medium", nextAction: "", dueDate: "", status: "open" },
    risk: { statement: "", ownerId, probability: 1, impact: 1, trigger: "", mitigation: "", nextAction: "", dueDate: "", reviewDate: "", acceptanceRationale: "", status: "identified" },
    decision: { title: "", statement: "", ownerId, decisionMakerId: "", alternatives: "", rationale: "", expectedImpact: "", status: "draft", evidenceLinks: [] },
  };
  return structuredClone(drafts[recordType] || drafts.milestone);
}

export function hydrateProjectRecordDraft(recordType, record = null, defaults = {}) {
  const draft = { ...createProjectRecordDraft(recordType, defaults), ...(record || {}) };
  if (recordType === "decision" && record && !Object.hasOwn(record, "evidenceLinks")) delete draft.evidenceLinks;
  return draft;
}

export function riskScorePresentation(score) {
  const value = Number(score);
  if (!Number.isFinite(value) || score == null) return { label: "Not scored", tone: "muted" };
  if (value >= 20) return { label: "Critical", tone: "rose" };
  if (value >= 15) return { label: "High", tone: "orange" };
  if (value >= 6) return { label: "Moderate", tone: "blue" };
  return { label: "Low", tone: "teal" };
}

export function projectRecordActions(recordType, status, role) {
  return [...(ACTIONS[recordType]?.[role]?.[status] || [])];
}

export function isProjectRecordEditable(recordType, status, role, ownerId, userId, isNew = false) {
  if (isNew) return role === "admin" || ["blocker", "risk"].includes(recordType);
  if (["submitted", "resubmitted", "approved", "completed", "resolved", "accepted", "closed", "rejected", "superseded", "cancelled"].includes(status)) return false;
  if (role === "admin" || recordType === "blocker") return true;
  return ownerId === userId;
}

export function filterProjectRecords(records = [], filters = {}) {
  const query = String(filters.query || "").trim().toLowerCase();
  return records.filter((record) => {
    if (filters.ownerId && record.ownerId !== filters.ownerId) return false;
    if (filters.status && filters.status !== "all" && record.status !== filters.status) return false;
    if (filters.overdue && !(record.dueDate && record.dueDate < filters.today)) return false;
    return !query || [record.title, record.statement, record.outcome, record.ownerName, record.status].some((value) => String(value || "").toLowerCase().includes(query));
  });
}

export function sortProjectRecords(records = [], sort = "dueDate") {
  const copy = [...records];
  if (sort === "riskScore") return copy.sort((a, b) => (Number(b.score) || 0) - (Number(a.score) || 0) || String(a.title || a.statement).localeCompare(String(b.title || b.statement)));
  return copy.sort((a, b) => String(a.dueDate || a.reviewDate || "9999-12-31").localeCompare(String(b.dueDate || b.reviewDate || "9999-12-31")) || String(a.title || a.statement).localeCompare(String(b.title || b.statement)));
}

export function scopePreviewProject(role = "admin") {
  const project = { id: "demo-project", code: "LANTERN-01", name: "Lantern Trial Workspace", objective: "Coordinate a fictional community event with traceable owners and decisions.", health: "at_risk", healthLabel: "At risk", status: "active", sponsorName: "Northstar Sandbox Cooperative", managerName: "Avery Example", plannedStart: "2026-07-13", plannedFinish: "2026-09-25", updatedAt: "2026-08-12T12:00:00Z" };
  const milestone = { id: "preview-milestone-1", title: "Event readiness checkpoint", outcome: "Owners, venue, and documentation are ready for the fictional event.", ownerId: role === "intern" ? "m1" : "preview-admin", ownerName: role === "intern" ? "Morgan Example" : "Avery Example", status: "active", plannedDate: "2026-08-21", dueDate: "2026-08-18", progress: 68, acceptanceCriteria: "Venue, schedule, and accessibility review have named owners.", nextAction: "Close the remaining venue blocker.", updatedAt: "2026-08-12T12:00:00Z" };
  const blocker = { id: "preview-blocker-1", title: "Accessible venue confirmation is late", description: "The fictional venue has not returned its access checklist.", resolutionOwnerId: "m1", ownerId: "m1", ownerName: "Morgan Example", impact: "high", status: "resolving", blockedSince: "2026-08-06", expectedResolutionDate: "2026-08-15", dueDate: "2026-08-15", nextAction: "Confirm the alternate sandbox venue.", escalated: true, updatedAt: "2026-08-12T12:00:00Z" };
  const risk = { id: "preview-risk-1", statement: "Volunteer feedback may overrepresent experienced coordinators.", title: "Experience sampling bias", ownerId: "m1", ownerName: "Morgan Example", probability: 4, impact: 4, score: 16, trigger: "More than 60% of reviewers have coordinated prior events.", mitigation: "Invite first-time volunteers and review the mix weekly.", nextAction: "Confirm the first-time volunteer sample.", dueDate: "2026-08-16", reviewDate: "2026-08-16", status: "monitoring", updatedAt: "2026-08-12T12:00:00Z" };
  const decision = { id: "preview-decision-1", title: "Keep clinician context in the pilot readout", statement: "Pilot results will pair product findings with explicit clinician-context limitations.", ownerId: "m1", ownerName: "Kayla Tillmon", decisionMakerName: "AOI Administrator", alternatives: "Publish a consumer-only score; delay all reporting until clinician recruitment closes.", rationale: "The current evidence supports learning now, but does not support context-free clinical conclusions.", expectedImpact: "The pilot can proceed without overstating actionability.", status: "submitted", updatedAt: "2026-08-12T12:00:00Z", evidenceLinks: [{ evidenceId: "e1", stance: "supporting", relevanceNote: "Direct family signal" }, { evidenceId: "e2", stance: "contradicting", relevanceNote: "Clinical limitation" }], evidence: { supporting: [{ id: "e1", evidenceId: "e1", title: "Families recognize visible change", provenance: "Approved interview synthesis", limitations: "Recruited caregiver segment", relevanceNote: "Direct family signal" }], contradicting: [{ id: "e2", evidenceId: "e2", title: "Action selection still needs clinician context", provenance: "Approved orthodontic interview", limitations: "One participant", relevanceNote: "Clinical limitation" }] }, snapshots: [{ id: "preview-snapshot-1", version: 1, approved_at: "2026-08-10T12:00:00Z", content: { title: "Keep clinician context in the pilot readout", statement: "Pilot findings retain explicit clinical limitations.", alternatives: ["Publish a consumer-only score"], rationale: "The evidence supports learning without context-free claims.", expectedImpact: "A useful but bounded pilot readout." }, evidence: { supporting: [{ sourceId: "e1", stance: "supporting", title: "Families recognize visible change", provenance: "Approved interview synthesis", limitations: "Recruited caregiver segment" }], contradicting: [{ sourceId: "e2", stance: "contradicting", title: "Action selection still needs clinician context", provenance: "Approved orthodontic interview", limitations: "One participant" }] } }], history: [{ id: "h1", action: "submitted", actorName: "Kayla Tillmon", note: "Ready for governance review." }] };
  Object.assign(decision, {
    title: "Keep access context in the event readout",
    statement: "The fictional event readout will state unresolved accessibility limitations.",
    ownerName: "Morgan Example",
    decisionMakerName: "Avery Example",
    alternatives: "Publish without limitations; delay the fictional readout.",
    rationale: "The synthetic evidence supports planning while keeping limitations visible.",
    expectedImpact: "The team can proceed without overstating readiness.",
    evidence: {
      supporting: [{ id: "e1", evidenceId: "e1", title: "Main hall route documented", provenance: "Synthetic checklist", limitations: "Preview fixture", relevanceNote: "Venue checklist" }],
      contradicting: [{ id: "e2", evidenceId: "e2", title: "Side entrance remains unverified", provenance: "Synthetic walkthrough", limitations: "Preview fixture", relevanceNote: "Unresolved access route" }],
    },
    snapshots: [],
    history: [{ id: "h1", actorName: "Avery Example", action: "submit", note: "Ready for governance review", occurredAt: "2026-08-12T12:00:00Z" }],
  });
  return {
    context: { organizations: [{ id: "demo-org", name: "Northstar Sandbox Cooperative", role, isOwner: role === "admin", projects: [project] }], projects: [project], selectedOrganizationId: "demo-org", selectedProjectId: project.id, role, isOwner: role === "admin", selectionRequired: false, preview: true },
    snapshot: { project, members: [{ userId: "preview-admin", displayName: "Avery Example", role: "admin" }, { userId: "m1", displayName: "Morgan Example", role: "intern" }], eligibleOrganizationMembers: [{ userId: "m2", displayName: "Rowan Example", role: "intern", active: true }], milestones: [milestone], blockers: [blocker], risks: [risk], decisions: [decision], activity: [{ id: "pa1", actorName: "Morgan Example", action: "updated risk mitigation", occurredAt: "2026-08-12T11:30:00Z" }], generatedAt: "2026-08-12T12:00:00Z", preview: true },
  };
}
