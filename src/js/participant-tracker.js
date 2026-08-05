import "../css/participant-tracker.css";

import { loadParticipantTracker, saveParticipantRecruitment } from "./api.js";
import { getExistingWorkspaceAccess, signOut } from "./auth.js";
import { initials, pageUrl, readableError, routeForRole } from "./core.js";

const STATUS_OPTIONS = ["new", "contacted", "responded", "screening", "scheduled", "completed", "declined", "no_response"];

function blankForm(ownerId = "") {
  return {
    id: "",
    participantId: "",
    name: "",
    email: "",
    phone: "",
    source: "Facebook",
    timeZone: "",
    status: "new",
    segment: "",
    consentStatus: "pending",
    ownerId,
    nextAction: "Confirm eligibility, timezone, and interview availability",
    nextActionDue: "2026-08-06",
    interviewDate: "",
    qualificationNotes: "",
    notes: "",
    crmContactId: "",
    respondentId: "",
  };
}

export function registerParticipantTracker(Alpine) {
  Alpine.data("participantTrackerPage", () => ({
    access: null,
    embedded: false,
    ready: false,
    loading: true,
    saving: false,
    error: "",
    notice: null,
    items: [],
    query: "",
    filter: "all",
    selected: null,
    editorOpen: false,
    form: blankForm(),
    trackerUrl: pageUrl(import.meta.env.BASE_URL, "Participant_Recruitment_Tracker.html"),
    crmUrl: pageUrl(import.meta.env.BASE_URL, "workspace.html?view=crm"),
    loginUrl: pageUrl(import.meta.env.BASE_URL, "login.html"),
    statusOptions: STATUS_OPTIONS,

    async init() {
      try {
        const access = await getExistingWorkspaceAccess();
        if (!access) {
          location.replace(this.loginUrl);
          return;
        }
        this.access = access;
        await this.refresh();
        this.ready = true;
      } catch (reason) {
        this.error = readableError(reason, "Unable to open the participant tracker.");
        this.ready = true;
      } finally {
        this.loading = false;
      }
    },
    async refresh() {
      const snapshot = await loadParticipantTracker();
      this.items = snapshot?.items || [];
    },
    async logout() {
      await signOut();
      location.replace(this.loginUrl);
    },
    initials,
    formatDate(value) {
      if (!value) return "Not scheduled";
      const date = new Date(`${value}T12:00:00`);
      return Number.isNaN(date.getTime()) ? "Invalid date" : new Intl.DateTimeFormat(this.access?.locale || "en", { month: "short", day: "numeric", year: "numeric" }).format(date);
    },
    statusLabel(value) {
      return String(value || "new").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
    },
    get filteredItems() {
      const query = this.query.trim().toLowerCase();
      return this.items.filter((item) => {
        const matchesQuery = !query || [item.participantId, item.name, item.email, item.source, item.segment, item.status].some((value) => String(value || "").toLowerCase().includes(query));
        const matchesFilter = this.filter === "all" || item.status === this.filter;
        return matchesQuery && matchesFilter;
      });
    },
    count(status) {
      return this.items.filter((item) => item.status === status).length;
    },
    openNew() {
      this.selected = null;
      this.form = blankForm(this.access?.userId || "");
      this.notice = null;
      this.editorOpen = true;
    },
    openEdit(item) {
      this.selected = item;
      this.form = { ...blankForm(this.access?.userId || ""), ...item, interviewDate: item.interviewDate || "", crmContactId: item.crmContactId || "", respondentId: item.respondentId || "" };
      this.notice = null;
      this.editorOpen = true;
    },
    closeEditor() {
      this.selected = null;
      this.notice = null;
      this.editorOpen = false;
    },
    openCrm(item) {
      if (!item.crmContactId) return;
      location.href = `${pageUrl(import.meta.env.BASE_URL, "workspace.html")}?view=crm&contact=${encodeURIComponent(item.crmContactId)}`;
    },
    async save() {
      if (!this.form.participantId.trim() || !this.form.name.trim()) {
        this.notice = { tone: "error", text: "Participant ID and name are required." };
        return;
      }
      this.saving = true;
      this.notice = null;
      try {
        await saveParticipantRecruitment(this.form);
        await this.refresh();
        this.closeEditor();
        this.notice = { tone: "success", text: "Recruitment record saved." };
      } catch (reason) {
        this.notice = { tone: "error", text: readableError(reason, "Unable to save the recruitment record.") };
      } finally {
        this.saving = false;
      }
    },
    async quickStatus(item, status) {
      try {
        await saveParticipantRecruitment({ ...item, status });
        await this.refresh();
        this.notice = { tone: "success", text: `${item.name} moved to ${this.statusLabel(status)}.` };
      } catch (reason) {
        this.notice = { tone: "error", text: readableError(reason, "Unable to update the recruitment stage.") };
      }
    },
    routeForRole,
  }));
}
