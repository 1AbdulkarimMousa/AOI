import { localDateValue } from "./core.js";

const REQUIRED_CONTACT_FIELDS = ["name", "contactType", "primaryChannel", "sourceUrl", "nextAction", "nextActionDue"];
const OUTREACH_SECTIONS = new Set(["pipeline", "evidence", "imports"]);
const LEGACY_OUTREACH_VIEWS = { outreach: "pipeline", evidence: "evidence", imports: "imports" };
const LEGACY_WORKSPACE_VIEWS = { research: "collect", pmf: "analyze", "daily-eod": "eod", "end-of-day": "eod" };

export const CRM_LIFECYCLES = ["new", "researching", "ready", "contacted", "engaged", "qualified", "paused"];

export function resolveCrmWorkspaceRoute({ view, tab, section, defaultView } = {}) {
  if (LEGACY_OUTREACH_VIEWS[view]) {
    return {
      view: "crm",
      crmTab: "outreach",
      outreachSection: LEGACY_OUTREACH_VIEWS[view],
      normalize: true,
    };
  }

  const requestedView = view || defaultView;
  const resolvedView = LEGACY_WORKSPACE_VIEWS[requestedView] || requestedView;
  const crmTab = resolvedView === "crm" && ["recruitment", "outreach"].includes(tab) ? tab : "contacts";
  const hasValidOutreachSection = OUTREACH_SECTIONS.has(section);
  const hasNonCanonicalTab = resolvedView === "crm" && Boolean(tab) && !["recruitment", "outreach"].includes(tab);
  const hasNonCanonicalSection = resolvedView === "crm"
    ? (crmTab === "outreach" ? !hasValidOutreachSection : Boolean(section))
    : Boolean(tab || section);
  return {
    view: resolvedView,
    crmTab,
    outreachSection: crmTab === "outreach" && hasValidOutreachSection ? section : "pipeline",
    normalize: Boolean(LEGACY_WORKSPACE_VIEWS[requestedView]) || hasNonCanonicalTab || hasNonCanonicalSection,
  };
}

export function createContactDraft(ownerName = "") {
  return {
    name: "",
    contactType: "KOL",
    organization: "",
    email: "",
    phone: "",
    primaryChannel: "Email",
    sourceUrl: "",
    tags: "",
    ownerName,
    lifecycle: "new",
    nextAction: "",
    nextActionDue: "",
    notes: "",
  };
}

export function contactCompleteness(contact = {}) {
  const complete = REQUIRED_CONTACT_FIELDS.filter((field) => String(contact[field] || "").trim()).length;
  return Math.round((complete / REQUIRED_CONTACT_FIELDS.length) * 100);
}

export function buildTodayQueue(contacts = [], today = localDateValue()) {
  return contacts
    .filter((contact) => contact.lifecycle !== "paused")
    .map((contact) => {
      const completeness = contact.completeness ?? contactCompleteness(contact);
      const due = contact.nextActionDue || "9999-12-31";
      const overdue = due < today;
      const dueToday = due === today;
      const queueReason = overdue ? "Overdue" : dueToday ? "Due today" : completeness < 100 ? "Needs enrichment" : "Up next";
      return { ...contact, completeness, queueReason, queueRank: overdue ? 0 : dueToday ? 1 : completeness < 100 ? 2 : 3 };
    })
    .sort((a, b) => a.queueRank - b.queueRank || (a.nextActionDue || "9999-12-31").localeCompare(b.nextActionDue || "9999-12-31") || (b.priorityScore || 0) - (a.priorityScore || 0));
}

export function rewardForAction(action, completeness = 0) {
  const base = { enrich: 35, outreach: 45, follow_up: 55, qualify: 70 }[action] || 20;
  return base + (Number(completeness) >= 100 ? 10 : 0);
}
