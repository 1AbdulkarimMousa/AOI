import {
  addEvidence,
  adminSaveProject,
  adminUpdateDailyEodBrief,
  appendConsentVersion,
  createGateSnapshot,
  completeOnboardingStep,
  importCandidates,
  logCrmActivity,
  loadDailyEod,
  loadDailyEodReports,
  loadDashboard,
  loadCrmSnapshot,
  loadInbox,
  loadInboxItemDetail,
  loadOperationsSnapshot,
  loadCollectRecordDetail,
  loadProjectContext,
  loadProjectRecordDetail,
  loadProjectSnapshot,
  loadTaskDetail,
  loadTodayBriefing,
  markInboxRead,
  logOutreach,
  reviewTask,
  reviewResearchRecord as persistResearchReview,
  saveDailyEodBrief,
  saveResearchRecord as persistResearchRecord,
  saveProjectRecord as persistProjectRecord,
  setProjectMember as persistProjectMember,
  selectProjectContext,
  snoozePasswordReminder,
  updateTaskCheckpoint,
  updateResearchRecord as persistResearchUpdate,
  transitionProjectRecord as persistProjectTransition,
  transitionProject as persistProjectLifecycle,
  uploadResearchAttachment,
  upsertCandidate,
  upsertCrmContact,
} from "./api.js";
import { changePassword, getExistingWorkspaceAccess, signOut } from "./auth.js";
import { clamp, csvCell, initials, isSafeHttpUrl, localDateValue, pageUrl, readableError, routeForRole, safeHttpUrl, scopePreviewDashboard } from "./core.js";
import { emptyDashboard, fallbackDashboard } from "./demo-data.js";
import { translate, translateData } from "./i18n.js";
import { buildCandidateExport, buildRecommendations, parseCandidateFile } from "./operations.js";
import { buildLayerMatrices, buildPmfRecommendations, normalizeObservationValues, validateResearchRecord } from "./pmf.js";
import { shouldConfirmSurveyRoute } from "./surveys/analysis.js";
import { buildTodayQueue, contactCompleteness, createContactDraft, nextTabFromKey, resolveWorkspaceRoute, rewardForAction } from "./crm.js";
import { buildCollectIndex, filterCollectRecords, gamificationLevel, hydrateResearchRevisionForm, prefillResearchForm, restoreResearchDrafts } from "./collect.js";
import { createDailyEodDraft, createDailyEodDraftKey, dailyEodAttentionCount, filterDailyEodTeam, formatDailyEodTimestamp, isLegacyEvidenceException, readDailyEodDraft, toggleExecutiveOwner, validateDailyEodFields, writeDailyEodDraft } from "./daily-eod.js";
import { shouldShowPasswordReminder, snoozeUntil } from "./password-reminder.js";
import { createSurveyWorkspaceState } from "./surveys/workspace.js";
import { createChatState } from "./chat.js";
import { createProfileState } from "./profile.js";
import { createCollaborationState } from "./collaboration.js";
import { createInboxState, inboxBucketLabel, inboxCount as countInboxBucket, inboxRoleCopy, projectSourceLabel, unreadInboxCount } from "./inbox.js";
import { activeProjectAccess, createProjectRecordDraft, ensureProjectMutationNonce, filterProjectRecords, hydrateProjectRecordDraft as buildProjectRecordDraft, isProjectRecordEditable, mergeProjectSelection, normalizeProjectDetail, normalizeProjectSnapshot, projectRecordActions, projectTabNavigation, riskScorePresentation, scopePreviewProject, serializeProjectRecord, sortProjectRecords } from "./projects.js";
import { briefingProgress, briefingRoleCopy, briefingSampleDestination, briefingSourceDestination, createBriefingState, createPreviewBriefing } from "./briefing.js";

function today() {
  return localDateValue();
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
    ...createSurveyWorkspaceState(),
    ...createChatState(),
    ...createProfileState(),
    ...createCollaborationState(),
    expectedRole: document.body.dataset.expectedRole,
    loginUrl: pageUrl(import.meta.env.BASE_URL, "login.html"),
    administrationUrl: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=administration`,
    helpCenterUrl: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=help-center`,
     participantTrackerUrl: pageUrl(import.meta.env.BASE_URL, "Participant_Recruitment_Tracker.html"),
    access: null,
    data: emptyDashboard(),
    ready: false,
    loading: true,
    dashboardRefreshSequence: 0,
    briefingRefreshSequence: 0,
    briefingState: createBriefingState(),
    briefingLoading: true,
    briefingError: "",
    briefingStale: false,
    briefingPreviewMode: false,
    preview: false,
    error: "",
    view: "today",
    locale: localStorage.getItem("aoi-locale") === "zh-CN" ? "zh-CN" : "en",
    dark: localStorage.getItem("aoi-theme") === "dark",
    todayTab: document.body.dataset.expectedRole === "intern" ? "relationships" : "briefing",
    relationshipsTab: "contacts",
    outreachSection: "pipeline",
    researchTab: "collect",
    projectTab: "overview",
    supportTab: "overview",
    projectContext: null,
    projectSnapshot: null,
    projectLoading: false,
    projectError: "",
    projectReconciliationWarning: "",
    projectStale: false,
    projectConflictDraft: null,
    projectDirty: false,
    projectSaving: false,
    projectNotice: null,
    projectUnavailable: null,
    projectDetailLoading: false,
    projectMutationNonces: {},
    projectAdminMode: null,
    projectAdminDraft: createProjectRecordDraft("project"),
    projectMemberDraft: { userId: "", active: true, responsibility: "" },
    projectLifecycleNote: "",
    projectSupersedeDecisionId: "",
    projectFilters: { query: "", status: "all", ownerId: "", sort: "dueDate" },
    selectedProjectRecord: null,
    projectRecordType: null,
    projectRecordDraft: createProjectRecordDraft("milestone"),
    projectEditorMode: null,
    projectTransitionNote: "",
    projectReturnFocus: null,
    projectDetailRequest: 0,
    recruitmentMounted: false,
    mobileNav: false,
    sidebarCollapsed: false,
    commandOpen: false,
    notificationOpen: false,
    inbox: createInboxState(),
    selectedInboxItem: null,
    inboxReturnFocus: null,
    inboxLoading: false,
    inboxNotice: null,
    inboxDetailRequest: 0,
    previewCollaboration: {},
    query: "",
    taskFilter: "all",
    selectedTask: null,
    taskDetailRequest: 0,
    loadingTaskDetail: false,
    taskDetailReady: false,
    taskCheckpointForm: { progress: 0, status: "assigned", note: "" },
    taskReviewForm: { note: "" },
    taskCheckpointNotice: null,
    savingTaskCheckpoint: false,
    savingTaskReview: "",
    taskReturnFocus: null,
     selectedLayer: null,
       selectedCandidate: null,
       candidateEditorOpen: false,
       candidateReturnFocus: null,
     candidateFilter: "all",
     candidateQuery: "",
      candidateNotice: null,
       selectedCrmContact: null,
       crmEditorOpen: false,
       crmReturnFocus: null,
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
       collectMode: "browse",
       collectQuery: "",
       collectTypeFilter: "all",
       collectStatusFilter: "all",
       selectedCollectRecord: null,
       collectDetail: null,
       collectDetailRequest: 0,
       collectReturnFocus: null,
       loadingCollectDetail: false,
       collectionType: "respondent",
       researchForms: defaultResearchForms(),
       researchEditState: null,
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
       candidateForm: { name: "", category: "Dental Professional", platforms: "", reach: "", tier: "Micro", contactReadiness: "Research needed", contactChannel: "", contactDetail: "", pmfCandidate: false, pmfRationale: "", priorityScore: 50, priorityBand: "Medium", ownerId: "", ownerName: "", outreachStatus: "Not Contacted", nextStep: "", nextStepDue: "", sourceUrl: "", notes: "" },
     outreachForm: { channel: "Email", kind: "Initial", status: "Drafted", summary: "" },
     evidenceForm: { type: "PMF interview", stance: "supporting", strength: 3, title: "", notes: "", consentStatus: "pending" },
    toast: null,
      dailyEodForm: createDailyEodDraft(),
      dailyEodNotice: null,
      dailyEodError: "",
      dailyEodState: "uninitialized",
      refreshingDailyEod: false,
      dailyEodFieldErrors: {},
      dailyEodRecovery: null,
      dailyEodRecoveryTimer: null,
      dailyEodBeforeUnloadHandler: null,
      savingDailyEod: false,
      dailyEodTeamFilter: "all",
      selectedDailyEod: null,
      dailyEodAdminForm: createDailyEodDraft(),
      dailyEodAdminReason: "",
      dailyEodAdminNotice: null,
      dailyEodAdminFieldErrors: {},
      dailyEodAdminValidationAction: "save",
      dailyEodReturnFocus: null,
      dailyEodRefreshTimer: null,
      dailyEodVisibilityHandler: null,
      dailyEodFocusHandler: null,
      dailyEodConflictDraft: null,
      dailyEodConflictLoaded: false,
      dailyEodDirty: false,
      dailyEodDraftScope: "",
       dailyEodRefreshSequence: 0,
       dailyEodReportsSequence: 0,
       routePopstateHandler: null,
      passwordReminderOpen: false,
      passwordReminderSnoozing: false,
      passwordChanging: false,
      passwordChangeForm: { currentPassword: "", password: "", confirmation: "" },
      savingDailyEodAdmin: false,
      dailyEodReportFilters: { search: "", authorId: "", engagementManagerId: "", personInChargeId: "", projectId: "", projectLifecycle: "", fromDate: "", toDate: "", authorRole: "", projectStatus: "", workflowStatus: "" },
      dailyEodReports: { items: [], total: 0, page: 1, pageSize: 25 },
      dailyEodReportError: "",
      loadingDailyEodReports: false,
      dailyEodReportsLoaded: false,
      navigation: [
        { id: "today", label: "Today" },
        { id: "relationships", label: "Relationships" },
        { id: "research", label: "Research" },
        { id: "projects", label: "Projects" },
        { id: "eod", label: "End-of-Day Brief" },
        { id: "chat", label: "Chat" },
        { id: "help-center", label: "Help Center" },
        { id: "administration", label: "Administration" },
      ],

    async init() {
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
      document.documentElement.lang = this.locale;
       const searchParams = new URLSearchParams(location.search);
       const requestedView = searchParams.get("view");
       const requestedContactId = searchParams.get("contact");
       const requestedTaskId = searchParams.get("task");
       const requestedRecordType = searchParams.get("type");
       const requestedRecordId = searchParams.get("id");
       const requestedTab = searchParams.get("tab");
       const route = resolveWorkspaceRoute({ view: requestedView, tab: requestedTab, section: searchParams.get("section"), project: searchParams.get("project"), milestone: searchParams.get("milestone"), blocker: searchParams.get("blocker"), risk: searchParams.get("risk"), decision: searchParams.get("decision"), defaultView: "today", defaultTodayTab: this.todayTab });
       this.applyWorkspaceRoute(route);
         if (requestedContactId) {
           this.view = "relationships";
           this.relationshipsTab = "contacts";
           this.outreachSection = "pipeline";
           this.replaceWorkspaceLocation(true, requestedContactId);
        } else if (route.normalize) {
           this.replaceWorkspaceLocation(true);
         }
        this.setupRouteHistory();

      if (new URLSearchParams(location.search).get("preview") === "1") {
        const previewName = this.expectedRole === "admin" ? "Avery Example" : "Morgan Example";
         this.access = {
          userId: this.expectedRole === "admin" ? "preview-admin" : "m1",
          role: this.expectedRole,
          displayName: previewName,
          organizationName: fallbackDashboard.organization.name,
          locale: this.locale,
        };
          this.data = scopePreviewDashboard(fallbackDashboard, this.expectedRole, previewName);
          this.briefingState = createPreviewBriefing(fallbackDashboard, this.expectedRole, previewName);
          this.briefingLoading = false;
          this.briefingPreviewMode = true;
         const previewProject = scopePreviewProject(this.expectedRole);
          this.data = { ...this.data, project: { ...this.data.project, ...previewProject.snapshot.project } };
          this.briefingState = { ...this.briefingState, project: previewProject.snapshot.project };
          this.projectContext = previewProject.context;
         this.projectSnapshot = normalizeProjectSnapshot(previewProject.snapshot);
          this.previewCollaboration = Object.fromEntries([...(this.projectSnapshot.milestones || []), ...(this.projectSnapshot.blockers || []), ...(this.projectSnapshot.risks || []), ...(this.projectSnapshot.decisions || [])].map((record) => {
            const sourceType = record.id.includes("milestone") ? "milestone" : record.id.includes("blocker") ? "blocker" : record.id.includes("risk") ? "risk" : "decision";
            return [`${sourceType}:${record.id}`, {
              sourceType, sourceId: record.id, projectId: previewProject.context.selectedProjectId, isFollowing: sourceType === "decision", eligibleCollaborators: this.projectSnapshot.members,
              comments: sourceType === "decision" ? [
                { id: "preview-comment-1", body: "The synthetic checklist supports proceeding, with the access limitation kept visible.", authorId: "preview-admin", authorName: "Avery Example", authorRole: "admin", createdAt: "2026-08-12T10:00:00Z", revisionCount: 1, canRevise: this.expectedRole === "admin", revisions: [] },
                { id: "preview-comment-2", body: "I added the unresolved route to the next-action list.", authorId: "m1", authorName: "Morgan Example", authorRole: "intern", createdAt: "2026-08-12T11:00:00Z", editedAt: "2026-08-12T11:10:00Z", revisionCount: 2, canRevise: this.expectedRole === "intern", revisions: [{ revision: 1, body: "I added the route to the list.", editorName: "Morgan Example", createdAt: "2026-08-12T11:00:00Z" }] },
              ] : [],
            }];
          }));
          for (const [sourceType, records] of [["milestone", this.projectSnapshot.milestones], ["blocker", this.projectSnapshot.blockers], ["risk", this.projectSnapshot.risks], ["decision", this.projectSnapshot.decisions]]) {
            for (const record of records || []) record.collaboration = this.previewCollaboration[`${sourceType}:${record.id}`];
          }
          this.access.projectId = previewProject.context.selectedProjectId;
          this.access.organizationId = previewProject.context.selectedOrganizationId;
          this.access.organizationName = previewProject.context.organizations[0]?.name || this.access.organizationName;
         this.preview = true;
         this.inbox = createInboxState({
           projectId: previewProject.context.selectedProjectId,
           counts: { needsAction: 1 },
           items: [{ id: "preview-project-inbox-1", projectId: previewProject.context.selectedProjectId, sourceType: "project_decision", sourceId: "preview-decision-1", summary: "Review the pilot context decision", reason: "A project decision is ready for governance review.", priority: "high", readAt: null, resolvedAt: null }],
           generatedAt: previewProject.snapshot.generatedAt,
         });
         this.hydrateDailyEod(this.data.dailyEod);
         this.setupDailyEodRecovery();
         this.openRequestedCrmContact(requestedContactId);
         if (requestedTaskId) this.openRequestedTask(requestedTaskId);
         if (requestedRecordType && requestedRecordId) this.openRequestedCollectRecord(requestedRecordType, requestedRecordId);
         if (route.projectRecordType && route.projectRecordId) this.openRequestedProjectRecord(route.projectRecordType, route.projectRecordId);
         this.ready = true;
        this.loading = false;
        if (this.isSurveyWorkspaceActive) await this.openSurveyWorkspace();
        if (this.view === "eod") await this.searchDailyEodReports(1);
        await this.initializeChat();
        return;
      }

      try {
        const access = await getExistingWorkspaceAccess();
        if (!access) {
          location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
          return;
        }
        if (access.mustChangePassword) {
          location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
          return;
        }
        if (access.role !== this.expectedRole) {
          const url = new URL(location.href);
          url.pathname = pageUrl(import.meta.env.BASE_URL, routeForRole(access.role));
          location.replace(url);
          return;
        }
        this.access = access;
        this.hydrateResearchDrafts();
        this.setupResearchDraftAutosave();
        this.locale = localStorage.getItem("aoi-locale") || access.locale || "en";
        document.documentElement.lang = this.locale;
         this.ready = true;
         await this.refreshProjectContext(route.projectId);
          await Promise.all([this.refreshBriefing(), this.refreshDashboard()]);
        if (this.isSurveyWorkspaceActive) await this.openSurveyWorkspace();
        this.openRequestedCrmContact(requestedContactId);
        if (requestedTaskId) this.openRequestedTask(requestedTaskId);
         if (requestedRecordType && requestedRecordId) this.openRequestedCollectRecord(requestedRecordType, requestedRecordId);
         if (route.projectRecordType && route.projectRecordId) this.openRequestedProjectRecord(route.projectRecordType, route.projectRecordId);
        await this.refreshDailyEod();
        this.setupDailyEodRecovery();
        this.setupDailyEodRefresh();
        if (this.view === "eod") await this.searchDailyEodReports(1);
        await this.initializeChat();
      } catch (reason) {
        this.error = readableError(reason, "Unable to open the AOI workspace.");
        this.ready = true;
      } finally {
        this.loading = false;
      }
    },

    destroy() {
      this.dashboardRefreshSequence += 1;
      this.projectDetailRequest += 1;
      window.clearTimeout(this.dailyEodRefreshTimer);
      window.clearTimeout(this.dailyEodRecoveryTimer);
      if (this.dailyEodVisibilityHandler) document.removeEventListener("visibilitychange", this.dailyEodVisibilityHandler);
      if (this.dailyEodFocusHandler) window.removeEventListener("focus", this.dailyEodFocusHandler);
      if (this.dailyEodBeforeUnloadHandler) window.removeEventListener("beforeunload", this.dailyEodBeforeUnloadHandler);
      if (this.routePopstateHandler) window.removeEventListener("popstate", this.routePopstateHandler);
      this.destroyChat();
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
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
    formatBriefingTimestamp(value, timezone = "UTC") {
      const parsed = new Date(value);
      if (Number.isNaN(parsed.getTime())) return "Invalid time";
      try {
        return new Intl.DateTimeFormat(this.locale, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: timezone, timeZoneName: "short" }).format(parsed);
      } catch {
        return new Intl.DateTimeFormat(this.locale, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "UTC", timeZoneName: "short" }).format(parsed);
      }
    },
    formatDailyEodTimestamp(value) {
      return formatDailyEodTimestamp(value, this.locale, this.dailyEod.timezone || "UTC");
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
    get inboxRoleText() { return inboxRoleCopy(this.access || { role: this.expectedRole }); },
    get inboxBucketName() { return inboxBucketLabel(this.inbox.bucket); },
    get inboxUnread() { return unreadInboxCount(this.inbox); },
    inboxCount(bucket) { return countInboxBucket(this.inbox, bucket); },
    get canUpdateSelectedTask() {
      return this.taskDetailReady && this.access?.role === "intern" && this.selectedTask && !["submitted", "approved", "completed", "cancelled"].includes(this.selectedTask.status);
    },
    get focusTasks() { return this.data.tasks.filter((task) => ["submitted", "revision_requested", "blocked"].includes(task.status)).slice(0, 3); },
    get briefingCopy() {
      if (!this.briefingState.generatedAt) return {
        eyebrow: this.access?.role === "admin" ? "Administrator briefing" : "Your briefing",
        heading: this.briefingLoading ? "Loading authorized project facts" : "Briefing facts are unavailable",
        body: this.briefingLoading ? "AOI is deriving the current action queue from maintained source records." : "Retry the live projection. No preview or zero-value claim has been substituted.",
      };
      return briefingRoleCopy(this.access?.role || this.expectedRole, this.briefingState.summary, this.briefingState.summary.attentionCount);
    },
    briefingProgress,
    briefingSourceLabel(sourceType) { return projectSourceLabel(sourceType).replace(/^./, (letter) => letter.toUpperCase()); },
    openBriefingCategory(category) {
      const item = this.briefingState.attention.find((entry) => entry.category === category || (category === "overdue" && entry.sourceType === "task" && entry.dueOn));
      if (item) return this.openBriefingItem(item);
      this.showToast("No matching source", "No authorized record is available in this category.");
      return false;
    },
    async openBriefingSample(item) {
      const destination = briefingSampleDestination(item);
      if (!destination) return false;
      await this.setResearchTab(destination.tab);
      if (destination.assetId) {
        await this.openSurveyWorkspace();
        const asset = (this.surveyLibrary.assets || []).find((entry) => entry.id === destination.assetId);
        if (asset) await this.openSurveyAsset(asset);
      }
      return true;
    },
    get dailyEod() { return this.data.dailyEod || {}; },
    get dailyEodMembers() { return this.dailyEod.members || []; },
    get dailyEodUserId() { return this.preview ? (this.expectedRole === "admin" ? "preview-admin" : "m1") : this.access?.userId; },
    get dailyEodLocked() { return this.dailyEodForm.workflowStatus === "completed"; },
    get dailyEodLegacyEvidence() { return isLegacyEvidenceException(this.selectedDailyEod); },
    get dailyEodRecoveryKey() { return createDailyEodDraftKey(this.dailyEodUserId, this.dailyEod.projectId || this.dailyEod.myBrief?.projectId, this.dailyEod.serverDate); },
    dailyEodFieldError(field) { return this.dailyEodFieldErrors[field] || ""; },
    dailyEodAdminFieldError(field) { return this.dailyEodAdminFieldErrors[field] || ""; },
    dailyEodEvidenceFieldInvalid(link, field, target = "own") {
      const error = target === "admin" ? this.dailyEodAdminFieldError("evidenceLinks") : this.dailyEodFieldError("evidenceLinks");
      if (!error) return false;
      return field === "label" ? !String(link?.label || "").trim() : !isSafeHttpUrl(link?.url);
    },
    get dailyEodAttention() { return dailyEodAttentionCount(this.dailyEod, this.access?.role, this.dailyEodUserId); },
    get showPasswordReminder() {
      return !this.preview && shouldShowPasswordReminder({
        seeded: Boolean(this.access?.passwordReminderSeededAt),
        changedAt: this.access?.passwordChangedAt,
        snoozedUntil: this.access?.passwordReminderSnoozedUntil,
      });
    },
    get filteredDailyEodTeam() { return filterDailyEodTeam(this.dailyEod.teamToday || [], this.dailyEodTeamFilter); },
    get dailyEodDueCopy() {
      return {
        due: this.t("eodDue"),
        overdue: this.t("eodOverdue"),
        submitted: this.t("eodSubmitted"),
        completed: this.t("eodCompleted"),
        not_required: this.t("eodNotRequired"),
      }[this.dailyEod.dueState] || this.t("eodDue");
    },
    get commandPages() {
      const value = this.query.trim().toLowerCase();
      return this.navigation.filter((item) => !value || item.label.toLowerCase().includes(value));
    },
    get commandTasks() {
      const value = this.query.trim().toLowerCase();
      return this.data.tasks.filter((task) => !value || task.title.toLowerCase().includes(value)).slice(0, 5);
    },
    get activeProject() { return this.projectSnapshot?.project || this.projectContext?.projects?.find((project) => project.id === this.projectContext?.selectedProjectId) || this.data.project; },
    get activeProjectAccess() { return activeProjectAccess(this.projectContext || {}); },
    get activeProjectRole() { return this.activeProjectAccess.role; },
    get activeProjectIsOwner() { return this.activeProjectAccess.isOwner; },
    get projectSwitcherValue() { return this.projectContext?.selectedProjectId || this.activeProject?.id || ""; },
    get projectOptions() { return this.projectContext?.projects || this.projectContext?.organizations?.flatMap((organization) => organization.projects || []) || []; },
    get projectRegisterTitle() { return { milestones: "Milestone register", blockers: "Blocker register", risks: "Risk register", decisions: "Decision register" }[this.projectTab] || "Project register"; },
    get currentProjectRecordType() { return this.projectTypeForTab(this.projectTab); },
    get currentProjectRecords() { return this.projectSnapshot?.[this.projectTab] || []; },
    get filteredProjectRecords() {
      return sortProjectRecords(filterProjectRecords(this.currentProjectRecords, { ...this.projectFilters, today: today() }), this.projectFilters.sort);
    },
    get canEditSelectedProjectRecord() {
      return isProjectRecordEditable(this.projectRecordType, this.selectedProjectRecord?.status || this.projectRecordDraft.status, this.activeProjectRole, this.selectedProjectRecord?.ownerId, this.access?.userId, this.projectEditorMode === "new");
    },
    get selectedProjectActions() { return projectRecordActions(this.projectRecordType, this.selectedProjectRecord?.status, this.activeProjectRole); },
    projectSourceLabel,
    riskPresentation: riskScorePresentation,
    projectTypeForTab(tab) { return { milestones: "milestone", blockers: "blocker", risks: "risk", decisions: "decision" }[tab] || "project"; },
    projectStatusLabel(value) { return String(value || "Unknown").replaceAll("_", " ").replace(/^./, (letter) => letter.toUpperCase()); },
    projectActionLabel(value) { return this.projectStatusLabel(value); },
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
        followUps: candidates.filter((candidate) => candidate.nextStepDue && candidate.nextStepDue <= today()).length,
      };
    },
    get relationshipOwners() {
      const members = this.projectSnapshot?.members || this.dailyEodMembers || [];
      return members.map((member) => ({
        userId: member.userId || member.user_id,
        displayName: member.displayName || member.display_name,
        role: member.role || "member",
      })).filter((member) => member.userId && member.displayName);
    },
    candidateEvents(candidateId = this.selectedCandidate?.id) {
      return (this.data.outreachEvents || []).filter((event) => event.candidateId === candidateId);
    },
    candidateEvidence(candidateId = this.selectedCandidate?.id) {
      return (this.data.evidenceRecords || []).filter((record) => record.candidateId === candidateId);
    },
    crmContactActivities(contactId = this.selectedCrmContact?.id) {
      return (this.data.crmActivity || []).filter((activity) => activity.contactId === contactId);
    },
    get researchRespondents() { return this.data.collect?.respondents || this.data.respondents || []; },
    get collectRecords() { return buildCollectIndex(this.data.collect || this.data); },
    get filteredCollectRecords() {
      return filterCollectRecords(this.collectRecords, {
        type: this.collectTypeFilter,
        status: this.collectStatusFilter,
        query: this.collectQuery,
      });
    },
    get canEditSelectedCollectRecord() {
      const record = this.collectDetail?.record || {};
      const workflowStatus = record.workflow_status || this.selectedCollectRecord?.workflowStatus;
      const assignedTo = record.assigned_to || this.selectedCollectRecord?.ownerId || this.selectedCollectRecord?.assignedTo;
      return !this.preview
        && ["draft", "revision_requested"].includes(workflowStatus)
        && assignedTo === this.access?.userId;
    },
    get gamification() {
      return this.data.gamification || {
        xp: this.data.crmProgress?.xp || 0,
        completedToday: this.data.crmProgress?.completedToday || 0,
        streakDays: this.data.crmProgress?.streakDays || 0,
        badges: [],
        recentEvents: [],
        teamGoals: [],
      };
    },
    get gamificationLevelData() { return gamificationLevel(this.gamification.xp); },
    get reviewQueue() { return this.data.reviewQueue || []; },
    get pmfMatrices() {
      return buildLayerMatrices({
        segments: this.data.segments || [],
        definitions: this.data.definitions || [],
        observations: this.data.observations || [],
        respondents: this.researchRespondents,
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

    safeSourceUrl: safeHttpUrl,

    get isSurveyWorkspaceActive() { return this.view === "research" && this.researchTab === "surveys"; },

    get workspaceSectionLabel() {
      if (this.view === "today") return { briefing: "Briefing", tasks: "Tasks", relationships: "Relationships", momentum: "Momentum" }[this.todayTab];
      if (this.view === "relationships") return { contacts: "Contacts", recruitment: "Recruitment", outreach: "Outreach" }[this.relationshipsTab];
      if (this.view === "research") return { collect: "Collect", surveys: "Surveys", analyze: "Analyze", reports: "Reports" }[this.researchTab];
      if (this.view === "projects") return { overview: "Overview", milestones: "Milestones", blockers: "Blockers & Risks", risks: "Blockers & Risks", decisions: "Decisions" }[this.projectTab];
      return this.navigation.find((item) => item.id === this.view)?.label || "Today";
    },

    applyWorkspaceRoute(route) {
      this.view = route.view;
      this.todayTab = route.todayTab;
      this.relationshipsTab = route.relationshipsTab;
      this.outreachSection = route.outreachSection;
      this.researchTab = route.researchTab;
      this.projectTab = route.projectTab;
      this.supportTab = route.supportTab || "overview";
      if (route.relationshipsTab === "recruitment") this.recruitmentMounted = true;
    },
    remountRecruitment() {
      if (!this.recruitmentMounted) return;
      this.recruitmentMounted = false;
      this.$nextTick(() => { this.recruitmentMounted = true; });
    },

    async setView(view) {
      const tab = view === "today" ? this.todayTab : view === "relationships" ? this.relationshipsTab : view === "research" ? this.researchTab : view === "projects" ? this.projectTab : view === "administration" ? this.supportTab : null;
      const route = resolveWorkspaceRoute({ view, tab, section: view === "relationships" ? this.outreachSection : null, project: view === "projects" ? this.projectSwitcherValue : null, defaultTodayTab: this.todayTab });
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, route.view === "research" && route.researchTab === "surveys", this.surveyDirty)
        && !await this.confirmSurveyNavigation()) return false;
      if (this.view === "projects" && route.view !== "projects" && !await this.confirmProjectNavigation()) return false;
      if (this.view === "eod" && route.view !== "eod" && !this.confirmDailyEodNavigation()) return false;
      if (this.view === "projects" && route.view !== "projects") this.closeProjectRecord(false);
      this.applyWorkspaceRoute(route);
      this.replaceWorkspaceLocation();
      if (this.view === "eod" && !this.dailyEodReportsLoaded) this.searchDailyEodReports();
      if (this.isSurveyWorkspaceActive) this.openSurveyWorkspace();
      if (this.view === "chat") this.initializeChat().then(() => this.markSelectedChatRead());
      if (this.view === "help-center") this.$nextTick(() => document.querySelector(".helpcenter-shell input")?.focus());
      if (this.view === "projects" && !this.projectSnapshot) this.refreshProjectSnapshot();
      this.mobileNav = false;
      this.commandOpen = false;
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    openPmfLayer(layer) {
      if (!layer) return;
      this.selectedLayer = layer;
      this.matrixLayer = layer.code;
      this.setView("analyze");
    },
    async setTodayTab(tab) {
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, false, this.surveyDirty) && !await this.confirmSurveyNavigation()) return false;
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "today", tab, defaultTodayTab: this.todayTab }));
      this.replaceWorkspaceLocation();
    },
    async setRelationshipsTab(tab) {
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, false, this.surveyDirty) && !await this.confirmSurveyNavigation()) return false;
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "relationships", tab, section: tab === "outreach" ? this.outreachSection : null }));
      this.replaceWorkspaceLocation();
    },
    async onRelationshipsTabKeydown(event, currentTab) {
      const tab = nextTabFromKey(["contacts", "recruitment", "outreach"], currentTab, event.key);
      if (!tab) return;
      event.preventDefault();
      await this.setRelationshipsTab(tab);
      this.$nextTick(() => document.getElementById(`relationships-tab-${tab}`)?.focus());
    },
    async setResearchTab(tab) {
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, tab === "surveys", this.surveyDirty) && !await this.confirmSurveyNavigation()) return false;
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "research", tab }));
      this.replaceWorkspaceLocation();
      if (this.isSurveyWorkspaceActive) this.openSurveyWorkspace();
    },
    async setOutreachSection(section) {
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, false, this.surveyDirty) && !await this.confirmSurveyNavigation()) return false;
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "relationships", tab: "outreach", section }));
      this.replaceWorkspaceLocation();
    },
    async onOutreachTabKeydown(event, currentTab) {
      const section = nextTabFromKey(["pipeline", "evidence", "imports"], currentTab, event.key);
      if (!section) return;
      event.preventDefault();
      await this.setOutreachSection(section);
      this.$nextTick(() => document.getElementById(`outreach-tab-${section}`)?.focus());
    },
    async setProjectTab(tab) {
      if (!await this.confirmProjectNavigation()) return false;
      this.closeProjectRecord(false);
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "projects", tab, project: this.projectSwitcherValue }));
      this.replaceWorkspaceLocation();
      return true;
    },
    async onProjectTabKeydown(event, currentTab) {
      const tab = projectTabNavigation(["overview", "milestones", "blockers", "decisions"], currentTab, event.key);
      if (!tab) return;
      event.preventDefault();
      if (!await this.setProjectTab(tab)) return;
      this.$nextTick(() => document.getElementById(`project-tab-${tab}`)?.focus?.());
    },
    replaceWorkspaceLocation(replace = false, contactId = "") {
      this.writeWorkspaceLocation(replace, contactId);
    },
    writeWorkspaceLocation(replace = false, contactId = "") {
      const url = new URL(location.href);
      url.searchParams.set("view", this.view);
      for (const param of ["tab", "section", "task", "type", "id", "contact", "participant", "response", "version", "layer"]) url.searchParams.delete(param);
      if (this.view === "today") url.searchParams.set("tab", this.todayTab);
      if (this.view === "relationships") {
        url.searchParams.set("tab", this.relationshipsTab);
        if (this.relationshipsTab === "outreach") url.searchParams.set("section", this.outreachSection);
      }
      if (this.view === "research") url.searchParams.set("tab", this.researchTab);
      for (const param of ["project", "milestone", "blocker", "risk", "decision"]) url.searchParams.delete(param);
      if (this.view === "projects") {
        url.searchParams.set("tab", this.projectTab);
        if (this.projectSwitcherValue) url.searchParams.set("project", this.projectSwitcherValue);
        if (this.selectedProjectRecord?.id && this.projectRecordType) url.searchParams.set(this.projectRecordType, this.selectedProjectRecord.id);
      }
      if (this.view === "administration" && this.supportTab !== "overview") url.searchParams.set("tab", this.supportTab);
      if (this.view === "relationships" && this.relationshipsTab === "contacts" && contactId) url.searchParams.set("contact", contactId);
      if (replace) window.history.replaceState({}, "", url);
      else window.history.pushState({}, "", url);
    },
    setupRouteHistory() {
      this.routePopstateHandler ||= () => this.syncRouteFromLocation();
      window.addEventListener("popstate", this.routePopstateHandler);
    },
    async syncRouteFromLocation() {
      const params = new URLSearchParams(location.search);
      const route = resolveWorkspaceRoute({ view: params.get("view"), tab: params.get("tab"), section: params.get("section"), project: params.get("project"), milestone: params.get("milestone"), blocker: params.get("blocker"), risk: params.get("risk"), decision: params.get("decision"), defaultView: "today", defaultTodayTab: this.expectedRole === "intern" ? "relationships" : "briefing" });
      if (!await this.confirmProjectNavigation()) {
        this.replaceWorkspaceLocation(true);
        return false;
      }
      if (this.view === "eod" && route.view !== "eod" && !this.confirmDailyEodNavigation()) {
        this.replaceWorkspaceLocation(true);
        return false;
      }
      if (shouldConfirmSurveyRoute(this.isSurveyWorkspaceActive, route.view === "research" && route.researchTab === "surveys", this.surveyDirty)
        && !await this.confirmSurveyNavigation()) {
        this.replaceWorkspaceLocation(true);
        return false;
      }
      this.applyWorkspaceRoute(route);
      if (this.view === "eod" && !this.dailyEodReportsLoaded) this.searchDailyEodReports(1);
      if (this.isSurveyWorkspaceActive) this.openSurveyWorkspace();
      if (route.projectId && route.projectId !== this.projectSwitcherValue) await this.changeProject(route.projectId, { updateHistory: false });
      if (route.projectRecordType && route.projectRecordId) this.openRequestedProjectRecord(route.projectRecordType, route.projectRecordId);
      else if (this.selectedProjectRecord) this.closeProjectRecord(false);
      const contactId = params.get("contact");
      if (contactId && this.view === "relationships" && this.relationshipsTab === "contacts") {
        const contact = this.crmContacts.find((item) => item.id === contactId);
        if (contact) this.selectCrmContact(contact);
      } else if (this.crmEditorOpen) {
        this.selectedCrmContact = null;
        this.crmEditorOpen = false;
        this.crmNotice = null;
        this.crmActionNotice = null;
      }
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
    async refreshInbox(bucket = this.inbox.bucket) {
      if (this.preview) return true;
      this.inboxLoading = true;
      this.inboxNotice = null;
      try {
        this.inbox = createInboxState(await loadInbox(bucket, this.access?.projectId || null));
        if (this.selectedInboxItem) this.selectedInboxItem = this.inbox.items.find((item) => item.id === this.selectedInboxItem.id) || null;
        return true;
      } catch (reason) {
        this.inboxNotice = { tone: "error", text: readableError(reason, "The work inbox is temporarily unavailable.") };
        return false;
      } finally {
        this.inboxLoading = false;
      }
    },
    async setInboxBucket(bucket) {
      this.closeCollaborationSource();
      this.selectedInboxItem = null;
      await this.refreshInbox(bucket);
    },
    async openInboxItem(item) {
      this.inboxReturnFocus = document.activeElement;
      this.selectedInboxItem = { ...item };
      const request = ++this.inboxDetailRequest;
      this.$nextTick(() => document.querySelector(".inbox-detail")?.focus?.());
      try {
        const detail = this.preview ? this.previewInboxItemDetail(item) : await loadInboxItemDetail(item.id);
        if (request !== this.inboxDetailRequest || this.selectedInboxItem?.id !== item.id) return;
        this.selectedInboxItem = { ...this.selectedInboxItem, ...detail };
        this.openCollaborationSource(detail.collaboration, { surface: "today", density: "compact", inboxItemId: item.id });
      } catch (reason) {
        this.inboxNotice = { tone: "error", text: readableError(reason, "The selected inbox detail is unavailable.") };
      }
      if (!item.readAt && !this.preview) {
        try {
          const saved = await markInboxRead(item.id);
          if (request !== this.inboxDetailRequest || this.selectedInboxItem?.id !== item.id) return;
          this.selectedInboxItem.readAt = saved.readAt;
          this.inbox.items = this.inbox.items.map((entry) => entry.id === item.id ? { ...entry, readAt: saved.readAt } : entry);
        } catch (reason) {
          this.inboxNotice = { tone: "error", text: readableError(reason, "The inbox item could not be marked read.") };
        }
      }
    },
    closeInboxItem() {
      this.inboxDetailRequest += 1;
      this.closeCollaborationSource();
      this.selectedInboxItem = null;
      const focus = this.inboxReturnFocus;
      this.$nextTick(() => focus?.focus?.());
    },
    async openInboxSource(item) {
      if (!item) return;
      const projectSourceTypes = new Set(["milestone", "blocker", "risk", "decision", "project_milestone", "project_blocker", "project_risk", "project_decision"]);
      if (item.sourceType === "task") {
        const task = this.data.tasks.find((entry) => entry.id === item.sourceId) || { id: item.sourceId, title: item.summary, status: "assigned" };
        this.selectTask(task);
      } else if (projectSourceTypes.has(item.sourceType)) {
        const recordType = item.sourceType.replace("project_", "");
        const tab = recordType === "milestone" ? "milestones" : recordType === "decision" ? "decisions" : `${recordType}s`;
        if (item.projectId && item.projectId !== this.projectSwitcherValue && !await this.changeProject(item.projectId, { updateHistory: false })) return;
        this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "projects", tab, project: item.projectId || this.projectSwitcherValue, [recordType]: item.sourceId }));
        this.replaceWorkspaceLocation();
        this.closeInboxItem();
        await this.openRequestedProjectRecord(recordType, item.sourceId);
      } else {
        const record = this.collectRecords.find((entry) => entry.id === item.sourceId && entry.recordType === item.sourceType);
        if (record) {
          this.setResearchTab("collect");
          this.openCollectRecord(record);
        } else this.inboxNotice = { tone: "error", text: "This source record is not available in the current authorized snapshot." };
      }
    },
    async confirmProjectNavigation() {
      if (!this.projectDirty) return true;
      return globalThis.confirm("Discard unsaved project edits and continue?");
    },
    async confirmProjectSwitch() { return this.confirmProjectNavigation(); },
    async refreshProjectContext(requestedProjectId = null) {
      this.projectLoading = true;
      this.projectError = "";
      try {
        const context = this.preview ? scopePreviewProject(this.expectedRole).context : await loadProjectContext();
        this.projectContext = context;
        const projectId = requestedProjectId || context.selectedProjectId;
        if (projectId && projectId !== context.selectedProjectId && !this.preview) {
          const selection = await selectProjectContext(projectId);
          this.projectContext = mergeProjectSelection(context, selection);
          this.projectNotice = { tone: "success", text: "Project selected. Refreshing the selected context." };
        } else if (projectId) this.projectContext.selectedProjectId = projectId;
        if (this.projectContext.selectedProjectId) {
          this.syncAccessToProjectContext();
          const refreshed = await this.refreshProjectSnapshot(this.projectContext.selectedProjectId);
          if (!refreshed) this.projectReconciliationWarning = "Project selected. The project snapshot needs reconciliation; the selected context remains active.";
        }
        return true;
      } catch (reason) {
        this.projectError = readableError(reason, "Project context is unavailable.");
        return false;
      } finally {
        this.projectLoading = false;
      }
    },
    syncAccessToProjectContext() {
      const selected = this.activeProjectAccess;
      this.access = {
        ...this.access,
        projectId: this.projectContext?.selectedProjectId || null,
        organizationId: selected.organizationId || this.access?.organizationId,
        organizationName: selected.organizationName || this.access?.organizationName,
        role: selected.role || this.access?.role,
        isOwner: selected.isOwner,
        projectRole: selected.role,
        projectIsOwner: selected.isOwner,
      };
      if (this.activeProject) this.data = { ...this.data, project: { ...(this.data.project || {}), ...this.activeProject } };
    },
    async refreshProjectSnapshot(projectId = this.projectSwitcherValue) {
      if (!projectId) return false;
      this.projectLoading = true;
      this.projectError = "";
      try {
        const snapshot = this.preview ? scopePreviewProject(this.expectedRole).snapshot : await loadProjectSnapshot(projectId);
        this.projectSnapshot = normalizeProjectSnapshot(snapshot);
        this.projectStale = false;
        return true;
      } catch (reason) {
        this.projectError = readableError(reason, "The project snapshot is unavailable.");
        return false;
      } finally {
        this.projectLoading = false;
      }
    },
    async changeProject(projectId, { updateHistory = true } = {}) {
      if (!projectId || projectId === this.projectSwitcherValue) return true;
      if (!await this.confirmProjectSwitch()) return false;
      if (!this.confirmDailyEodNavigation()) return false;
      this.persistDailyEodRecovery();
      this.closeProjectRecord(false);
      this.projectLoading = true;
      this.projectError = "";
      this.projectReconciliationWarning = "";
      try {
        if (this.preview) {
          const previewProject = scopePreviewProject(this.expectedRole);
          this.data = { ...this.data, project: { ...this.data.project, ...previewProject.snapshot.project } };
          this.briefingState = { ...this.briefingState, project: previewProject.snapshot.project };
          this.projectContext = previewProject.context;
          this.projectSnapshot = normalizeProjectSnapshot(previewProject.snapshot);
          this.previewCollaboration = Object.fromEntries([...(this.projectSnapshot.milestones || []), ...(this.projectSnapshot.blockers || []), ...(this.projectSnapshot.risks || []), ...(this.projectSnapshot.decisions || [])].map((record) => {
            const sourceType = record.id.includes("milestone") ? "milestone" : record.id.includes("blocker") ? "blocker" : record.id.includes("risk") ? "risk" : "decision";
            return [`${sourceType}:${record.id}`, {
              sourceType, sourceId: record.id, projectId: previewProject.context.selectedProjectId, isFollowing: sourceType === "decision", eligibleCollaborators: this.projectSnapshot.members,
              comments: sourceType === "decision" ? [
                { id: "preview-comment-1", body: "The synthetic checklist supports proceeding, with the access limitation kept visible.", authorId: "preview-admin", authorName: "Avery Example", authorRole: "admin", createdAt: "2026-08-12T10:00:00Z", revisionCount: 1, canRevise: this.expectedRole === "admin", revisions: [] },
                { id: "preview-comment-2", body: "I added the unresolved route to the next-action list.", authorId: "m1", authorName: "Morgan Example", authorRole: "intern", createdAt: "2026-08-12T11:00:00Z", editedAt: "2026-08-12T11:10:00Z", revisionCount: 2, canRevise: this.expectedRole === "intern", revisions: [{ revision: 1, body: "I added the route to the list.", editorName: "Morgan Example", createdAt: "2026-08-12T11:00:00Z" }] },
              ] : [],
            }];
          }));
          for (const [sourceType, records] of [["milestone", this.projectSnapshot.milestones], ["blocker", this.projectSnapshot.blockers], ["risk", this.projectSnapshot.risks], ["decision", this.projectSnapshot.decisions]]) {
            for (const record of records || []) record.collaboration = this.previewCollaboration[`${sourceType}:${record.id}`];
          }
        } else {
          const selection = await selectProjectContext(projectId);
          this.projectContext = mergeProjectSelection(this.projectContext, selection);
          this.syncAccessToProjectContext();
          this.projectNotice = { tone: "success", text: "Project selected. Refreshing dashboard, inbox, and project data." };
          if (updateHistory) this.replaceWorkspaceLocation();
          this.dailyEodRefreshSequence += 1;
          this.dailyEodReportsSequence += 1;
          this.dailyEodReportsLoaded = false;
          this.dailyEodState = "loading";
          this.data.dailyEod = {};
          const refreshes = await Promise.allSettled([this.refreshBriefing(this.projectContext.selectedProjectId), this.refreshDashboard({ refreshInbox: false }), this.refreshInbox(), this.refreshProjectSnapshot(this.projectContext.selectedProjectId), this.refreshDailyEod(), this.searchDailyEodReports(1)]);
          if (refreshes.some((result) => result.status === "rejected" || result.value === false)) {
            this.projectReconciliationWarning = "Project selected. Some workspace data could not be refreshed; retry reconciliation without changing context.";
          }
        }
        this.remountRecruitment();
        if (this.preview && updateHistory) this.replaceWorkspaceLocation();
        return true;
      } catch (reason) {
        this.projectError = readableError(reason, "The requested project selection is unavailable.");
        return false;
      } finally {
        this.projectLoading = false;
      }
    },
    async reconcileSelectedProject() {
      if (!this.projectSwitcherValue) return this.refreshProjectContext();
      this.projectLoading = true;
      const refreshes = await Promise.all([this.refreshBriefing(this.projectSwitcherValue), this.refreshDashboard({ refreshInbox: false }), this.refreshInbox(), this.refreshProjectSnapshot(this.projectSwitcherValue)]);
      const reconciled = refreshes.every((result) => result !== false);
      this.projectReconciliationWarning = reconciled ? "" : "Project selected. Some workspace data still needs reconciliation.";
      this.projectLoading = false;
      return reconciled;
    },
    async onProjectSwitcherChange(event) {
      const changed = await this.changeProject(event.target.value);
      if (!changed) event.target.value = this.projectSwitcherValue;
    },
    hydrateProjectRecordDraft(record = null) {
      this.projectRecordDraft = buildProjectRecordDraft(this.projectRecordType, record, { ownerId: this.access?.userId });
      this.projectDirty = false;
    },
    startProjectRecord(recordType) {
      this.projectReturnFocus = document.activeElement;
      this.projectRecordType = recordType;
      this.selectedProjectRecord = null;
      this.projectEditorMode = "new";
      this.hydrateProjectRecordDraft();
      this.$nextTick(() => document.querySelector(".project-detail-pane")?.focus?.());
    },
    startProjectConfiguration() {
      this.projectReturnFocus = document.activeElement;
      this.projectAdminMode = "configure";
      this.projectAdminDraft = { ...createProjectRecordDraft("project", { ownerId: this.access?.userId }), ...(this.activeProject || {}) };
      this.projectDirty = false;
      this.$nextTick(() => document.querySelector(".project-admin-pane")?.focus?.());
    },
    startProjectCreation() {
      this.projectReturnFocus = document.activeElement;
      this.projectAdminMode = "create";
      this.projectAdminDraft = createProjectRecordDraft("project", { ownerId: this.access?.userId });
      this.projectDirty = false;
      this.$nextTick(() => document.querySelector(".project-admin-pane")?.focus?.());
    },
    async closeProjectAdmin() {
      if (!await this.confirmProjectNavigation()) return false;
      this.projectAdminMode = null;
      this.projectDirty = false;
      const focus = this.projectReturnFocus;
      this.$nextTick(() => focus?.focus?.());
      return true;
    },
    async saveAdminProject() {
      if (this.projectSaving || this.activeProjectRole !== "admin") return;
      this.projectSaving = true;
      this.projectNotice = null;
      try {
        const projectId = this.projectAdminMode === "configure" ? this.activeProject?.id : null;
        const saved = this.preview
          ? { ...this.projectAdminDraft, id: projectId || `preview-project-${Date.now()}`, updatedAt: new Date().toISOString() }
          : await adminSaveProject(this.projectAdminDraft, projectId, projectId ? this.activeProject?.updatedAt : null);
        if (projectId) this.projectSnapshot.project = { ...this.projectSnapshot.project, ...saved };
        else if (!this.preview) await this.refreshProjectContext(saved.id);
        else this.projectSnapshot.project = saved;
        this.syncAccessToProjectContext();
        this.projectAdminMode = null;
        this.projectDirty = false;
        this.projectNotice = { tone: "success", text: this.preview ? "Preview only: project changes were not persisted." : "Project saved." };
      } catch (reason) {
        this.projectNotice = { tone: "error", text: readableError(reason, "The project could not be saved.") };
      } finally {
        this.projectSaving = false;
      }
    },
    async saveProjectMember(member = this.projectMemberDraft) {
      if (!this.activeProject?.id || this.projectSaving || this.activeProjectRole !== "admin") return;
      this.projectSaving = true;
      try {
        const eligible = this.projectSnapshot.eligibleOrganizationMembers.find((item) => item.userId === member.userId);
        const expectedUpdatedAt = member.updatedAt || eligible?.projectMemberUpdatedAt || null;
        if (!this.preview) await persistProjectMember(this.activeProject.id, member.userId, member.active !== false, member.responsibility || "", expectedUpdatedAt);
        else {
          const existing = this.projectSnapshot.members.find((item) => (item.userId || item.user_id) === member.userId);
          if (existing) Object.assign(existing, member);
          else {
            this.projectSnapshot.members.push({ ...member, displayName: eligible?.displayName || "Unavailable member", role: eligible?.role || "member" });
          }
        }
        this.projectMemberDraft = { userId: "", active: true, responsibility: "" };
        if (!this.preview) await this.refreshProjectSnapshot();
        this.projectNotice = { tone: "success", text: this.preview ? "Preview only: membership was not persisted." : "Project membership updated." };
      } catch (reason) {
        this.projectNotice = { tone: "error", text: readableError(reason, "Project membership could not be updated.") };
      } finally {
        this.projectSaving = false;
      }
    },
    async transitionActiveProject(action) {
      if (!this.activeProject?.id || this.projectSaving || this.activeProjectRole !== "admin") return;
      this.projectSaving = true;
      try {
        const statuses = { activate: "active", hold: "on_hold", reopen: "active", complete: "completed", archive: "archived" };
        const saved = this.preview ? { ...this.activeProject, status: statuses[action] || this.activeProject.status, updatedAt: new Date().toISOString() } : await persistProjectLifecycle(this.activeProject.id, action, this.projectLifecycleNote.trim(), this.activeProject.updatedAt);
        this.projectSnapshot.project = { ...this.projectSnapshot.project, ...saved };
        this.projectLifecycleNote = "";
        this.syncAccessToProjectContext();
        this.projectNotice = { tone: "success", text: this.preview ? "Preview only: lifecycle change was not persisted." : "Project lifecycle updated." };
      } catch (reason) {
        this.projectNotice = { tone: "error", text: readableError(reason, "The project lifecycle could not be updated.") };
      } finally {
        this.projectSaving = false;
      }
    },
    addProjectEvidenceLink() {
      this.projectRecordDraft.evidenceLinks ||= [];
      this.projectRecordDraft.evidenceLinks.push({ evidenceId: "", stance: "supporting", relevanceNote: "" });
      this.projectDirty = true;
    },
    removeProjectEvidenceLink(index) {
      this.projectRecordDraft.evidenceLinks?.splice(index, 1);
      this.projectDirty = true;
    },
    async openProjectRecord(record, returnFocus = null, updateHistory = true) {
      if (!record) return;
      if (this.projectDirty && !await this.confirmProjectNavigation()) return false;
      this.projectReturnFocus = returnFocus || document.activeElement;
      this.selectedProjectRecord = { ...record };
      this.projectRecordType = this.currentProjectRecordType;
      this.projectEditorMode = "edit";
      this.projectNotice = null;
      this.projectUnavailable = null;
      this.hydrateProjectRecordDraft(record);
      if (updateHistory) this.replaceWorkspaceLocation();
      this.$nextTick(() => document.querySelector(".project-detail-pane")?.focus?.());
      if (this.preview) {
        const collaboration = record.collaboration || this.previewCollaborationProjection(this.projectRecordType, record.id);
        this.selectedProjectRecord = { ...this.selectedProjectRecord, collaboration };
        this.openCollaborationSource(collaboration, { surface: "project", density: "full" });
        return;
      }
      const request = ++this.projectDetailRequest;
      this.projectDetailLoading = true;
      try {
        const detail = normalizeProjectDetail(this.projectRecordType, await loadProjectRecordDetail(this.projectRecordType, record.id), this.projectSnapshot?.members);
        if (request !== this.projectDetailRequest || this.selectedProjectRecord?.id !== record.id) return;
        this.selectedProjectRecord = detail;
        this.hydrateProjectRecordDraft(detail);
        this.openCollaborationSource(detail.collaboration, { surface: "project", density: "full" });
      } catch (reason) {
        this.projectNotice = { tone: "error", text: readableError(reason, "The project record detail is unavailable.") };
      } finally {
        if (request === this.projectDetailRequest) this.projectDetailLoading = false;
      }
    },
    async openRequestedProjectRecord(recordType, recordId) {
      const tab = recordType === "milestone" ? "milestones" : recordType === "decision" ? "decisions" : `${recordType}s`;
      const record = this.projectSnapshot?.[tab]?.find((item) => item.id === recordId);
      if (record) return this.openProjectRecord(record, null, false);
      this.projectRecordType = recordType;
      try {
        const detail = normalizeProjectDetail(recordType, await loadProjectRecordDetail(recordType, recordId), this.projectSnapshot?.members);
        if (!this.projectSnapshot || this.projectSnapshot.project?.id !== this.projectSwitcherValue) {
          const selectedProject = this.projectOptions.find((project) => project.id === this.projectSwitcherValue)
            || (this.briefingState.project?.id === this.projectSwitcherValue ? this.briefingState.project : null);
          const fallbackSnapshot = {
            project: selectedProject,
            members: detail.collaboration?.eligibleCollaborators || [],
            milestones: [], blockers: [], risks: [], decisions: [], activity: [],
            generatedAt: new Date().toISOString(),
          };
          fallbackSnapshot[tab] = [detail];
          this.projectSnapshot = normalizeProjectSnapshot(fallbackSnapshot);
        }
        this.selectedProjectRecord = detail;
        this.projectEditorMode = "edit";
        this.hydrateProjectRecordDraft(detail);
        this.openCollaborationSource(detail.collaboration, { surface: "project", density: "full" });
        this.$nextTick(() => document.querySelector(".project-detail-pane")?.focus?.());
        return true;
      } catch (reason) {
        this.projectUnavailable = { recordType, recordId };
        this.projectNotice = { tone: "error", text: readableError(reason, "The project record detail is unavailable.") };
        this.normalizeUnavailableProjectRoute();
        return false;
      }
    },
    normalizeUnavailableProjectRoute() {
      if (this.view === "projects") this.replaceWorkspaceLocation(true);
    },
    async requestCloseProjectRecord(updateHistory = true) {
      if (!await this.confirmProjectNavigation()) return false;
      this.closeProjectRecord(updateHistory);
      return true;
    },
    closeProjectRecord(updateHistory = true) {
      this.projectDetailRequest += 1;
      this.selectedProjectRecord = null;
      this.projectEditorMode = null;
      this.projectRecordType = null;
      this.projectDirty = false;
      this.projectConflictDraft = null;
      this.projectNotice = null;
      this.projectUnavailable = null;
      this.projectDetailLoading = false;
      this.closeCollaborationSource();
      if (updateHistory && this.view === "projects") this.replaceWorkspaceLocation(true);
      const focus = this.projectReturnFocus;
      this.$nextTick(() => focus?.focus?.());
    },
    async saveProjectRecord() {
      if (this.projectSaving) return;
      this.projectSaving = true;
      this.projectNotice = null;
      try {
        const payload = serializeProjectRecord(this.projectRecordType, this.projectRecordDraft, this.projectSwitcherValue);
        const mutationKey = this.selectedProjectRecord?.id ? `save:${this.projectRecordType}:${this.selectedProjectRecord.id}` : `create:${this.projectRecordType}`;
        const clientNonce = this.selectedProjectRecord?.id ? null : ensureProjectMutationNonce(this.projectMutationNonces, mutationKey);
        const persisted = this.preview ? { ...this.projectRecordDraft, id: this.selectedProjectRecord?.id || `preview-${this.projectRecordType}-${Date.now()}`, updatedAt: new Date().toISOString() } : await persistProjectRecord(this.projectRecordType, payload, this.selectedProjectRecord?.id || null, this.selectedProjectRecord?.updatedAt || null, clientNonce);
        const saved = this.projectRecordType === "project" ? persisted : normalizeProjectDetail(this.projectRecordType, persisted, this.projectSnapshot?.members);
        if (this.projectRecordType === "project") this.projectSnapshot.project = { ...this.projectSnapshot.project, ...saved };
        else {
          const tab = this.projectRecordType === "milestone" ? "milestones" : this.projectRecordType === "decision" ? "decisions" : `${this.projectRecordType}s`;
          const exists = this.projectSnapshot[tab].some((item) => item.id === saved.id);
          this.projectSnapshot[tab] = exists ? this.projectSnapshot[tab].map((item) => item.id === saved.id ? saved : item) : [saved, ...this.projectSnapshot[tab]];
        }
        this.selectedProjectRecord = saved;
        this.projectEditorMode = "edit";
        this.projectDirty = false;
        this.projectConflictDraft = null;
        this.projectNotice = { tone: "success", text: "Project record saved." };
        delete this.projectMutationNonces[mutationKey];
        this.replaceWorkspaceLocation(true);
      } catch (reason) {
        const stale = reason instanceof Error && /STALE|CONFLICT/.test(reason.message);
        this.projectStale = stale;
        if (stale) this.projectConflictDraft = structuredClone(this.projectRecordDraft);
        this.projectNotice = { tone: "error", text: stale ? "This record changed elsewhere. Your draft is preserved." : readableError(reason, "The project record could not be saved.") };
      } finally {
        this.projectSaving = false;
      }
    },
    async transitionProjectRecord(action) {
      if (!this.selectedProjectRecord || this.projectSaving) return;
      this.projectSaving = true;
      try {
        const mutationKey = `transition:${this.projectRecordType}:${this.selectedProjectRecord.id}:${action}`;
        const clientNonce = ensureProjectMutationNonce(this.projectMutationNonces, mutationKey);
        const note = action === "supersede" ? this.projectSupersedeDecisionId.trim() : this.projectTransitionNote.trim();
        const persisted = this.preview ? { ...this.selectedProjectRecord, status: { activate: "active", submit: "submitted", resubmit: "resubmitted", request_revision: "revision_requested", approve: "approved", reject: "rejected", supersede: "superseded", complete: "completed", resolve: "resolved", reopen: "open", accept: "accepted", close: "closed", block: "blocked", unblock: "active", cancel: "cancelled", assess: "assessing", mitigate: "mitigating", monitor: "monitoring" }[action] || this.selectedProjectRecord.status, updatedAt: new Date().toISOString() } : await persistProjectTransition(this.projectRecordType, this.selectedProjectRecord.id, action, note, this.selectedProjectRecord.updatedAt, clientNonce);
        const saved = normalizeProjectDetail(this.projectRecordType, persisted, this.projectSnapshot?.members);
        this.selectedProjectRecord = saved;
        this.projectTransitionNote = "";
        this.projectSupersedeDecisionId = "";
        delete this.projectMutationNonces[mutationKey];
        await this.refreshProjectSnapshot();
        this.openRequestedProjectRecord(this.projectRecordType, saved.id);
        this.projectNotice = { tone: "success", text: `${this.projectActionLabel(action)} recorded in project history.` };
      } catch (reason) {
        this.projectStale = reason instanceof Error && /STALE|CONFLICT/.test(reason.message);
        this.projectNotice = { tone: "error", text: readableError(reason, "The project transition could not be recorded.") };
      } finally {
        this.projectSaving = false;
      }
    },
    async reloadStaleProjectRecord() {
      if (!this.selectedProjectRecord) return;
      const localDraft = structuredClone(this.projectConflictDraft || this.projectRecordDraft);
      try {
        const detail = normalizeProjectDetail(this.projectRecordType, await loadProjectRecordDetail(this.projectRecordType, this.selectedProjectRecord.id), this.projectSnapshot?.members);
        this.selectedProjectRecord = detail;
        this.projectRecordDraft = localDraft;
        this.projectDirty = true;
        this.projectStale = false;
        this.projectNotice = { tone: "warning", text: "The latest revision is loaded for comparison. Your unsaved draft remains in the form." };
      } catch (reason) {
        this.projectNotice = { tone: "error", text: readableError(reason, "The latest project record could not be loaded.") };
      }
    },
    previewCollaborationProjection(sourceType = this.collaboration?.sourceType, sourceId = this.collaboration?.sourceId) {
      const canonicalType = String(sourceType || "").replace(/^project_/, "");
      const projection = this.previewCollaboration[`${canonicalType}:${sourceId}`] || { sourceType: canonicalType, sourceId, comments: [], eligibleCollaborators: this.projectSnapshot?.members || [] };
      return JSON.parse(JSON.stringify(projection));
    },
    previewInboxItemDetail(item) { return { ...item, collaboration: this.previewCollaborationProjection(item.sourceType, item.sourceId) }; },
    previewAddCollaborationComment(body, mentionedUserIds, nonce, sourceKey = this.collaborationSourceKey()) {
      this.previewCollaboration[sourceKey].comments.push({ id: `preview-comment-${Date.now()}`, body, authorId: this.access.userId, authorName: this.access.displayName, authorRole: this.access.role, createdAt: new Date().toISOString(), revisionCount: 1, canRevise: true, revisions: [] });
    },
    previewSetCollaborationFollow(following, sourceKey = this.collaborationSourceKey()) { this.previewCollaboration[sourceKey].isFollowing = following; },
    previewAddCollaborationHandoff(toUserId, reason, nonce, sourceKey = this.collaborationSourceKey()) {
      const projection = this.previewCollaboration[sourceKey];
      const recipient = projection.eligibleCollaborators.find((member) => (member.userId || member.user_id) === toUserId);
      projection.recentHandoff = { toUserId, toDisplayName: recipient?.displayName || recipient?.display_name || "Team member", reason, createdAt: new Date().toISOString() };
    },
    previewReviseCollaborationComment(commentId, body, changeReason) {
      const comment = this.previewCollaboration[this.collaborationSourceKey()].comments.find((item) => item.id === commentId);
      comment.revisions ||= [];
      comment.revisions.push({ revision: comment.revisionCount, body: comment.body, changeReason, editorName: this.access.displayName, createdAt: new Date().toISOString() });
      comment.body = body; comment.revisionCount += 1; comment.editedAt = new Date().toISOString();
    },
    async reloadActiveCollaborationProjection() {
      if (!this.collaboration) return null;
      if (this.preview) return this.previewCollaborationProjection();
      if (this.collaborationSurface === "today") {
        const detail = await loadInboxItemDetail(this.collaborationInboxItemId);
        return detail.collaboration;
      }
      const detail = normalizeProjectDetail(this.projectRecordType, await loadProjectRecordDetail(this.projectRecordType, this.collaboration.sourceId), this.projectSnapshot?.members);
      return detail.collaboration;
    },
    showToast(title, body) {
      this.toast = { title, body };
      setTimeout(() => { this.toast = null; }, 4200);
    },
    async openBriefingItem(item) {
      const destination = briefingSourceDestination(item);
      if (!destination) {
        this.showToast("Source unavailable", "This recorded item does not have a supported workspace destination yet.");
        return false;
      }
      if (destination.view === "today") {
        await this.setTodayTab(destination.tab);
        if (destination.task) {
          const task = this.data.tasks.find((entry) => entry.id === destination.task) || { id: destination.task, title: item.title, status: "assigned" };
          await this.selectTask(task, { preview: this.briefingState.preview });
        }
        return true;
      }
      if (destination.view === "projects") {
        this.applyWorkspaceRoute(resolveWorkspaceRoute({ ...destination, project: this.projectSwitcherValue }));
        this.replaceWorkspaceLocation();
        const recordType = ["milestone", "blocker", "risk", "decision"].find((type) => destination[type]);
        if (recordType) await this.openRequestedProjectRecord(recordType, destination[recordType]);
        return true;
      }
      if (destination.view === "research") {
        await this.setResearchTab(destination.tab);
        if (destination.tab === "surveys") {
          await this.openSurveyWorkspace();
          const asset = (this.surveyLibrary.assets || []).find((entry) => entry.id === destination.assetId);
          if (!asset) {
            this.surveyError = "The survey owning this review item is not available in the authorized library.";
            return false;
          }
          await this.openSurveyAsset(asset);
          await this.setSurveyTab(destination.response ? "review" : "distribution");
          if (destination.version) {
            this.surveyRequestedVersionId = destination.version;
            this.$nextTick(() => document.querySelector(".survey-version-list .is-requested")?.focus?.());
          }
          if (destination.response) {
            this.surveySelectedResponse = (this.surveyWorkspace?.submissions || []).find((entry) => entry.id === destination.response) || null;
            if (!this.surveySelectedResponse) this.surveyError = "The selected response is not available in this authorized survey snapshot.";
          }
          return Boolean(destination.version || this.surveySelectedResponse);
        }
        if (destination.layer) {
          this.matrixLayer = destination.layer;
          this.selectedLayer = this.data.pmfLayers?.find((layer) => layer.code === destination.layer) || null;
        }
        if (destination.type && destination.id) this.openRequestedCollectRecord(destination.type, destination.id);
        return true;
      }
      if (destination.view === "relationships") {
        if (destination.participant) {
          const url = new URL(location.href);
          url.search = "";
          url.searchParams.set("view", "relationships");
          url.searchParams.set("tab", "recruitment");
          url.searchParams.set("participant", destination.participant);
          location.assign(url);
          return true;
        }
        await this.setRelationshipsTab(destination.tab);
        if (destination.candidate) {
          try {
            let candidate = this.candidates.find((entry) => entry.id === destination.candidate);
            if (!candidate && !this.briefingState.preview) {
              const operations = await loadOperationsSnapshot();
              this.data = { ...this.data, ...operations };
              candidate = this.candidates.find((entry) => entry.id === destination.candidate);
            }
            if (candidate) this.selectCandidate(candidate);
            else this.showToast("Candidate unavailable", "This outreach source is unavailable in your authorized snapshot.");
          } catch (reason) {
            this.showToast("Candidate unavailable", readableError(reason, "The outreach source could not be loaded."));
          }
        }
        if (destination.contact) {
          let contact = this.crmContacts.find((entry) => entry.id === destination.contact);
          if (!contact && !this.briefingState.preview) {
            try {
              const crm = await loadCrmSnapshot();
              this.data = { ...this.data, ...crm };
              contact = this.crmContacts.find((entry) => entry.id === destination.contact);
            } catch (reason) {
              this.showToast("Contact unavailable", readableError(reason, "The contact record could not be loaded."));
            }
          }
          if (contact) this.openCrmContact(contact);
          else this.showToast("Contact unavailable", "This authorized Briefing item could not be found in the current CRM snapshot.");
        }
        return true;
      }
      return false;
    },
    async completeInternOnboarding(stepKey, destination) {
      try {
        if (!this.preview) await completeOnboardingStep(stepKey);
        this.setView(destination);
      } catch (reason) {
        this.showToast("Onboarding step", readableError(reason, "Unable to update onboarding right now."));
      }
    },
    resetTaskForms(task) {
      this.taskCheckpointForm = {
        progress: Number(task.progress) || 0,
        status: task.status === "revision_requested" ? "resubmitted" : task.status,
        note: "",
      };
      this.taskReviewForm = { note: "" };
    },
    async selectTask(task, { preview = this.preview } = {}) {
      if (!task) return;
      if (!this.selectedTask) this.taskReturnFocus = document.activeElement;
      this.selectedTask = { ...task };
      this.taskDetailReady = preview;
      this.resetTaskForms(task);
      this.taskCheckpointNotice = null;
      this.$nextTick(() => this.focusDialog(".task-drawer"));
      if (preview) return;
      const requestId = ++this.taskDetailRequest;
      this.loadingTaskDetail = true;
      try {
        const detail = await loadTaskDetail(task.id);
        if (requestId !== this.taskDetailRequest || this.selectedTask?.id !== task.id) return;
        this.selectedTask = detail;
        this.taskDetailReady = true;
        this.resetTaskForms(detail);
      } catch (reason) {
        if (requestId !== this.taskDetailRequest) return;
        this.taskCheckpointNotice = { tone: "error", text: readableError(reason, "Unable to load the task detail.") };
        this.taskDetailReady = false;
      } finally {
        if (requestId === this.taskDetailRequest) this.loadingTaskDetail = false;
      }
    },
    openRequestedTask(taskId) {
      const task = this.data.tasks.find((entry) => entry.id === taskId);
      if (task) this.selectTask(task);
    },
    openRequestedCollectRecord(recordType, recordId) {
      const record = this.collectRecords.find((entry) => entry.id === recordId && entry.recordType === recordType)
        || { id: recordId, recordType, title: "Loading collected record", workflowStatus: "loading" };
      this.openCollectRecord(record);
    },
    openTaskCheckpoint() {
      const task = this.data.tasks.find((item) => !["completed", "submitted", "approved", "cancelled"].includes(item.status));
      if (task) this.selectTask(task);
      else this.showToast("No open task", "There is no task available for a checkpoint update.");
    },
    closeTask() {
      this.taskDetailRequest += 1;
      this.selectedTask = null;
      this.taskCheckpointNotice = null;
      this.loadingTaskDetail = false;
      this.taskDetailReady = false;
      this.$nextTick(() => this.taskReturnFocus?.focus?.());
    },
    selectCandidate(candidate) {
      if (!this.candidateEditorOpen) this.candidateReturnFocus = document.activeElement;
      this.selectedCandidate = { ...candidate };
      this.candidateForm = { ...this.candidateForm, ...candidate, ownerId: candidate.ownerId || "" };
      this.candidateEditorOpen = true;
      this.$nextTick(() => this.focusDialog(".candidate-drawer"));
    },
    closeCandidate() {
      this.selectedCandidate = null;
      this.candidateEditorOpen = false;
      this.candidateNotice = null;
      this.$nextTick(() => this.candidateReturnFocus?.focus?.());
    },
    selectCrmContact(contact) {
      if (!this.crmEditorOpen) this.crmReturnFocus = document.activeElement;
      this.selectedCrmContact = { ...contact };
      this.crmForm = { ...createContactDraft(this.access?.displayName || ""), ...contact };
      this.crmActionForm = { activityType: "follow_up", summary: "", nextAction: contact.nextAction || "", nextActionDue: contact.nextActionDue || "", lifecycle: contact.lifecycle || "" };
      this.crmNotice = null;
      this.crmActionNotice = null;
      this.crmEditorOpen = true;
      this.$nextTick(() => this.focusDialog(".crm-drawer"));
    },
    openCrmContact(contact) {
      if (!contact) return;
      const returnToVisibleControl = this.view === "relationships" && this.relationshipsTab === "contacts";
      this.applyWorkspaceRoute(resolveWorkspaceRoute({ view: "relationships", tab: "contacts" }));
      this.replaceWorkspaceLocation(false, contact.id);
      this.selectCrmContact(contact);
      if (!returnToVisibleControl) this.crmReturnFocus = null;
    },
    openRequestedCrmContact(contactId) {
      if (!contactId) return;
      this.view = "relationships";
      this.relationshipsTab = "contacts";
      this.outreachSection = "pipeline";
      const contact = this.crmContacts.find((item) => item.id === contactId);
      if (contact) this.selectCrmContact(contact);
    },
    startNewCrmContact() {
      if (!this.crmEditorOpen) this.crmReturnFocus = document.activeElement;
      this.selectedCrmContact = null;
      this.crmForm = createContactDraft(this.access?.displayName || "");
      this.crmActionForm = { activityType: "follow_up", summary: "", nextAction: "", nextActionDue: "", lifecycle: "" };
      this.crmNotice = null;
      this.crmActionNotice = null;
      this.crmEditorOpen = true;
      this.view = "relationships";
      this.relationshipsTab = "contacts";
      this.replaceWorkspaceLocation();
      this.$nextTick(() => this.focusDialog(".crm-drawer"));
    },
    closeCrmContact() {
      this.selectedCrmContact = null;
      this.crmEditorOpen = false;
      this.crmNotice = null;
      this.crmActionNotice = null;
      if (new URL(location.href).searchParams.has("contact")) this.replaceWorkspaceLocation(true);
      this.$nextTick(() => this.crmReturnFocus?.focus?.());
    },
    focusDialog(selector) {
      const dialog = document.querySelector(selector);
      const initial = dialog?.querySelector('input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled])');
      (initial || dialog)?.focus?.();
    },
    trapDialogFocus(event, selector) {
      const dialog = document.querySelector(selector);
      if (!dialog) return;
      const controls = [...dialog.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter((element) => element.offsetParent !== null);
      if (!controls.length) return;
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    async refreshMutationState({ candidateId = null, crmContactId = null } = {}) {
      if (this.preview) return;
      await this.refreshDashboard();
      if (candidateId) {
        const candidate = this.candidates.find((item) => item.id === candidateId);
        if (candidate) {
          this.selectedCandidate = { ...candidate };
          this.candidateForm = { ...this.candidateForm, ...candidate };
        }
      }
      if (crmContactId) {
        const contact = this.crmContacts.find((item) => item.id === crmContactId);
        if (contact) {
          this.selectedCrmContact = { ...contact };
          this.crmForm = { ...this.crmForm, ...contact };
        }
      }
    },
    async saveCrmContact() {
      const completeness = contactCompleteness(this.crmForm);
      if (!this.crmForm.name.trim()) {
        this.crmNotice = { tone: "error", text: "Add a person or organization name before saving." };
        return;
      }
      if (this.crmForm.sourceUrl && !isSafeHttpUrl(this.crmForm.sourceUrl)) {
        this.crmNotice = { tone: "error", text: "Source URL must use http or https." };
        return;
      }
      const reward = rewardForAction("enrich", completeness);
      let awarded = reward;
      let saved = { ...this.crmForm, id: this.selectedCrmContact?.id || `crm-local-${Date.now()}`, candidateId: this.selectedCrmContact?.candidateId || null, completeness, priorityScore: this.selectedCrmContact?.priorityScore || 50, lastUpdated: today() };
      this.crmSaving = true;
      try {
        if (!this.preview) {
          const persisted = await upsertCrmContact({ ...saved, createOutreach: Boolean(this.crmForm.createOutreach) });
          awarded = persisted.rewardPoints || 0;
          saved = { ...saved, ...persisted };
        }
        this.data.crmContacts = this.selectedCrmContact ? this.crmContacts.map((contact) => contact.id === saved.id ? { ...contact, ...saved, completeness } : contact) : [{ ...saved, completeness }, ...this.crmContacts];
        this.data.crmProgress = { ...(this.data.crmProgress || {}), xp: (this.data.crmProgress?.xp || 0) + awarded, completedToday: (this.data.crmProgress?.completedToday || 0) + (awarded > 0 ? 1 : 0) };
        this.selectedCrmContact = { ...saved, completeness };
        this.crmForm = { ...this.crmForm, ...saved };
        this.crmNotice = { tone: "success", text: awarded ? `Saved. +${awarded} XP for verified enrichment.` : "Saved. Today's enrichment reward was already recorded." };
        await this.refreshMutationState({ crmContactId: saved.id });
      } catch (reason) {
        const stale = reason instanceof Error && reason.message.includes("OUTREACH_STALE_WRITE");
        this.crmNotice = { tone: "error", text: stale ? "This contact changed elsewhere. Your edits are preserved; load the current record before saving again." : readableError(reason, "Unable to save the CRM contact."), action: stale ? "reload" : "" };
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
        if (!this.preview) await completeOnboardingStep("log_crm_outcome");
        await this.refreshMutationState({ crmContactId: updated.id });
      } catch (reason) {
        this.crmActionNotice = { tone: "error", text: readableError(reason, "Unable to log the CRM action.") };
      } finally {
        this.crmActionSaving = false;
      }
    },
    async saveCandidate() {
      let candidate = { ...this.candidateForm, id: this.selectedCandidate?.id || null, externalId: this.selectedCandidate?.externalId || "", priorityScore: this.selectedCandidate?.priorityScore || 50, priorityBand: this.selectedCandidate?.priorityBand || "Medium", interestLevel: this.selectedCandidate?.interestLevel || "Unknown", lastUpdated: today() };
      if (!candidate.name.trim()) {
        this.candidateNotice = { tone: "error", text: "Add a creator or organization name before saving." };
        return;
      }
      if (candidate.sourceUrl && !isSafeHttpUrl(candidate.sourceUrl)) {
        this.candidateNotice = { tone: "error", text: "Source URL must use http or https." };
        return;
      }
      if (!this.preview) {
        try {
          const saved = await upsertCandidate(candidate);
          candidate = { ...candidate, ...saved };
        } catch (reason) {
          const stale = reason instanceof Error && reason.message.includes("OUTREACH_STALE_WRITE");
          this.candidateNotice = { tone: "error", text: stale ? "This candidate changed elsewhere. Your edits are preserved; load the current record before saving again." : readableError(reason, "Unable to save the candidate."), action: stale ? "reload" : "" };
          return;
        }
      }
      this.data.candidates = this.selectedCandidate ? this.candidates.map((item) => item.id === candidate.id ? candidate : item) : [candidate, ...this.candidates];
      this.selectedCandidate = { ...candidate };
      this.candidateNotice = { tone: "success", text: "Candidate record saved to this workspace view." };
      this.data.outreachSummary = { ...this.data.outreachSummary, totalCandidates: this.candidates.length };
      await this.refreshMutationState({ candidateId: candidate.id });
    },
    async reloadStaleRelationship(kind) {
      const draft = structuredClone(kind === "contact" ? this.crmForm : this.candidateForm);
      await this.refreshDashboard();
      if (kind === "contact") {
        const current = this.crmContacts.find((item) => item.id === this.selectedCrmContact?.id);
        if (current) {
          this.selectedCrmContact = { ...current };
          this.crmForm = { ...draft, updatedAt: current.updatedAt };
          this.crmNotice = { tone: "warning", text: "Current revision loaded. Review your preserved edits, then save again." };
        }
      } else {
        const current = this.candidates.find((item) => item.id === this.selectedCandidate?.id);
        if (current) {
          this.selectedCandidate = { ...current };
          this.candidateForm = { ...draft, updatedAt: current.updatedAt };
          this.candidateNotice = { tone: "warning", text: "Current revision loaded. Review your preserved edits, then save again." };
        }
      }
    },
    startNewCandidate() {
      this.setOutreachSection("pipeline");
      if (!this.candidateEditorOpen) this.candidateReturnFocus = document.activeElement;
      this.selectedCandidate = null;
      this.candidateEditorOpen = true;
      this.candidateForm = { name: "", category: "Dental Professional", platforms: "", reach: "", tier: "Micro", contactReadiness: "Research needed", contactChannel: "", contactDetail: "", pmfCandidate: false, pmfRationale: "", priorityScore: 50, priorityBand: "Medium", ownerId: this.access?.userId || "", ownerName: this.access?.displayName || "", outreachStatus: "Not Contacted", nextStep: "", nextStepDue: "", sourceUrl: "", notes: "" };
      this.candidateNotice = null;
      this.$nextTick(() => this.focusDialog(".candidate-drawer"));
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
      this.candidates.splice(this.candidates.findIndex((item) => item.id === this.selectedCandidate.id), 1, { ...this.selectedCandidate, outreachStatus: this.outreachForm.status === "Sent" ? "Sent" : this.selectedCandidate.outreachStatus, lastUpdated: today() });
      this.outreachForm = { channel: "Email", kind: "Initial", status: "Drafted", summary: "" };
      this.candidateNotice = { tone: "success", text: "Outreach activity logged with an auditable timestamp." };
      await this.refreshMutationState({ candidateId: this.selectedCandidate.id });
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
      this.data.evidenceRecords = [{ id: `evidence-${Date.now()}`, candidateId: this.selectedCandidate.id, ...this.evidenceForm, recordedBy: this.access?.displayName || "AOI", recordedAt: today() }, ...(this.data.evidenceRecords || [])];
      this.evidenceForm = { type: "PMF interview", stance: "supporting", strength: 3, title: "", notes: "", consentStatus: "pending" };
      this.candidateNotice = { tone: "success", text: "Evidence record added. Keep consent and limitations explicit." };
      await this.refreshMutationState({ candidateId: this.selectedCandidate.id });
    },
    respondentSegmentCode(respondentId) {
      return this.researchRespondents.find((item) => item.id === respondentId)?.segmentCode || "families";
    },
    researchSessionsFor(recordType) {
      const form = this.researchForms[recordType] || {};
      return (this.data.sessions || []).filter((session) => !form.respondentId || session.respondentId === form.respondentId);
    },
    syncResearchSession(recordType) {
      const form = this.researchForms[recordType];
      if (!form?.sessionId) return;
      if (!this.researchSessionsFor(recordType).some((session) => session.id === form.sessionId)) form.sessionId = "";
    },
    syncObservationDefinition() {
      this.researchForms.observation = normalizeObservationValues(this.researchForms.observation, this.selectedMetricDefinition);
    },
    startCollectionRecord(recordType = "respondent", respondentId = "") {
      if (this.researchEditState) {
        this.researchForms[this.researchEditState.recordType] = defaultResearchForms()[this.researchEditState.recordType];
      }
      this.resetResearchEditState();
      this.collectionType = recordType;
      this.collectMode = "create";
      if (respondentId && this.researchForms[recordType] && recordType !== "respondent") {
        const respondent = this.researchRespondents.find((item) => item.id === respondentId);
        this.researchForms[recordType] = prefillResearchForm(this.researchForms[recordType], respondent);
      }
      this.researchNotice = null;
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    resetResearchEditState() {
      this.researchEditState = null;
    },
    startResearchRevision() {
      if (!this.canEditSelectedCollectRecord) return;
      const selected = this.selectedCollectRecord;
      const detail = this.collectDetail;
      const record = { ...selected, ...detail.record };
      const expectedUpdatedAt = record.updated_at || selected.updatedAt;
      if (!expectedUpdatedAt) {
        this.researchNotice = { tone: "error", text: "This record has no revision timestamp. Reload it before editing." };
        return;
      }
      this.researchForms[selected.recordType] = hydrateResearchRevisionForm(
        selected.recordType,
        defaultResearchForms()[selected.recordType],
        { ...detail, record, summary: selected, segments: this.data.segments || [] },
      );
      this.researchEditState = {
        recordType: selected.recordType,
        recordId: this.selectedCollectRecord.id,
        expectedUpdatedAt: expectedUpdatedAt,
        workflowStatus: record.workflow_status || selected.workflowStatus,
        reviewNotes: record.review_notes || selected.reviewNotes || "",
      };
      this.collectionType = selected.recordType;
      this.collectMode = "create";
      this.researchNotice = null;
      this.closeCollectRecord();
      this.persistResearchDrafts();
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    continueCollection(recordType) {
      const record = this.selectedCollectRecord;
      const respondentId = record?.respondentId || (record?.recordType === "respondent" ? record.id : "");
      this.closeCollectRecord();
      this.startCollectionRecord(recordType, respondentId);
    },
    async openCollectRecord(record) {
      const requestId = ++this.collectDetailRequest;
      this.collectReturnFocus = document.activeElement;
      this.selectedCollectRecord = record;
      this.collectDetail = null;
      this.$nextTick(() => document.querySelector(".collect-detail-drawer")?.focus());
      if (this.preview) {
        this.collectDetail = { record };
        return;
      }
      this.loadingCollectDetail = true;
      try {
        const detail = await loadCollectRecordDetail(record.recordType, record.id);
        if (requestId === this.collectDetailRequest && this.selectedCollectRecord?.id === record.id) this.collectDetail = detail;
      } catch (reason) {
        if (requestId !== this.collectDetailRequest) return;
        this.researchNotice = { tone: "error", text: readableError(reason, "Unable to open the collected record.") };
        this.selectedCollectRecord = null;
      } finally {
        if (requestId === this.collectDetailRequest) this.loadingCollectDetail = false;
      }
    },
    closeCollectRecord() {
      this.collectDetailRequest += 1;
      this.selectedCollectRecord = null;
      this.collectDetail = null;
      this.$nextTick(() => this.collectReturnFocus?.focus?.());
    },
    trapCollectDetailFocus(event) {
      const drawer = document.querySelector(".collect-detail-drawer");
      if (!drawer) return;
      const controls = [...drawer.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter((element) => element.offsetParent !== null);
      if (!controls.length) return;
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    researchDraftStorageKey() {
      return `aoi-research-drafts:${this.access?.userId || this.expectedRole}`;
    },
    hydrateResearchDrafts() {
      try {
        const stored = JSON.parse(globalThis.sessionStorage.getItem(this.researchDraftStorageKey()) || "null");
        const fresh = stored?.savedAt && Date.now() - stored.savedAt < 8 * 60 * 60 * 1000;
        this.researchForms = restoreResearchDrafts(defaultResearchForms(), fresh ? stored.forms : null);
        this.researchEditState = fresh
          && stored.editState
          && defaultResearchForms()[stored.editState.recordType]
          && stored.editState.recordId
          && stored.editState.expectedUpdatedAt
          && ["draft", "revision_requested"].includes(stored.editState.workflowStatus)
          ? { ...stored.editState }
          : null;
        if (this.researchEditState) {
          this.collectionType = this.researchEditState.recordType;
          this.collectMode = "create";
        }
      } catch {
        this.researchForms = defaultResearchForms();
        this.researchEditState = null;
      }
    },
    persistResearchDrafts() {
      if (this.preview) return;
      globalThis.sessionStorage.setItem(this.researchDraftStorageKey(), JSON.stringify({ savedAt: Date.now(), forms: this.researchForms, editState: this.researchEditState }));
    },
    setupResearchDraftAutosave() {
      if (this.preview || typeof this.$watch !== "function") return;
      this.$watch("researchForms", () => this.persistResearchDrafts());
    },
    async saveResearchRecord(recordType, workflowStatus) {
      const form = this.researchForms[recordType];
      let payload = { ...form };
      if (recordType === "observation") {
        payload = normalizeObservationValues(payload, this.selectedMetricDefinition);
        this.researchForms.observation = { ...payload };
      }
      if (["session", "product_event", "value_exchange"].includes(recordType)) {
        payload.segmentCode = this.respondentSegmentCode(form.respondentId);
      }
      const errors = validateResearchRecord(recordType, payload, workflowStatus, {
        definitions: this.data.definitions || [],
        sessions: this.data.sessions || [],
      });
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
        const editState = this.researchEditState?.recordType === recordType ? this.researchEditState : null;
        const action = workflowStatus === "draft"
          ? "save"
          : editState?.workflowStatus === "revision_requested" ? "resubmit" : "submit";
        if (editState) {
          await persistResearchUpdate(recordType, editState.recordId, payload, this.researchEditState.expectedUpdatedAt, action);
        } else {
          await persistResearchRecord(recordType, { ...payload, workflowStatus });
        }
        this.researchForms[recordType] = defaultResearchForms()[recordType];
        this.resetResearchEditState();
        this.persistResearchDrafts();
        this.collectMode = "browse";
        this.researchNotice = { tone: "success", text: `${recordType.replaceAll("_", " ")} ${action === "resubmit" ? "resubmitted for review" : workflowStatus === "submitted" ? "submitted for review" : "saved as a draft"}.` };
        await this.refreshDashboard();
      } catch (reason) {
        const stale = reason instanceof Error && reason.message.includes("RESEARCH_STALE_WRITE");
        this.researchNotice = { tone: "error", text: stale ? "This research record changed in another session. Reopen it to load the latest version before saving." : readableError(reason, "Unable to save the research record.") };
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
        await persistResearchReview(record.recordType, record.id, action, this.reviewNotes[record.id] || "", record.updatedAt);
        this.researchNotice = { tone: "success", text: action === "approve" ? "Record approved and included in analysis." : "Revision requested from the record owner." };
        await this.refreshDashboard();
      } catch (reason) {
        const stale = reason instanceof Error && reason.message.includes("RESEARCH_STALE_WRITE");
        this.researchNotice = { tone: "error", text: stale ? "This submitted record changed. Refresh the review queue before deciding." : readableError(reason, "Unable to review the record.") };
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
    async completeCheckpoint() {
      if (!this.canUpdateSelectedTask || this.savingTaskCheckpoint) return;
      const progress = clamp(this.taskCheckpointForm.progress);
      const note = this.taskCheckpointForm.note.trim();
      if (!note) {
        this.taskCheckpointNotice = { tone: "error", text: "Add a checkpoint note describing the evidence, blocker, or completed work." };
        return;
      }
      this.savingTaskCheckpoint = true;
      this.taskCheckpointNotice = null;
      let committed = false;
      try {
        const saved = this.preview
          ? { progress, status: this.taskCheckpointForm.status, updatedAt: new Date().toISOString() }
          : await updateTaskCheckpoint(this.selectedTask.id, progress, this.taskCheckpointForm.status, note, this.selectedTask.updatedAt);
        committed = true;
        this.data.tasks = this.data.tasks.map((task) => task.id === this.selectedTask.id ? { ...task, progress: saved.progress, status: saved.status } : task);
        this.selectedTask = { ...this.selectedTask, progress: saved.progress, status: saved.status, updatedAt: saved.updatedAt };
        this.taskCheckpointForm = { progress: saved.progress, status: saved.status, note: "" };
        if (!this.preview) await this.refreshDashboard();
        if (!this.preview) this.selectedTask = await loadTaskDetail(saved.id || this.selectedTask.id);
        this.taskCheckpointNotice = { tone: "success", text: saved.status === "resubmitted" ? "Revision resubmitted for administrator review." : "Checkpoint saved with an auditable note." };
      } catch (reason) {
        const stale = reason instanceof Error && reason.message.includes("TASK_STALE_WRITE");
        this.taskCheckpointNotice = committed
          ? { tone: "warning", text: "The checkpoint was saved, but the refreshed task could not be loaded. Close and reopen the task before taking another action." }
          : { tone: "error", text: stale ? "This task changed in another session. Close and reopen it before trying again." : readableError(reason, "Unable to persist task progress.") };
      } finally {
        this.savingTaskCheckpoint = false;
      }
    },
    async reviewSelectedTask(action) {
      if (this.access?.role !== "admin" || !this.selectedTask || this.savingTaskReview) return;
      const note = this.taskReviewForm.note.trim();
      if (action === "request_revision" && note.length < 12) {
        this.taskCheckpointNotice = { tone: "error", text: "Add at least 12 characters of actionable revision guidance." };
        return;
      }
      this.savingTaskReview = action;
      let committed = false;
      try {
        const saved = this.preview
          ? { id: this.selectedTask.id, status: { request_revision: "revision_requested", approve: "approved", complete: "completed" }[action], updatedAt: new Date().toISOString() }
          : await reviewTask(this.selectedTask.id, action, note, this.selectedTask.updatedAt);
        committed = true;
        this.data.tasks = this.data.tasks.map((task) => task.id === saved.id ? { ...task, status: saved.status, progress: saved.status === "completed" ? 100 : task.progress, updatedAt: saved.updatedAt } : task);
        this.selectedTask = { ...this.selectedTask, status: saved.status, progress: saved.status === "completed" ? 100 : this.selectedTask.progress, updatedAt: saved.updatedAt };
        this.taskReviewForm.note = "";
        if (!this.preview) await this.refreshDashboard();
        if (!this.preview) this.selectedTask = await loadTaskDetail(saved.id);
        this.taskCheckpointNotice = { tone: "success", text: { request_revision: "Revision requested with guidance for the assignee.", approve: "Task approved. It is ready for administrator completion.", complete: "Approved task completed." }[action] };
      } catch (reason) {
        const stale = reason instanceof Error && reason.message.includes("TASK_STALE_WRITE");
        this.taskCheckpointNotice = committed
          ? { tone: "warning", text: "The review action was saved, but the refreshed task could not be loaded. Close and reopen the task before taking another action." }
          : { tone: "error", text: stale ? "This task changed in another session. Close and reopen it before trying again." : readableError(reason, "Unable to review this task.") };
      } finally {
        this.savingTaskReview = "";
      }
    },
    async snoozePasswordReminder() {
      this.passwordReminderSnoozing = true;
      try {
        const until = snoozeUntil().toISOString();
        if (!this.preview) await snoozePasswordReminder(until);
        this.access = { ...this.access, passwordReminderSnoozedUntil: until };
        this.showToast("Reminder snoozed", "We will remind you again in seven days.");
      } catch (reason) {
        this.showToast("Reminder not saved", readableError(reason, "Unable to snooze the reminder."));
      } finally {
        this.passwordReminderSnoozing = false;
      }
    },
    async savePasswordChange() {
      if (!this.passwordChangeForm.currentPassword) {
        this.showToast("Current password required", "Enter your current password to confirm the change.");
        return;
      }
      if (this.passwordChangeForm.password !== this.passwordChangeForm.confirmation) {
        this.showToast("Passwords do not match", "Enter the same new password twice.");
        return;
      }
      this.passwordChanging = true;
      try {
        await changePassword(this.passwordChangeForm.password, this.passwordChangeForm.currentPassword);
        this.access = { ...this.access, passwordChangedAt: new Date().toISOString(), passwordReminderSnoozedUntil: null };
        this.passwordChangeForm = { currentPassword: "", password: "", confirmation: "" };
        this.passwordReminderOpen = false;
        this.showToast("Password updated", "Your account now has a unique password.");
      } catch (reason) {
        this.showToast("Password not updated", readableError(reason, "Unable to update your password."));
      } finally {
        this.passwordChanging = false;
      }
    },
    setupDailyEodRefresh() {
      if (this.preview) return;
      this.dailyEodVisibilityHandler ||= () => {
        if (!document.hidden) this.refreshDailyEod({ preserveDraft: true });
      };
      this.dailyEodFocusHandler ||= () => this.refreshDailyEod({ preserveDraft: true });
      document.addEventListener("visibilitychange", this.dailyEodVisibilityHandler);
      window.addEventListener("focus", this.dailyEodFocusHandler);
      this.scheduleDailyEodRefresh();
    },
    scheduleDailyEodRefresh() {
      window.clearTimeout(this.dailyEodRefreshTimer);
      if (this.preview) return;
      const dueAt = new Date(this.dailyEod.dueAt || "").getTime();
      const untilDue = Number.isFinite(dueAt) && dueAt > Date.now() ? dueAt - Date.now() + 1000 : Infinity;
      this.dailyEodRefreshTimer = setTimeout(() => this.refreshDailyEod({ preserveDraft: true }), Math.max(1000, Math.min(300000, untilDue)));
    },
    setupDailyEodRecovery() {
      this.dailyEodBeforeUnloadHandler ||= (event) => {
        if (!this.dailyEodDirty) return;
        this.persistDailyEodRecovery();
        event.preventDefault();
        event.returnValue = "";
      };
      window.addEventListener("beforeunload", this.dailyEodBeforeUnloadHandler);
      if (typeof this.$watch === "function") {
        this.$watch("dailyEodForm", () => {
          if (!this.dailyEodDirty) return;
          window.clearTimeout(this.dailyEodRecoveryTimer);
          this.dailyEodRecoveryTimer = setTimeout(() => this.persistDailyEodRecovery(), 300);
        });
      }
    },
    confirmDailyEodNavigation() {
      if (!this.dailyEodDirty) return true;
      const confirmed = globalThis.confirm("Leave this EOD brief? Your unsaved work will remain available for recovery.");
      if (confirmed) this.persistDailyEodRecovery();
      return confirmed;
    },
    persistDailyEodRecovery() {
      if (!this.dailyEodDirty || !this.dailyEodRecoveryKey) return;
      writeDailyEodDraft(globalThis.localStorage, this.dailyEodRecoveryKey, this.dailyEodForm);
    },
    recoverDailyEodDraft() {
      if (!this.dailyEodRecovery?.draft) return;
      this.dailyEodForm = createDailyEodDraft(this.dailyEodRecovery.draft);
      this.dailyEodRecovery = null;
      this.dailyEodDirty = true;
      this.dailyEodNotice = { tone: "warning", text: "Recovered unsaved work. Review it against the current server record before saving." };
    },
    discardDailyEodRecovery() {
      if (this.dailyEodRecoveryKey) globalThis.localStorage.removeItem(this.dailyEodRecoveryKey);
      this.dailyEodRecovery = null;
    },
    markDailyEodDirty() {
      this.dailyEodDirty = true;
      if (Object.keys(this.dailyEodFieldErrors).length) {
        this.dailyEodFieldErrors = validateDailyEodFields({
          ...this.dailyEodForm,
          evidenceLinks: (this.dailyEodForm.evidenceLinks || []).filter((link) => String(link.label || "").trim() || String(link.url || "").trim()),
        });
        if (this.dailyEodNotice?.kind === "validation") {
          const count = Object.keys(this.dailyEodFieldErrors).length;
          this.dailyEodNotice = count
            ? { tone: "error", kind: "validation", text: `Review ${count} required ${count === 1 ? "field" : "fields"} before submitting.` }
            : null;
        }
      }
    },
    focusDailyEodField(field) {
      const fields = [...document.querySelectorAll(`.eod-layout [data-eod-field="${field}"]`)];
      const fieldElement = fields.find((element) => element.getAttribute("aria-invalid") === "true") || fields[0];
      const target = fieldElement?.matches("fieldset")
        ? fieldElement.querySelector("input:not([disabled]), select:not([disabled]), textarea:not([disabled])")
        : fieldElement;
      target?.focus();
    },
    dailyEodAdminValidationErrors(action = this.dailyEodAdminValidationAction) {
      const errors = {};
      if (this.dailyEodAdminReason.trim().length < 3) errors.adminReason = "Add an edit or completion reason with at least three characters.";
      const requiresCompleteBrief = ["submitted", "completed"].includes(this.selectedDailyEod?.workflowStatus) || action === "complete";
      if (requiresCompleteBrief && !this.dailyEodLegacyEvidence) {
        Object.assign(errors, validateDailyEodFields({
          ...this.dailyEodAdminForm,
          evidenceLinks: (this.dailyEodAdminForm.evidenceLinks || []).filter((link) => String(link.label || "").trim() || String(link.url || "").trim()),
        }));
      }
      return errors;
    },
    revalidateDailyEodAdmin() {
      if (!Object.keys(this.dailyEodAdminFieldErrors).length) return;
      this.dailyEodAdminFieldErrors = this.dailyEodAdminValidationErrors();
      const count = Object.keys(this.dailyEodAdminFieldErrors).length;
      this.dailyEodAdminNotice = count
        ? { tone: "error", kind: "validation", text: `Review ${count} administrator ${count === 1 ? "field" : "fields"}.` }
        : null;
      this.syncDailyEodAdminStaticErrors();
    },
    syncDailyEodAdminStaticErrors() {
      this.$nextTick(() => {
        const drawer = document.querySelector(".eod-record-drawer");
        if (!drawer) return;
        const fields = [
          ["engagementManagerId", '[x-model="dailyEodAdminForm.engagementManagerId"]'],
          ["personInChargeId", '[x-model="dailyEodAdminForm.personInChargeId"]'],
          ["adminReason", '[x-model="dailyEodAdminReason"]'],
        ];
        for (const [field, selector] of fields) {
          const control = drawer.querySelector(selector);
          if (!control) continue;
          control.dataset.eodField = field;
          const error = this.dailyEodAdminFieldError(field);
          let message = control.closest("label")?.querySelector(`[data-eod-admin-error-for="${field}"]`);
          if (!message) {
            message = document.createElement("span");
            message.id = `eod-admin-error-${field}`;
            message.className = "eod-field-error";
            message.dataset.eodAdminErrorFor = field;
            control.closest("label")?.append(message);
          }
          message.textContent = error;
          message.hidden = !error;
          if (error) {
            control.setAttribute("aria-invalid", "true");
            control.setAttribute("aria-errormessage", message.id);
            control.setAttribute("aria-describedby", message.id);
          } else {
            control.removeAttribute("aria-invalid");
            control.removeAttribute("aria-errormessage");
            control.removeAttribute("aria-describedby");
          }
        }
      });
    },
    focusDailyEodAdminField(field) {
      const drawer = document.querySelector(".eod-record-drawer");
      const fields = [...(drawer?.querySelectorAll(`[data-eod-field="${field}"]`) || [])];
      const fieldElement = fields.find((element) => element.getAttribute("aria-invalid") === "true") || fields[0];
      const target = fieldElement?.matches("fieldset")
        ? fieldElement.querySelector("input:not([disabled]), select:not([disabled]), textarea:not([disabled])")
        : fieldElement;
      target?.focus();
    },
    hydrateDailyEod(snapshot = {}, { preserveDraft = false } = {}) {
      const localDraft = this.dailyEodForm;
      const incomingScope = `${snapshot?.serverDate || ""}:${snapshot?.projectId || snapshot?.myBrief?.projectId || ""}`;
      const sameScope = !this.dailyEodDraftScope || this.dailyEodDraftScope === incomingScope;
      const keepDraft = preserveDraft && this.dailyEodDirty && sameScope;
      this.data.dailyEod = snapshot || {};
      const manager = (snapshot?.members || []).find((member) => member.role === "admin");
      const defaults = {
        engagementManagerId: manager?.userId || "",
        personInChargeId: this.dailyEodUserId || "",
      };
      this.dailyEodForm = keepDraft
        ? createDailyEodDraft(localDraft)
        : createDailyEodDraft(snapshot?.myBrief || defaults);
      if (preserveDraft && this.dailyEodDirty && !sameScope) {
        this.dailyEodNotice = { tone: "warning", text: "The EOD workday or project changed. The previous draft was not carried into the new brief." };
      }
      this.dailyEodDraftScope = incomingScope;
      if (!keepDraft) {
        this.dailyEodDirty = false;
        this.dailyEodRecovery = readDailyEodDraft(globalThis.localStorage, this.dailyEodRecoveryKey);
      }
      this.dailyEodState = "ready";
    },
    toggleDailyEodOwner(owner, target = "own") {
      const form = target === "admin" ? this.dailyEodAdminForm : this.dailyEodForm;
      form.executiveOwners = toggleExecutiveOwner(form.executiveOwners, owner);
      if (target === "own") this.markDailyEodDirty();
      else this.revalidateDailyEodAdmin();
    },
    addDailyEodEvidence(target = "own") {
      const form = target === "admin" ? this.dailyEodAdminForm : this.dailyEodForm;
      form.evidenceLinks.push({ sourceType: "onedrive", label: "", url: "" });
      if (target === "own") this.markDailyEodDirty();
      else this.revalidateDailyEodAdmin();
    },
    removeDailyEodEvidence(index, target = "own") {
      const form = target === "admin" ? this.dailyEodAdminForm : this.dailyEodForm;
      if (form.evidenceLinks.length === 1) {
        form.evidenceLinks.splice(0, 1, { sourceType: "onedrive", label: "", url: "" });
        if (target === "own") this.markDailyEodDirty();
        else this.revalidateDailyEodAdmin();
        return;
      }
      form.evidenceLinks.splice(index, 1);
      if (target === "own") this.markDailyEodDirty();
      else this.revalidateDailyEodAdmin();
    },
    async saveDailyEod(workflowStatus) {
      const payload = {
        ...this.dailyEodForm,
        evidenceLinks: (this.dailyEodForm.evidenceLinks || []).filter((link) => String(link.label || "").trim() || String(link.url || "").trim()),
        workflowStatus,
        scopeDate: this.dailyEod.serverDate,
        scopeProjectId: this.dailyEod.projectId || this.dailyEod.myBrief?.projectId,
      };
      if (workflowStatus === "submitted") {
        this.dailyEodFieldErrors = validateDailyEodFields(payload);
        const errors = Object.values(this.dailyEodFieldErrors);
        if (errors.length) {
          this.dailyEodNotice = { tone: "error", kind: "validation", text: `Review ${errors.length} required ${errors.length === 1 ? "field" : "fields"} before submitting.` };
          this.$nextTick(() => {
            document.querySelector("#eod-error-summary")?.focus();
          });
          return;
        }
      }
      this.savingDailyEod = true;
      this.dailyEodNotice = null;
      try {
        if (this.preview) {
          const now = new Date().toISOString();
          const memberName = (id) => this.dailyEodMembers.find((member) => member.userId === id)?.displayName || "";
          const saved = {
            ...payload,
            id: payload.id || `eod-preview-${Date.now()}`,
            briefDate: this.dailyEod.serverDate,
            authorId: this.dailyEodUserId,
            authorName: this.access.displayName,
            authorRole: this.access.role,
            engagementManagerName: memberName(payload.engagementManagerId),
            personInChargeName: memberName(payload.personInChargeId),
            submittedAt: workflowStatus === "submitted" ? (payload.submittedAt || now) : payload.submittedAt,
            isLate: this.dailyEod.dueState === "overdue",
            updatedAt: now,
          };
          this.data.dailyEod = {
            ...this.dailyEod,
            myBrief: saved,
            dueState: workflowStatus === "submitted" ? "submitted" : this.dailyEod.dueState,
            teamToday: (this.dailyEod.teamToday || []).map((member) => member.userId === this.dailyEodUserId ? { ...member, briefId: saved.id, brief: saved, workflowStatus } : member),
          };
          this.upsertPreviewDailyEod(saved);
          this.dailyEodForm = createDailyEodDraft(saved);
        } else {
          const saved = await saveDailyEodBrief(payload, this.dailyEodForm.updatedAt);
          this.hydrateDailyEod({ ...this.dailyEod, myBrief: saved, dueState: saved.workflowStatus });
          await this.refreshDailyEod();
          await this.searchDailyEodReports(1);
        }
        this.dailyEodConflictDraft = null;
        this.dailyEodConflictLoaded = false;
        this.dailyEodDirty = false;
        this.dailyEodFieldErrors = {};
        this.discardDailyEodRecovery();
        this.dailyEodNotice = { tone: "success", text: workflowStatus === "submitted" ? "EOD brief submitted for administrator check." : "Draft saved. Your daily requirement is complete only after submission." };
      } catch (reason) {
        if (reason instanceof Error && reason.message.includes("EOD_STALE_WRITE")) {
          this.dailyEodConflictDraft = createDailyEodDraft(payload);
          this.dailyEodConflictLoaded = false;
        }
        this.dailyEodNotice = { tone: "error", text: readableError(reason, "Unable to save the EOD brief.") };
      } finally {
        this.savingDailyEod = false;
      }
    },
    async reloadDailyEodConflict() {
      if (!this.dailyEodConflictDraft) return;
      try {
        const loaded = await this.refreshDailyEod({ throwOnError: true });
        if (!loaded) return;
        this.dailyEodConflictLoaded = true;
        this.dailyEodNotice = { tone: "warning", text: "The latest saved brief is loaded. Review it, or restore your unsaved draft for comparison." };
      } catch (reason) {
        this.dailyEodNotice = { tone: "error", text: readableError(reason, "Unable to reload the latest EOD brief.") };
      }
    },
    restoreDailyEodConflictDraft() {
      if (!this.dailyEodConflictDraft || !this.dailyEodConflictLoaded) return;
      this.dailyEodForm = createDailyEodDraft({
        ...this.dailyEodConflictDraft,
        id: this.dailyEod.myBrief?.id || this.dailyEodConflictDraft.id,
        updatedAt: this.dailyEod.myBrief?.updatedAt || null,
      });
      this.dailyEodDirty = true;
      this.dailyEodNotice = { tone: "warning", text: "Your unsaved draft is restored over the latest version. Review every field before saving." };
    },
    openDailyEodRecord(record) {
      if (!record) return;
      if (!this.selectedDailyEod) this.dailyEodReturnFocus = document.activeElement;
      this.selectedDailyEod = record;
      this.dailyEodAdminForm = createDailyEodDraft(record);
      this.dailyEodAdminReason = "";
      this.dailyEodAdminNotice = null;
      this.dailyEodAdminFieldErrors = {};
      this.dailyEodAdminValidationAction = "save";
      this.$nextTick(() => {
        const drawer = document.querySelector(".eod-record-drawer");
        const title = drawer?.querySelector(".drawer-title h2");
        const close = drawer?.querySelector(".drawer-header .icon-button");
        const notice = document.querySelector(".eod-drawer-notice");
        const errorSummary = document.querySelector("#eod-admin-error-summary");
        if (drawer && notice && notice.parentElement !== drawer) drawer.prepend(notice);
        const form = drawer?.querySelector(".eod-drawer-form");
        if (form && errorSummary && errorSummary.parentElement !== form) form.prepend(errorSummary);
        if (form && !form.dataset.adminValidationBound) {
          form.dataset.adminValidationBound = "true";
          form.addEventListener("input", () => this.revalidateDailyEodAdmin());
          form.addEventListener("change", () => this.revalidateDailyEodAdmin());
        }
        if (drawer && title) {
          title.id = "eod-record-title";
          drawer.setAttribute("aria-labelledby", title.id);
        }
        const previousMetadata = drawer?.querySelector(".eod-record-metadata");
        previousMetadata?.remove();
        const metadata = document.createElement("div");
        metadata.className = "eod-record-metadata";
        const timestamp = (value) => formatDailyEodTimestamp(value, this.locale, this.dailyEod.timezone || "UTC");
        metadata.textContent = [
          record.projectCode && `${record.projectCode}${record.projectName ? `, ${record.projectName}` : ""}`,
          record.submittedAt && `Submitted ${timestamp(record.submittedAt)}${record.isLate ? " (late)" : ""}`,
          record.completedAt && `Completed by ${record.completedByName || "administrator"} ${timestamp(record.completedAt)}`,
          record.lastEditedByName && `Last edited by ${record.lastEditedByName}${record.lastEditReason ? `: ${record.lastEditReason}` : ""}`,
        ].filter(Boolean).join(" · ") || "Draft record.";
        drawer?.querySelector(".drawer-title")?.after(metadata);
        const existingLinks = form?.querySelector(".eod-linked-evidence");
        existingLinks?.remove();
        const evidenceLinks = (record.evidenceLinks || []).filter((link) => {
          try {
            return ["http:", "https:"].includes(new URL(link.url).protocol);
          } catch {
            return false;
          }
        });
        if (form && evidenceLinks.length) {
          const section = document.createElement("section");
          section.className = "eod-linked-evidence";
          const heading = document.createElement("span");
          heading.className = "section-kicker";
          heading.textContent = "Open evidence";
          section.append(heading);
          for (const link of evidenceLinks) {
            const anchor = document.createElement("a");
            anchor.href = link.url;
            anchor.target = "_blank";
            anchor.rel = "noopener noreferrer";
            anchor.textContent = `${String(link.sourceType || "evidence").replaceAll("_", " ")} · ${link.label}`;
            section.append(anchor);
          }
          form.append(section);
        }
        close?.setAttribute("aria-label", "Close EOD record");
        close?.focus();
        this.syncDailyEodAdminStaticErrors();
      });
    },
    closeDailyEodRecord() {
      this.selectedDailyEod = null;
      this.dailyEodAdminReason = "";
      this.dailyEodAdminNotice = null;
      this.dailyEodAdminFieldErrors = {};
      this.$nextTick(() => this.dailyEodReturnFocus?.focus?.());
    },
    trapDailyEodFocus(event) {
      const drawer = document.querySelector(".eod-record-drawer");
      if (!drawer) return;
      const controls = [...drawer.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter((element) => element.offsetParent !== null);
      if (!controls.length) return;
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    upsertPreviewDailyEod(record) {
      const items = this.data.dailyEodReportItems || [];
      this.data.dailyEodReportItems = items.some((item) => item.id === record.id)
        ? items.map((item) => item.id === record.id ? { ...item, ...record } : item)
        : [record, ...items];
    },
    async adminCompleteDailyEod(action = "complete") {
      if (this.access?.role !== "admin" || !this.selectedDailyEod) return;
      this.dailyEodAdminValidationAction = action;
      const payload = {
        ...this.dailyEodAdminForm,
        evidenceLinks: (this.dailyEodAdminForm.evidenceLinks || []).filter((link) => String(link.label || "").trim() || String(link.url || "").trim()),
      };
      this.dailyEodAdminFieldErrors = this.dailyEodAdminValidationErrors(action);
      const errorCount = Object.keys(this.dailyEodAdminFieldErrors).length;
      if (errorCount) {
        this.dailyEodAdminNotice = { tone: "error", kind: "validation", text: `Review ${errorCount} administrator ${errorCount === 1 ? "field" : "fields"}.` };
        this.syncDailyEodAdminStaticErrors();
        this.$nextTick(() => document.querySelector("#eod-admin-error-summary")?.focus());
        return;
      }
      this.savingDailyEodAdmin = true;
      this.dailyEodAdminNotice = null;
      try {
        let saved;
        if (this.preview) {
          const now = new Date().toISOString();
          saved = { ...payload, workflowStatus: action === "complete" ? "completed" : this.selectedDailyEod.workflowStatus, completedByName: action === "complete" ? this.access.displayName : this.selectedDailyEod.completedByName, completedAt: action === "complete" ? now : this.selectedDailyEod.completedAt, lastEditedByName: this.access.displayName, lastEditReason: this.dailyEodAdminReason.trim(), updatedAt: now };
          this.data.dailyEod.teamToday = (this.dailyEod.teamToday || []).map((member) => member.briefId === saved.id ? { ...member, brief: saved, workflowStatus: saved.workflowStatus, updatedAt: saved.updatedAt } : member);
          this.dailyEodReports.items = this.dailyEodReports.items.map((item) => item.id === saved.id ? saved : item);
          this.upsertPreviewDailyEod(saved);
        } else {
          saved = await adminUpdateDailyEodBrief(this.selectedDailyEod.id, payload, this.dailyEodAdminReason, this.selectedDailyEod.updatedAt, action);
          await this.refreshDailyEod({ preserveDraft: true });
          await this.searchDailyEodReports(this.dailyEodReports.page);
          const refreshed = this.dailyEodReports.items.find((item) => item.id === saved.id);
          saved = { ...saved, auditHistory: refreshed?.auditHistory || this.selectedDailyEod.auditHistory || [] };
        }
        this.openDailyEodRecord(saved);
        this.dailyEodAdminNotice = { tone: "success", text: action === "complete" ? "EOD brief marked complete." : "Administrator edit saved with an audit reason." };
      } catch (reason) {
        this.dailyEodAdminNotice = { tone: "error", text: readableError(reason, "Unable to update the EOD brief.") };
      } finally {
        this.savingDailyEodAdmin = false;
      }
    },
    async searchDailyEodReports(page = 1) {
      const sequence = ++this.dailyEodReportsSequence;
      this.loadingDailyEodReports = true;
      this.dailyEodReportError = "";
      try {
        let reports;
        if (this.preview) {
          const filters = this.dailyEodReportFilters;
          const query = filters.search.trim().toLowerCase();
          let items = (this.data.dailyEodReportItems || []).filter((item) => {
            const matchesSearch = !query || [item.authorName, item.engagementManagerName, item.personInChargeName, item.projectCode, item.projectName].some((value) => String(value || "").toLowerCase().includes(query));
            return matchesSearch
              && (!filters.authorId || item.authorId === filters.authorId)
              && (!filters.engagementManagerId || item.engagementManagerId === filters.engagementManagerId)
              && (!filters.personInChargeId || item.personInChargeId === filters.personInChargeId)
              && (!filters.projectId || item.projectId === filters.projectId)
              && (!filters.projectLifecycle || item.projectLifecycle === filters.projectLifecycle)
              && (!filters.fromDate || item.briefDate >= filters.fromDate)
              && (!filters.toDate || item.briefDate <= filters.toDate)
              && (!filters.authorRole || item.authorRole === filters.authorRole)
              && (!filters.projectStatus || item.projectStatus === filters.projectStatus)
              && (!filters.workflowStatus || item.workflowStatus === filters.workflowStatus);
          });
          if (this.access?.role !== "admin") items = items.filter((item) => item.authorId === this.dailyEodUserId);
          reports = { items, total: items.length, page: 1, pageSize: 25 };
        } else {
          reports = await loadDailyEodReports(this.dailyEodReportFilters, page, 25);
        }
        if (sequence !== this.dailyEodReportsSequence) return false;
        this.dailyEodReports = reports;
        this.dailyEodReportsLoaded = true;
        return true;
      } catch (reason) {
        if (sequence !== this.dailyEodReportsSequence) return false;
        this.dailyEodReportError = readableError(reason, "Unable to load EOD reports.");
        return false;
      } finally {
        if (sequence === this.dailyEodReportsSequence) this.loadingDailyEodReports = false;
      }
    },
    async refreshDailyEod({ preserveDraft = false, throwOnError = false } = {}) {
      const sequence = ++this.dailyEodRefreshSequence;
      const hasUsableSnapshot = this.dailyEodState === "ready" && Boolean(this.dailyEod.serverDate);
      this.dailyEodError = "";
      this.refreshingDailyEod = true;
      if (!hasUsableSnapshot) this.dailyEodState = "loading";
      try {
        const snapshot = await loadDailyEod();
        if (sequence !== this.dailyEodRefreshSequence) return false;
        this.hydrateDailyEod(snapshot, { preserveDraft });
        return true;
      } catch (reason) {
        if (sequence !== this.dailyEodRefreshSequence) return false;
        this.dailyEodError = readableError(reason, "The EOD brief is temporarily unavailable.");
        this.dailyEodState = hasUsableSnapshot ? "ready" : "failed";
        if (throwOnError) throw reason;
        return false;
      } finally {
        if (sequence === this.dailyEodRefreshSequence) {
          this.refreshingDailyEod = false;
          this.scheduleDailyEodRefresh();
        }
      }
    },
    async refreshDashboard({ refreshInbox = true } = {}) {
      const sequence = ++this.dashboardRefreshSequence;
      this.loading = true;
      this.error = "";
      try {
        const liveData = await loadDashboard();
        if (sequence !== this.dashboardRefreshSequence) return false;
        this.data = {
          ...liveData,
          dailyEod: liveData.dailyEod || this.data.dailyEod,
          campaign: liveData.campaign || { name: "", deadline: null, targetLow: 0, targetHigh: 0, planningTarget: 0, conversionRate: 0 },
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
        if (refreshInbox) await this.refreshInbox();
        return true;
      } catch (reason) {
        if (sequence !== this.dashboardRefreshSequence) return false;
        this.error = readableError(reason, "Live workspace data is unavailable.");
        return false;
      } finally {
        if (sequence === this.dashboardRefreshSequence) this.loading = false;
      }
    },
    async refreshBriefing(projectId = this.projectSwitcherValue || this.access?.projectId || null) {
      const sequence = ++this.briefingRefreshSequence;
      const hasConfirmedData = Boolean(this.briefingState.generatedAt);
      this.briefingLoading = true;
      this.briefingError = "";
      try {
        const payload = this.briefingPreviewMode
          ? createPreviewBriefing(fallbackDashboard, this.expectedRole, this.access?.displayName)
          : createBriefingState(await loadTodayBriefing(projectId));
        if (sequence !== this.briefingRefreshSequence) return false;
        this.briefingState = payload;
        this.briefingPreviewMode = payload.preview;
        this.briefingStale = false;
        return true;
      } catch (reason) {
        if (sequence !== this.briefingRefreshSequence) return false;
        this.briefingError = readableError(reason, "The live briefing is temporarily unavailable.");
        this.briefingStale = hasConfirmedData;
        return false;
      } finally {
        if (sequence === this.briefingRefreshSequence) this.briefingLoading = false;
      }
    },
    async retryLiveBriefing() {
      this.briefingPreviewMode = false;
      return this.refreshBriefing();
    },
    usePreview() {
      this.dashboardRefreshSequence += 1;
      this.briefingRefreshSequence += 1;
      const previewName = this.expectedRole === "admin" ? "Avery Example" : "Morgan Example";
      this.data = scopePreviewDashboard(fallbackDashboard, this.expectedRole, previewName);
      this.briefingState = createPreviewBriefing(fallbackDashboard, this.expectedRole, previewName);
      this.briefingPreviewMode = true;
      this.briefingLoading = false;
      this.briefingError = "";
      this.briefingStale = false;
      const previewProject = scopePreviewProject(this.expectedRole);
      this.data = { ...this.data, project: { ...this.data.project, ...previewProject.snapshot.project } };
      this.briefingState = { ...this.briefingState, project: previewProject.snapshot.project };
      this.projectContext = previewProject.context;
      this.projectSnapshot = normalizeProjectSnapshot(previewProject.snapshot);
      this.previewCollaboration = Object.fromEntries([...(this.projectSnapshot.milestones || []), ...(this.projectSnapshot.blockers || []), ...(this.projectSnapshot.risks || []), ...(this.projectSnapshot.decisions || [])].map((record) => {
        const sourceType = record.id.includes("milestone") ? "milestone" : record.id.includes("blocker") ? "blocker" : record.id.includes("risk") ? "risk" : "decision";
        return [`${sourceType}:${record.id}`, { sourceType, sourceId: record.id, projectId: previewProject.context.selectedProjectId, isFollowing: false, eligibleCollaborators: this.projectSnapshot.members, comments: [] }];
      }));
      for (const [sourceType, records] of [["milestone", this.projectSnapshot.milestones], ["blocker", this.projectSnapshot.blockers], ["risk", this.projectSnapshot.risks], ["decision", this.projectSnapshot.decisions]]) {
        for (const record of records || []) record.collaboration = this.previewCollaboration[`${sourceType}:${record.id}`];
      }
      this.inbox = createInboxState({
        projectId: previewProject.context.selectedProjectId,
        counts: { needsAction: 1 },
        items: [{ id: "preview-project-inbox-1", projectId: previewProject.context.selectedProjectId, sourceType: "project_decision", sourceId: "preview-decision-1", summary: "Review the accessibility context decision", reason: "A fictional project decision is ready for governance review.", priority: "high", readAt: null, resolvedAt: null }],
        generatedAt: previewProject.snapshot.generatedAt,
      });
      this.access = { ...this.access, projectId: previewProject.context.selectedProjectId, organizationId: previewProject.context.selectedOrganizationId };
      this.preview = true;
      this.hydrateDailyEod(this.data.dailyEod);
      this.dailyEodReportsLoaded = false;
      this.error = "";
      this.chatReady = false;
      this.destroyChat().then(() => this.initializeChat());
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
      if (!this.confirmDailyEodNavigation()) return;
      this.persistDailyEodRecovery();
      globalThis.sessionStorage.removeItem(this.researchDraftStorageKey());
      await this.destroyChat();
      await signOut();
      location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
    },
  }));
}
