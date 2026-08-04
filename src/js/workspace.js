import {
  addEvidence,
  appendConsentVersion,
  createAdminTask,
  createAdminUser,
  createGateSnapshot,
  importCandidates,
  logCrmActivity,
  listAdminUsers,
  loadDashboard,
  logOutreach,
  reviewResearchRecord as persistResearchReview,
  saveResearchRecord as persistResearchRecord,
  uploadResearchAttachment,
  upsertCandidate,
  upsertCrmContact,
} from "./api.js";
import { getExistingWorkspaceAccess, signOut } from "./auth.js";
import { clamp, csvCell, initials, pageUrl, readableError, routeForRole, scopePreviewDashboard } from "./core.js";
import { fallbackDashboard } from "./demo-data.js";
import { translate, translateData } from "./i18n.js";
import { buildCandidateExport, buildRecommendations, parseCandidateFile } from "./operations.js";
import { buildLayerMatrices, buildPmfRecommendations, validateResearchRecord } from "./pmf.js";
import { buildTodayQueue, contactCompleteness, createContactDraft, rewardForAction } from "./crm.js";

function defaultTask() {
  const date = new Date();
  date.setDate(date.getDate() + 7);
  return {
    title: "",
    objective: "",
    priority: "medium",
    dueDate: date.toISOString().slice(0, 10),
    pmfLayer: "H1 · Need Truth",
    assignedTo: "",
    estimatedHours: 4,
    points: 100,
  };
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function defaultResearchForms() {
  return {
    respondent: {
      externalId: "", segmentCode: "families", respondentType: "Consumer", specialtyStatus: "",
      ageChildAge: "", recruitmentSource: "", consentStatus: "pending", stage: "Concept",
      status: "recruiting", contactName: "", email: "", phone: "", preferredChannel: "Email",
      interviewAllowed: false, recordingAllowed: false, imagesAllowed: false,
      quotationAllowed: false, recontactAllowed: false, notes: "", retentionReviewAt: "",
    },
    session: {
      respondentId: "", pmfLayer: "H1", method: "JTBD interview", sessionDate: today(),
      currentBehavior: "", biggestHassle: "", recentIncident: "", currentAction: "",
      unmetNeed: "", limitations: "",
    },
    evidence: {
      respondentId: "", sessionId: "", segmentCode: "families", pmfLayer: "H1",
      dimension: "Frequency", topic: "", evidenceType: "Interview", stance: "supporting",
      strength: 2, title: "", evidenceText: "", sourceLink: "", decisionRelevance: "",
      consentStatus: "not_applicable", followUpNeeded: false, limitations: "", notes: "",
    },
    product_event: {
      respondentId: "", eventDate: today(), studyWeek: 0, triggerType: "Natural Trigger",
      triggerDescription: "", targetUser: "Self", sessionDurationMinutes: "",
      captureSuccess: "", validImage: "", compareUsed: "", resultUnderstood: "",
      valueObtained: "", actionTaken: "", sharedWithDoctor: "", mainFriction: "", notes: "",
    },
    value_exchange: {
      respondentId: "", observedAt: today(), hardwarePrice: 259, reasonablePriceMin: "",
      reasonablePriceMax: "", purchaseIntent: 3, preferredOffer: "Hardware + basic app",
      subscriptionPlan: "None", commitmentType: "None", commitmentAmount: "",
      mainObjection: "", postTrialPurchaseIntent: "", notes: "",
    },
    observation: {
      definitionId: "", segmentCode: "families", respondentId: "", sessionId: "",
      numericValue: "", booleanValue: "", textValue: "", sourceLink: "", notes: "",
    },
  };
}

function downloadCsv(filename, rows) {
  const content = `\uFEFF${rows.map((row) => row.map(csvCell).join(",")).join("\r\n")}`;
  const url = URL.createObjectURL(new Blob([content], { type: "text/csv;charset=utf-8" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function registerWorkspace(Alpine) {
  Alpine.data("workspacePage", () => ({
    expectedRole: document.body.dataset.expectedRole,
    loginUrl: pageUrl(import.meta.env.BASE_URL, "login.html"),
    access: null,
    data: fallbackDashboard,
    users: [],
    ready: false,
    loading: true,
    loadingUsers: false,
    preview: false,
    error: "",
    view: document.body.dataset.expectedRole === "intern" ? "today" : "overview",
    locale: localStorage.getItem("aoi-locale") === "zh-CN" ? "zh-CN" : "en",
    dark: localStorage.getItem("aoi-theme") === "dark",
    mobileNav: false,
    sidebarCollapsed: false,
    commandOpen: false,
    notificationOpen: false,
    notificationsRead: false,
    query: "",
    taskFilter: "all",
    selectedTask: null,
     selectedLayer: null,
      selectedCandidate: null,
      candidateEditorOpen: false,
     candidateFilter: "all",
     candidateQuery: "",
      candidateNotice: null,
      selectedCrmContact: null,
      crmEditorOpen: false,
      crmQuery: "",
      crmFilter: "all",
      crmNotice: null,
      crmActionNotice: null,
      crmActionSaving: false,
      crmSaving: false,
      crmForm: createContactDraft(),
      crmActionForm: { activityType: "follow_up", summary: "", nextAction: "", nextActionDue: "", lifecycle: "" },
     importPreview: null,
     importErrors: [],
      importFileName: "",
      importFileFormat: "csv",
      importing: false,
      collectionType: "respondent",
      researchForms: defaultResearchForms(),
      researchNotice: null,
      savingResearch: false,
      reviewNotes: {},
      reviewingRecord: null,
      matrixLayer: "H1",
      gateForm: { pmfLayer: "H1", decision: "insufficient", rationale: "" },
      gateNotice: null,
      attachmentForm: { respondentId: "", sessionId: "", bucketId: "aoi-sources" },
      consentForm: { respondentId: "", status: "granted", interviewAllowed: true, recordingAllowed: false, imagesAllowed: false, quotationAllowed: false, recontactAllowed: false, withdrawalReason: "" },
      uploadingAttachment: false,
     candidateForm: { name: "", category: "Dental Professional", platforms: "", reach: "", tier: "Micro", contactReadiness: "Research needed", contactChannel: "", contactDetail: "", pmfCandidate: false, ownerName: "", outreachStatus: "Not Contacted", nextStep: "", nextStepDue: "", sourceUrl: "", notes: "" },
     outreachForm: { channel: "Email", kind: "Initial", status: "Drafted", summary: "" },
     evidenceForm: { type: "PMF interview", stance: "supporting", strength: 3, title: "", notes: "", consentStatus: "pending" },
    toast: null,
    bonusXp: 0,
    savingUser: false,
    savingTask: false,
    userNotice: null,
    taskNotice: null,
    userForm: { displayName: "", email: "", password: "", role: "intern" },
    taskForm: defaultTask(),
      navigation: [
        { id: "overview", label: "Overview" },
        { id: "today", label: "Today" },
        { id: "crm", label: "CRM" },
        { id: "work", label: "My work" },
       { id: "collect", label: "Collect" },
       { id: "outreach", label: "Outreach" },
       { id: "evidence", label: "Evidence" },
       { id: "analyze", label: "Analyze" },
       { id: "imports", label: "Imports" },
       { id: "reports", label: "Reports" },
       { id: "team", label: "Team momentum" },
     ],

    async init() {
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
      document.documentElement.lang = this.locale;

      if (new URLSearchParams(location.search).get("preview") === "1") {
        const previewName = this.expectedRole === "admin" ? "AOI Administrator" : "Kayla Tillmon";
        this.access = {
          role: this.expectedRole,
          displayName: previewName,
          organizationName: fallbackDashboard.organization.name,
          locale: this.locale,
        };
        this.data = scopePreviewDashboard(fallbackDashboard, this.expectedRole, previewName);
        this.preview = true;
        this.ready = true;
        this.loading = false;
        if (this.expectedRole === "admin") await this.loadPreviewUsers();
        return;
      }

      try {
        const access = await getExistingWorkspaceAccess();
        if (!access) {
          location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
          return;
        }
        if (access.role !== this.expectedRole) {
          location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
          return;
        }
        this.access = access;
        this.locale = localStorage.getItem("aoi-locale") || access.locale || "en";
        document.documentElement.lang = this.locale;
        this.ready = true;
        await this.refreshDashboard();
        if (access.role === "admin") await this.refreshUsers();
      } catch (reason) {
        this.error = readableError(reason, "Unable to open the AOI workspace.");
        this.ready = true;
      } finally {
        this.loading = false;
      }
    },

    t(key) { return translate(this.locale, key); },
    td(value) { return translateData(this.locale, value ?? ""); },
    initials,
    clamp,
    statusLabel(status) { return this.t(`status_${status}`); },
    priorityLabel(priority) { return this.t(`priority_${priority}`); },
    progressTone(value) { return value >= 70 ? "teal" : value >= 40 ? "orange" : "muted"; },
    formatDate(value) {
      if (!value) return "No date";
      const parsed = new Date(/^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T12:00:00` : value);
      return Number.isNaN(parsed.getTime()) ? "Invalid date" : new Intl.DateTimeFormat(this.locale, { month: "short", day: "numeric" }).format(parsed);
    },
    relativeTime(value) {
      const minutes = Math.max(1, Math.round((new Date(this.data.generatedAt).getTime() - new Date(value).getTime()) / 60000));
      if (this.locale === "zh-CN") return minutes < 60 ? `${minutes} 分钟前` : `${Math.round(minutes / 60)} 小时前`;
      return minutes < 60 ? `${minutes}m ago` : `${Math.round(minutes / 60)}h ago`;
    },
    samplePercent(item) { return Math.round((item.actual / Math.max(1, item.target)) * 100); },
    get overallSample() {
      const actual = this.data.samplePlan.reduce((sum, item) => sum + item.actual, 0);
      const target = this.data.samplePlan.reduce((sum, item) => sum + item.target, 0);
      return Math.round((actual / Math.max(1, target)) * 100);
    },
    get filteredTasks() {
      if (this.taskFilter === "attention") return this.data.tasks.filter((task) => ["blocked", "revision_requested"].includes(task.status));
      if (this.taskFilter === "progress") return this.data.tasks.filter((task) => ["assigned", "in_progress"].includes(task.status));
      if (this.taskFilter === "submitted") return this.data.tasks.filter((task) => task.status === "submitted");
      return this.data.tasks;
    },
    get focusTasks() { return this.data.tasks.filter((task) => ["submitted", "revision_requested", "blocked"].includes(task.status)).slice(0, 3); },
    get activeUsers() { return this.users.filter((user) => user.membership_status === "active"); },
    get interns() { return this.activeUsers.filter((user) => user.role === "intern"); },
    get commandPages() {
      const value = this.query.trim().toLowerCase();
      return this.navigation.filter((item) => !value || item.label.toLowerCase().includes(value));
    },
    get commandTasks() {
      const value = this.query.trim().toLowerCase();
      return this.data.tasks.filter((task) => !value || task.title.toLowerCase().includes(value)).slice(0, 5);
    },
    get candidates() { return this.data.candidates || []; },
    get crmContacts() { return this.data.crmContacts || []; },
    get crmQueue() { return buildTodayQueue(this.crmContacts, today()); },
    get filteredCrmContacts() {
      const query = this.crmQuery.trim().toLowerCase();
      return this.crmContacts.filter((contact) => {
        const matchesQuery = !query || [contact.name, contact.organization, contact.contactType, contact.ownerName, contact.lifecycle, contact.outreachStatus].some((value) => String(value || "").toLowerCase().includes(query));
        const matchesFilter = this.crmFilter === "all" || (this.crmFilter === "mine" && contact.ownerName === this.access?.displayName) || (this.crmFilter === "attention" && (contact.queueReason === "Overdue" || (contact.completeness || contactCompleteness(contact)) < 100)) || (this.crmFilter === "qualified" && contact.lifecycle === "qualified");
        return matchesQuery && matchesFilter;
      });
    },
    get crmStats() {
      const queue = this.crmQueue;
      return {
        total: this.crmContacts.length,
        due: queue.filter((contact) => ["Overdue", "Due today"].includes(contact.queueReason)).length,
        needsEnrichment: this.crmContacts.filter((contact) => (contact.completeness || contactCompleteness(contact)) < 100).length,
        xp: this.data.crmProgress?.xp || 0,
      };
    },
    contactCompleteness,
    get filteredCandidates() {
      const query = this.candidateQuery.trim().toLowerCase();
      return this.candidates.filter((candidate) => {
        const matchesQuery = !query || [candidate.name, candidate.category, candidate.ownerName, candidate.outreachStatus].some((value) => String(value || "").toLowerCase().includes(query));
        const matchesFilter = this.candidateFilter === "all" || (this.candidateFilter === "attention" && ["Unreachable", "Research needed", "No Response"].includes(candidate.contactReadiness || candidate.outreachStatus)) || (this.candidateFilter === "ready" && ["Ready to Send", "Email ready", "Form ready", "Social DM ready"].includes(candidate.outreachStatus || candidate.contactReadiness)) || (this.candidateFilter === "pmf" && candidate.pmfCandidate);
        return matchesQuery && matchesFilter;
      });
    },
    get candidateStats() {
      const candidates = this.candidates;
      return {
        total: candidates.length,
        ready: candidates.filter((candidate) => !["Research needed", "Unreachable"].includes(candidate.contactReadiness)).length,
        pmf: candidates.filter((candidate) => candidate.pmfCandidate).length,
        followUps: candidates.filter((candidate) => candidate.nextStepDue && candidate.nextStepDue <= new Date().toISOString().slice(0, 10)).length,
      };
    },
    get researchRespondents() { return this.data.respondents || []; },
    get reviewQueue() { return this.data.reviewQueue || []; },
    get pmfMatrices() {
      return buildLayerMatrices({
        segments: this.data.segments || [],
        definitions: this.data.definitions || [],
        observations: this.data.observations || [],
      });
    },
    get activeMatrixRows() { return this.pmfMatrices[this.matrixLayer] || []; },
    get pmfRecommendations() {
      return buildPmfRecommendations({
        reviewQueue: this.reviewQueue,
        samplePlan: this.data.samplePlan || [],
        evidence: this.data.evidence || [],
        respondents: this.researchRespondents,
      });
    },
    get researchStats() {
      return {
        respondents: this.researchRespondents.length,
        sessions: (this.data.sessions || []).length,
        approvedEvidence: (this.data.evidence || []).filter((item) => item.workflowStatus === "approved").length,
        pendingReview: this.reviewQueue.length,
      };
    },
    get selectedMetricDefinition() {
      return (this.data.definitions || []).find((item) => item.id === this.researchForms.observation.definitionId) || null;
    },

    setView(view) {
      view = { research: "collect", pmf: "analyze" }[view] || view;
      if (view === "admin" && this.access?.role !== "admin") return;
      this.view = view;
      this.mobileNav = false;
      this.commandOpen = false;
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    toggleTheme() {
      this.dark = !this.dark;
      localStorage.setItem("aoi-theme", this.dark ? "dark" : "light");
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
    },
    toggleLocale() {
      this.locale = this.locale === "en" ? "zh-CN" : "en";
      localStorage.setItem("aoi-locale", this.locale);
      document.documentElement.lang = this.locale;
    },
    showToast(title, body) {
      this.toast = { title, body };
      setTimeout(() => { this.toast = null; }, 4200);
    },
    selectTask(task) { this.selectedTask = { ...task }; },
    selectCandidate(candidate) {
      this.selectedCandidate = { ...candidate };
      this.candidateForm = { ...this.candidateForm, ...candidate };
      this.candidateEditorOpen = true;
    },
    closeCandidate() {
      this.selectedCandidate = null;
      this.candidateEditorOpen = false;
      this.candidateNotice = null;
    },
    selectCrmContact(contact) {
      this.selectedCrmContact = { ...contact };
      this.crmForm = { ...createContactDraft(this.access?.displayName || ""), ...contact };
      this.crmActionForm = { activityType: "follow_up", summary: "", nextAction: contact.nextAction || "", nextActionDue: contact.nextActionDue || "", lifecycle: contact.lifecycle || "" };
      this.crmNotice = null;
      this.crmActionNotice = null;
      this.crmEditorOpen = true;
    },
    startNewCrmContact() {
      this.selectedCrmContact = null;
      this.crmForm = createContactDraft(this.access?.displayName || "");
      this.crmActionForm = { activityType: "follow_up", summary: "", nextAction: "", nextActionDue: "", lifecycle: "" };
      this.crmNotice = null;
      this.crmActionNotice = null;
      this.crmEditorOpen = true;
      this.view = "crm";
    },
    closeCrmContact() {
      this.selectedCrmContact = null;
      this.crmEditorOpen = false;
      this.crmNotice = null;
      this.crmActionNotice = null;
    },
    async saveCrmContact() {
      const completeness = contactCompleteness(this.crmForm);
      if (!this.crmForm.name.trim()) {
        this.crmNotice = { tone: "error", text: "Add a person or organization name before saving." };
        return;
      }
      const reward = rewardForAction("enrich", completeness);
      let awarded = reward;
      let saved = { ...this.crmForm, id: this.selectedCrmContact?.id || `crm-local-${Date.now()}`, candidateId: this.selectedCrmContact?.candidateId || null, completeness, priorityScore: this.selectedCrmContact?.priorityScore || 50, lastUpdated: today() };
      this.crmSaving = true;
      try {
        if (!this.preview) {
          const persisted = await upsertCrmContact({ ...saved, createOutreach: true });
          awarded = persisted.rewardPoints || 0;
          saved = { ...saved, ...persisted };
        }
        this.data.crmContacts = this.selectedCrmContact ? this.crmContacts.map((contact) => contact.id === saved.id ? { ...contact, ...saved, completeness } : contact) : [{ ...saved, completeness }, ...this.crmContacts];
        this.data.crmProgress = { ...(this.data.crmProgress || {}), xp: (this.data.crmProgress?.xp || 0) + awarded, completedToday: (this.data.crmProgress?.completedToday || 0) + (awarded > 0 ? 1 : 0) };
        this.selectedCrmContact = { ...saved, completeness };
        this.crmForm = { ...this.crmForm, ...saved };
        this.crmNotice = { tone: "success", text: awarded ? `Saved. +${awarded} XP for verified enrichment.` : "Saved. Today's enrichment reward was already recorded." };
      } catch (reason) {
        this.crmNotice = { tone: "error", text: readableError(reason, "Unable to save the CRM contact.") };
      } finally {
        this.crmSaving = false;
      }
    },
    async logCrmAction() {
      if (!this.selectedCrmContact || !this.crmActionForm.summary.trim()) {
        this.crmActionNotice = { tone: "error", text: "Add a short outcome before logging the action." };
        return;
      }
      this.crmActionSaving = true;
      const reward = rewardForAction(this.crmActionForm.activityType, contactCompleteness(this.crmForm));
      let awarded = reward;
      try {
        if (!this.preview) awarded = (await logCrmActivity(this.selectedCrmContact.id, this.crmActionForm)).rewardPoints || 0;
        const updated = { ...this.selectedCrmContact, nextAction: this.crmActionForm.nextAction || this.selectedCrmContact.nextAction, nextActionDue: this.crmActionForm.nextActionDue || this.selectedCrmContact.nextActionDue, lifecycle: this.crmActionForm.lifecycle || this.selectedCrmContact.lifecycle };
        this.data.crmContacts = this.crmContacts.map((contact) => contact.id === updated.id ? updated : contact);
        this.data.crmActivity = [{ id: `crm-activity-local-${Date.now()}`, contactId: updated.id, activityType: this.crmActionForm.activityType, summary: this.crmActionForm.summary, actorName: this.access?.displayName || "AOI", createdAt: new Date().toISOString() }, ...(this.data.crmActivity || [])];
        this.data.crmProgress = { ...(this.data.crmProgress || {}), xp: (this.data.crmProgress?.xp || 0) + awarded, completedToday: (this.data.crmProgress?.completedToday || 0) + (awarded > 0 ? 1 : 0) };
        this.selectedCrmContact = updated;
        this.crmForm = { ...this.crmForm, ...updated };
        this.crmActionForm = { ...this.crmActionForm, summary: "" };
        this.crmActionNotice = { tone: "success", text: awarded ? `Action logged. +${awarded} XP.` : "Action logged. Today's reward for this action was already recorded." };
      } catch (reason) {
        this.crmActionNotice = { tone: "error", text: readableError(reason, "Unable to log the CRM action.") };
      } finally {
        this.crmActionSaving = false;
      }
    },
    async saveCandidate() {
      let candidate = { ...this.candidateForm, id: this.selectedCandidate?.id || null, externalId: this.selectedCandidate?.externalId || "", priorityScore: this.selectedCandidate?.priorityScore || 50, priorityBand: this.selectedCandidate?.priorityBand || "Medium", interestLevel: this.selectedCandidate?.interestLevel || "Unknown", lastUpdated: new Date().toISOString().slice(0, 10) };
      if (!candidate.name.trim()) {
        this.candidateNotice = { tone: "error", text: "Add a creator or organization name before saving." };
        return;
      }
      if (!this.preview) {
        try {
          const saved = await upsertCandidate(candidate);
          candidate = { ...candidate, ...saved };
        } catch (reason) {
          this.candidateNotice = { tone: "error", text: readableError(reason, "Unable to save the candidate.") };
          return;
        }
      }
      this.data.candidates = this.selectedCandidate ? this.candidates.map((item) => item.id === candidate.id ? candidate : item) : [candidate, ...this.candidates];
      this.selectedCandidate = { ...candidate };
      this.candidateNotice = { tone: "success", text: "Candidate record saved to this workspace view." };
      this.data.outreachSummary = { ...this.data.outreachSummary, totalCandidates: this.candidates.length };
    },
    startNewCandidate() {
      this.selectedCandidate = null;
      this.candidateEditorOpen = true;
      this.candidateForm = { name: "", category: "Dental Professional", platforms: "", reach: "", tier: "Micro", contactReadiness: "Research needed", contactChannel: "", contactDetail: "", pmfCandidate: false, ownerName: this.access?.displayName || "", outreachStatus: "Not Contacted", nextStep: "", nextStepDue: "", sourceUrl: "", notes: "" };
      this.candidateNotice = null;
      this.view = "outreach";
    },
    async importFile(event) {
      const file = event.target.files?.[0];
      if (!file) return;
      this.importFileName = file.name;
      try {
        const result = await parseCandidateFile(file);
        this.importPreview = result.rows;
        this.importErrors = result.errors;
        this.importFileFormat = result.fileFormat;
        this.candidateNotice = result.errors.length ? { tone: "error", text: `${result.errors.length} row(s) need attention before import.` } : { tone: "success", text: `${result.rows.length} candidate row(s) ready to import.` };
      } catch (reason) {
        this.importPreview = null;
        this.importErrors = [readableError(reason, "The workbook could not be read.")];
      }
    },
    async commitImport() {
      if (!this.importPreview?.length || this.importErrors.length) return;
      if (this.access?.role !== "admin") {
        this.candidateNotice = { tone: "error", text: "Submit this preview to an administrator for atomic import." };
        return;
      }
      this.importing = true;
      try {
        if (this.preview) throw new Error("Imports are disabled in preview mode.");
        const result = await importCandidates(this.importPreview, this.importFileName, this.importFileFormat);
        this.importPreview = null;
        this.importErrors = [];
        this.candidateNotice = { tone: "success", text: `${result.imported} candidates imported and persisted.` };
        await this.refreshDashboard();
      } catch (reason) {
        this.candidateNotice = { tone: "error", text: readableError(reason, "The import was rolled back.") };
      } finally {
        this.importing = false;
      }
    },
    exportCandidates(format) {
      const exported = buildCandidateExport(this.candidates);
      const content = format === "json" ? exported.json : exported.csv;
      const type = format === "json" ? "application/json" : "text/csv;charset=utf-8";
      const url = URL.createObjectURL(new Blob([content], { type }));
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `ambiloop-candidates.${format}`;
      anchor.click();
      URL.revokeObjectURL(url);
      this.showToast("Export ready", `${this.candidates.length} candidate records exported as ${format.toUpperCase()}.`);
    },
    async logOutreach() {
      if (!this.selectedCandidate || !this.outreachForm.summary.trim()) return;
      if (!this.preview) {
        try {
          await logOutreach(this.selectedCandidate.id, this.outreachForm);
        } catch (reason) {
          this.candidateNotice = { tone: "error", text: readableError(reason, "Unable to log outreach.") };
          return;
        }
      }
      this.data.outreachEvents = [{ id: `outreach-${Date.now()}`, candidateId: this.selectedCandidate.id, ...this.outreachForm, occurredAt: new Date().toISOString(), actorName: this.access?.displayName || "AOI" }, ...(this.data.outreachEvents || [])];
      this.candidates.splice(this.candidates.findIndex((item) => item.id === this.selectedCandidate.id), 1, { ...this.selectedCandidate, outreachStatus: this.outreachForm.status === "Sent" ? "Sent" : this.selectedCandidate.outreachStatus, lastUpdated: new Date().toISOString().slice(0, 10) });
      this.outreachForm = { channel: "Email", kind: "Initial", status: "Drafted", summary: "" };
      this.candidateNotice = { tone: "success", text: "Outreach activity logged with an auditable timestamp." };
    },
    async addEvidence() {
      if (!this.selectedCandidate || !this.evidenceForm.title.trim()) return;
      if (!this.preview) {
        try {
          await addEvidence(this.selectedCandidate.id, this.evidenceForm);
        } catch (reason) {
          this.candidateNotice = { tone: "error", text: readableError(reason, "Unable to add evidence.") };
          return;
        }
      }
      this.data.evidenceRecords = [{ id: `evidence-${Date.now()}`, candidateId: this.selectedCandidate.id, ...this.evidenceForm, recordedBy: this.access?.displayName || "AOI", recordedAt: new Date().toISOString().slice(0, 10) }, ...(this.data.evidenceRecords || [])];
      this.evidenceForm = { type: "PMF interview", stance: "supporting", strength: 3, title: "", notes: "", consentStatus: "pending" };
      this.candidateNotice = { tone: "success", text: "Evidence record added. Keep consent and limitations explicit." };
    },
    respondentSegmentCode(respondentId) {
      return this.researchRespondents.find((item) => item.id === respondentId)?.segmentCode || "families";
    },
    async saveResearchRecord(recordType, workflowStatus) {
      const form = this.researchForms[recordType];
      const payload = { ...form, workflowStatus };
      if (["session", "product_event", "value_exchange"].includes(recordType)) {
        payload.segmentCode = this.respondentSegmentCode(form.respondentId);
      }
      const errors = validateResearchRecord(recordType, payload, workflowStatus);
      if (errors.length) {
        this.researchNotice = { tone: "error", text: errors.join(" ") };
        return;
      }
      this.savingResearch = true;
      this.researchNotice = null;
      try {
        if (this.preview) {
          this.researchNotice = { tone: "success", text: `Preview ${recordType.replaceAll("_", " ")} validated. Live mode will persist it as ${workflowStatus}.` };
          return;
        }
        await persistResearchRecord(recordType, payload);
        this.researchForms[recordType] = defaultResearchForms()[recordType];
        this.researchNotice = { tone: "success", text: `${recordType.replaceAll("_", " ")} ${workflowStatus === "submitted" ? "submitted for review" : "saved as a draft"}.` };
        await this.refreshDashboard();
      } catch (reason) {
        this.researchNotice = { tone: "error", text: readableError(reason, "Unable to save the research record.") };
      } finally {
        this.savingResearch = false;
      }
    },
    async reviewResearchRecord(record, action) {
      if (this.access?.role !== "admin") return;
      this.reviewingRecord = record.id;
      this.researchNotice = null;
      try {
        if (this.preview) throw new Error("Review actions are disabled in preview mode.");
        await persistResearchReview(record.recordType, record.id, action, this.reviewNotes[record.id] || "");
        this.researchNotice = { tone: "success", text: action === "approve" ? "Record approved and included in analysis." : "Revision requested from the record owner." };
        await this.refreshDashboard();
      } catch (reason) {
        this.researchNotice = { tone: "error", text: readableError(reason, "Unable to review the record.") };
      } finally {
        this.reviewingRecord = null;
      }
    },
    async prepareGateSnapshot() {
      if (this.access?.role !== "admin") return;
      if (this.gateForm.rationale.trim().length < 10) {
        this.gateNotice = { tone: "error", text: "Add a decision rationale with at least ten characters." };
        return;
      }
      try {
        if (this.preview) throw new Error("Gate snapshots are disabled in preview mode.");
        await createGateSnapshot(this.gateForm.pmfLayer, this.gateForm.decision, this.gateForm.rationale);
        this.gateNotice = { tone: "success", text: `${this.gateForm.pmfLayer} Gate snapshot created.` };
        this.gateForm.rationale = "";
        await this.refreshDashboard();
      } catch (reason) {
        this.gateNotice = { tone: "error", text: readableError(reason, "Unable to create the Gate snapshot.") };
      }
    },
    async saveConsentVersion() {
      if (!this.consentForm.respondentId) {
        this.researchNotice = { tone: "error", text: "Choose a respondent before recording consent." };
        return;
      }
      try {
        if (this.preview) {
          this.researchNotice = { tone: "success", text: "Preview consent version validated. Live mode records it append-only." };
          return;
        }
        const saved = await appendConsentVersion(this.consentForm.respondentId, this.consentForm);
        this.researchNotice = { tone: "success", text: `Consent version ${saved.version} recorded as ${saved.status}.` };
        await this.refreshDashboard();
      } catch (reason) {
        this.researchNotice = { tone: "error", text: readableError(reason, "Unable to record the consent version.") };
      }
    },
    async uploadAttachment(event) {
      const file = event.target.files?.[0];
      const respondentId = this.attachmentForm.respondentId;
      if (!file || !respondentId) {
        this.researchNotice = { tone: "error", text: "Choose a respondent and a file before uploading." };
        return;
      }
      this.uploadingAttachment = true;
      try {
        if (this.preview) throw new Error("File uploads are disabled in preview mode.");
        await uploadResearchAttachment({
          bucketId: this.attachmentForm.bucketId,
          file,
          projectId: this.access.projectId,
          organizationId: this.access.organizationId,
          respondentId,
          sessionId: this.attachmentForm.sessionId || null,
        });
        this.researchNotice = { tone: "success", text: `${file.name} uploaded to private research storage.` };
        event.target.value = "";
      } catch (reason) {
        this.researchNotice = { tone: "error", text: readableError(reason, "Unable to upload the research file.") };
      } finally {
        this.uploadingAttachment = false;
      }
    },
    recommendations() {
      return this.data.recommendations?.length ? this.data.recommendations : buildRecommendations({ ...this.data.outreachSummary, ...this.data.campaign, categories: this.data.categories || [] });
    },
    completeCheckpoint() {
      if (!this.selectedTask) return;
      const reward = Math.min(80, Math.max(30, Math.round(this.selectedTask.points / 3)));
      const progress = clamp(this.selectedTask.progress + 18);
      this.data.tasks = this.data.tasks.map((task) => task.id === this.selectedTask.id ? { ...task, progress } : task);
      this.selectedTask.progress = progress;
      this.bonusXp += reward;
      this.showToast(this.t("actionDone"), `${this.t("actionDoneCopy")} +${reward} XP`);
    },
     async refreshDashboard() {
      this.loading = true;
      this.error = "";
      try {
         const liveData = await loadDashboard();
         this.data = {
           ...liveData,
           campaign: liveData.campaign || fallbackDashboard.campaign,
           outreachSummary: liveData.outreachSummary || { totalCandidates: 0, contactReady: 0, contacted: 0, responses: 0, interested: 0, confirmed: 0, pmfCandidates: 0, researchNeeded: 0 },
           categories: liveData.categories || [],
           candidates: liveData.candidates || [],
           outreachEvents: liveData.outreachEvents || [],
            evidenceRecords: liveData.evidenceRecords || [],
            crmContacts: liveData.crmContacts || [],
            crmActivity: liveData.crmActivity || [],
            crmProgress: liveData.crmProgress || { xp: 0, completedToday: 0, streakDays: 0 },
           recommendations: liveData.recommendations || [],
           segments: liveData.segments || [],
           respondents: liveData.respondents || [],
           sessions: liveData.sessions || [],
           evidence: liveData.evidence || [],
           productEvents: liveData.productEvents || [],
           valueExchange: liveData.valueExchange || [],
           definitions: liveData.definitions || [],
           observations: liveData.observations || [],
           hypotheses: liveData.hypotheses || [],
           reviewQueue: liveData.reviewQueue || [],
           gateSnapshots: liveData.gateSnapshots || [],
          };
        this.preview = false;
      } catch (reason) {
        this.error = readableError(reason, "Live workspace data is unavailable.");
      } finally {
        this.loading = false;
      }
    },
    usePreview() {
      this.data = scopePreviewDashboard(fallbackDashboard, this.expectedRole, this.access?.displayName);
      this.preview = true;
      this.error = "";
    },
    loadPreviewUsers() {
      this.users = fallbackDashboard.team.map((member, index) => ({
        user_id: member.id,
        display_name: member.displayName,
        login_identifier: `preview${index + 1}@aoi.example`,
        role: "intern",
        membership_status: "active",
        joined_at: fallbackDashboard.generatedAt,
      }));
    },
    async refreshUsers() {
      if (this.preview) return this.loadPreviewUsers();
      this.loadingUsers = true;
      try {
        this.users = await listAdminUsers();
      } catch (reason) {
        this.userNotice = { tone: "error", text: readableError(reason, "Unable to load workspace users.") };
      } finally {
        this.loadingUsers = false;
      }
    },
    async submitUser() {
      this.savingUser = true;
      this.userNotice = null;
      try {
        if (this.preview) throw new Error("Account creation is disabled in preview mode.");
        const created = await createAdminUser(this.userForm);
        this.users = [...this.users, created].sort((a, b) => a.display_name.localeCompare(b.display_name));
        this.userForm = { displayName: "", email: "", password: "", role: "intern" };
        this.userNotice = { tone: "success", text: `${created.display_name} can now sign in.` };
      } catch (reason) {
        this.userNotice = { tone: "error", text: readableError(reason, "Unable to create the user.") };
      } finally {
        this.savingUser = false;
      }
    },
    async submitTask() {
      this.savingTask = true;
      this.taskNotice = null;
      try {
        if (this.preview) throw new Error("Task creation is disabled in preview mode.");
        await createAdminTask(this.taskForm);
        this.taskForm = defaultTask();
        this.taskNotice = { tone: "success", text: "Task created and added to the AOI work queue." };
        await this.refreshDashboard();
      } catch (reason) {
        this.taskNotice = { tone: "error", text: readableError(reason, "Unable to create the task.") };
      } finally {
        this.savingTask = false;
      }
    },
    async copyPassword() {
      if (!this.userForm.password) return;
      await navigator.clipboard.writeText(this.userForm.password);
      this.userNotice = { tone: "success", text: "Temporary password copied. Share it through a secure channel." };
    },
    exportDashboard() {
      downloadCsv(`aoi-dashboard-${this.locale}.csv`, [
        ["metric_key", "label", "value", "target", "unit", "delta"],
        ...this.data.metrics.map((metric) => [metric.key, metric.label, metric.value, metric.target, metric.unit, metric.delta]),
      ]);
      this.showToast(this.t("exportSuccess"), this.t("demoNotice"));
    },
    exportEvidence() {
      downloadCsv(`aoi-evidence-${this.locale}.csv`, [
        ["theme", "stance", "evidence_count", "change_percent", "strength"],
        ...this.data.signals.map((signal) => [this.td(signal.theme), signal.stance, signal.evidenceCount, signal.changePercent, signal.strength]),
      ]);
      this.showToast(this.t("exportSuccess"), this.t("demoNotice"));
    },
    async logout() {
      await signOut();
      location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
    },
  }));
}
