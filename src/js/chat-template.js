export const chatTemplate = String.raw`
<div x-show="view==='chat'" class="chat-workspace">
  <section class="chat-layout" :class="chatMobileThreadOpen && 'thread-open'">
    <aside class="chat-conversation-list" aria-label="Conversations">
      <header class="chat-rail-heading">
        <div><span class="eyebrow" x-text="t('internalChat')"></span><h1 x-text="t('chat')"></h1></div>
        <span class="chat-connection" :class="chatStatus" x-text="chatStatus==='connected' ? t('chatConnected') : chatStatus==='preview' ? t('previewOnly') : t('chatReconnecting')"></span>
      </header>
      <div class="chat-member-launcher">
        <span x-text="t('startDirect')"></span>
        <div>
          <template x-for="member in chatDirectMembers()" :key="member.userId">
            <button @click="openDirectConversation(member)" :title="member.displayName">
              <span :class="avatarClass(member,'sm')" :style="avatarStyle(member)" x-text="avatarText(member)"></span>
              <i :class="chatMemberOnline(member.userId) && 'online'"></i>
            </button>
          </template>
        </div>
      </div>
      <div class="chat-thread-list">
        <template x-for="conversation in chatConversations" :key="conversation.id">
          <button class="chat-thread-row" :class="selectedChatConversationId===conversation.id && 'active'" @click="selectChatConversation(conversation.id)">
            <span x-show="conversation.kind==='team'" class="chat-team-avatar">#</span>
            <template x-if="conversation.kind==='direct'"><span :class="avatarClass(conversation.members.find(member=>member.userId!==access.userId)||{},'md')" :style="avatarStyle(conversation.members.find(member=>member.userId!==access.userId)||{})" x-text="avatarText(conversation.members.find(member=>member.userId!==access.userId)||{})"></span></template>
            <span class="chat-thread-copy"><strong x-text="conversation.kind==='team' ? t('teamRoom') : conversation.title"></strong><small x-text="conversation.lastMessage?.deletedAt ? t('messageRemoved') : (conversation.lastMessage?.body || t('noMessagesYet'))"></small></span>
            <em x-show="conversation.unreadCount" x-text="conversation.unreadCount"></em>
          </button>
        </template>
      </div>
      <div x-show="!chatConversations.length && !chatLoading" class="chat-empty"><strong x-text="t('noConversations')"></strong><p x-text="t('noConversationsCopy')"></p></div>
    </aside>

    <article class="chat-conversation" aria-label="Selected conversation">
      <header class="chat-conversation-heading">
        <button class="chat-mobile-back" @click="chatMobileThreadOpen=false" :aria-label="t('backToChats')">‹</button>
        <span class="chat-team-avatar" x-show="selectedChatConversation()?.kind==='team'">#</span>
        <template x-if="selectedChatConversation()?.kind==='direct'"><span :class="avatarClass(selectedChatConversation()?.members.find(member=>member.userId!==access.userId)||{},'md')" :style="avatarStyle(selectedChatConversation()?.members.find(member=>member.userId!==access.userId)||{})" x-text="avatarText(selectedChatConversation()?.members.find(member=>member.userId!==access.userId)||{})"></span></template>
        <div><strong x-text="selectedChatConversation()?.kind==='team' ? t('teamRoom') : selectedChatConversation()?.title"></strong><small x-text="selectedChatConversation()?.kind==='team' ? chatMembers.filter(member=>chatMemberOnline(member.userId)).length+' '+t('online') : (chatMemberOnline(selectedChatConversation()?.members.find(member=>member.userId!==access.userId)?.userId) ? t('online') : t('offlineMember'))"></small></div>
        <div class="chat-heading-actions"><button class="icon-button" @click="chatSearchOpen=!chatSearchOpen" :aria-label="t('searchMessages')">⌕</button><button class="icon-button" @click="chatDetailsOpen=!chatDetailsOpen" :aria-label="t('conversationDetails')">•••</button></div>
      </header>
      <form x-show="chatSearchOpen" class="chat-search" @submit.prevent="runChatSearch()"><input x-model="chatSearchQuery" :placeholder="t('searchMessages')"><button class="button button-secondary" x-text="t('searchShort')"></button></form>
      <div x-show="chatSearchOpen && chatSearchResults.length" class="chat-search-results"><template x-for="message in chatSearchResults" :key="message.id"><button @click="chatSearchOpen=false"><strong x-text="chatMessageSender(message).displayName"></strong><span x-text="message.body"></span><small x-text="chatMessageTime(message.createdAt)"></small></button></template></div>
      <div x-show="chatError" class="chat-error" role="alert"><span x-text="chatError"></span><button @click="chatError=''">×</button></div>
      <div class="chat-message-list" role="log" aria-live="polite">
        <button x-show="selectedChatMessages().length>=50" class="chat-load-earlier" :disabled="chatLoadingEarlier" @click="loadEarlierChatMessages()" x-text="chatLoadingEarlier ? t('loading') : t('loadEarlier')"></button>
        <div x-show="chatLoading && !selectedChatMessages().length" class="chat-skeleton"><span></span><span></span><span></span></div>
        <div x-show="!chatLoading && !selectedChatMessages().length" class="chat-empty"><strong x-text="t('startConversation')"></strong><p x-text="t('startConversationCopy')"></p></div>
        <template x-for="message in selectedChatMessages()" :key="message.id">
          <article class="chat-message" :class="{'mine':message.senderId===access.userId,'is-deleted':message.deletedAt,'is-pending':message.pending,'is-failed':message.failed}">
            <span :class="avatarClass(chatMessageSender(message),'sm')" :style="avatarStyle(chatMessageSender(message))" x-text="avatarText(chatMessageSender(message))"></span>
            <div class="chat-message-content">
              <div class="chat-message-meta"><strong x-text="message.senderId===access.userId ? t('you') : chatMessageSender(message).displayName"></strong><span x-text="chatMessageTime(message.createdAt)"></span><i x-show="message.editedAt" x-text="t('edited')"></i><i x-show="message.pending" x-text="t('sending')"></i><i x-show="message.failed" x-text="t('sendFailed')"></i></div>
              <div class="chat-bubble">
                <div x-show="message.replyToId && chatReplyMessage(message)" class="chat-reply-quote"><strong x-text="chatMessageSender(chatReplyMessage(message)||{}).displayName"></strong><span x-text="chatReplyMessage(message)?.body"></span></div>
                <p x-show="!message.deletedAt" x-text="message.body"></p><p x-show="message.deletedAt" class="chat-removed" x-text="t('messageRemoved')"></p>
                <div x-show="message.attachments?.length && !message.deletedAt" class="chat-attachments"><template x-for="attachment in message.attachments" :key="attachment.id"><button @click="openChatAttachment(attachment)"><span x-text="attachment.mimeType?.startsWith('image/') ? 'IMG' : 'FILE'"></span><span><strong x-text="attachment.fileName"></strong><small x-text="chatFileSize(attachment.sizeBytes)"></small></span></button></template></div>
              </div>
              <div x-show="!message.deletedAt" class="chat-message-reactions"><template x-for="reaction in message.reactions||[]" :key="reaction.reaction"><button :class="reaction.reactedByMe && 'mine'" @click="toggleMessageReaction(message,reaction.reaction)"><span x-text="reactionEmoji(reaction.reaction)"></span><em x-text="reaction.count"></em></button></template></div>
              <div x-show="!message.deletedAt && !message.pending" class="chat-message-actions"><button @click="replyToMessage(message)" x-text="t('reply')"></button><template x-for="reaction in chatReactions" :key="reaction"><button class="reaction-option" @click="toggleMessageReaction(message,reaction)" x-text="reactionEmoji(reaction)"></button></template><button x-show="message.senderId===access.userId" @click="beginEditChatMessage(message)" x-text="t('edit')"></button><button x-show="message.senderId===access.userId" @click="deleteOwnChatMessage(message)" x-text="t('delete')"></button><button x-show="access.role==='admin' && message.senderId!==access.userId" @click="moderateMessage(message)" x-text="t('removeAsAdmin')"></button></div>
            </div>
          </article>
        </template>
      </div>
      <div x-show="chatTypingNames().length" class="chat-typing"><span></span><span></span><span></span><em x-text="chatTypingNames().join(', ')+' '+t('isTyping')"></em></div>
      <form class="chat-composer" @submit.prevent="sendChatMessage()">
        <div x-show="chatReply || chatEditing" class="chat-composer-context"><span><strong x-text="chatEditing ? t('editingMessage') : t('replyingTo')+' '+chatMessageSender(chatReply||{}).displayName"></strong><small x-text="(chatEditing||chatReply)?.body"></small></span><button type="button" @click="cancelChatComposerMode()">×</button></div>
        <div x-show="chatFiles.length" class="chat-pending-files"><template x-for="(file,index) in chatFiles" :key="file.name+index"><span><strong x-text="file.name"></strong><small x-text="chatFileSize(file.size)"></small><button type="button" @click="removePendingChatFile(index)">×</button></span></template></div>
        <textarea x-model="chatDraft" @input="trackChatTyping()" @keydown.enter.exact.prevent="sendChatMessage()" :placeholder="preview ? t('previewChatPlaceholder') : t('messagePlaceholder')" maxlength="4000" rows="2" :disabled="chatSending || preview || !selectedChatConversationId"></textarea>
        <div><label class="chat-attach-button"><input type="file" multiple accept="image/jpeg,image/png,image/webp,application/pdf,text/plain,text/csv,.doc,.docx,.xls,.xlsx" @change="selectChatFiles($event)" :disabled="chatSending || preview"><span>＋</span><em x-text="t('attach')"></em></label><span class="chat-character-count" x-text="chatDraft.length+'/4000'"></span><button class="button button-primary" :disabled="chatSending || preview || (!chatDraft.trim() && !chatFiles.length)" x-text="chatSending ? t('sending') : (chatEditing ? t('saveEdit') : t('send'))"></button></div>
      </form>
    </article>

    <aside class="chat-details" :class="chatDetailsOpen && 'open'">
      <button class="chat-details-close" @click="chatDetailsOpen=false">×</button>
      <div class="chat-details-identity"><span class="chat-team-avatar" x-show="selectedChatConversation()?.kind==='team'">#</span><h2 x-text="selectedChatConversation()?.kind==='team' ? t('teamRoom') : selectedChatConversation()?.title"></h2><p x-text="selectedChatConversation()?.kind==='team' ? t('teamRoomCopy') : t('directConversation')"></p></div>
      <section><span class="eyebrow" x-text="t('members')"></span><template x-for="member in selectedChatConversation()?.members||[]" :key="member.userId"><button class="chat-detail-member" @click="openDirectConversation(member)"><span :class="avatarClass(member,'sm')" :style="avatarStyle(member)" x-text="avatarText(member)"></span><span><strong x-text="member.displayName"></strong><small x-text="member.jobTitle || (member.role==='admin' ? 'Admin' : 'Intern')"></small></span><i :class="chatMemberOnline(member.userId) && 'online'"></i></button></template></section>
      <section><span class="eyebrow" x-text="t('conversationDetails')"></span><p x-text="t('privateWorkspaceCopy')"></p></section>
    </aside>
  </section>
</div>`;
