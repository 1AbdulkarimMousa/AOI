import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";
import { createClient } from "@supabase/supabase-js";

import { buildInternSeedPlan, WEN_ACCOUNT } from "./intern-seed-data.mjs";

if (existsSync(".env.local")) loadEnvFile(".env.local");

const supabaseUrl = process.env.VITE_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const bootstrapPassword = process.env.AOI_BOOTSTRAP_PASSWORD ?? "";
const resetAllPasswords = process.env.AOI_RESET_ALL_PASSWORDS === "1";

if (!supabaseUrl || !serviceRoleKey) throw new Error("Supabase URL and service-role key are required.");
if (!resetAllPasswords) throw new Error("Set AOI_RESET_ALL_PASSWORDS=1 to acknowledge the organization-wide password reset.");
if (!bootstrapPassword || bootstrapPassword.length < 14 || !/[A-Z]/.test(bootstrapPassword) || !/[a-z]/.test(bootstrapPassword) || !/[0-9]/.test(bootstrapPassword) || !/[^A-Za-z0-9]/.test(bootstrapPassword)) {
  throw new Error("Set AOI_BOOTSTRAP_PASSWORD to a strong value (at least 14 characters with mixed case, digit, and symbol).");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function required(data, error, label) {
  if (error) throw new Error(`${label}: ${error.message}`);
  if (!data) throw new Error(`${label}: no record returned`);
  return data;
}

async function findAuthUser(email) {
  for (let page = 1; ; page += 1) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw new Error(`List Auth users: ${error.message}`);
    const user = data.users.find((item) => item.email?.toLowerCase() === email);
    if (user) return user;
    if (data.users.length < 100) return null;
  }
}

async function resetAuthPassword(userId) {
  const { data, error } = await supabase.auth.admin.updateUserById(userId, {
    password: bootstrapPassword,
    ban_duration: "none",
  });
  return required(data?.user, error, `Reset Auth password for ${userId}`);
}

async function countRows(table, column = "id") {
  const { count, error } = await supabase.from(table).select(column, { count: "exact", head: true });
  if (error) throw new Error(`Count ${table}: ${error.message}`);
  return count ?? 0;
}

const { data: organization, error: organizationError } = await supabase
  .from("organizations")
  .select("id,slug")
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

const protectedTables = [["respondents", "id"], ["respondent_contacts", "respondent_id"], ["research_sessions", "id"], ["evidence_records", "id"]];
const protectedCounts = await Promise.all(protectedTables.map(([table, column]) => countRows(table, column)));
let authUser = await findAuthUser(WEN_ACCOUNT.email);
let accountCreated = false;
if (!authUser) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: WEN_ACCOUNT.email,
    password: bootstrapPassword,
    email_confirm: true,
    user_metadata: { display_name: WEN_ACCOUNT.displayName },
  });
  authUser = required(data?.user, error, "Create Wen Auth user");
  accountCreated = true;
}

const seededAt = new Date().toISOString();
const { error: profileError } = await supabase.from("profiles").upsert({
  id: authUser.id,
  display_name: WEN_ACCOUNT.displayName,
  login_identifier: WEN_ACCOUNT.email,
  locale: "en",
  must_change_password: false,
  status: "active",
  password_reminder_seeded_at: seededAt,
  password_changed_at: null,
  password_reminder_snoozed_until: null,
  updated_at: seededAt,
}, { onConflict: "id" });
if (profileError) throw new Error(`Upsert Wen profile: ${profileError.message}`);

const { error: membershipError } = await supabase.from("organization_memberships").upsert({
  organization_id: organization.id,
  user_id: authUser.id,
  role: WEN_ACCOUNT.role,
  status: "active",
  updated_at: seededAt,
}, { onConflict: "organization_id,user_id" });
if (membershipError) throw new Error(`Upsert Wen membership: ${membershipError.message}`);

const { error: staffError } = await supabase.from("staff_profiles").upsert({
  organization_id: organization.id,
  user_id: authUser.id,
  timezone: "America/New_York",
  skills: ["Consumer research", "Interview design", "PMF evidence"],
  availability: "Weekdays · consumer fieldwork",
  start_date: "2026-07-29",
  notes: "Consumer & Family Oral Health Research Lead. Personal contact data belongs in restricted records only.",
  updated_at: seededAt,
}, { onConflict: "organization_id,user_id" });
if (staffError) throw new Error(`Upsert Wen staff profile: ${staffError.message}`);

const onboarding = [
  ["secure_account", "Secure your account", 10],
  ["review_workspace", "Review workspace responsibilities", 20],
  ["review_data_handling", "Review data handling rules", 30],
  ["log_crm_outcome", "Log CRM outcomes", 35],
  ["file_first_eod", "File your first EOD brief", 40],
].map(([step_key, label, sequence]) => ({ organization_id: organization.id, user_id: authUser.id, step_key, label, sequence }));
const { error: onboardingError } = await supabase.from("staff_onboarding_steps").upsert(onboarding, { onConflict: "organization_id,user_id,step_key" });
if (onboardingError) throw new Error(`Upsert Wen onboarding: ${onboardingError.message}`);

const { data: activeMembers, error: membersError } = await supabase
  .from("organization_memberships")
  .select("user_id")
  .eq("organization_id", organization.id)
  .eq("status", "active");
required(activeMembers, membersError, "Find active AOI members");
const { error: reminderError } = await supabase.from("profiles").update({
  password_reminder_seeded_at: seededAt,
  password_changed_at: null,
  password_reminder_snoozed_until: null,
  updated_at: seededAt,
}).in("id", activeMembers.map((member) => member.user_id));
if (reminderError) throw new Error(`Mark password reminders: ${reminderError.message}`);
for (const member of activeMembers) await resetAuthPassword(member.user_id);

const plan = buildInternSeedPlan({ organizationId: organization.id, projectId: project.id, userId: authUser.id });
const stableTaskIds = plan.tasks.map((task) => task.id);
const { data: legacyTasks, error: legacyTaskError } = await supabase
  .from("tasks")
  .select("id")
  .eq("project_id", project.id)
  .eq("assigned_to", authUser.id)
  .ilike("acceptance_criteria", "%Seed key: wen-pmf-%");
required(legacyTasks, legacyTaskError, "Find legacy Wen seed tasks");
const legacyIds = legacyTasks.filter((task) => !stableTaskIds.includes(task.id)).map((task) => task.id);
if (legacyIds.length) {
  const { error } = await supabase.from("tasks").delete().in("id", legacyIds);
  if (error) throw new Error(`Delete legacy Wen tasks: ${error.message}`);
}
const { data: tasks, error: tasksError } = await supabase.from("tasks").upsert(plan.tasks, { onConflict: "id" }).select("id,title,status,progress,assigned_to");
required(tasks, tasksError, "Upsert Wen tasks");

const { data: eodBriefs, error: eodError } = await supabase.from("daily_eod_briefs").upsert(plan.eodBriefs, { onConflict: "project_id,author_id,brief_date" }).select("id,brief_date,workflow_status,author_id");
required(eodBriefs, eodError, "Upsert Wen EOD briefs");

const { data: sampleItems, error: sampleError } = await supabase
  .from("sample_plan_items")
  .select("id")
  .eq("project_id", project.id)
  .eq("label", "Consumer interviews")
  .limit(1);
if (sampleError) throw new Error(`Find consumer sample plan: ${sampleError.message}`);
if (sampleItems.length) {
  const { error } = await supabase.from("sample_plan_items").update({ target: 40, pmf_layer: "Need Truth", accent: "teal" }).eq("id", sampleItems[0].id);
  if (error) throw new Error(`Update consumer sample plan: ${error.message}`);
} else {
  const { error } = await supabase.from("sample_plan_items").insert({ organization_id: organization.id, project_id: project.id, label: "Consumer interviews", pmf_layer: "Need Truth", actual: 0, target: 40, accent: "teal" });
  if (error) throw new Error(`Create consumer sample plan: ${error.message}`);
}

const afterProtectedCounts = await Promise.all(protectedTables.map(([table, column]) => countRows(table, column)));
if (protectedCounts.some((count, index) => count !== afterProtectedCounts[index])) throw new Error("Wen seed changed protected research records unexpectedly.");
if (tasks.length !== plan.tasks.length || eodBriefs.length !== plan.eodBriefs.length) throw new Error("Wen seed verification count mismatch.");

console.log(JSON.stringify({
  account: { id: authUser.id, email: WEN_ACCOUNT.email, created: accountCreated, role: WEN_ACCOUNT.role, activeMembersReset: activeMembers.length },
  project: project.code,
  tasks: tasks.length,
  eodBriefs: eodBriefs.length,
  protectedResearchRecordsPreserved: true,
  password: { bootstrapApplied: true, reminderEnabled: true },
}, null, 2));
