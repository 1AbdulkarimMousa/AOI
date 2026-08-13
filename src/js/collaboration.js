import { createWorkComment, followWorkSource, handoffWork, reviseWorkComment } from "./api.js";

export function canonicalWorkSourceType(sourceType) {
  return String(sourceType || "").replace(/^project_/, "");
}

function normalizeMember(member = {}) {
  return { userId: member.userId ?? member.user_id ?? "", displayName: member.displayName ?? member.display_name ?? "Team member", role: member.role ?? member.role_name ?? "member", active: member.active !== false };
}

function normalizeRevision(revision = {}) {
  return { ...revision, revision: Number(revision.revision) || 1, body: revision.body || "", changeReason: revision.changeReason ?? revision.change_reason ?? "", editorId: revision.editorId ?? revision.editor_id ?? "", editorName: revision.editorName ?? revision.editor_name ?? "Team member", createdAt: revision.createdAt ?? revision.created_at ?? null };
}

function normalizeComment(comment = {}) {
  return {
    ...comment,
    authorId: comment.authorId ?? comment.author_id ?? "",
    authorName: comment.authorName ?? comment.author_display_name ?? comment.author_name ?? "Team member",
    authorRole: comment.authorRole ?? comment.author_role ?? "member",
    createdAt: comment.createdAt ?? comment.created_at ?? null,
    editedAt: comment.editedAt ?? comment.edited_at ?? null,
    revisionCount: Number(comment.revisionCount ?? comment.revision_count ?? comment.current_revision) || 1,
    canRevise: Boolean(comment.canRevise ?? comment.can_revise),
    revisions: (comment.revisions || []).map(normalizeRevision).sort((a, b) => a.revision - b.revision),
  };
}

export function eligibleCollaborationRecipients(collaborators = [], currentUserId = null) {
  return collaborators.map(normalizeMember).filter((member) => member.active && member.userId && member.userId !== currentUserId);
}

export function normalizeCollaborationProjection(input = {}, { currentUserId = null, density = "full" } = {}) {
  const allComments = (input.comments || []).map(normalizeComment).sort((a, b) => String(a.createdAt || "").localeCompare(String(b.createdAt || "")) || String(a.id).localeCompare(String(b.id)));
  return {
    sourceType: canonicalWorkSourceType(input.sourceType ?? input.source_type),
    sourceId: input.sourceId ?? input.source_id ?? "",
    projectId: input.projectId ?? input.project_id ?? null,
    commentCount: Number(input.commentCount ?? input.comment_count) || allComments.length,
    comments: density === "compact" ? allComments.slice(-3) : allComments,
    isFollowing: Boolean(input.isFollowing ?? input.is_following),
    eligibleCollaborators: eligibleCollaborationRecipients(input.eligibleCollaborators ?? input.eligible_collaborators ?? [], currentUserId),
    recentHandoff: input.recentHandoff ?? input.recent_handoff ?? null,
  };
}

function blankDraft() {
  return { body: "", mentionedUserIds: [], commentNonce: null, handoffRecipientId: "", handoffReason: "", handoffNonce: null };
}

export function ensureCollaborationNonce(drafts, sourceKey, field, crypto = globalThis.crypto) {
  drafts[sourceKey] ||= blankDraft();
  drafts[sourceKey][field] ||= crypto.randomUUID();
  return drafts[sourceKey][field];
}

export function collaborationFollowLabel(isFollowing) {
  return isFollowing ? "Unfollow updates" : "Follow updates";
}

export function collaborationRequestIsCurrent(request, sequence, sourceKey) {
  return request.sequence === sequence && request.key === sourceKey;
}

function errorText(reason, fallback) {
  const message = reason instanceof Error ? reason.message : String(reason || "");
  if (/WORK_RECIPIENT_MEMBERSHIP_REQUIRED/.test(message)) return "That person no longer has access to this record. Choose another collaborator.";
  if (/WORK_SOURCE_ACCESS_REQUIRED|NOT_FOUND/.test(message)) return "This collaboration is no longer available to you. Refresh the source record.";
  if (/WORK_COMMENT_EDIT_FORBIDDEN/.test(message)) return "You no longer have permission to revise this comment.";
  return message || fallback;
}

export function createCollaborationState() {
  return {
    collaboration: null,
    collaborationDrafts: {},
    collaborationDraft: blankDraft(),
    collaborationSurface: null,
    collaborationInboxItemId: null,
    collaborationMutation: null,
    collaborationNotice: null,
    collaborationRevision: { commentId: null, body: "", reason: "", revisionsOpen: false },
    collaborationRequestSequence: 0,
    collaborationSourceKey(sourceType = this.collaboration?.sourceType, sourceId = this.collaboration?.sourceId) { return `${canonicalWorkSourceType(sourceType)}:${sourceId || ""}`; },
    openCollaborationSource(projection = {}, context = {}) {
      const normalized = normalizeCollaborationProjection(projection, { currentUserId: this.access?.userId, density: context.density || "full" });
      const nextKey = this.collaborationSourceKey(normalized.sourceType, normalized.sourceId);
      if (nextKey !== this.collaborationSourceKey()) {
        this.collaborationRequestSequence += 1;
        this.collaborationMutation = null;
      }
      this.collaboration = normalized;
      this.collaborationSurface = context.surface || "project";
      this.collaborationInboxItemId = context.inboxItemId || null;
      const key = nextKey;
      this.collaborationDrafts[key] ||= blankDraft();
      this.collaborationDraft = this.collaborationDrafts[key];
      this.collaborationNotice = null;
      this.collaborationRevision = { commentId: null, body: "", reason: "", revisionsOpen: false };
    },
    closeCollaborationSource() {
      this.collaborationRequestSequence += 1;
      this.collaboration = null;
      this.collaborationSurface = null;
      this.collaborationInboxItemId = null;
      this.collaborationNotice = null;
      this.collaborationRevision = { commentId: null, body: "", reason: "", revisionsOpen: false };
    },
    collaborationFollowText() { return collaborationFollowLabel(this.collaboration?.isFollowing); },
    toggleCollaborationMention(userId) {
      const selected = this.collaborationDraft.mentionedUserIds;
      const index = selected.indexOf(userId);
      if (index >= 0) selected.splice(index, 1); else selected.push(userId);
    },
    async refreshCollaboration() {
      if (!this.collaboration || typeof this.reloadActiveCollaborationProjection !== "function") return;
      const request = { key: this.collaborationSourceKey(), sequence: this.collaborationRequestSequence };
      const context = { surface: this.collaborationSurface, density: this.collaborationSurface === "today" ? "compact" : "full", inboxItemId: this.collaborationInboxItemId };
      const projection = await this.reloadActiveCollaborationProjection();
      if (projection && collaborationRequestIsCurrent(request, this.collaborationRequestSequence, this.collaborationSourceKey())) this.openCollaborationSource(projection, context);
    },
    async submitCollaborationComment() {
      const body = this.collaborationDraft.body.trim();
      if (!this.collaboration || !body || this.collaborationMutation) return;
      const source = { type: this.collaboration.sourceType, id: this.collaboration.sourceId, key: this.collaborationSourceKey(), sequence: this.collaborationRequestSequence };
      const draft = this.collaborationDraft;
      this.collaborationMutation = "comment";
      const nonce = ensureCollaborationNonce(this.collaborationDrafts, source.key, "commentNonce");
      try {
        if (this.preview) this.previewAddCollaborationComment(body, draft.mentionedUserIds, nonce, source.key);
        else await createWorkComment(source.type, source.id, body, nonce, draft.mentionedUserIds);
        Object.assign(draft, { body: "", mentionedUserIds: [], commentNonce: null });
        if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) {
          await this.refreshCollaboration();
          this.collaborationNotice = { tone: "success", text: "Comment added to this source record." };
        }
      } catch (reason) {
        if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) this.collaborationNotice = { tone: "error", text: errorText(reason, "The comment was not saved. Your draft is preserved."), retry: "comment" };
      } finally { if (source.sequence === this.collaborationRequestSequence) this.collaborationMutation = null; }
    },
    async toggleCollaborationFollow() {
      if (!this.collaboration || this.collaborationMutation) return;
      const source = { type: this.collaboration.sourceType, id: this.collaboration.sourceId, key: this.collaborationSourceKey(), sequence: this.collaborationRequestSequence };
      this.collaborationMutation = "follow";
      const next = !this.collaboration.isFollowing;
      try {
        if (this.preview) this.previewSetCollaborationFollow(next, source.key); else await followWorkSource(source.type, source.id, next);
        if (!collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) return;
        this.collaboration.isFollowing = next;
        if (!this.preview && typeof this.refreshInbox === "function") await this.refreshInbox(this.inbox?.bucket);
        this.collaborationNotice = { tone: "success", text: next ? "You are following this record." : "You are no longer following this record." };
      } catch (reason) { if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) this.collaborationNotice = { tone: "error", text: errorText(reason, "Follow state was not saved.") }; }
      finally { if (source.sequence === this.collaborationRequestSequence) this.collaborationMutation = null; }
    },
    async submitCollaborationHandoff() {
      const toUserId = this.collaborationDraft.handoffRecipientId;
      const reasonText = this.collaborationDraft.handoffReason.trim();
      if (!this.collaboration || this.collaborationMutation) return;
      if (!toUserId || reasonText.length < 12) { this.collaborationNotice = { tone: "error", text: "Choose an authorized person and provide at least 12 characters of context." }; return; }
      const source = { type: this.collaboration.sourceType, id: this.collaboration.sourceId, key: this.collaborationSourceKey(), sequence: this.collaborationRequestSequence };
      const draft = this.collaborationDraft;
      this.collaborationMutation = "handoff";
      const nonce = ensureCollaborationNonce(this.collaborationDrafts, source.key, "handoffNonce");
      try {
        if (this.preview) this.previewAddCollaborationHandoff(toUserId, reasonText, nonce, source.key); else await handoffWork(source.type, source.id, toUserId, reasonText, nonce);
        Object.assign(draft, { handoffRecipientId: "", handoffReason: "", handoffNonce: null });
        if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) {
          await this.refreshCollaboration();
          this.collaborationNotice = { tone: "success", text: "Reasoned handoff sent." };
        }
      } catch (reason) { if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) this.collaborationNotice = { tone: "error", text: errorText(reason, "The handoff was not saved. Your draft is preserved."), retry: "handoff" }; }
      finally { if (source.sequence === this.collaborationRequestSequence) this.collaborationMutation = null; }
    },
    startCommentRevision(comment) { this.collaborationRevision = { commentId: comment.id, body: comment.body, reason: "", revisionsOpen: true }; },
    cancelCommentRevision() { this.collaborationRevision = { commentId: null, body: "", reason: "", revisionsOpen: false }; },
    async saveCommentRevision() {
      const revision = this.collaborationRevision;
      if (!revision.commentId || !revision.body.trim() || revision.reason.trim().length < 3 || this.collaborationMutation) return;
      const source = { key: this.collaborationSourceKey(), sequence: this.collaborationRequestSequence };
      this.collaborationMutation = "revision";
      try {
        if (this.preview) this.previewReviseCollaborationComment(revision.commentId, revision.body.trim(), revision.reason.trim()); else await reviseWorkComment(revision.commentId, revision.body.trim(), revision.reason.trim());
        if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) {
          this.cancelCommentRevision();
          await this.refreshCollaboration();
          this.collaborationNotice = { tone: "success", text: "Comment revision saved with its audit history." };
        }
      } catch (reason) { if (collaborationRequestIsCurrent(source, this.collaborationRequestSequence, this.collaborationSourceKey())) this.collaborationNotice = { tone: "error", text: errorText(reason, "The revision may not have reconciled. Refresh before retrying.") }; }
      finally { if (source.sequence === this.collaborationRequestSequence) this.collaborationMutation = null; }
    },
    retryCollaborationMutation() {
      if (this.collaborationNotice?.retry === "comment") return this.submitCollaborationComment();
      if (this.collaborationNotice?.retry === "handoff") return this.submitCollaborationHandoff();
    },
  };
}
