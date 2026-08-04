const REQUIRED_CONTACT_FIELDS = ["name", "contactType", "primaryChannel", "sourceUrl", "nextAction", "nextActionDue"];

export const CRM_LIFECYCLES = ["new", "researching", "ready", "contacted", "engaged", "qualified", "paused"];

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

export function buildTodayQueue(contacts = [], today = new Date().toISOString().slice(0, 10)) {
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
