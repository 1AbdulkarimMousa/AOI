import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";
import { createClient } from "@supabase/supabase-js";

import {
  buildKaylaSeedPlan,
  KAYLA_ACCOUNT,
  KAYLA_UNFINISHED_TASK_STATUSES,
} from "./kayla-seed-data.mjs";
import { runCleanupSteps } from "./seed-utils.mjs";

if (existsSync(".env.local")) loadEnvFile(".env.local");

const supabaseUrl = process.env.VITE_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const temporaryPassword = process.env.KAYLA_TEMPORARY_PASSWORD;

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Supabase URL and service-role key are required.");
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

async function deleteLegacyRows(table, rows, stableIds, label) {
  const legacyIds = rows.filter((row) => !stableIds.includes(row.id)).map((row) => row.id);
  if (!legacyIds.length) return;
  const { error } = await supabase.from(table).delete().in("id", legacyIds);
  if (error) throw new Error(`Delete legacy ${label}: ${error.message}`);
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

let authUser;
let accountCreated = false;
let result;
let finalAuthUser;

try {
  authUser = await findAuthUser(KAYLA_ACCOUNT.email);
  if (!authUser) {
    if (!temporaryPassword) throw new Error("KAYLA_TEMPORARY_PASSWORD is required when creating Kayla's Auth user.");
    const { data, error } = await supabase.auth.admin.createUser({
      email: KAYLA_ACCOUNT.email,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: { display_name: KAYLA_ACCOUNT.displayName },
    });
    authUser = required(data?.user, error, "Create Kayla Auth user");
    accountCreated = true;
  }

  const { error: profileError } = await supabase.from("profiles").upsert({
    id: authUser.id,
    display_name: KAYLA_ACCOUNT.displayName,
    login_identifier: KAYLA_ACCOUNT.email,
    locale: "en",
    must_change_password: true,
    status: "active",
    updated_at: new Date().toISOString(),
  }, { onConflict: "id" });
  if (profileError) throw new Error(`Activate Kayla profile for historical import: ${profileError.message}`);

  const { error: membershipError } = await supabase.from("organization_memberships").upsert({
    organization_id: organization.id,
    user_id: authUser.id,
    role: KAYLA_ACCOUNT.role,
    status: "active",
    updated_at: new Date().toISOString(),
  }, { onConflict: "organization_id,user_id" });
  if (membershipError) throw new Error(`Activate Kayla membership for historical import: ${membershipError.message}`);

  const plan = buildKaylaSeedPlan({
    organizationId: organization.id,
    projectId: project.id,
    userId: authUser.id,
  });

  const stableTaskIds = plan.tasks.map((task) => task.id);
  const { data: legacyTasks, error: legacyTaskError } = await supabase
    .from("tasks")
    .select("id")
    .eq("project_id", project.id)
    .eq("assigned_to", authUser.id)
    .ilike("acceptance_criteria", "%Seed key: kayla-pmf-%");
  required(legacyTasks, legacyTaskError, "Find legacy Kayla seed tasks");
  await deleteLegacyRows("tasks", legacyTasks, stableTaskIds, "Kayla seed tasks");

  const { data: tasks, error: tasksError } = await supabase
    .from("tasks")
    .upsert(plan.tasks, { onConflict: "id" })
    .select("id,title,status,assigned_to");
  required(tasks, tasksError, "Upsert Kayla tasks");

  const { error: cancelError } = await supabase
    .from("tasks")
    .update({ status: "cancelled", updated_at: new Date().toISOString() })
    .eq("project_id", project.id)
    .eq("assigned_to", authUser.id)
    .in("status", KAYLA_UNFINISHED_TASK_STATUSES);
  if (cancelError) throw new Error(`Cancel Kayla unfinished tasks: ${cancelError.message}`);

  const { data: segments, error: segmentsError } = await supabase
    .from("research_segments")
    .upsert(plan.segments, { onConflict: "project_id,code" })
    .select("id,code,name");
  required(segments, segmentsError, "Upsert professional segments");

  const { data: sampleItems, error: sampleFindError } = await supabase
    .from("sample_plan_items")
    .select("id")
    .eq("project_id", project.id)
    .eq("label", plan.samplePlan.label)
    .limit(1);
  if (sampleFindError) throw new Error(`Find professional sample plan: ${sampleFindError.message}`);

  let samplePlan;
  if (sampleItems.length) {
    const { data, error } = await supabase
      .from("sample_plan_items")
      .update({ target: plan.samplePlan.target, pmf_layer: plan.samplePlan.pmf_layer, accent: plan.samplePlan.accent })
      .eq("id", sampleItems[0].id)
      .select("id,label,actual,target")
      .single();
    samplePlan = required(data, error, "Update professional sample plan");
  } else {
    const { data, error } = await supabase
      .from("sample_plan_items")
      .insert({ ...plan.samplePlan, actual: 0 })
      .select("id,label,actual,target")
      .single();
    samplePlan = required(data, error, "Create professional sample plan");
  }

  const { data: eodBriefs, error: eodError } = await supabase
    .from("daily_eod_briefs")
    .upsert(plan.eodBriefs, { onConflict: "project_id,author_id,brief_date" })
    .select("id,brief_date,workflow_status,author_id");
  required(eodBriefs, eodError, "Upsert Kayla historical EOD briefs");

  const stableActivityIds = plan.activities.map((activity) => activity.id);
  const withdrawalActivity = plan.activities[0];
  const { data: legacyActivities, error: legacyActivityError } = await supabase
    .from("activity_events")
    .select("id")
    .eq("project_id", project.id)
    .eq("actor_name", KAYLA_ACCOUNT.displayName)
    .eq("event_type", withdrawalActivity.event_type)
    .eq("subject", withdrawalActivity.subject)
    .eq("action", withdrawalActivity.action)
    .eq("occurred_at", withdrawalActivity.occurred_at);
  required(legacyActivities, legacyActivityError, "Find legacy Kayla withdrawal activities");
  await deleteLegacyRows("activity_events", legacyActivities, stableActivityIds, "Kayla withdrawal activities");

  const { data: activities, error: activitiesError } = await supabase
    .from("activity_events")
    .upsert(plan.activities, { onConflict: "id" })
    .select("id,action,event_type,occurred_at");
  required(activities, activitiesError, "Upsert Kayla withdrawal activity");

  result = {
    project: project.code,
    tasks,
    segments,
    samplePlan,
    eodBriefs,
    activities,
    lifecycle: plan.lifecycle,
  };
} finally {
  if (authUser) {
    const cleanup = await runCleanupSteps([
      {
        name: "auth",
        run: async () => {
          const { data, error } = await supabase.auth.admin.updateUserById(authUser.id, { ban_duration: "876000h" });
          return required(data?.user, error, "Disable Kayla Auth login");
        },
      },
      {
        name: "membership",
        run: async () => {
          const { data, error } = await supabase
            .from("organization_memberships")
            .update({ status: "disabled", updated_at: new Date().toISOString() })
            .eq("organization_id", organization.id)
            .eq("user_id", authUser.id)
            .select("role,status")
            .single();
          return required(data, error, "Disable Kayla membership");
        },
      },
      {
        name: "profile",
        run: async () => {
          const { data, error } = await supabase
            .from("profiles")
            .update({ status: "disabled", updated_at: new Date().toISOString() })
            .eq("id", authUser.id)
            .select("display_name,login_identifier,status")
            .single();
          return required(data, error, "Disable Kayla profile");
        },
      },
    ]);
    finalAuthUser = cleanup.values.auth;
    if (cleanup.errors.length) {
      throw new Error(`Kayla terminal cleanup failed: ${cleanup.errors.map(({ name, error }) => `${name}: ${error.message}`).join("; ")}`);
    }
  }
}

if (!result || !authUser || !finalAuthUser) throw new Error("Kayla seed did not reach a verifiable terminal state.");

const [profileCheck, membershipCheck, taskCheck, eodCheck, activityCheck] = await Promise.all([
  supabase.from("profiles").select("status").eq("id", authUser.id).single(),
  supabase.from("organization_memberships").select("status").eq("organization_id", organization.id).eq("user_id", authUser.id).single(),
  supabase.from("tasks").select("id", { count: "exact", head: true }).in("id", result.tasks.map((task) => task.id)),
  supabase.from("daily_eod_briefs").select("id", { count: "exact", head: true }).eq("project_id", project.id).eq("author_id", authUser.id).in("brief_date", ["2026-07-29", "2026-07-30", "2026-07-31"]),
  supabase.from("activity_events").select("id", { count: "exact", head: true }).in("id", result.activities.map((activity) => activity.id)),
]);

if (profileCheck.error || profileCheck.data?.status !== "disabled") throw new Error("Kayla profile disable verification failed.");
if (membershipCheck.error || membershipCheck.data?.status !== "disabled") throw new Error("Kayla membership disable verification failed.");
if (taskCheck.error || taskCheck.count !== 8) throw new Error("Kayla task verification failed.");
if (eodCheck.error || eodCheck.count !== 3) throw new Error("Kayla EOD verification failed.");
if (activityCheck.error || activityCheck.count !== 1) throw new Error("Kayla withdrawal activity verification failed.");
if (!finalAuthUser.banned_until || new Date(finalAuthUser.banned_until) <= new Date()) throw new Error("Kayla Auth ban verification failed.");

console.log(JSON.stringify({
  account: {
    id: authUser.id,
    email: KAYLA_ACCOUNT.email,
    created: accountCreated,
    role: KAYLA_ACCOUNT.role,
    profileStatus: profileCheck.data.status,
    membershipStatus: membershipCheck.data.status,
    authBannedUntil: finalAuthUser.banned_until,
  },
  ...result,
}, null, 2));
