import {
  createAvatarSignedUrls,
  createChatAttachmentUrl,
  deleteChatMessage,
  editChatMessage,
  loadChatBootstrap,
  loadChatMessageByNonce,
  loadChatMessages,
  markChatRead,
  moderateChatMessage as persistModeration,
  openDirectChat,
  persistChatMessage,
  removeChatAttachments,
  searchChatMessages,
  toggleChatReaction,
  uploadChatAttachment,
} from "./api.js";
import { readableError } from "./core.js";
import { getSupabaseClient } from "./supabase.js";

const CHAT_FILE_TYPES = new Set([
  "image/jpeg", "image/png", "image/webp", "application/pdf", "text/plain", "text/csv",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);

const REACTION_EMOJI = {
  thumbs_up: "👍", heart: "♥", celebrate: "🎉", laugh: "😄", surprised: "😮", sad: "😔",
};

export function mergeMessages(current = [], incoming = []) {
  const merged = new Map(current.map((message) => [message.id, message]));
  for (const message of incoming) merged.set(message.id, { ...merged.get(message.id), ...message });
  return [...merged.values()].sort((left, right) => {
    const order = new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime();
    return order || String(left.id).localeCompare(String(right.id));
  });
}

export function validateMessage(value) {
  const body = String(value || "").trim();
  if (!body || body.length > 4000) return { valid: false, body, reasonKey: body ? "messageTooLong" : "messageRequired" };
  return { valid: true, body };
}

export function validateChatFile(file) {
  if (!file || !CHAT_FILE_TYPES.has(file.type)) return { valid: false, reasonKey: "chatFileTypeInvalid" };
  if (file.size < 1 || file.size > 10 * 1024 * 1024) return { valid: false, reasonKey: "chatFileTooLarge" };
  return { valid: true };
}

export function totalUnread(conversations = []) {
  return conversations.reduce((total, conversation) => total + (conversation.muted ? 0 : Number(conversation.unreadCount) || 0), 0);
}

export async function persistReadState(conversations, conversationId, messageId, persist = markChatRead) {
  await persist(conversationId, messageId);
  return conversations.map((conversation) => conversation.id === conversationId ? { ...conversation, unreadCount: 0 } : conversation);
}

export function previewChat(userId, displayName) {
  const members = [
    { userId, displayName, role: userId === "preview-admin" ? "admin" : "intern", jobTitle: userId === "preview-admin" ? "Research Operations Lead" : "Research Intern", avatarKey: "coral" },
    { userId: "preview-kayla", displayName: "Kayla Tillmon", role: "intern", jobTitle: "Research Intern", avatarKey: "teal" },
    { userId: "preview-wen", displayName: "Wen Tang", role: "intern", jobTitle: "Research Intern", avatarKey: "blue" },
  ];
  const other = members.find((member) => member.userId !== userId);
  const conversations = [
    { id: "preview-team-chat", kind: "team", title: "AOI Team", members, unreadCount: 3, muted: false, lastMessageAt: "2026-08-04T14:03:00.000Z" },
    { id: "preview-direct-chat", kind: "direct", title: other.displayName, members: [members[0], other], unreadCount: 1, muted: false, lastMessageAt: "2026-08-04T13:47:00.000Z" },
  ];
  return {
    members,
    conversations,
    reactions: Object.keys(REACTION_EMOJI),
    messages: {
      "preview-team-chat": [
        { id: "preview-message-1", conversationId: "preview-team-chat", senderId: "preview-kayla", sender: members[1], body: "I updated the EOD brief and added the missing consent totals.", reactions: [{ reaction: "thumbs_up", count: 2, reactedByMe: false }], attachments: [], createdAt: "2026-08-04T13:42:00.000Z" },
        { id: "preview-message-2", conversationId: "preview-team-chat", senderId: userId, sender: members[0], body: "I’ll review it and post the decision here.", reactions: [], attachments: [], createdAt: "2026-08-04T14:03:00.000Z" },
      ],
      "preview-direct-chat": [
        { id: "preview-message-3", conversationId: "preview-direct-chat", senderId: other.userId, sender: other, body: "Can you review the notes before the closeout?", reactions: [], attachments: [], createdAt: "2026-08-04T13:47:00.000Z" },
      ],
    },
  };
}

function withAvatarUrls(person, urls) {
  return person ? { ...person, avatarUrl: urls[person.avatarPath] || person.avatarUrl || "" } : person;
}

export function createChatState() {
  return {
    chatReady: false,
    chatLoading: false,
    chatLoadingEarlier: false,
    chatSending: false,
    chatStatus: "idle",
    chatError: "",
    chatMembers: [],
    chatConversations: [],
    chatMessages: {},
    chatReactions: Object.keys(REACTION_EMOJI),
    selectedChatConversationId: null,
    chatDraft: "",
    chatReply: null,
    chatEditing: null,
    chatFiles: [],
    chatSearchQuery: "",
    chatSearchResults: [],
    chatSearchOpen: false,
    chatDetailsOpen: false,
    chatMobileThreadOpen: false,
    chatPresence: {},
    chatChannel: null,
    chatRefreshTimer: null,
    chatTypingTimer: null,
    chatTyping: false,

    reactionEmoji(reaction) { return REACTION_EMOJI[reaction] || "•"; },
    totalChatUnread() { return totalUnread(this.chatConversations); },
    selectedChatConversation() { return this.chatConversations.find((conversation) => conversation.id === this.selectedChatConversationId) || null; },
    selectedChatMessages() { return this.chatMessages[this.selectedChatConversationId] || []; },
    chatDirectMembers() { return this.chatMembers.filter((member) => member.userId !== this.access?.userId); },
    chatMessageTime(value) {
      if (!value) return "";
      return new Intl.DateTimeFormat(this.locale, { hour: "numeric", minute: "2-digit" }).format(new Date(value));
    },
    chatFileSize(value) {
      const size = Number(value) || 0;
      return size >= 1024 * 1024 ? `${(size / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(size / 1024))} KB`;
    },
    chatMemberOnline(userId) { return Boolean(this.chatPresence[userId]); },
    chatTypingNames() {
      return Object.values(this.chatPresence)
        .filter((presence) => presence.typing && presence.userId !== this.access?.userId)
        .map((presence) => this.chatMembers.find((member) => member.userId === presence.userId)?.displayName)
        .filter(Boolean);
    },
    chatMessageSender(message) { return message.sender || this.chatMembers.find((member) => member.userId === message.senderId) || { displayName: "AOI member" }; },
    chatReplyMessage(message) { return this.selectedChatMessages().find((candidate) => candidate.id === message.replyToId) || null; },

    async initializeChat() {
      if (this.chatLoading || this.chatReady) return;
      this.chatLoading = true;
      this.chatError = "";
      try {
        if (this.preview) {
          const preview = previewChat(this.access.userId, this.access.displayName);
          this.chatMembers = preview.members;
          this.chatConversations = preview.conversations;
          this.chatMessages = preview.messages;
          this.chatReactions = preview.reactions;
          this.selectedChatConversationId = preview.conversations[0].id;
          this.chatStatus = "preview";
        } else {
          await this.refreshChatBootstrap();
          if (!this.selectedChatConversationId) this.selectedChatConversationId = this.chatConversations[0]?.id || null;
          if (this.selectedChatConversationId) {
            await this.refreshChatMessages(this.selectedChatConversationId);
            await this.markSelectedChatRead();
          }
          await this.subscribeChatRealtime();
        }
        this.chatReady = true;
      } catch (reason) {
        this.chatError = readableError(reason, "Unable to open internal chat.");
        this.chatStatus = "error";
      } finally {
        this.chatLoading = false;
      }
    },
    async refreshChatBootstrap() {
      if (this.preview) return;
      const snapshot = await loadChatBootstrap();
      const paths = [
        ...(snapshot.members || []).map((member) => member.avatarPath),
        ...(snapshot.conversations || []).flatMap((conversation) => (conversation.members || []).map((member) => member.avatarPath)),
      ].filter(Boolean);
      const urls = await createAvatarSignedUrls(paths).catch(() => ({}));
      this.chatMembers = (snapshot.members || []).map((member) => withAvatarUrls(member, urls));
      this.chatConversations = (snapshot.conversations || []).map((conversation) => ({
        ...conversation,
        members: (conversation.members || []).map((member) => withAvatarUrls(member, urls)),
        lastMessage: conversation.lastMessage ? { ...conversation.lastMessage, sender: withAvatarUrls(conversation.lastMessage.sender, urls) } : null,
      }));
      this.chatReactions = snapshot.reactions || Object.keys(REACTION_EMOJI);
      const me = this.chatMembers.find((member) => member.userId === this.access?.userId);
      if (me) this.access = { ...this.access, ...me };
    },
    async refreshChatMessages(conversationId, before = null) {
      if (!conversationId || this.preview) return;
      const page = await loadChatMessages(conversationId, before, 50);
      const paths = page.flatMap((message) => [message.sender?.avatarPath]).filter(Boolean);
      const urls = await createAvatarSignedUrls(paths).catch(() => ({}));
      const hydrated = page.map((message) => ({ ...message, sender: withAvatarUrls(message.sender, urls) }));
      this.chatMessages = { ...this.chatMessages, [conversationId]: mergeMessages(this.chatMessages[conversationId] || [], hydrated) };
    },
    async loadEarlierChatMessages() {
      const first = this.selectedChatMessages()[0];
      if (!first || this.chatLoadingEarlier || this.preview) return;
      this.chatLoadingEarlier = true;
      try { await this.refreshChatMessages(this.selectedChatConversationId, first.createdAt); }
      catch (reason) { this.chatError = readableError(reason, "Unable to load earlier messages."); }
      finally { this.chatLoadingEarlier = false; }
    },
    async selectChatConversation(conversationId) {
      this.selectedChatConversationId = conversationId;
      this.chatMobileThreadOpen = true;
      this.chatDetailsOpen = false;
      this.chatSearchOpen = false;
      this.chatReply = null;
      this.chatEditing = null;
      if (!this.preview) {
        await this.refreshChatMessages(conversationId);
        await this.subscribeChatRealtime();
      }
      await this.markSelectedChatRead();
    },
    async openDirectConversation(member) {
      if (!member || member.userId === this.access?.userId) return;
      if (this.preview) {
        const existing = this.chatConversations.find((conversation) => conversation.kind === "direct" && conversation.members.some((item) => item.userId === member.userId));
        if (existing) await this.selectChatConversation(existing.id);
        return;
      }
      try {
        const conversation = await openDirectChat(member.userId);
        this.chatConversations = [conversation, ...this.chatConversations.filter((item) => item.id !== conversation.id)];
        await this.selectChatConversation(conversation.id);
      } catch (reason) {
        this.chatError = readableError(reason, "Unable to open the direct conversation.");
      }
    },
    replyToMessage(message) { this.chatReply = message; this.chatEditing = null; },
    beginEditChatMessage(message) { this.chatEditing = message; this.chatReply = null; this.chatDraft = message.body; },
    cancelChatComposerMode() { this.chatReply = null; this.chatEditing = null; this.chatDraft = ""; },
    selectChatFiles(event) {
      const selected = [...(event.target.files || [])];
      event.target.value = "";
      for (const file of selected) {
        const check = validateChatFile(file);
        if (!check.valid) { this.chatError = this.t(check.reasonKey); continue; }
        if (this.chatFiles.length >= 10) { this.chatError = this.t("chatFileLimit"); break; }
        this.chatFiles.push(file);
      }
    },
    removePendingChatFile(index) { this.chatFiles.splice(index, 1); },
    async sendChatMessage() {
      if (this.chatSending) return;
      if (this.chatEditing) {
        const check = validateMessage(this.chatDraft);
        if (!check.valid) { this.chatError = this.t(check.reasonKey); return; }
        try {
          const saved = await editChatMessage(this.chatEditing.id, check.body);
          this.chatMessages[this.selectedChatConversationId] = mergeMessages(this.selectedChatMessages(), [saved]);
          this.cancelChatComposerMode();
        } catch (reason) { this.chatError = readableError(reason, "Unable to edit the message."); }
        return;
      }
      const body = this.chatDraft.trim();
      const check = body ? validateMessage(body) : { valid: this.chatFiles.length > 0, body: "", reasonKey: "messageOrFileRequired" };
      if (!check.valid) { this.chatError = this.t(check.reasonKey); return; }
      if (this.preview) { this.chatError = this.t("previewSendingDisabled"); return; }
      const conversationId = this.selectedChatConversationId;
      const nonce = globalThis.crypto.randomUUID();
      const optimistic = {
        id: `pending-${nonce}`, conversationId, senderId: this.access.userId, sender: this.access,
        body: check.body, replyToId: this.chatReply?.id || null, reactions: [], attachments: [],
        createdAt: new Date().toISOString(), pending: true,
      };
      this.chatMessages[conversationId] = mergeMessages(this.selectedChatMessages(), [optimistic]);
      const uploaded = [];
      this.chatSending = true;
      this.chatError = "";
      try {
        for (const file of this.chatFiles) uploaded.push(await uploadChatAttachment(file, this.access.organizationId, conversationId, this.access.userId));
        const saved = await persistChatMessage(conversationId, check.body, { clientNonce: nonce, replyToId: this.chatReply?.id || null, attachments: uploaded });
        this.chatMessages[conversationId] = mergeMessages(this.selectedChatMessages().filter((message) => message.id !== optimistic.id), [saved]);
        this.chatDraft = "";
        this.chatFiles = [];
        this.chatReply = null;
        await this.refreshChatBootstrap();
        await this.markSelectedChatRead();
      } catch (reason) {
        let committed = null;
        let reconciliationCompleted = false;
        try {
          committed = await loadChatMessageByNonce(conversationId, nonce);
          reconciliationCompleted = true;
        } catch {
          // Preserve uploaded objects when the commit outcome is still ambiguous.
        }
        if (committed) {
          this.chatMessages[conversationId] = mergeMessages(this.selectedChatMessages().filter((message) => message.id !== optimistic.id), [committed]);
          this.chatDraft = "";
          this.chatFiles = [];
          this.chatReply = null;
          await this.refreshChatBootstrap();
          await this.markSelectedChatRead();
        } else {
          if (reconciliationCompleted) await removeChatAttachments(uploaded.map((attachment) => attachment.objectPath)).catch(() => {});
          this.chatMessages[conversationId] = this.selectedChatMessages().map((message) => message.id === optimistic.id ? { ...message, pending: false, failed: true } : message);
          this.chatError = readableError(reason, this.t("sendMessageFailed"));
        }
      } finally { this.chatSending = false; }
    },
    async deleteOwnChatMessage(message) {
      if (this.preview || !globalThis.confirm(this.t("deleteMessageConfirm"))) return;
      try {
        const saved = await deleteChatMessage(message.id);
        await removeChatAttachments((message.attachments || []).map((attachment) => attachment.objectPath)).catch(() => {});
        this.chatMessages[message.conversationId] = mergeMessages(this.chatMessages[message.conversationId], [saved]);
      } catch (reason) { this.chatError = readableError(reason, this.t("deleteMessageFailed")); }
    },
    async moderateMessage(message) {
      if (this.preview || this.access?.role !== "admin") return;
      const reason = globalThis.prompt(this.t("moderationReasonPrompt"));
      if (!reason) return;
      try {
        const saved = await persistModeration(message.id, reason);
        await removeChatAttachments((message.attachments || []).map((attachment) => attachment.objectPath)).catch(() => {});
        this.chatMessages[message.conversationId] = mergeMessages(this.chatMessages[message.conversationId], [saved]);
      } catch (error) { this.chatError = readableError(error, this.t("moderateMessageFailed")); }
    },
    async toggleMessageReaction(message, reaction) {
      if (this.preview) return;
      try {
        await toggleChatReaction(message.id, reaction);
        await this.refreshChatMessages(message.conversationId);
      } catch (reason) { this.chatError = readableError(reason, "Unable to update the reaction."); }
    },
    async markSelectedChatRead() {
      if (this.preview || !this.selectedChatConversationId || document.hidden || this.view !== "chat") return;
      if (window.matchMedia("(max-width: 760px)").matches && !this.chatMobileThreadOpen) return;
      const messages = this.selectedChatMessages();
      const last = messages[messages.length - 1];
      if (!last) return;
      try {
        this.chatConversations = await persistReadState(this.chatConversations, this.selectedChatConversationId, last.id);
      } catch (reason) {
        this.chatError = readableError(reason, "Unable to update read state.");
      }
    },
    async runChatSearch() {
      const query = this.chatSearchQuery.trim();
      if (query.length < 2) { this.chatSearchResults = []; return; }
      if (this.preview) {
        this.chatSearchResults = Object.values(this.chatMessages).flat().filter((message) => message.body.toLowerCase().includes(query.toLowerCase()));
        return;
      }
      try { this.chatSearchResults = await searchChatMessages(query, this.selectedChatConversationId); }
      catch (reason) { this.chatError = readableError(reason, "Unable to search messages."); }
    },
    async openChatAttachment(attachment) {
      if (this.preview) return;
      try {
        const url = await createChatAttachmentUrl(attachment.objectPath);
        window.open(url, "_blank", "noopener,noreferrer");
      } catch (reason) { this.chatError = readableError(reason, "Unable to open the attachment."); }
    },
    updateChatPresence() {
      if (!this.chatChannel) return;
      const next = {};
      for (const entries of Object.values(this.chatChannel.presenceState())) {
        for (const presence of entries) if (presence.userId) next[presence.userId] = presence;
      }
      this.chatPresence = next;
    },
    trackChatTyping() {
      if (!this.chatChannel || this.preview) return;
      this.chatTyping = true;
      this.chatChannel.track({ userId: this.access.userId, typing: true, onlineAt: new Date().toISOString() });
      globalThis.clearTimeout(this.chatTypingTimer);
      this.chatTypingTimer = globalThis.setTimeout(() => {
        this.chatTyping = false;
        this.chatChannel?.track({ userId: this.access.userId, typing: false, onlineAt: new Date().toISOString() });
      }, 1400);
    },
    scheduleChatRefresh() {
      globalThis.clearTimeout(this.chatRefreshTimer);
      this.chatRefreshTimer = globalThis.setTimeout(async () => {
            try {
              await this.refreshChatBootstrap();
              if (this.selectedChatConversationId) {
                await this.refreshChatMessages(this.selectedChatConversationId);
                await this.markSelectedChatRead();
              }
        } catch { this.chatStatus = "reconnecting"; }
      }, 180);
    },
    async subscribeChatRealtime() {
      if (this.preview) return;
      await this.destroyChat();
      const client = getSupabaseClient();
      const conversationId = this.selectedChatConversationId;
      if (!conversationId) return;
      const organizationFilter = `organization_id=eq.${this.access.organizationId}`;
      const channel = client.channel(`chat:${conversationId}`, { config: { private: true, presence: { key: this.access.userId } } });
      for (const table of ["chat_messages", "chat_message_reactions", "chat_conversations", "chat_conversation_members"]) {
        channel.on("postgres_changes", { event: "*", schema: "public", table, filter: organizationFilter }, () => this.scheduleChatRefresh());
      }
      channel
        .on("presence", { event: "sync" }, () => this.updateChatPresence())
        .on("presence", { event: "join" }, () => this.updateChatPresence())
        .on("presence", { event: "leave" }, () => this.updateChatPresence())
        .on("broadcast", { event: "profile-changed" }, () => this.scheduleChatRefresh())
        .subscribe(async (status) => {
          this.chatStatus = status === "SUBSCRIBED" ? "connected" : status === "CHANNEL_ERROR" || status === "TIMED_OUT" ? "reconnecting" : status.toLowerCase();
              if (status === "SUBSCRIBED") {
                await this.refreshChatBootstrap();
                if (this.selectedChatConversationId) {
                  await this.refreshChatMessages(this.selectedChatConversationId);
                  await this.markSelectedChatRead();
                }
            if (this.chatChannel === channel) await channel.track({ userId: this.access.userId, typing: false, onlineAt: new Date().toISOString() });
          }
        });
      this.chatChannel = channel;
    },
    async destroyChat() {
      globalThis.clearTimeout(this.chatRefreshTimer);
      globalThis.clearTimeout(this.chatTypingTimer);
      if (this.chatChannel) {
        const channel = this.chatChannel;
        this.chatChannel = null;
        await channel.untrack().catch(() => {});
        await getSupabaseClient().removeChannel(channel).catch(() => {});
      }
      this.chatPresence = {};
    },
  };
}
