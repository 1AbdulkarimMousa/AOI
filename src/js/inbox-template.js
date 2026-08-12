export const inboxTemplate = String.raw`
<section class="inbox-workspace" aria-labelledby="inbox-heading">
  <div class="inbox-intro"><div><span class="eyebrow" x-text="inboxRoleText.eyebrow"></span><h1 id="inbox-heading" x-text="inboxRoleText.heading"></h1><p x-text="inboxRoleText.body"></p></div><button class="button button-secondary" :disabled="inboxLoading" @click="refreshInbox()" x-text="inboxLoading?'Refreshing…':'Refresh work inbox'"></button></div>
  <div x-show="inboxNotice" class="admin-notice" :class="inboxNotice?.tone" role="status" aria-live="polite" x-text="inboxNotice?.text"></div>
  <nav class="inbox-buckets" aria-label="Work inbox views">
    <button :aria-pressed="inbox.bucket==='needs_action'" :class="inbox.bucket==='needs_action'&&'active'" @click="setInboxBucket('needs_action')"><span>Needs action</span><strong x-text="inboxCount('needs_action')"></strong></button>
    <button :aria-pressed="inbox.bucket==='waiting'" :class="inbox.bucket==='waiting'&&'active'" @click="setInboxBucket('waiting')"><span>Waiting on others</span><strong x-text="inboxCount('waiting')"></strong></button>
    <button :aria-pressed="inbox.bucket==='mentioned'" :class="inbox.bucket==='mentioned'&&'active'" @click="setInboxBucket('mentioned')"><span>Mentioned</span><strong x-text="inboxCount('mentioned')"></strong></button>
    <button :aria-pressed="inbox.bucket==='following'" :class="inbox.bucket==='following'&&'active'" @click="setInboxBucket('following')"><span>Following</span><strong x-text="inboxCount('following')"></strong></button>
    <button :aria-pressed="inbox.bucket==='recently_resolved'" :class="inbox.bucket==='recently_resolved'&&'active'" @click="setInboxBucket('recently_resolved')"><span>Recently resolved</span><strong x-text="inboxCount('recently_resolved')"></strong></button>
    <button :aria-pressed="inbox.bucket==='system_attention'" :class="inbox.bucket==='system_attention'&&'active'" @click="setInboxBucket('system_attention')"><span>System attention</span><strong x-text="inboxCount('system_attention')"></strong></button>
  </nav>
  <div class="inbox-layout" :class="selectedInboxItem&&'has-selection'">
    <section class="panel inbox-list" aria-label="Inbox items">
      <div class="panel-heading compact"><div><span class="eyebrow" x-text="inboxBucketName"></span><h2 x-text="inbox.items.length+(inbox.items.length===1?' item':' items')"></h2></div></div>
      <div x-show="inboxLoading" class="empty-state compact"><strong>Loading authorized work…</strong></div>
      <template x-for="item in inbox.items" :key="item.id"><button class="inbox-row" :class="[selectedInboxItem?.id===item.id&&'active',!item.readAt&&'unread']" @click="openInboxItem(item)"><span class="inbox-state" x-text="item.readAt?'Read':'Unread'"></span><span><small x-text="projectSourceLabel(item.sourceType)+' · '+item.priority"></small><strong x-text="item.summary"></strong><p x-text="item.reason"></p></span><span class="inbox-open">Open</span></button></template>
      <div x-show="!inboxLoading&&!inbox.items.length" class="empty-state"><strong>No work in this view.</strong><p>The queue is derived from authorized source records. Nothing is added to make the inbox look busy.</p></div>
    </section>
    <article x-show="selectedInboxItem" class="panel inbox-detail" aria-labelledby="inbox-item-heading" tabindex="-1">
      <button class="text-button inbox-back" @click="closeInboxItem()">← Back to inbox</button>
       <div class="panel-heading"><div><span class="eyebrow" x-text="projectSourceLabel(selectedInboxItem?.sourceType)"></span><h2 id="inbox-item-heading" x-text="selectedInboxItem?.summary"></h2><p x-text="selectedInboxItem?.reason"></p></div><span class="status-badge" x-text="selectedInboxItem?.priority"></span></div>
      <div class="inbox-actions"><button class="button button-primary" @click="openInboxSource(selectedInboxItem)">Open source record</button><button class="button button-secondary" @click="toggleInboxFollow()">Follow updates</button></div>
      <form class="research-form inbox-comment" @submit.prevent="submitInboxComment()"><label><span>Contextual comment</span><textarea rows="3" x-model.trim="inboxComment" placeholder="Add evidence, guidance, or a blocker to this source record."></textarea></label><button class="button button-secondary" :disabled="inboxMutation" type="submit">Add comment</button></form>
      <form class="research-form inbox-handoff" @submit.prevent="submitInboxHandoff()"><label><span>Handoff recipient ID</span><input x-model.trim="inboxHandoff.toUserId" placeholder="Authorized team member UUID"></label><label><span>Handoff reason</span><textarea rows="3" minlength="12" x-model.trim="inboxHandoff.reason" placeholder="Explain the unresolved work and expected next action."></textarea></label><button class="button button-secondary" :disabled="inboxMutation" type="submit">Send reasoned handoff</button></form>
    </article>
  </div>
</section>`;
