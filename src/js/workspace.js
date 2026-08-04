import { createAdminTask, createAdminUser, listAdminUsers, loadDashboard } from "./api.js";
import { getExistingWorkspaceAccess, signOut } from "./auth.js";
import { clamp, csvCell, initials, pageUrl, readableError, routeForRole, scopePreviewDashboard } from "./core.js";
import { fallbackDashboard } from "./demo-data.js";
import { translate, translateData } from "./i18n.js";

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
        this.data = await loadDashboard();
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
