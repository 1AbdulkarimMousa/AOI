const MIKE_OUTREACH_DATE = "2026-08-05";

export const MIKE_OUTREACH_CONTACTS = Object.freeze([
  {
    externalId: "12",
    handle: "@dentist_emi",
    emails: ["dentist_emi@outlook.com"],
    phone: null,
    outreachChannels: ["Instagram", "Email"],
  },
  {
    externalId: "13",
    handle: "@dryazdan",
    emails: ["doctoryazdan@gmail.com", "info@dryazdan.com"],
    phone: "949.644-6988",
    outreachChannels: ["Facebook", "Instagram", "Email", "Phone Call"],
  },
  {
    externalId: "14",
    handle: "@fitlittlehygienist",
    emails: ["Fitlittlehygienist@gmail.com"],
    phone: null,
    outreachChannels: ["Instagram", "Email"],
  },
  {
    externalId: "15",
    handle: "@justflossit",
    emails: ["jasminecapra@yahoo.com"],
    phone: null,
    outreachChannels: ["Email", "Instagram"],
  },
  {
    externalId: "16",
    handle: "@drashleyizadi",
    emails: ["dr.roham@valleydentalhealth.com"],
    phone: "+14106661178",
    outreachChannels: ["Instagram"],
  },
  {
    externalId: "17",
    handle: "@smilewithcallie",
    emails: ["rdhcallie@gmail.com"],
    phone: null,
    outreachChannels: ["Email", "Instagram"],
  },
  {
    externalId: "18",
    handle: "@iamdr_a",
    emails: ["info@smileddstudio.com"],
    phone: "+1 212-223-7946",
    outreachChannels: ["Email", "Instagram", "Facebook", "Phone Call"],
  },
  {
    externalId: "19",
    handle: "@jerry_rdh",
    emails: ["JerryRDH@gmail.com", "dentistryhumor@gmail.com"],
    phone: null,
    outreachChannels: ["Instagram", "Facebook", "Email"],
  },
  {
    externalId: "20",
    handle: "@pediatric.dentist.mom",
    emails: ["hello@yourfirstgrin.com"],
    phone: null,
    outreachChannels: ["Instagram", "Email"],
  },
]);

function stableId(prefix, contactIndex, channelIndex = 0) {
  const suffix = String((contactIndex + 1) * 100 + channelIndex + 1).padStart(12, "0");
  return `${prefix}-0000-4000-8000-${suffix}`;
}

function contactDetail(contact) {
  return [...contact.emails, contact.phone].filter(Boolean).join("; ");
}

function appendSeedNote(existingNotes, seedNote) {
  const marker = `[Mike outreach seed ${MIKE_OUTREACH_DATE}]`;
  const markedNote = `${marker} ${seedNote}`;
  if (!existingNotes) return markedNote;
  if (!existingNotes.includes(marker)) return `${existingNotes}\n${markedNote}`;
  return existingNotes.split("\n").map((line) => line.startsWith(marker) ? markedNote : line).join("\n");
}

export function buildMikeOutreachSeedPlan({ organizationId, projectId, ownerId, candidatesByExternalId }) {
  const candidateUpdates = [];
  const crmContacts = [];
  const crmActivities = [];
  const outreachEvents = [];

  MIKE_OUTREACH_CONTACTS.forEach((contact, contactIndex) => {
    const candidate = candidatesByExternalId[contact.externalId];
    if (!candidate) throw new Error(`Missing outreach candidate ${contact.externalId} (${contact.handle})`);

    const reached = contact.outreachChannels.length > 0;
    const channels = reached ? contact.outreachChannels.join(" + ") : "Email + Phone";
    const details = contactDetail(contact);
    const nextAction = reached
      ? `Follow up if no response by 2026-08-10 via ${contact.outreachChannels.join(", ")}`
      : "Personalize and send the first outreach using the verified email or phone number";
    const nextActionDue = reached ? "2026-08-10" : "2026-08-06";
    const seedNote = reached
      ? `Initial outreach reported via ${contact.outreachChannels.join(", ")}. Exact outreach times were not provided. Contact details: ${details}.`
      : `Contact details were supplied, but no completed outreach channel was reported. Contact details: ${details}.`;
    const crmContactId = candidate.crm_contact_id || stableId("63000000", contactIndex);
    const updateValues = {
      crm_contact_id: crmContactId,
      owner_id: ownerId,
      assigned_to: ownerId,
      contact_readiness: "Email ready",
      contact_channel: channels,
      contact_detail: details,
      source_updated_on: MIKE_OUTREACH_DATE,
      next_step: nextAction,
      next_step_due: nextActionDue,
      notes: appendSeedNote(candidate.notes, seedNote),
    };

    if (reached) {
      updateValues.outreach_status = "Sent";
      updateValues.first_outreach = candidate.first_outreach || MIKE_OUTREACH_DATE;
    }

    candidateUpdates.push({ id: candidate.id, externalId: contact.externalId, handle: contact.handle, values: updateValues });
    crmContacts.push({
      id: crmContactId,
      organization_id: organizationId,
      project_id: projectId,
      contact_type: "Dental Professional",
      name: contact.handle,
      email: contact.emails[0],
      phone: contact.phone,
      primary_channel: channels,
      source_url: candidate.source_url,
      tags: "dental-kol,mike-outreach",
      owner_id: ownerId,
      lifecycle: reached ? "contacted" : "ready",
      next_action: nextAction,
      next_action_due: nextActionDue,
      priority_score: candidate.priority_score,
      notes: seedNote,
      created_by: ownerId,
    });
    crmActivities.push({
      id: stableId("64000000", contactIndex),
      organization_id: organizationId,
      project_id: projectId,
      contact_id: crmContactId,
      actor_id: ownerId,
      activity_type: reached ? "outreach" : "enrich",
      summary: reached
        ? `Initial outreach sent via ${contact.outreachChannels.join(", ")} on ${MIKE_OUTREACH_DATE}; exact times not provided.`
        : `Verified email and phone added on ${MIKE_OUTREACH_DATE}; no completed outreach reported.`,
      created_at: `${MIKE_OUTREACH_DATE}T00:00:00.000Z`,
    });

    contact.outreachChannels.forEach((channel, channelIndex) => {
      outreachEvents.push({
        id: stableId("61000000", contactIndex, channelIndex),
        organization_id: organizationId,
        project_id: projectId,
        candidate_id: candidate.id,
        channel,
        kind: "Initial",
        status: "Sent",
        occurred_at: `${MIKE_OUTREACH_DATE}T00:00:00.000Z`,
        actor_id: ownerId,
        summary: `Initial outreach sent via ${channel} on ${MIKE_OUTREACH_DATE}; exact time not provided.`,
      });
    });
  });

  return {
    candidateUpdates,
    crmContacts,
    crmActivities,
    outreachEvents,
    executionPlanUpdate: { planDate: MIKE_OUTREACH_DATE, minimumFirstTouches: 9 },
  };
}
