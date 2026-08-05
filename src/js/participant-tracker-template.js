const participantTrackerContentTemplate = String.raw`
<template x-if="ready">
  <div class="participant-tracker-content">
    <section x-show="error" class="admin-notice error" role="alert"><span x-text="error"></span><button class="text-button" @click="refresh()">Retry</button></section>
    <section x-show="notice" class="admin-notice" :class="notice?.tone" role="status" x-text="notice?.text"></section>

    <section class="participant-stats">
      <article><span>Total prospects</span><strong x-text="items.length"></strong><small>restricted recruitment records</small></article>
      <article><span>Needs first touch</span><strong x-text="count('new')"></strong><small>ready for an approved outreach message</small></article>
      <article><span>In screening</span><strong x-text="count('screening')"></strong><small>eligibility still being verified</small></article>
      <article class="participant-stat-accent"><span>Scheduled</span><strong x-text="count('scheduled')"></strong><small>confirmed interview dates</small></article>
    </section>

    <section class="participant-workbench">
      <div class="participant-workbench-head">
        <div><span class="eyebrow">Recruitment pipeline</span><h2 x-text="filteredItems.length+' people in view'"></h2></div>
        <div class="participant-controls"><label class="participant-search"><span>⌕</span><input x-model="query" placeholder="Search name, email, source" aria-label="Search recruitment prospects"></label><select x-model="filter" aria-label="Filter recruitment status"><option value="all">All stages</option><template x-for="status in statusOptions" :key="status"><option :value="status" x-text="statusLabel(status)"></option></template></select></div>
      </div>
      <div class="participant-table-head"><span>Prospect</span><span>Source</span><span>Stage</span><span>Next action</span><span>Interview</span><span></span></div>
      <div class="participant-list">
        <template x-for="item in filteredItems" :key="item.id"><article class="participant-row" @click="openEdit(item)"><div class="participant-identity"><span class="participant-avatar" x-text="initials(item.name)"></span><span><strong x-text="item.name"></strong><small x-text="item.participantId+' · '+item.email"></small></span></div><div class="participant-source"><strong x-text="item.source"></strong><small x-text="item.timeZone||'Time zone needed'"></small></div><div><span class="participant-status" :data-status="item.status" x-text="statusLabel(item.status)"></span><small class="participant-consent" x-text="'Consent: '+item.consentStatus"></small></div><div class="participant-next"><strong x-text="item.nextAction||'Add next action'"></strong><small x-text="item.nextActionDue ? 'Due '+formatDate(item.nextActionDue) : 'No due date'"></small></div><div class="participant-interview"><strong x-text="item.interviewDate ? formatDate(item.interviewDate) : 'Not booked'"></strong><small x-text="item.respondentId ? 'Respondent connected' : item.crmContactId ? 'CRM linked' : 'No CRM link'"></small></div><div class="participant-row-actions"><button class="icon-button" @click.stop="openCrm(item)" :disabled="!item.crmContactId" aria-label="Open CRM record">↗</button><button class="participant-more" @click.stop="openEdit(item)" aria-label="Edit participant">⋯</button></div></article></template>
        <div x-show="!filteredItems.length" class="participant-empty"><strong>No prospects match this view.</strong><p>Try another stage or add a new recruitment prospect.</p><button class="button button-secondary" @click="openNew()">Add prospect</button></div>
      </div>
    </section>

    <section class="participant-note"><span>◎</span><div><strong>Research boundary</strong><p>These are recruitment prospects only. Convert to a respondent only after screening, segment assignment, and granted consent are complete.</p></div></section>

    <div x-show="editorOpen" class="modal-backdrop participant-drawer-backdrop" @mousedown.self="closeEditor()">
      <aside class="participant-drawer" role="dialog" aria-modal="true" aria-labelledby="participant-editor-title">
        <div class="drawer-header"><span class="eyebrow" x-text="selected ? 'Prospect record' : 'New prospect'"></span><button class="icon-button" @click="closeEditor()" aria-label="Close">×</button></div>
        <div class="drawer-title"><span class="participant-status" :data-status="form.status" x-text="statusLabel(form.status)"></span><h2 id="participant-editor-title" x-text="form.name||'Add a prospect'"></h2><p>Capture verified recruitment facts, then connect the prospect to research without re-entering identity data.</p></div>
        <form class="participant-form" @submit.prevent="save()">
          <div class="participant-form-grid"><label><span>Participant ID</span><input x-model.trim="form.participantId" placeholder="PR-004" required></label><label><span>Recruitment stage</span><select x-model="form.status"><template x-for="status in statusOptions" :key="status"><option :value="status" x-text="statusLabel(status)"></option></template></select></label></div>
          <label><span>Full name</span><input x-model.trim="form.name" required></label>
          <div class="participant-form-grid"><label><span>Email</span><input type="email" x-model.trim="form.email"></label><label><span>Phone</span><input type="tel" x-model.trim="form.phone"></label></div>
          <div class="participant-form-grid"><label><span>Source</span><input x-model.trim="form.source"></label><label><span>Time zone</span><input x-model.trim="form.timeZone" placeholder="Eastern Time Zone"></label></div>
          <div class="participant-form-grid"><label><span>Segment</span><select x-model="form.segment"><option value="">Unscreened</option><option>Families with Children</option><option>Adult Orthodontic Patients</option><option>Implant Maintenance</option><option>Highly Engaged Oral-Care Adults</option></select></label><label><span>Consent</span><select x-model="form.consentStatus"><option value="pending">Pending</option><option value="granted">Granted</option><option value="declined">Declined</option><option value="withdrawn">Withdrawn</option></select></label></div>
          <div class="participant-form-grid"><label><span>Next action</span><input x-model.trim="form.nextAction"></label><label><span>Due date</span><input type="date" x-model="form.nextActionDue"></label></div>
          <label><span>Interview date</span><input type="date" x-model="form.interviewDate"></label>
          <label><span>Qualification notes</span><textarea rows="3" x-model.trim="form.qualificationNotes" placeholder="Eligibility facts, recent oral-health experience, and screening outcome"></textarea></label>
          <label><span>Notes</span><textarea rows="3" x-model.trim="form.notes"></textarea></label>
          <div x-show="selected" class="participant-conversion">
            <div><span class="eyebrow">Identity automation</span><strong x-text="form.respondentId ? 'Respondent connected' : 'Convert to respondent'"></strong><p x-show="!conversionReadiness(form).ready && !form.respondentId" x-text="conversionReadiness(form).reasons.join(' ')"></p><p x-show="conversionReadiness(form).ready">Creates the CRM link, respondent code, consent version, and identity trail in one audited action.</p></div>
            <button x-show="access?.role==='admin' && !form.respondentId" type="button" class="button button-secondary" :disabled="!conversionReadiness(form).ready || convertingId===form.id" @click="convertToRespondent(form)" x-text="convertingId===form.id?'Converting…':'Convert to respondent'"></button>
            <span x-show="form.respondentId" class="status-badge status-approved" x-text="form.respondentId"></span>
          </div>
          <div class="participant-form-actions"><button type="button" class="button button-secondary" @click="closeEditor()">Cancel</button><button type="submit" class="button button-primary" :disabled="saving" x-text="saving?'Saving…':'Save prospect'"></button></div>
        </form>
      </aside>
    </div>
  </div>
</template>`;

export const participantTrackerTemplate = String.raw`
<div x-data="participantTrackerPage" x-init="init()" x-cloak class="participant-tracker-shell">
  <template x-if="!ready"><main class="access-gate"><section><div class="brand-mark">A</div><h1>Ambiloop Ops</h1><p>Opening participant recruitment…</p><span class="spin">◌</span></section></main></template>
  <main x-show="ready" class="participant-tracker-page">
    <header class="participant-topbar"><a class="participant-brand" :href="crmUrl"><span class="brand-mark">A</span><span><strong>Ambiloop Ops</strong><small>Participant recruitment</small></span></a><div class="participant-top-actions"><a class="button button-secondary" :href="crmUrl">Back to CRM</a><button class="user-card participant-user" @click="logout()"><span class="avatar avatar-sm" x-text="initials(access.displayName)"></span><span x-text="access.displayName"></span><span>↪</span></button></div></header>
    <div class="participant-content"><section class="participant-hero"><div><span class="eyebrow">Consumer fieldwork</span><h1>Participant Recruitment Tracker</h1><p>Keep early interest moving toward a confirmed, consented interview without confusing a prospect with research evidence.</p></div><div class="participant-hero-actions"><a class="button button-secondary" :href="crmUrl">Open CRM</a><button class="button button-primary" @click="openNew()">+ Add prospect</button></div></section>${participantTrackerContentTemplate}</div>
  </main>
</div>`;

export const participantTrackerEmbedTemplate = String.raw`
<div x-data="participantTrackerPage" x-init="embedded=true; init()" x-cloak class="participant-embedded-shell">
  <div class="participant-embedded-heading"><div><span class="eyebrow">Prospect pipeline</span><h2>Recruitment</h2><p>Move verified interest toward screening without creating research evidence.</p></div><a class="button button-secondary" :href="trackerUrl">Open full tracker</a></div>
  ${participantTrackerContentTemplate}
</div>`;
