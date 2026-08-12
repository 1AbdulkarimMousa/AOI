const EMPTY_COUNTS = Object.freeze({
  needsAction: 0,
  waiting: 0,
  mentioned: 0,
  following: 0,
  recentlyResolved: 0,
  systemAttention: 0,
});

const BUCKET_LABELS = Object.freeze({
  needs_action: "Needs action",
  waiting: "Waiting on others",
  mentioned: "Mentioned",
  following: "Following",
  recently_resolved: "Recently resolved",
  system_attention: "System attention",
});

export function createInboxState(input = {}) {
  return {
    bucket: input.bucket || "needs_action",
    projectId: input.projectId || null,
    counts: { ...EMPTY_COUNTS, ...(input.counts || {}) },
    items: Array.isArray(input.items) ? input.items : [],
    generatedAt: input.generatedAt || null,
  };
}

export function inboxBucketLabel(bucket) {
  return BUCKET_LABELS[bucket] || "Needs action";
}

export function inboxRoleCopy(access = {}) {
  if (access.role === "admin" && access.isOwner) {
    return { eyebrow: "Owner workspace", heading: "Governance and escalations requiring your authority", body: "Resolve access, consent, security, and ownership decisions without losing their source history." };
  }
  if (access.role === "admin") {
    return { eyebrow: "Administrator workspace", heading: "Review queues and team decisions", body: "Approve submitted work, return clear revision guidance, and unblock assignments from their source records." };
  }
  return { eyebrow: "Your work inbox", heading: "Assigned actions and revision guidance", body: "Complete the next valid action, keep evidence attached, and make blockers visible to the team." };
}

export function unreadInboxCount(inbox = {}) {
  return (inbox.items || []).filter((item) => !item.readAt && !item.resolvedAt).length;
}

export function inboxCount(inbox, bucket) {
  const key = {
    needs_action: "needsAction",
    waiting: "waiting",
    mentioned: "mentioned",
    following: "following",
    recently_resolved: "recentlyResolved",
    system_attention: "systemAttention",
  }[bucket];
  return Number(inbox?.counts?.[key]) || 0;
}

export function projectSourceLabel(sourceType) {
  return {
    project_milestone: "Project milestone",
    project_blocker: "Project blocker",
    project_risk: "Project risk",
    project_decision: "Project decision",
    milestone: "Project milestone",
    blocker: "Project blocker",
    risk: "Project risk",
    decision: "Project decision",
  }[sourceType] || String(sourceType || "Source record").replaceAll("_", " ");
}
