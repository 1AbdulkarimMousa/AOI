import { getSupabaseClient } from "./supabase.js";

export async function loadDashboard() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_demo_dashboard");
  if (error || !data) throw new Error(`SUPABASE_DASHBOARD_FAILED:${error?.code ?? "UNKNOWN"}`);
  const operations = await getSupabaseClient().rpc("rpc_aoi_operations_snapshot");
  return operations.error ? data : { ...data, ...operations.data };
}

export async function upsertCandidate(candidate) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_upsert_candidate", { candidate });
  if (error) throw new Error(error.message);
  return data;
}

export async function logOutreach(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_log_outreach", {
    candidate_id: candidateId,
    event_channel: input.channel,
    event_kind: input.kind,
    event_status: input.status,
    event_summary: input.summary,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function addEvidence(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_add_evidence", {
    candidate_id: candidateId,
    evidence_type: input.type,
    evidence_stance: input.stance,
    evidence_strength: Number(input.strength) || 1,
    evidence_title: input.title,
    evidence_notes: input.notes,
    evidence_consent: input.consentStatus,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function queueEmail(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_queue_email", {
    candidate_id: candidateId,
    recipient: input.recipient,
    email_subject: input.subject,
    email_body: input.body,
    send_at: input.sendAt || new Date().toISOString(),
    template_id: input.templateId || null,
  });
  if (error) throw new Error(error.message);
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
