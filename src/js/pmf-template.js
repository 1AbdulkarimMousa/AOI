export const pmfCollectionTemplate = String.raw`
<div x-show="view==='research' && researchTab==='collect'" class="pmf-surface">
  <section class="page-intro collection-intro">
    <div><span class="eyebrow">Guided collection</span><h1>Capture the source before the conclusion.</h1><p>Save working notes as drafts. Submit only when provenance, consent, and limitations are complete.</p></div>
    <div class="collection-summary" aria-label="Research collection summary">
      <span><strong x-text="researchStats.respondents"></strong><small>respondents</small></span>
      <span><strong x-text="researchStats.sessions"></strong><small>sessions</small></span>
      <span><strong x-text="researchStats.approvedEvidence"></strong><small>approved</small></span>
      <span><strong x-text="researchStats.pendingReview"></strong><small>in review</small></span>
    </div>
  </section>

  <section class="collect-progress-panel" aria-label="Personal and cooperative progress">
    <div class="collect-level"><span class="collect-level-number" x-text="gamificationLevelData.level"></span><div><span class="eyebrow">Personal progress</span><strong x-text="gamification.xp+' verified XP'"></strong><small x-text="gamificationLevelData.maxLevel ? 'Highest level reached' : gamificationLevelData.nextLevelXp-gamification.xp+' XP to level '+(gamificationLevelData.level+1)"></small></div></div>
    <div class="collect-progress-track"><span :style="'width:'+gamificationLevelData.progress+'%'"></span></div>
    <div class="collect-streak"><strong x-text="gamification.streakDays"></strong><span>day streak</span><small x-text="gamification.completedToday+' verified actions today'"></small></div>
    <div class="collect-badges"><template x-for="badge in gamification.badges.slice(0,3)" :key="badge.code"><span :title="badge.description" x-text="badge.name"></span></template><small x-show="!gamification.badges.length">Badges unlock after reviewed work.</small></div>
    <div class="collect-team-goals"><template x-for="goal in gamification.teamGoals" :key="goal.code"><div><span><strong x-text="goal.name"></strong><small x-text="Math.min(goal.progress,goal.target)+' / '+goal.target"></small></span><div class="progress-track"><span class="progress-fill progress-teal" :style="'width:'+Math.min(100,Math.round(goal.progress/goal.target*100))+'%'"></span></div></div></template></div>
  </section>

  <div class="collect-mode-switch" role="tablist" aria-label="Collect workspace mode">
    <button role="tab" :aria-selected="collectMode==='browse'" :class="collectMode==='browse'&&'active'" @click="collectMode='browse'"><strong>Collected data</strong><small>Browse, inspect, and continue records</small></button>
    <button role="tab" :aria-selected="collectMode==='create'" :class="collectMode==='create'&&'active'" @click="startCollectionRecord(collectionType)"><strong>New record</strong><small>Guided, prefilled research entry</small></button>
  </div>

  <section x-show="collectMode==='browse'" class="panel collect-library">
    <div class="collect-library-head"><div><span class="eyebrow">Source-of-truth library</span><h2 x-text="filteredCollectRecords.length+' collected records'"></h2><p>Admins see the complete project. Interns see assigned drafts and approved shared research.</p></div><button class="button button-primary" @click="startCollectionRecord('respondent')">+ New record</button></div>
    <div class="collect-filters"><label><span>Search records</span><input x-model.debounce.200ms="collectQuery" placeholder="Code, owner, segment, identity"></label><label><span>Record type</span><select x-model="collectTypeFilter"><option value="all">All records</option><option value="respondent">Respondents</option><option value="session">Sessions</option><option value="evidence">Evidence</option><option value="product_event">Product events</option><option value="value_exchange">Value exchange</option><option value="observation">PMF observations</option></select></label><label><span>Workflow</span><select x-model="collectStatusFilter"><option value="all">All states</option><option value="draft">Draft</option><option value="submitted">Submitted</option><option value="revision_requested">Revision requested</option><option value="approved">Approved</option><option value="archived">Archived</option></select></label></div>
    <div class="collect-table" role="table" aria-label="Collected research records">
      <div class="collect-table-row collect-table-header" role="row"><span>Record</span><span>Respondent</span><span>Owner</span><span>Workflow</span><span>Updated</span></div>
      <template x-for="record in filteredCollectRecords" :key="record.recordType+'-'+record.id"><button class="collect-table-row" role="row" @click="openCollectRecord(record)"><span><small x-text="record.recordType.replaceAll('_',' ')"></small><strong x-text="record.title"></strong><em x-show="record.identityTrail" x-text="record.identityTrail"></em></span><span><strong x-text="record.respondentCode||'Unlinked'"></strong><small x-text="record.segmentName||'No segment'"></small></span><span x-text="record.ownerName||'Shared contributor'"></span><span class="status-badge" :class="'status-'+record.workflowStatus" x-text="record.workflowStatus.replaceAll('_',' ')"></span><span x-text="formatDate(record.recordDate)"></span></button></template>
      <div x-show="!filteredCollectRecords.length" class="empty-state collect-empty"><strong>No records match this view.</strong><p>Start a guided record or broaden the filters. Nothing is synthesized to fill this space.</p><button class="button button-secondary" @click="startCollectionRecord('respondent')">Create the first record</button></div>
    </div>
  </section>

  <section x-show="collectMode==='create'" class="collection-layout">
    <nav class="collection-rail" aria-label="Collection record type">
      <button :class="collectionType==='respondent' && 'active'" @click="collectionType='respondent'"><b>01</b><span><strong>Respondent</strong><small>Identity, assignment, consent</small></span></button>
      <button :class="collectionType==='session' && 'active'" @click="collectionType='session'"><b>02</b><span><strong>Session</strong><small>Behavior and unmet need</small></span></button>
      <button :class="collectionType==='evidence' && 'active'" @click="collectionType='evidence'"><b>03</b><span><strong>Evidence</strong><small>Claim, source, limitations</small></span></button>
      <button :class="collectionType==='product_event' && 'active'" @click="collectionType='product_event'"><b>04</b><span><strong>Product event</strong><small>Use, value, friction</small></span></button>
      <button :class="collectionType==='value_exchange' && 'active'" @click="collectionType='value_exchange'"><b>05</b><span><strong>Value exchange</strong><small>Price and commitment</small></span></button>
      <button :class="collectionType==='observation' && 'active'" @click="collectionType='observation'"><b>06</b><span><strong>Matrix observation</strong><small>Structured PMF metric</small></span></button>
    </nav>

    <article class="panel collection-form-panel">
      <div class="collection-form-heading"><div><span class="eyebrow" x-text="collectionType.replaceAll('_',' ')"></span><h2>Research record</h2></div><span class="draft-rule">Drafts stay assignment-scoped</span></div>

      <form x-show="collectionType==='respondent'" class="research-form" @submit.prevent>
        <div class="form-grid form-grid-three">
          <label><span>Segment</span><select x-model="researchForms.respondent.segmentCode" required><template x-for="segment in data.segments" :key="segment.code"><option :value="segment.code" x-text="segment.name"></option></template></select></label>
          <label><span>Respondent type</span><select x-model="researchForms.respondent.respondentType"><option>Consumer</option><option>Dental Professional</option></select></label>
          <label><span>External ID</span><input x-model.trim="researchForms.respondent.externalId" placeholder="Generated if blank"></label>
        </div>
        <div class="form-grid">
          <label><span>Specialty or status</span><input x-model.trim="researchForms.respondent.specialtyStatus" placeholder="Parent, orthodontist, hygienist"></label>
          <label><span>Recruitment source</span><input x-model.trim="researchForms.respondent.recruitmentSource" placeholder="Referral, outreach, panel"></label>
        </div>
        <div class="form-divider"><span>Restricted contact</span><small>Visible only to the assignee and administrators.</small></div>
        <div class="form-grid form-grid-three">
          <label><span>Contact name</span><input x-model.trim="researchForms.respondent.contactName"></label>
          <label><span>Email</span><input type="email" x-model.trim="researchForms.respondent.email"></label>
          <label><span>Phone</span><input type="tel" x-model.trim="researchForms.respondent.phone"></label>
        </div>
        <div class="form-grid form-grid-three">
          <label><span>Consent state</span><select x-model="researchForms.respondent.consentStatus"><option value="pending">Pending</option><option value="granted">Granted</option><option value="declined">Declined</option><option value="not_applicable">Not applicable</option></select></label>
          <label><span>Research stage</span><select x-model="researchForms.respondent.stage"><option>Concept</option><option>Product</option><option>Launch</option><option>Concept + Product</option></select></label>
          <label><span>Retention review</span><input type="date" x-model="researchForms.respondent.retentionReviewAt"></label>
        </div>
        <fieldset class="permission-grid"><legend>Granted uses</legend><label><input type="checkbox" x-model="researchForms.respondent.interviewAllowed"> Interview</label><label><input type="checkbox" x-model="researchForms.respondent.recordingAllowed"> Recording</label><label><input type="checkbox" x-model="researchForms.respondent.imagesAllowed"> Oral images</label><label><input type="checkbox" x-model="researchForms.respondent.quotationAllowed"> Quotation</label><label><input type="checkbox" x-model="researchForms.respondent.recontactAllowed"> Recontact</label></fieldset>
        <label><span>Notes</span><textarea rows="3" x-model.trim="researchForms.respondent.notes" placeholder="Eligibility, context, and restrictions"></textarea></label>
      </form>

      <form x-show="collectionType==='session'" class="research-form" @submit.prevent>
        <div class="form-grid form-grid-three">
          <label><span>Respondent</span><select x-model="researchForms.session.respondentId" required><option value="">Choose respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.segmentName"></option></template></select></label>
          <label><span>PMF layer</span><select x-model="researchForms.session.pmfLayer"><template x-for="layer in data.pmfLayers" :key="layer.code"><option :value="layer.code" x-text="layer.code+' · '+layer.name"></option></template></select></label>
          <label><span>Session date</span><input type="date" x-model="researchForms.session.sessionDate" required></label>
        </div>
        <label><span>Method</span><input x-model.trim="researchForms.session.method" placeholder="JTBD interview, observation, usability test" required></label>
        <div class="form-grid"><label><span>Current behavior</span><textarea rows="3" x-model.trim="researchForms.session.currentBehavior"></textarea></label><label><span>Recent incident</span><textarea rows="3" x-model.trim="researchForms.session.recentIncident"></textarea></label></div>
        <div class="form-grid"><label><span>Biggest hassle</span><textarea rows="3" x-model.trim="researchForms.session.biggestHassle"></textarea></label><label><span>Current action</span><textarea rows="3" x-model.trim="researchForms.session.currentAction"></textarea></label></div>
        <label><span>Unmet need</span><textarea rows="3" x-model.trim="researchForms.session.unmetNeed" placeholder="Required before submission"></textarea></label>
        <label><span>Limitations</span><textarea rows="2" x-model.trim="researchForms.session.limitations"></textarea></label>
      </form>

      <form x-show="collectionType==='evidence'" class="research-form" @submit.prevent>
        <div class="form-grid form-grid-three">
          <label><span>Respondent</span><select x-model="researchForms.evidence.respondentId" @change="syncResearchSession('evidence')"><option value="">No respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.segmentName"></option></template></select></label>
          <label><span>Session</span><select x-model="researchForms.evidence.sessionId"><option value="">No session</option><template x-for="item in researchSessionsFor('evidence')" :key="item.id"><option :value="item.id" x-text="formatDate(item.sessionDate)+' · '+item.method"></option></template></select></label>
          <label><span>PMF layer</span><select x-model="researchForms.evidence.pmfLayer"><template x-for="layer in data.pmfLayers" :key="layer.code"><option :value="layer.code" x-text="layer.code+' · '+layer.name"></option></template></select></label>
        </div>
        <div class="form-grid form-grid-three"><label><span>Dimension</span><input x-model.trim="researchForms.evidence.dimension" placeholder="Frequency, capture, price"></label><label><span>Stance</span><select x-model="researchForms.evidence.stance"><option value="supporting">Supporting</option><option value="contradicting">Contradicting</option><option value="neutral">Neutral</option></select></label><label><span>Strength</span><select x-model.number="researchForms.evidence.strength"><option :value="1">1 · weak</option><option :value="2">2 · useful</option><option :value="3">3 · strong</option><option :value="4">4 · decisive</option></select></label></div>
        <label><span>Consent metadata</span><select x-model="researchForms.evidence.consentStatus"><option value="not_applicable">Not applicable</option><option value="pending">Pending</option><option value="granted">Granted</option><option value="declined">Declined</option><option value="withdrawn">Withdrawn</option><option value="expired">Expired</option></select></label>
        <label><span>Evidence title</span><input x-model.trim="researchForms.evidence.title" required placeholder="One precise, falsifiable finding"></label>
        <label><span>Evidence or quote</span><textarea rows="4" x-model.trim="researchForms.evidence.evidenceText" required></textarea></label>
        <div class="form-grid"><label><span>Source link</span><input type="url" x-model.trim="researchForms.evidence.sourceLink" placeholder="https://"></label><label><span>Decision relevance</span><input x-model.trim="researchForms.evidence.decisionRelevance"></label></div>
        <label><span>Limitations</span><textarea rows="3" x-model.trim="researchForms.evidence.limitations" placeholder="Required before submission"></textarea></label>
      </form>

      <form x-show="collectionType==='product_event'" class="research-form" @submit.prevent>
        <div class="form-grid form-grid-three"><label><span>Respondent</span><select x-model="researchForms.product_event.respondentId" required><option value="">Choose respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.segmentName"></option></template></select></label><label><span>Event date</span><input type="date" x-model="researchForms.product_event.eventDate"></label><label><span>Study week</span><input type="number" min="0" max="52" x-model.number="researchForms.product_event.studyWeek"></label></div>
        <div class="form-grid"><label><span>Trigger</span><input x-model.trim="researchForms.product_event.triggerType"></label><label><span>Target user</span><input x-model.trim="researchForms.product_event.targetUser"></label></div>
        <label><span>Trigger description</span><textarea rows="3" x-model.trim="researchForms.product_event.triggerDescription"></textarea></label>
        <div class="form-grid form-grid-three"><label><span>Capture succeeded?</span><select x-model="researchForms.product_event.captureSuccess"><option value="">Unknown</option><option value="true">Yes</option><option value="false">No</option></select></label><label><span>Result understood?</span><select x-model="researchForms.product_event.resultUnderstood"><option value="">Unknown</option><option value="true">Yes</option><option value="false">No</option></select></label><label><span>Value obtained?</span><select x-model="researchForms.product_event.valueObtained"><option value="">Unknown</option><option value="true">Yes</option><option value="false">No</option></select></label></div>
        <div class="form-grid"><label><span>Main friction</span><textarea rows="3" x-model.trim="researchForms.product_event.mainFriction"></textarea></label><label><span>Notes</span><textarea rows="3" x-model.trim="researchForms.product_event.notes"></textarea></label></div>
      </form>

      <form x-show="collectionType==='value_exchange'" class="research-form" @submit.prevent>
        <div class="form-grid form-grid-three"><label><span>Respondent</span><select x-model="researchForms.value_exchange.respondentId" required><option value="">Choose respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.segmentName"></option></template></select></label><label><span>Observed at</span><input type="date" x-model="researchForms.value_exchange.observedAt"></label><label><span>Tested hardware price</span><input type="number" min="0" step="1" x-model.number="researchForms.value_exchange.hardwarePrice"></label></div>
        <div class="form-grid form-grid-three"><label><span>Reasonable minimum</span><input type="number" min="0" x-model.number="researchForms.value_exchange.reasonablePriceMin"></label><label><span>Reasonable maximum</span><input type="number" min="0" x-model.number="researchForms.value_exchange.reasonablePriceMax"></label><label><span>Purchase intent (1 to 5)</span><input type="number" min="1" max="5" x-model.number="researchForms.value_exchange.purchaseIntent"></label></div>
        <div class="form-grid"><label><span>Preferred offer</span><input x-model.trim="researchForms.value_exchange.preferredOffer"></label><label><span>Subscription plan</span><input x-model.trim="researchForms.value_exchange.subscriptionPlan"></label></div>
        <div class="form-grid"><label><span>Commitment type</span><input x-model.trim="researchForms.value_exchange.commitmentType" placeholder="Waitlist, deposit, purchase"></label><label><span>Commitment amount</span><input type="number" min="0" x-model.number="researchForms.value_exchange.commitmentAmount"></label></div>
        <label><span>Main objection</span><textarea rows="3" x-model.trim="researchForms.value_exchange.mainObjection"></textarea></label>
      </form>

      <form x-show="collectionType==='observation'" class="research-form" @submit.prevent>
        <div class="form-grid"><label><span>Matrix metric</span><select x-model="researchForms.observation.definitionId" @change="syncObservationDefinition()" required><option value="">Choose metric</option><template x-for="item in data.definitions" :key="item.id"><option :value="item.id" x-text="item.layer+' · '+item.dimension+' · '+item.label"></option></template></select></label><label><span>Segment</span><select x-model="researchForms.observation.segmentCode"><template x-for="segment in data.segments" :key="segment.code"><option :value="segment.code" x-text="segment.name"></option></template></select></label></div>
        <div x-show="selectedMetricDefinition" class="metric-context"><span x-text="selectedMetricDefinition?.layer"></span><strong x-text="selectedMetricDefinition?.label"></strong><small x-text="selectedMetricDefinition?.unit || selectedMetricDefinition?.valueType"></small></div>
        <label x-show="selectedMetricDefinition?.valueType==='numeric'"><span>Numeric value</span><input type="number" step="any" x-model="researchForms.observation.numericValue"></label>
        <label x-show="selectedMetricDefinition?.valueType==='boolean'"><span>Observed result</span><select x-model="researchForms.observation.booleanValue"><option value="">Choose result</option><option value="true">Yes</option><option value="false">No</option></select></label>
        <label x-show="selectedMetricDefinition?.valueType==='text'"><span>Text value</span><input x-model.trim="researchForms.observation.textValue"></label>
        <div class="form-grid form-grid-three"><label><span>Respondent</span><select x-model="researchForms.observation.respondentId" @change="syncResearchSession('observation')"><option value="">Aggregate or unlinked</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId"></option></template></select></label><label><span>Session</span><select x-model="researchForms.observation.sessionId"><option value="">No session</option><template x-for="item in researchSessionsFor('observation')" :key="item.id"><option :value="item.id" x-text="formatDate(item.sessionDate)+' · '+item.method"></option></template></select></label><label><span>Source link</span><input type="url" x-model.trim="researchForms.observation.sourceLink" placeholder="https://"></label></div>
        <label><span>Notes</span><textarea rows="3" x-model.trim="researchForms.observation.notes"></textarea></label>
      </form>

      <div x-show="researchNotice" class="admin-notice" :class="researchNotice?.tone" x-text="researchNotice?.text" role="status"></div>
      <div class="collection-actions"><button class="button button-secondary" :disabled="savingResearch" @click="saveResearchRecord(collectionType,'draft')">Save draft</button><button class="button button-primary" :disabled="savingResearch" @click="saveResearchRecord(collectionType,'submitted')" x-text="savingResearch ? 'Saving…' : 'Submit for review'"></button></div>
    </article>
  </section>

  <section x-show="collectMode==='create'" class="panel attachment-workspace">
    <div class="panel-heading"><div><span class="eyebrow">Private research files</span><h2>Upload only what current consent permits.</h2></div><span class="privacy-chip">Private bucket</span></div>
    <div class="attachment-grid">
      <label><span>Respondent</span><select x-model="attachmentForm.respondentId"><option value="">Choose respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.segmentName"></option></template></select></label>
      <label><span>File class</span><select x-model="attachmentForm.bucketId"><option value="aoi-sources">Research source</option><option value="aoi-consent">Consent document</option><option value="aoi-recordings">Recording</option><option value="aoi-oral-images">Oral image</option></select></label>
      <label class="upload-control"><span>Choose file</span><input type="file" :disabled="uploadingAttachment" @change="uploadAttachment($event)"><small>Recordings and oral images require an active matching consent version.</small></label>
    </div>
    <div class="consent-version-form">
      <div><span class="eyebrow">Append-only consent</span><strong>Record a new version when permission changes.</strong><small>A withdrawal immediately restricts active recordings and oral images.</small></div>
      <label><span>Respondent</span><select x-model="consentForm.respondentId"><option value="">Choose respondent</option><template x-for="item in researchRespondents" :key="item.id"><option :value="item.id" x-text="item.externalId+' · '+item.consentStatus"></option></template></select></label>
      <label><span>New status</span><select x-model="consentForm.status"><option value="granted">Granted</option><option value="pending">Pending</option><option value="declined">Declined</option><option value="withdrawn">Withdrawn</option><option value="expired">Expired</option></select></label>
      <fieldset class="permission-grid"><legend>Current permissions</legend><label><input type="checkbox" x-model="consentForm.interviewAllowed"> Interview</label><label><input type="checkbox" x-model="consentForm.recordingAllowed"> Recording</label><label><input type="checkbox" x-model="consentForm.imagesAllowed"> Oral images</label><label><input type="checkbox" x-model="consentForm.quotationAllowed"> Quotation</label><label><input type="checkbox" x-model="consentForm.recontactAllowed"> Recontact</label></fieldset>
      <label x-show="consentForm.status==='withdrawn'"><span>Withdrawal reason</span><input x-model.trim="consentForm.withdrawalReason"></label>
      <button class="button button-secondary" @click="saveConsentVersion()">Record consent version</button>
    </div>
  </section>

  <div x-show="selectedCollectRecord" class="modal-backdrop drawer-backdrop" @mousedown.self="closeCollectRecord()">
    <aside class="collect-detail-drawer" role="dialog" aria-modal="true" aria-labelledby="collect-detail-title" tabindex="-1" @keydown.escape.stop="closeCollectRecord()" @keydown.tab="trapCollectDetailFocus($event)">
      <div class="drawer-header"><span class="eyebrow" x-text="selectedCollectRecord?.recordType.replaceAll('_',' ')"></span><button class="icon-button" @click="closeCollectRecord()" aria-label="Close">×</button></div>
      <div class="collect-detail-title"><span class="status-badge" :class="'status-'+selectedCollectRecord?.workflowStatus" x-text="selectedCollectRecord?.workflowStatus.replaceAll('_',' ')"></span><h2 id="collect-detail-title" x-text="selectedCollectRecord?.title"></h2><p x-text="selectedCollectRecord?.identityTrail||'No additional external identities'"></p></div>
      <div x-show="loadingCollectDetail" class="empty-state compact"><strong>Loading the auditable record…</strong></div>
      <template x-if="collectDetail"><div class="collect-detail-body">
        <section class="collect-detail-facts"><div><span>Respondent</span><strong x-text="selectedCollectRecord?.respondentCode||'Unlinked'"></strong></div><div><span>Segment</span><strong x-text="selectedCollectRecord?.segmentName||'Not set'"></strong></div><div><span>Owner</span><strong x-text="selectedCollectRecord?.ownerName||'Shared contributor'"></strong></div><div><span>Updated</span><strong x-text="formatDate(selectedCollectRecord?.recordDate)"></strong></div></section>
        <section x-show="selectedCollectRecord?.recordType==='respondent'" class="respondent-profile"><span class="eyebrow">Respondent profile</span><h3>Connected research timeline</h3><div class="respondent-profile-counts"><span><strong x-text="collectDetail.sessions?.length||0"></strong> sessions</span><span><strong x-text="collectDetail.evidence?.length||0"></strong> evidence</span><span><strong x-text="collectDetail.productEvents?.length||0"></strong> product events</span><span><strong x-text="collectDetail.valueExchange?.length||0"></strong> value records</span><span><strong x-text="collectDetail.consentHistory?.length||0"></strong> consent versions</span><span><strong x-text="collectDetail.attachments?.length||0"></strong> files</span></div></section>
        <section class="collect-provenance"><span class="eyebrow">Provenance and review</span><p x-text="selectedCollectRecord?.limitations||selectedCollectRecord?.notes||'No limitations or notes recorded.'"></p><a x-show="safeSourceUrl(selectedCollectRecord?.sourceLink)" :href="safeSourceUrl(selectedCollectRecord?.sourceLink)" target="_blank" rel="noopener noreferrer">Open source ↗</a><small x-show="selectedCollectRecord?.consentStatus" x-text="'Consent: '+selectedCollectRecord.consentStatus"></small><small x-show="selectedCollectRecord?.reviewNotes" x-text="'Review note: '+selectedCollectRecord.reviewNotes"></small></section>
        <section x-show="selectedCollectRecord?.respondentId||selectedCollectRecord?.recordType==='respondent'" class="collect-follow-on"><span class="eyebrow">Continue collection</span><div><button class="button button-secondary" @click="closeCollectRecord();startCollectionRecord('session',selectedCollectRecord?.respondentId||selectedCollectRecord?.id)">New session</button><button class="button button-secondary" @click="closeCollectRecord();startCollectionRecord('evidence',selectedCollectRecord?.respondentId||selectedCollectRecord?.id)">New evidence</button><button class="button button-secondary" @click="closeCollectRecord();startCollectionRecord('product_event',selectedCollectRecord?.respondentId||selectedCollectRecord?.id)">Product event</button></div></section>
      </div></template>
    </aside>
  </div>
</div>`;

export const pmfAnalysisTemplate = String.raw`
<div x-show="view==='research' && researchTab==='analyze'" class="pmf-surface">
  <section class="page-intro analysis-intro"><div><span class="eyebrow">PMF analysis</span><h1>Compare approved signals, then decide.</h1><p>Drafts and submitted records remain outside the matrix until an administrator approves them.</p></div><div class="analysis-proof"><span>Approved-only aggregation</span><strong>5 layers · explainable rules</strong></div></section>

  <div class="layer-tabs" role="tablist" aria-label="PMF layer"><template x-for="layer in data.pmfLayers" :key="layer.code"><button role="tab" :aria-selected="matrixLayer===layer.code" :class="matrixLayer===layer.code && 'active'" @click="matrixLayer=layer.code"><span x-text="layer.code"></span><strong x-text="layer.name"></strong><small x-text="data.evidence.filter(item=>item.pmfLayer===layer.code&&item.workflowStatus==='approved').length+' approved evidence'"></small></button></template></div>

  <section class="panel matrix-panel">
    <div class="panel-heading"><div><span class="eyebrow">Segment comparison matrix</span><h2 x-text="(data.pmfLayers.find(item=>item.code===matrixLayer)?.name||matrixLayer)+' evidence readout'"></h2></div><span class="matrix-count" x-text="activeMatrixRows.length+(activeMatrixRows.length===1?' metric':' metrics')"></span></div>
    <div class="matrix-scroll"><table class="pmf-matrix"><thead><tr><th>Dimension and metric</th><template x-for="segment in data.segments" :key="segment.code"><th><span x-text="segment.name"></span></th></template></tr></thead><tbody><template x-for="row in activeMatrixRows" :key="row.id"><tr><th><small x-text="row.dimension"></small><strong x-text="row.label"></strong><span x-text="row.unit||row.valueType"></span></th><template x-for="segment in data.segments" :key="segment.code"><td><strong x-text="row.values[segment.code]?.display||'—'"></strong><small x-text="'n='+(row.values[segment.code]?.sampleSize||0)"></small></td></template></tr></template><tr x-show="activeMatrixRows.length===0"><td :colspan="data.segments.length+1"><div class="matrix-empty"><strong>No approved observations yet</strong><span>Collect structured observations and approve them to populate this layer.</span><button class="text-button" @click="setView('collect');collectionType='observation'">Collect an observation →</button></div></td></tr></tbody></table></div>
  </section>

  <section class="analysis-grid">
    <article class="panel recommendation-panel"><div class="panel-heading"><div><span class="eyebrow">Deterministic recommendations</span><h2>Rules that show their work.</h2></div></div><div class="recommendation-list"><template x-for="item in pmfRecommendations" :key="item.id"><article class="recommendation-card" :class="'recommendation-'+item.priority"><span class="recommendation-icon" x-text="item.priority==='critical'?'!':'→'"></span><div><strong x-text="item.title"></strong><p x-text="item.reason"></p><small x-text="item.action"></small></div></article></template><div x-show="pmfRecommendations.length===0" class="empty-state compact"><strong>No rule-based action is currently triggered.</strong><p>Keep collecting counterevidence and monitor sample coverage.</p></div></div></article>

    <article class="panel review-panel"><div class="panel-heading"><div><span class="eyebrow">Review queue</span><h2 x-text="access.role==='admin' ? 'Approve evidence into analysis.' : 'Track your submitted records.'"></h2></div><span class="review-count" x-text="reviewQueue.length"></span></div><div class="review-list"><template x-for="record in reviewQueue" :key="record.recordType+'-'+record.id"><article class="review-row"><div><span class="status-badge status-submitted" x-text="record.recordType.replaceAll('_',' ')"></span><strong x-text="record.title"></strong><small x-text="record.submittedAt ? formatDate(record.submittedAt.slice(0,10)) : 'Awaiting review'"></small></div><template x-if="access.role==='admin'"><div class="review-actions"><input x-model.trim="reviewNotes[record.id]" placeholder="Review note"><button class="button button-secondary" :disabled="reviewingRecord===record.id" @click="reviewResearchRecord(record,'request_revision')">Revise</button><button class="button button-primary" :disabled="reviewingRecord===record.id" @click="reviewResearchRecord(record,'approve')">Approve</button></div></template></article></template><div x-show="reviewQueue.length===0" class="empty-state compact"><strong>The queue is clear.</strong><p>Submitted records will appear here with their provenance and workflow type.</p></div></div></article>
  </section>

  <section x-show="access.role==='admin'" class="panel gate-builder">
    <div><span class="eyebrow">Decision control</span><h2>Prepare Gate snapshot</h2><p>Freeze the current approved evidence readout with a decision and rationale. Snapshots are administrator-only.</p></div>
    <div class="gate-fields"><label><span>Layer</span><select x-model="gateForm.pmfLayer"><template x-for="layer in data.pmfLayers" :key="layer.code"><option :value="layer.code" x-text="layer.code+' · '+layer.name"></option></template></select></label><label><span>Decision</span><select x-model="gateForm.decision"><option value="go">Go</option><option value="revise">Revise</option><option value="stop">Stop</option><option value="insufficient">Insufficient evidence</option></select></label><label class="gate-rationale"><span>Rationale</span><textarea rows="3" minlength="10" x-model.trim="gateForm.rationale" placeholder="State the decision, strongest evidence, counterevidence, and limitation."></textarea></label><button class="button button-primary" @click="prepareGateSnapshot()">Create snapshot</button></div>
    <div x-show="gateNotice" class="admin-notice" :class="gateNotice?.tone" x-text="gateNotice?.text" role="status"></div>
  </section>
</div>`.replace("@click=\"setView('collect');collectionType='observation'\"", "@click=\"setResearchTab('collect');startCollectionRecord('observation')\"");
