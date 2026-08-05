import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";
import { createClient } from "@supabase/supabase-js";

import { buildParticipantSeedPlan, PARTICIPANT_PROSPECTS } from "./participant-seed-data.mjs";

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

async function countRows(table, column = "id") {
  const { count, error } = await supabase.from(table).select(column, { count: "exact", head: true });
  if (error) throw new Error(`Count ${table}: ${error.message}`);
  return count ?? 0;
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
  .select("id,display_name")
  .eq("login_identifier", "wxt116@gmail.com")
  .single();
required(owner, ownerError, "Resolve Wen owner");

const protectedBefore = await Promise.all([
  countRows("respondents"),
  countRows("research_sessions"),
  countRows("evidence_records"),
]);

const plan = buildParticipantSeedPlan({ organizationId: organization.id, projectId: project.id, ownerId: owner.id });
const rows = [];
for (let index = 0; index < PARTICIPANT_PROSPECTS.length; index += 1) {
  const prospect = PARTICIPANT_PROSPECTS[index];
  const row = plan.prospects[index];
  const crmContactId = `52000000-0000-4000-8000-00000000000${index + 1}`;
  const { error: contactError } = await supabase.from("crm_contacts").upsert({
    id: crmContactId,
    organization_id: organization.id,
    project_id: project.id,
    contact_type: "Consumer Prospect",
    name: prospect.name,
    email: prospect.email,
    phone: prospect.phone || null,
    primary_channel: prospect.source,
    tags: "consumer-recruitment,facebook,unscreened",
    owner_id: owner.id,
    lifecycle: "new",
    next_action: row.next_action,
    next_action_due: row.next_action_due,
    priority_score: 70,
    notes: row.qualification_notes,
    created_by: owner.id,
    updated_at: new Date().toISOString(),
  }, { onConflict: "id" });
  if (contactError) throw new Error(`Upsert CRM contact ${prospect.name}: ${contactError.message}`);

  const { data: existingActivity, error: activityFindError } = await supabase
    .from("crm_activity")
    .select("id")
    .eq("contact_id", crmContactId)
    .eq("activity_type", "import")
    .eq("summary", "Imported from Participant Recruitment Tracker")
    .limit(1);
  if (activityFindError) throw new Error(`Find CRM import activity ${prospect.name}: ${activityFindError.message}`);
  if (!existingActivity.length) {
    const { error: activityError } = await supabase.from("crm_activity").insert({
      organization_id: organization.id,
      project_id: project.id,
      contact_id: crmContactId,
      actor_id: owner.id,
      activity_type: "import",
      summary: "Imported from Participant Recruitment Tracker",
    });
    if (activityError) throw new Error(`Create CRM import activity ${prospect.name}: ${activityError.message}`);
  }

  rows.push({ ...row, crm_contact_id: crmContactId });
}

const { data: prospects, error: prospectsError } = await supabase
  .from("participant_recruitment")
  .upsert(rows, { onConflict: "id" })
  .select("id,participant_id,full_name,status,owner_id,crm_contact_id,respondent_id");
required(prospects, prospectsError, "Upsert participant prospects");

const protectedAfter = await Promise.all([
  countRows("respondents"),
  countRows("research_sessions"),
  countRows("evidence_records"),
]);
if (protectedBefore.some((count, index) => count !== protectedAfter[index])) throw new Error("Participant seed changed research evidence unexpectedly.");
if (prospects.length !== rows.length || prospects.some((prospect) => prospect.respondent_id !== null)) throw new Error("Participant prospect verification failed.");

console.log(JSON.stringify({
  project: project.code,
  owner: owner.display_name,
  prospects: prospects.length,
  crmLinked: prospects.filter((prospect) => prospect.crm_contact_id).length,
  respondentsCreated: 0,
  evidenceCreated: 0,
}, null, 2));
