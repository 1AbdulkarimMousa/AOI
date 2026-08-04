import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAdministrationExport,
  createPersonDraft,
  filterAdministrationPeople,
  parseAdministrationImport,
} from "../src/js/administration-data.js";

const packageData = {
  schemaVersion: 1,
  exportedAt: "2026-08-04T12:00:00.000Z",
  organization: { id: "org-1", name: "AOI" },
  people: [
    {
      userId: "user-1",
      displayName: "Lina Chen",
      loginIdentifier: "lina@example.com",
      role: "intern",
      membershipStatus: "active",
      locale: "zh-CN",
      skills: ["Research", "CRM"],
    },
  ],
  tasks: [{ id: "task-1", title: "Interview synthesis", assignedTo: "user-1" }],
  crmOwnership: [{ id: "contact-1", ownerId: "user-1", name: "Dr. Lee" }],
  activity: [{ id: "activity-1", actorId: "user-1", action: "follow_up" }],
  audit: [{ id: "audit-1", actorId: "user-1", action: "profile_updated" }],
};

test("creates a secure operational person draft", () => {
  assert.deepEqual(createPersonDraft(), {
    displayName: "",
    email: "",
    role: "intern",
    accessMethod: "invite",
    locale: "en",
    timezone: "America/New_York",
    phone: "",
    managerId: "",
    skills: "",
    availability: "",
    startDate: "",
    notes: "",
  });
});

test("filters people by query, role, and lifecycle status", () => {
  const people = [
    { displayName: "Lina Chen", loginIdentifier: "lina@example.com", role: "intern", membershipStatus: "active", skills: ["CRM"] },
    { displayName: "Alex Morgan", loginIdentifier: "alex@example.com", role: "admin", membershipStatus: "archived", skills: ["Operations"] },
  ];

  assert.deepEqual(filterAdministrationPeople(people, { query: "crm", role: "intern", status: "active" }).map((person) => person.displayName), ["Lina Chen"]);
  assert.deepEqual(filterAdministrationPeople(people, { query: "alex", role: "all", status: "archived" }).map((person) => person.displayName), ["Alex Morgan"]);
});

test("round-trips a full administration package through JSON", async () => {
  const exported = await buildAdministrationExport(packageData, "json");
  assert.equal(exported.extension, "json");
  assert.deepEqual(await parseAdministrationImport(exported.content, "json"), packageData);
});

test("round-trips a full administration package through formula-safe CSV", async () => {
  const input = structuredClone(packageData);
  input.people[0].displayName = "=IMPORTXML('bad')";
  const exported = await buildAdministrationExport(input, "csv");

  assert.equal(exported.extension, "csv");
  assert.match(exported.content, /^\uFEFFrecord_type,record_id,payload_json/m);
  assert.doesNotMatch(exported.content, /,"=IMPORTXML/);
  assert.deepEqual(await parseAdministrationImport(exported.content, "csv"), input);
});

test("round-trips a readable structured Markdown administration archive", async () => {
  const input = structuredClone(packageData);
  input.people[0].notes = "Use a fenced example:\n```json\n{}\n```";
  const exported = await buildAdministrationExport(input, "md");

  assert.equal(exported.extension, "md");
  assert.match(exported.content, /# AOI Administration Archive/);
  assert.match(exported.content, /\| Lina Chen \| Intern \| Active \|/);
  assert.match(exported.content, /aoi-administration-base64/);
  assert.deepEqual(await parseAdministrationImport(exported.content, "md"), input);
});

test("rejects unsupported or malformed administration imports", async () => {
  await assert.rejects(() => parseAdministrationImport("not-json", "json"), /valid JSON/i);
  await assert.rejects(() => parseAdministrationImport("# arbitrary notes", "md"), /generated AOI administration/i);
  await assert.rejects(() => parseAdministrationImport("x", "xml"), /unsupported/i);
});
