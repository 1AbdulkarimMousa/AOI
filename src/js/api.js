import { getSupabaseClient } from "./supabase.js";

export async function loadDashboard() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_demo_dashboard");
  if (error || !data) throw new Error(`SUPABASE_DASHBOARD_FAILED:${error?.code ?? "UNKNOWN"}`);
  return data;
}

export async function listAdminUsers() {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_list_users");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function createAdminUser(input) {
  const { data, error } = await getSupabaseClient().functions.invoke("admin-create-user", { body: input });
  if (error) throw new Error(error.message || "Unable to create the user.");
  if (!data?.user) throw new Error(data?.error || "Unable to create the user.");
  return data.user;
}

export async function createAdminTask(input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_create_task", {
    task_title: input.title,
    task_objective: input.objective,
    task_priority: input.priority,
    task_due_date: input.dueDate || null,
    task_pmf_layer: input.pmfLayer,
    task_assigned_to: input.assignedTo || null,
    task_estimated_hours: input.estimatedHours || null,
    task_points: Number(input.points) || 0,
  });
  if (error) throw new Error(error.message);
  return data;
}
