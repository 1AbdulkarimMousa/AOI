import { addEvidence, createAdminTask, createAdminUser, listAdminUsers, loadDashboard, logOutreach, upsertCandidate } from "./api.js";
import { getExistingWorkspaceAccess, signOut } from "./auth.js";
import { clamp, csvCell, initials, pageUrl, readableError, routeForRole, scopePreviewDashboard } from "./core.js";
import { fallbackDashboard } from "./demo-data.js";
import { translate, translateData } from "./i18n.js";
import { buildCandidateExport, buildRecommendations, parseCandidateImport } from "./operations.js";

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
    view: document.body.dataset.expectedRole === "intern" ? "work" : "overview",
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
     importPreview: null,
     importErrors: [],
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
      { id: "work", label: "My work" },
      { id: "research", label: "Research ops" },
      { id: "pmf", label: "PMF validation" },
      { id: "reports", label: "Reports" },
      { id: "team", label: "Team momentum" },
      { id: "outreach", label: "KOL outreach" },
      { id: "evidence", label: "Evidence & consent" },
      { id: "imports", label: "Import / export" },
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
      return new Intl.DateTimeFormat(this.locale, { month: "short", day: "numeric" }).format(new Date(`${value}T12:00:00`));
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

    setView(view) {
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
    async saveCandidate() {
      const candidate = { ...this.candidateForm, id: this.selectedCandidate?.id || `local-${Date.now()}`, externalId: this.selectedCandidate?.externalId || `local-${this.candidates.length + 1}`, priorityScore: this.selectedCandidate?.priorityScore || 50, priorityBand: this.selectedCandidate?.priorityBand || "Medium", interestLevel: this.selectedCandidate?.interestLevel || "Unknown", lastUpdated: new Date().toISOString().slice(0, 10) };
      if (!candidate.name.trim()) {
        this.candidateNotice = { tone: "error", text: "Add a creator or organization name before saving." };
        return;
      }
      if (!this.preview) {
        try {
          await upsertCandidate(candidate);
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
    importFile(event) {
      const file = event.target.files?.[0];
      if (!file) return;
      const reader = new globalThis.FileReader();
      reader.onload = () => {
        const result = parseCandidateImport(reader.result);
        this.importPreview = result.rows;
        this.importErrors = result.errors;
        this.candidateNotice = result.errors.length ? { tone: "error", text: `${result.errors.length} row(s) need attention before import.` } : { tone: "success", text: `${result.rows.length} candidate row(s) ready to import.` };
      };
      reader.readAsText(file);
    },
    commitImport() {
      if (!this.importPreview?.length) return;
      const imported = this.importPreview.map((row, index) => ({ ...row, id: `import-${Date.now()}-${index}`, priorityScore: 50, priorityBand: "Medium", interestLevel: "Unknown", lastUpdated: new Date().toISOString().slice(0, 10) }));
      this.data.candidates = [...imported, ...this.candidates];
      this.data.outreachSummary = { ...this.data.outreachSummary, totalCandidates: this.candidates.length };
      this.importPreview = null;
      this.importErrors = [];
      this.candidateNotice = { tone: "success", text: `${imported.length} candidates imported into the pipeline.` };
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
           recommendations: liveData.recommendations || [],
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
