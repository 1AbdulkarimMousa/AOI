import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";
import { createClient } from "@supabase/supabase-js";

import { buildMikeOutreachSeedPlan, MIKE_OUTREACH_CONTACTS } from "./mike-outreach-seed-data.mjs";

if (existsSync(".env.local")) loadEnvFile(".env.local");

const supabaseUrl = process.env.VITE_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) throw new Error("Supabase URL and service-role key are required.");

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function required(data, error, label) {
  if (error) throw new Error(`${label}: ${error.message}`);
  if (!data) throw new Error(`${label}: no record returned`);
  return data;
}

const { data: organization, error: organizationError } = await supabase
  .from("organizations")
  .select("id")
  .eq("slug", "aoi-technologics")
  .single();
required(organization, organizationError, "Resolve AOI organization");

const { data: project, error: projectError } = await supabase
  .from("projects")
  .select("id,code")
  .eq("organization_id", organization.id)
  .eq("code", "AOI-PMF-01")
  .single();
required(project, projectError, "Resolve AOI PMF project");

const { data: owner, error: ownerError } = await supabase
  .from("profiles")
  .select("id,display_name,login_identifier")
  .eq("login_identifier", "mikerevou@aoitechnology.com")
  .single();
required(owner, ownerError, "Resolve Mike owner");

const { data: membership, error: membershipError } = await supabase
  .from("organization_memberships")
  .select("status")
  .eq("organization_id", organization.id)
  .eq("user_id", owner.id)
  .eq("status", "active")
  .single();
required(membership, membershipError, "Verify Mike membership");

const externalIds = MIKE_OUTREACH_CONTACTS.map((contact) => contact.externalId);
const { data: candidates, error: candidatesError } = await supabase
  .from("candidates")
  .select("id,external_id,name,source_url,priority_score,outreach_status,first_outreach,notes,crm_contact_id")
  .eq("project_id", project.id)
  .in("external_id", externalIds);
required(candidates, candidatesError, "Resolve Mike outreach candidates");

if (candidates.length !== MIKE_OUTREACH_CONTACTS.length) {
  throw new Error(`Expected ${MIKE_OUTREACH_CONTACTS.length} outreach candidates, found ${candidates.length}.`);
}

const candidatesByExternalId = Object.fromEntries(candidates.map((candidate) => [candidate.external_id, candidate]));
for (const contact of MIKE_OUTREACH_CONTACTS) {
  const candidate = candidatesByExternalId[contact.externalId];
  if (candidate?.name.toLowerCase() !== contact.handle.toLowerCase()) {
    throw new Error(`Candidate identity mismatch for external ID ${contact.externalId}.`);
  }
}

const plan = buildMikeOutreachSeedPlan({
  organizationId: organization.id,
  projectId: project.id,
  ownerId: owner.id,
  candidatesByExternalId,
});

const { error: contactsError } = await supabase
  .from("crm_contacts")
  .upsert(plan.crmContacts, { onConflict: "id" });
if (contactsError) throw new Error(`Upsert Mike CRM contacts: ${contactsError.message}`);

for (const update of plan.candidateUpdates) {
  const { error } = await supabase.from("candidates").update(update.values).eq("id", update.id);
  if (error) throw new Error(`Update ${update.handle}: ${error.message}`);
}

const { error: eventsError } = await supabase
  .from("outreach_events")
  .upsert(plan.outreachEvents, { onConflict: "id" });
if (eventsError) throw new Error(`Upsert Mike outreach events: ${eventsError.message}`);

const { error: activitiesError } = await supabase
  .from("crm_activity")
  .upsert(plan.crmActivities, { onConflict: "id" });
if (activitiesError) throw new Error(`Upsert Mike CRM activity: ${activitiesError.message}`);

const { data: executionItem, error: executionFindError } = await supabase
  .from("outreach_plan_items")
  .select("id,actual_first_touches")
  .eq("project_id", project.id)
  .eq("plan_date", plan.executionPlanUpdate.planDate)
  .single();
required(executionItem, executionFindError, "Resolve August 5 outreach plan");

const actualFirstTouches = Math.max(executionItem.actual_first_touches, plan.executionPlanUpdate.minimumFirstTouches);
const { error: executionUpdateError } = await supabase
  .from("outreach_plan_items")
  .update({ actual_first_touches: actualFirstTouches, updated_at: new Date().toISOString() })
  .eq("id", executionItem.id);
if (executionUpdateError) throw new Error(`Update August 5 outreach plan: ${executionUpdateError.message}`);

const eventIds = plan.outreachEvents.map((event) => event.id);
const crmActivityIds = plan.crmActivities.map((activity) => activity.id);
const [candidateCheck, eventCheck, contactCheck, activityCheck] = await Promise.all([
  supabase.from("candidates").select("external_id,outreach_status,contact_detail,assigned_to").eq("project_id", project.id).in("external_id", externalIds),
  supabase.from("outreach_events").select("id,status", { count: "exact" }).in("id", eventIds),
  supabase.from("crm_contacts").select("id", { count: "exact" }).in("id", plan.crmContacts.map((contact) => contact.id)),
  supabase.from("crm_activity").select("id", { count: "exact" }).in("id", crmActivityIds),
]);

if (candidateCheck.error || candidateCheck.data.length !== 9) throw new Error("Mike candidate verification failed.");
if (candidateCheck.data.some((candidate) => candidate.outreach_status !== "Sent" || candidate.assigned_to !== owner.id)) {
  throw new Error("Mike contacted-candidate verification failed.");
}
if (eventCheck.error || eventCheck.count !== 22 || eventCheck.data.some((event) => event.status !== "Sent")) throw new Error("Mike outreach-event verification failed.");
if (contactCheck.error || contactCheck.count !== 9) throw new Error("Mike CRM-contact verification failed.");
if (activityCheck.error || activityCheck.count !== 9) throw new Error("Mike CRM-activity verification failed.");

console.log(JSON.stringify({
  project: project.code,
  owner: owner.display_name,
  candidatesUpdated: candidateCheck.data.length,
  candidatesContacted: 9,
  outreachEvents: eventCheck.count,
  crmContacts: contactCheck.count,
  crmActivities: activityCheck.count,
  executionPlanActualFirstTouches: actualFirstTouches,
}, null, 2));
