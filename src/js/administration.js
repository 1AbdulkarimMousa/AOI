import {
  createAdminTask,
  createAdminUser,
  exportAdministrationData,
  importAdministrationData,
  loadAdministrationOverview,
  loadAdministrationPeople,
  loadAdministrationPerson,
  runAdministrationUserAction,
  updateAdministrationPerson,
} from "./api.js";
import { requireWorkspaceAccess, signOut } from "./auth.js";
import { buildAdministrationExport, createPersonDraft, filterAdministrationPeople, parseAdministrationImport } from "./administration-data.js";
import { initials, pageUrl, readableError, routeForRole } from "./core.js";

const previewPeople = [
  { userId: "preview-admin", displayName: "AOI Administrator", loginIdentifier: "admin@aoi.example", role: "admin", membershipStatus: "active", isOwner: true, locale: "en", timezone: "America/New_York", managerId: null, managerName: null, skills: ["Operations", "Review"], availability: "Full time", startDate: "2026-07-13", joinedAt: "2026-07-13T12:00:00Z", archivedAt: null, onboardingCompleted: 4, onboardingTotal: 4 },
  { userId: "preview-intern-1", displayName: "Kayla Tillmon", loginIdentifier: "kayla@aoi.example", role: "intern", membershipStatus: "active", isOwner: false, locale: "en", timezone: "America/New_York", managerId: "preview-admin", managerName: "AOI Administrator", skills: ["Interviews", "CRM"], availability: "Weekdays · 20 hours", startDate: "2026-07-20", joinedAt: "2026-07-20T12:00:00Z", archivedAt: null, onboardingCompleted: 3, onboardingTotal: 4 },
  { userId: "preview-intern-2", displayName: "Wen Tang", loginIdentifier: "wen@aoi.example", role: "intern", membershipStatus: "invited", isOwner: false, locale: "zh-CN", timezone: "America/Los_Angeles", managerId: "preview-admin", managerName: "AOI Administrator", skills: ["Research"], availability: "Weekdays · 16 hours", startDate: "2026-08-10", joinedAt: "2026-08-04T12:00:00Z", archivedAt: null, onboardingCompleted: 0, onboardingTotal: 4 },
  { userId: "preview-archive", displayName: "Jordan Lee", loginIdentifier: "jordan@aoi.example", role: "intern", membershipStatus: "archived", isOwner: false, locale: "en", timezone: "America/New_York", managerId: "preview-admin", managerName: "AOI Administrator", skills: ["Outreach"], availability: "", startDate: "2026-05-01", joinedAt: "2026-05-01T12:00:00Z", archivedAt: "2026-07-31T12:00:00Z", onboardingCompleted: 4, onboardingTotal: 4 },
];

const previewOverview = {
  people: { total: 4, active: 2, invited: 1, disabled: 0, archived: 1, admins: 1 },
  onboarding: { pending: 5, completed: 11 },
  work: { unassignedTasks: 2, activeTasks: 8, crmContacts: 10 },
  recentTransfers: [{ id: "transfer-1", jobType: "archive_handoff", mode: "handoff", status: "completed", createdAt: "2026-07-31T12:00:00Z" }],
};

function taskDraft() {
  const due = new Date();
  due.setDate(due.getDate() + 7);
  return { title: "", objective: "", assignedTo: "", priority: "medium", dueDate: due.toISOString().slice(0, 10), pmfLayer: "H1 · Need Truth", estimatedHours: 4, points: 100, acceptanceCriteria: "" };
}

function previewPersonDetail(person) {
  return {
    person: { ...person, phone: "", notes: person.membershipStatus === "archived" ? "Archived after the handoff was completed." : "" },
    onboarding: [
      { id: `${person.userId}-1`, label: "Secure your account", status: "completed" },
      { id: `${person.userId}-2`, label: "Review workspace responsibilities", status: person.onboardingCompleted > 1 ? "completed" : "pending" },
      { id: `${person.userId}-3`, label: "Review data handling rules", status: person.onboardingCompleted > 2 ? "completed" : "pending" },
      { id: `${person.userId}-4`, label: "File your first EOD brief", status: person.onboardingCompleted > 3 ? "completed" : "pending" },
    ],
    workload: { tasks: person.membershipStatus === "archived" ? 0 : 3, candidates: 2, crmContacts: 4, researchRecords: 6 },
    recentAudit: [{ id: `${person.userId}-audit`, action: person.membershipStatus === "archived" ? "user_archived" : "profile_updated", createdAt: person.archivedAt || person.joinedAt }],
  };
}

function download(filename, mime, content) {
  const url = URL.createObjectURL(new Blob([content], { type: mime }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function registerAdministration(Alpine) {
  Alpine.data("administrationPage", () => ({
    ready: false,
    access: null,
    preview: false,
    error: "",
    dark: localStorage.getItem("aoi-theme") === "dark",
    locale: localStorage.getItem("aoi-locale") === "zh-CN" ? "zh-CN" : "en",
    loginUrl: pageUrl(import.meta.env.BASE_URL, "login.html"),
    workspaceUrl: pageUrl(import.meta.env.BASE_URL, "workspace.html"),
    workspaceCrmUrl: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=crm`,
    sidebarCollapsed: false,
    mobileNav: false,
    section: "overview",
    sections: [
      { id: "overview", label: "Overview" },
      { id: "people", label: "People" },
      { id: "work", label: "Work & CRM" },
      { id: "data", label: "Data" },
      { id: "archive", label: "Archive & Audit" },
      { id: "guides", label: "Guides" },
    ],
    workspaceLinks: [
      { label: "Workspace overview", symbol: "W", href: pageUrl(import.meta.env.BASE_URL, "workspace.html") },
      { label: "Today", symbol: "T", href: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=today` },
      { label: "CRM", symbol: "C", href: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=crm` },
      { label: "End-of-Day Brief", symbol: "E", href: `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=eod` },
    ],
    overview: structuredClone(previewOverview),
    people: [],
    filters: { query: "", role: "all", status: "all" },
    selectedPerson: null,
    personTab: "profile",
    addPersonOpen: false,
    archiveOpen: false,
    archiveForm: { replacementUserId: "", departureDate: "", reason: "" },
    personForm: createPersonDraft(),
    personNotice: null,
    savingPerson: false,
    taskForm: taskDraft(),
    taskNotice: null,
    savingTask: false,
    exportScope: "full",
    importPackage: null,
    importPreview: null,
    importMode: "merge",
    importing: false,
    dataNotice: null,
    toast: null,
    drawerReturnFocus: null,
    guideIndex: 0,
    guides: [
      { title: "Add secure access", purpose: "Create the login and operational profile together.", steps: ["Choose Admin or Intern.", "Use an email invitation by default, or a temporary password when necessary.", "Record locale, timezone, manager, skills, availability, and start date.", "Review the setup before creating access."], section: "people", action: "Open people" },
      { title: "Assign work and CRM", purpose: "Make every active responsibility visible before work begins.", steps: ["Create a task with a clear outcome and acceptance criteria.", "Assign CRM contacts and dated follow-ups.", "Confirm the person can see only the records allowed by their role.", "Review unassigned work from the Overview queue."], section: "work", action: "Open Work & CRM" },
      { title: "Review onboarding", purpose: "Help new staff learn the workflow without monitoring behavior.", steps: ["Confirm the account is secure.", "Review workspace and data handling responsibilities.", "Walk through Today, My Work, CRM, and evidence collection.", "Check that the first EOD brief is complete."], section: "people", action: "Review people" },
      { title: "Export and restore", purpose: "Keep administration data portable and auditable.", steps: ["Choose the smallest useful export scope.", "Select CSV, JSON, or Markdown.", "Upload generated files into preview first.", "Review conflicts and counts before applying a merge or owner-only restore."], section: "data", action: "Open data tools" },
      { title: "Archive safely", purpose: "Remove access while preserving work provenance.", steps: ["Open the person and review active work.", "Choose a replacement for open tasks and CRM relationships.", "Record departure date and reason.", "Archive, verify the handoff, and keep the audit summary."], section: "archive", action: "Open archive" },
    ],

    async init() {
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
      document.documentElement.lang = this.locale;
      if (new URLSearchParams(location.search).get("preview") === "1") {
        this.preview = true;
        this.access = { userId: "preview-admin", role: "admin", displayName: "AOI Administrator", organizationName: "AOI Technologics", isOwner: true };
        this.people = structuredClone(previewPeople);
        this.ready = true;
        return;
      }
      try {
        const access = await requireWorkspaceAccess();
        if (access.mustChangePassword) {
          location.replace(this.loginUrl);
          return;
        }
        if (access.role !== "admin") {
          location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
          return;
        }
        this.access = access;
        await this.refresh();
      } catch (reason) {
        this.error = readableError(reason, "Unable to open Administration.");
      } finally {
        this.ready = true;
      }
    },
    get filteredPeople() { return filterAdministrationPeople(this.people, this.filters); },
    get activePeople() { return this.people.filter((person) => person.membershipStatus === "active"); },
    get archivedPeople() { return this.people.filter((person) => person.membershipStatus === "archived"); },
    get currentUserIsOwner() { return Boolean(this.people.find((person) => person.userId === this.access?.userId)?.isOwner || this.access?.isOwner); },
    get archiveReplacements() { return this.activePeople.filter((person) => person.userId !== this.selectedPerson?.person?.userId); },
    get importSummary() {
      const counts = this.importPreview?.counts || {};
      const conflicts = this.importPreview?.conflicts?.length || 0;
      return `${counts.people || 0} people · ${counts.tasks || 0} tasks · ${counts.crmOwnership || 0} CRM ownership records${conflicts ? ` · ${conflicts} conflict(s)` : ""}`;
    },
    initials,
    formatDate(value) {
      if (!value) return "Not recorded";
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? "Invalid date" : new Intl.DateTimeFormat(this.locale, { year: "numeric", month: "short", day: "numeric" }).format(date);
    },
    async refresh() {
      if (this.preview) return;
      this.error = "";
      try {
        [this.overview, this.people] = await Promise.all([loadAdministrationOverview(), loadAdministrationPeople()]);
        if (this.access) this.access.isOwner = this.currentUserIsOwner;
      } catch (reason) {
        this.error = readableError(reason, "Unable to load Administration data.");
      }
    },
    openAddPerson() {
      this.drawerReturnFocus = document.activeElement;
      this.personForm = createPersonDraft();
      this.personNotice = null;
      this.addPersonOpen = true;
      this.$nextTick(() => [...document.querySelectorAll(".admin-person-drawer")].find((drawer) => drawer.offsetParent !== null)?.querySelector("button")?.focus());
    },
    async openPerson(person) {
      this.drawerReturnFocus = document.activeElement;
      this.personNotice = null;
      this.archiveForm = { replacementUserId: "", departureDate: new Date().toISOString().slice(0, 10), reason: "" };
      this.personTab = "profile";
      this.selectedPerson = this.preview ? previewPersonDetail(person) : { person: { ...person }, onboarding: [], workload: {}, recentAudit: [] };
      this.$nextTick(() => [...document.querySelectorAll(".admin-person-drawer")].find((drawer) => drawer.offsetParent !== null)?.querySelector("button")?.focus());
      if (!this.preview) {
        try { this.selectedPerson = await loadAdministrationPerson(person.userId); }
        catch (reason) { this.personNotice = { tone: "error", text: readableError(reason, "Unable to load this person.") }; }
      }
    },
    closeDrawers() {
      this.addPersonOpen = false;
      this.archiveOpen = false;
      this.selectedPerson = null;
      this.personNotice = null;
      const returnFocus = this.drawerReturnFocus;
      this.drawerReturnFocus = null;
      this.$nextTick(() => returnFocus?.focus?.());
    },
    trapDrawerFocus(event) {
      const selector = this.archiveOpen ? ".admin-confirm-dialog" : (this.addPersonOpen || this.selectedPerson) ? ".admin-person-drawer" : null;
      const container = selector ? [...document.querySelectorAll(selector)].find((element) => element.offsetParent !== null) : null;
      if (!container) return;
      const focusable = [...container.querySelectorAll('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])')].filter((element) => element.offsetParent !== null);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    },
    async submitPerson() {
      this.savingPerson = true;
      this.personNotice = null;
      try {
        if (this.preview) throw new Error("Account creation is disabled in preview mode.");
        const input = { ...this.personForm, action: "create", accessMethod: this.personForm.accessMethod === "temporary_password" ? "temporary_password" : "invite", skills: this.personForm.skills.split(",").map((skill) => skill.trim()).filter(Boolean) };
        const result = await createAdminUser(input);
        this.personNotice = { tone: "success", text: result.temporaryPassword ? `Account created. Temporary password: ${result.temporaryPassword}` : "Invitation sent and onboarding prepared." };
        await this.refresh();
        this.showToast("Person added", `${result.user.display_name} is ready for onboarding.`);
      } catch (reason) {
        this.personNotice = { tone: "error", text: readableError(reason, "Unable to add this person.") };
      } finally {
        this.savingPerson = false;
      }
    },
    async savePerson() {
      this.savingPerson = true;
      this.personNotice = null;
      try {
        if (this.preview) throw new Error("Profile changes are disabled in preview mode.");
        this.selectedPerson = await updateAdministrationPerson(this.selectedPerson.person.userId, this.selectedPerson.person);
        await this.refresh();
        this.personNotice = { tone: "success", text: "Operational profile updated." };
      } catch (reason) {
        this.personNotice = { tone: "error", text: readableError(reason, "Unable to save this profile.") };
      } finally { this.savingPerson = false; }
    },
    async archivePerson() {
      this.savingPerson = true;
      this.personNotice = null;
      try {
        if (this.preview) throw new Error("Archival is disabled in preview mode.");
        const personName = this.selectedPerson.person.displayName;
        await runAdministrationUserAction("archive", { userId: this.selectedPerson.person.userId, replacementUserId: this.archiveForm.replacementUserId || null, reason: this.archiveForm.reason.trim(), departureDate: this.archiveForm.departureDate });
        this.closeDrawers();
        await this.refresh();
        this.section = "archive";
        this.showToast("Person archived", `${personName}'s access stopped and historical work was retained.`);
      } catch (reason) {
        this.personNotice = { tone: "error", text: readableError(reason, "Unable to archive this person.") };
      } finally { this.savingPerson = false; }
    },
    async restorePerson() {
      this.savingPerson = true;
      try {
        if (this.preview) throw new Error("Restore is disabled in preview mode.");
        const personName = this.selectedPerson.person.displayName;
        await runAdministrationUserAction("restore", { userId: this.selectedPerson.person.userId });
        this.closeDrawers();
        await this.refresh();
        this.showToast("Access restored", `${personName} can rejoin the onboarding workflow.`);
      } catch (reason) { this.personNotice = { tone: "error", text: readableError(reason, "Unable to restore this person.") }; }
      finally { this.savingPerson = false; }
    },
    async submitTask() {
      this.savingTask = true;
      this.taskNotice = null;
      try {
        if (this.preview) throw new Error("Task creation is disabled in preview mode.");
        await createAdminTask(this.taskForm);
        this.taskForm = taskDraft();
        await this.refresh();
        this.taskNotice = { tone: "success", text: "Task created with an accountable next step." };
      } catch (reason) { this.taskNotice = { tone: "error", text: readableError(reason, "Unable to create this task.") }; }
      finally { this.savingTask = false; }
    },
    async downloadExport(format) {
      this.dataNotice = null;
      try {
        const packageData = this.preview ? { schemaVersion: 1, exportedAt: new Date().toISOString(), scope: this.exportScope, organization: { id: "preview-org", name: "AOI Technologics" }, people: this.people, onboarding: [], tasks: [], crmOwnership: [], activity: [], audit: [] } : await exportAdministrationData(this.exportScope);
        const exported = await buildAdministrationExport(packageData, format);
        download(`aoi-administration-${this.exportScope}-${new Date().toISOString().slice(0, 10)}.${exported.extension}`, exported.mime, exported.content);
        this.dataNotice = { tone: "success", text: `${format.toUpperCase()} export prepared. Passwords and sessions were excluded.` };
      } catch (reason) { this.dataNotice = { tone: "error", text: readableError(reason, "Unable to export Administration data.") }; }
    },
    async previewImport(event) {
      this.dataNotice = null;
      this.importPreview = null;
      try {
        const file = event.target.files?.[0];
        if (!file) return;
        const extension = file.name.split(".").pop()?.toLowerCase();
        const format = extension === "markdown" ? "md" : extension;
        this.importPackage = await parseAdministrationImport(await file.text(), format);
        this.importPreview = this.preview
          ? { status: "previewed", counts: { people: this.importPackage.people?.length || 0, tasks: this.importPackage.tasks?.length || 0, crmOwnership: this.importPackage.crmOwnership?.length || 0 } }
          : await importAdministrationData(this.importPackage, "preview", null, this.importMode);
        if (this.importPreview?.canApply === false) this.dataNotice = { tone: "error", text: `${this.importPreview.conflicts?.length || 0} conflict(s) must be resolved before this package can be applied.` };
      } catch (reason) { this.dataNotice = { tone: "error", text: readableError(reason, "Unable to preview this import.") }; }
    },
    async commitImport() {
      this.importing = true;
      this.dataNotice = null;
      try {
        if (this.preview) throw new Error("Imports are disabled in preview mode.");
        if (!this.importPreview?.canApply) throw new Error("Resolve every preview conflict before applying this import.");
        const result = await importAdministrationData(this.importPackage, this.importMode, this.importPreview.jobId);
        this.dataNotice = { tone: "success", text: `Import completed: ${result.applied || 0} applied, ${result.skipped || 0} skipped.` };
        this.importPreview = null;
        await this.refresh();
      } catch (reason) { this.dataNotice = { tone: "error", text: readableError(reason, "Unable to apply this import.") }; }
      finally { this.importing = false; }
    },
    toggleTheme() { this.dark = !this.dark; localStorage.setItem("aoi-theme", this.dark ? "dark" : "light"); document.documentElement.dataset.theme = this.dark ? "dark" : "light"; },
    toggleLocale() { this.locale = this.locale === "en" ? "zh-CN" : "en"; localStorage.setItem("aoi-locale", this.locale); document.documentElement.lang = this.locale; },
    showToast(title, body) { this.toast = { title, body }; setTimeout(() => { this.toast = null; }, 4200); },
    async logout() { await signOut(); location.replace(this.loginUrl); },
  }));
}
