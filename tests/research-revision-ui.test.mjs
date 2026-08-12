import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { hydrateResearchRevisionForm } from "../src/js/collect.js";

const root = new URL("../", import.meta.url);

test("hydrates each editable research detail into a new form without leaking record metadata", () => {
  const fixtures = {
    respondent: {
      defaults: { externalId: "", segmentCode: "families", contactName: "", interviewAllowed: false, notes: "" },
      detail: { record: { external_id: "R-42", segmentCode: "orthodontic", notes: "Context", id: "record-1" }, contact: { contact_name: "Ada" }, consentHistory: [{ interview_allowed: true }] },
      expected: { externalId: "R-42", segmentCode: "orthodontic", contactName: "Ada", interviewAllowed: true, notes: "Context" },
    },
    session: {
      defaults: { respondentId: "", method: "", currentBehavior: "", limitations: "" },
      detail: { record: { respondent_id: "respondent-1", method: "Interview", current_behavior: "Calls the clinic", limitations: "One interview" } },
      expected: { respondentId: "respondent-1", method: "Interview", currentBehavior: "Calls the clinic", limitations: "One interview" },
    },
    evidence: {
      defaults: { respondentId: "", evidenceType: "Interview", title: "", followUpNeeded: false },
      detail: { record: { respondent_id: "respondent-1", evidence_type: "Observation", title: "Finding", follow_up_needed: true } },
      expected: { respondentId: "respondent-1", evidenceType: "Observation", title: "Finding", followUpNeeded: true },
    },
    product_event: {
      defaults: { respondentId: "", eventDate: "", captureSuccess: "", mainFriction: "" },
      detail: { record: { respondent_id: "respondent-1", event_date: "2026-08-10", capture_success: false, main_friction: "Lighting" } },
      expected: { respondentId: "respondent-1", eventDate: "2026-08-10", captureSuccess: "false", mainFriction: "Lighting" },
    },
    value_exchange: {
      defaults: { respondentId: "", hardwarePrice: 259, purchaseIntent: 3, mainObjection: "" },
      detail: { record: { respondent_id: "respondent-1", hardware_price: 199, purchase_intent: 5, main_objection: "Subscription" } },
      expected: { respondentId: "respondent-1", hardwarePrice: 199, purchaseIntent: 5, mainObjection: "Subscription" },
    },
    observation: {
      defaults: { definitionId: "", segmentCode: "families", booleanValue: "", sourceLink: "" },
      detail: { record: { definition_id: "metric-1", segmentCode: "orthodontic", boolean_value: true, source_link: "https://example.com/source" } },
      expected: { definitionId: "metric-1", segmentCode: "orthodontic", booleanValue: "true", sourceLink: "https://example.com/source" },
    },
  };

  for (const [recordType, fixture] of Object.entries(fixtures)) {
    const before = structuredClone(fixture.detail);
    assert.deepEqual(hydrateResearchRevisionForm(recordType, fixture.defaults, fixture.detail), fixture.expected, recordType);
    assert.deepEqual(fixture.detail, before, `${recordType} detail remains unchanged`);
  }
});

test("wires assigned draft editing through optimistic update while retaining insert for new records", async () => {
  const [api, workspace, template] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/pmf-template.js", root), "utf8"),
  ]);

  assert.match(api, /updateResearchRecord\(recordType, recordId, payload, expectedUpdatedAt, action\)[\s\S]*rpc\("rpc_aoi_update_research_record"[\s\S]*p_expected_updated_at: expectedUpdatedAt[\s\S]*p_action: action/);
  assert.match(api, /reviewResearchRecord\(recordType, recordId, action, notes = "", expectedUpdatedAt = null\)[\s\S]*p_expected_updated_at: expectedUpdatedAt/);
  assert.match(workspace, /persistResearchReview\(record\.recordType, record\.id, action, this\.reviewNotes\[record\.id\] \|\| "", record\.updatedAt\)/);
  assert.match(workspace, /researchEditState:\s*null/);
  assert.match(workspace, /canEditSelectedCollectRecord[\s\S]*\["draft",\s*"revision_requested"\]/);
  assert.match(workspace, /startResearchRevision\(\)[\s\S]*hydrateResearchRevisionForm/);
  assert.match(workspace, /recordId:\s*this\.selectedCollectRecord\.id[\s\S]*expectedUpdatedAt:/);
  assert.match(workspace, /persistResearchUpdate\([\s\S]*this\.researchEditState\.expectedUpdatedAt[\s\S]*action/);
  assert.match(workspace, /persistResearchRecord\(recordType, \{ \.\.\.payload, workflowStatus \}\)/);
  assert.match(workspace, /RESEARCH_STALE_WRITE[\s\S]*changed in another session/);
  assert.match(workspace, /resetResearchEditState\(\)[\s\S]*researchEditState\s*=\s*null/);
  assert.match(workspace, /editState:\s*this\.researchEditState/);
  assert.match(workspace, /this\.researchEditState\s*=\s*fresh[\s\S]*stored\.editState/);
  assert.match(template, /canEditSelectedCollectRecord[\s\S]*Edit record/);
  assert.match(template, /researchEditState\?\.reviewNotes[\s\S]*Revision guidance/);
  assert.match(template, /researchEditState\?\.workflowStatus==='revision_requested'[\s\S]*Resubmit for review/);
});
