import { localDateValue } from "./core.js";

const REQUIRED_CONTACT_FIELDS = ["name", "contactType", "primaryChannel", "sourceUrl", "nextAction", "nextActionDue"];
const OUTREACH_SECTIONS = new Set(["pipeline", "evidence", "imports"]);
const TODAY_TABS = new Set(["briefing", "tasks", "relationships", "momentum"]);
const RELATIONSHIP_TABS = new Set(["contacts", "recruitment", "outreach"]);
const RESEARCH_TABS = new Set(["collect", "surveys", "analyze", "reports"]);
const PROJECT_TABS = new Set(["overview", "milestones", "blockers", "risks", "decisions"]);
const PROJECT_RECORD_PARAMS = { milestones: "milestone", blockers: "blocker", risks: "risk", decisions: "decision" };
const ADMINISTRATION_TABS = new Set(["overview", "people", "work", "data", "archive", "guides"]);
const PRIMARY_VIEWS = new Set(["today", "relationships", "research", "projects", "eod", "chat", "help-center", "administration"]);
const LEGACY_TODAY_VIEWS = { overview: "briefing", work: "tasks", team: "momentum" };
const LEGACY_OUTREACH_VIEWS = { outreach: "pipeline", evidence: "evidence", imports: "imports" };
const LEGACY_RESEARCH_VIEWS = { collect: "collect", surveys: "surveys", analyze: "analyze", reports: "reports", pmf: "analyze" };
const LEGACY_WORKSPACE_VIEWS = { crm: "relationships", "daily-eod": "eod", "end-of-day": "eod", help: "help-center", helpcenter: "help-center", admin: "administration" };

export function nextTabFromKey(tabs, currentTab, key) {
  const currentIndex = tabs.indexOf(currentTab);
  if (currentIndex < 0 || !tabs.length) return null;
  if (key === "Home") return tabs[0];
  if (key === "End") return tabs.at(-1);
  if (key === "ArrowRight") return tabs[(currentIndex + 1) % tabs.length];
  if (key === "ArrowLeft") return tabs[(currentIndex - 1 + tabs.length) % tabs.length];
  return null;
}

export function resolveWorkspaceRoute({ view, tab, section, project, milestone, blocker, risk, decision, defaultView = "today", defaultTodayTab = "briefing" } = {}) {
  const defaults = {
    todayTab: TODAY_TABS.has(defaultTodayTab) ? defaultTodayTab : "briefing",
    relationshipsTab: "contacts",
    outreachSection: "pipeline",
    researchTab: "collect",
    projectTab: "overview",
    projectId: null,
    projectRecordType: null,
    projectRecordId: null,
  };

  if (LEGACY_TODAY_VIEWS[view]) {
    return { view: "today", ...defaults, todayTab: LEGACY_TODAY_VIEWS[view], normalize: true };
  }

  if (LEGACY_OUTREACH_VIEWS[view]) {
    const outreachSection = view === "outreach" && OUTREACH_SECTIONS.has(section) ? section : LEGACY_OUTREACH_VIEWS[view];
    return {
      view: "relationships",
      ...defaults,
      relationshipsTab: "outreach",
      outreachSection,
      normalize: true,
    };
  }

  if (LEGACY_RESEARCH_VIEWS[view]) {
    return { view: "research", ...defaults, researchTab: LEGACY_RESEARCH_VIEWS[view], normalize: true };
  }

  const requestedView = view || defaultView;
  let resolvedView = LEGACY_WORKSPACE_VIEWS[requestedView] || requestedView;
  let normalize = !view || Boolean(LEGACY_WORKSPACE_VIEWS[requestedView]);
  if (!PRIMARY_VIEWS.has(resolvedView)) {
    resolvedView = PRIMARY_VIEWS.has(defaultView) ? defaultView : "today";
    normalize = true;
  }

  if (resolvedView === "today") {
    const todayTab = TODAY_TABS.has(tab) ? tab : defaults.todayTab;
    return { view: resolvedView, ...defaults, todayTab, normalize: normalize || tab !== todayTab || Boolean(section) };
  }

  if (resolvedView === "relationships") {
    const relationshipsTab = RELATIONSHIP_TABS.has(tab) ? tab : defaults.relationshipsTab;
    const outreachSection = relationshipsTab === "outreach" && OUTREACH_SECTIONS.has(section) ? section : defaults.outreachSection;
    const invalidSection = relationshipsTab === "outreach" ? section !== outreachSection : Boolean(section);
    return { view: resolvedView, ...defaults, relationshipsTab, outreachSection, normalize: normalize || tab !== relationshipsTab || invalidSection };
  }

  if (resolvedView === "research") {
    const researchTab = RESEARCH_TABS.has(tab) ? tab : defaults.researchTab;
    return { view: resolvedView, ...defaults, researchTab, normalize: normalize || tab !== researchTab || Boolean(section) };
  }

  if (resolvedView === "projects") {
    const projectTab = PROJECT_TABS.has(tab) ? tab : defaults.projectTab;
    const projectRecordType = PROJECT_RECORD_PARAMS[projectTab] || null;
    const values = { milestone, blocker, risk, decision };
    const projectRecordId = projectRecordType ? values[projectRecordType] || null : null;
    const recordCount = Object.values(values).filter(Boolean).length;
    const invalidRecords = recordCount > (projectRecordId ? 1 : 0);
    return {
      view: resolvedView,
      ...defaults,
      projectTab,
      projectId: project || null,
      projectRecordType,
      projectRecordId: invalidRecords ? null : projectRecordId,
      normalize: normalize || tab !== projectTab || invalidRecords || (!projectRecordType && recordCount > 0) || Boolean(section),
    };
  }

  if (resolvedView === "administration") {
    const supportTab = ADMINISTRATION_TABS.has(tab) ? tab : "overview";
    return { view: resolvedView, ...defaults, supportTab, normalize: normalize || (tab && tab !== supportTab) || Boolean(section) };
  }

  return { view: resolvedView, ...defaults, normalize: normalize || Boolean(tab || section) };
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
    createOutreach: false,
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
