import { getSupabaseClient } from "./supabase.js";

export async function loadDashboard() {
  const client = getSupabaseClient();
  const [dashboard, operations, pmf, crm] = await Promise.all([
    client.rpc("rpc_aoi_demo_dashboard"),
    client.rpc("rpc_aoi_operations_snapshot"),
    client.rpc("rpc_aoi_pmf_snapshot"),
    client.rpc("rpc_aoi_crm_snapshot"),
  ]);
  if (dashboard.error || !dashboard.data) throw new Error(`SUPABASE_DASHBOARD_FAILED:${dashboard.error?.code ?? "UNKNOWN"}`);
  if (operations.error) throw new Error(`SUPABASE_OPERATIONS_FAILED:${operations.error.code ?? "UNKNOWN"}`);
  if (pmf.error) throw new Error(`SUPABASE_PMF_FAILED:${pmf.error.code ?? "UNKNOWN"}`);
  if (crm.error) throw new Error(`SUPABASE_CRM_FAILED:${crm.error.code ?? "UNKNOWN"}`);
  return { ...dashboard.data, ...operations.data, ...pmf.data, ...crm.data };
}

export async function loadDailyEod() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_daily_eod_snapshot");
  if (error) throw new Error(error.message);
  return data?.dailyEod;
}

export async function saveDailyEodBrief(payload, expectedUpdatedAt = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_save_daily_eod_brief", {
    p_payload: payload,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function adminUpdateDailyEodBrief(briefId, payload, editReason, expectedUpdatedAt, action = "save") {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_admin_update_daily_eod_brief", {
    p_brief_id: briefId,
    p_payload: payload,
    p_edit_reason: editReason,
    p_expected_updated_at: expectedUpdatedAt,
    p_action: action,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadDailyEodReports(filters = {}, page = 1, pageSize = 25) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_daily_eod_reports", {
    p_filters: filters,
    p_page: page,
    p_page_size: pageSize,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function upsertCrmContact(contact) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_upsert_crm_contact", { contact });
  if (error) throw new Error(error.message);
  return data;
}

export async function logCrmActivity(contactId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_log_crm_activity", {
    contact_id: contactId,
    activity_type: input.activityType,
    activity_summary: input.summary,
    next_action: input.nextAction || null,
    next_action_due: input.nextActionDue || null,
    lifecycle: input.lifecycle || null,
    reward_points: Number(input.rewardPoints) || 0,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function upsertCandidate(candidate) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_upsert_candidate", { p_candidate: candidate });
  if (error) throw new Error(error.message);
  return data;
}

export async function logOutreach(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_log_outreach", {
    p_candidate_id: candidateId,
    p_event_channel: input.channel,
    p_event_kind: input.kind,
    p_event_status: input.status,
    p_event_summary: input.summary,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function addEvidence(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_add_evidence", {
    p_candidate_id: candidateId,
    p_evidence_type: input.type,
    p_evidence_stance: input.stance,
    p_evidence_strength: Number(input.strength) || 1,
    p_evidence_title: input.title,
    p_evidence_notes: input.notes,
    p_evidence_consent: input.consentStatus,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function queueEmail(candidateId, input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_queue_email", {
    p_candidate_id: candidateId,
    p_recipient: input.recipient,
    p_email_subject: input.subject,
    p_email_body: input.body,
    p_send_at: input.sendAt || new Date().toISOString(),
    p_template_id: input.templateId || null,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function saveResearchRecord(recordType, payload) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_save_research_record", {
    p_record_type: recordType,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function appendConsentVersion(respondentId, payload) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_append_consent_version", {
    p_respondent_id: respondentId,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function reviewResearchRecord(recordType, recordId, action, notes = "") {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_review_research_record", {
    p_record_type: recordType,
    p_record_id: recordId,
    p_action: action,
    p_notes: notes,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function importCandidates(rows, fileName, fileFormat) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_import_candidates", {
    p_rows: rows,
    p_file_name: fileName,
    p_file_format: fileFormat,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function createGateSnapshot(pmfLayer, decision, rationale) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_create_gate_snapshot", {
    p_pmf_layer: pmfLayer,
    p_decision: decision,
    p_rationale: rationale,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function uploadResearchAttachment({ bucketId, file, projectId, organizationId, respondentId, sessionId = null }) {
  const client = getSupabaseClient();
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user) throw new Error("Your session could not be verified for this upload.");
  let consentVersion = null;
  if (["aoi-recordings", "aoi-oral-images"].includes(bucketId)) {
    const permissionField = bucketId === "aoi-recordings" ? "recording_allowed" : "images_allowed";
    const consent = await client
      .from("consent_records")
      .select(`version,${permissionField}`)
      .eq("respondent_id", respondentId)
      .eq("status", "granted")
      .eq(permissionField, true)
      .order("version", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (consent.error || !consent.data) throw new Error("Current consent does not allow this upload type.");
    consentVersion = consent.data.version;
  }
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "research-file";
  const objectPath = `${projectId}/${respondentId}/${globalThis.crypto.randomUUID()}-${safeName}`;
  const uploaded = await client.storage.from(bucketId).upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type || "application/octet-stream",
    upsert: false,
  });
  if (uploaded.error) throw new Error(uploaded.error.message);

  const metadata = await client.from("research_attachments").insert({
    organization_id: organizationId,
    project_id: projectId,
    respondent_id: respondentId,
    session_id: sessionId,
    bucket_id: bucketId,
    object_path: uploaded.data.path,
    original_name: file.name,
    mime_type: file.type || "application/octet-stream",
    size_bytes: file.size,
    consent_version: consentVersion,
    uploaded_by: userData.user.id,
  }).select("id,bucket_id,object_path,original_name,mime_type,size_bytes,created_at").single();
  if (metadata.error) {
    await client.storage.from(bucketId).remove([uploaded.data.path]);
    throw new Error(metadata.error.message);
  }
  return metadata.data;
}

export async function listAdminUsers() {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_list_users");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function loadAdministrationOverview() {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_overview");
  if (error) throw new Error(error.message);
  return data;
}

export async function loadAdministrationPeople(filters = {}) {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_people", {
    p_query: filters.query || null,
    p_role: filters.role && filters.role !== "all" ? filters.role : null,
    p_status: filters.status && filters.status !== "all" ? filters.status : null,
  });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function loadAdministrationPerson(userId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_person_detail", { p_user_id: userId });
  if (error) throw new Error(error.message);
  return data;
}

export async function updateAdministrationPerson(userId, payload) {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_upsert_staff_profile", {
    p_user_id: userId,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function runAdministrationUserAction(action, input) {
  const { data, error } = await getSupabaseClient().functions.invoke("admin-create-user", {
    body: { action, ...input },
  });
  if (error) throw new Error(error.message || "Unable to update the user.");
  if (data?.error) throw new Error(data.error);
  return data;
}

export async function exportAdministrationData(scope = "full") {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_export_data", { p_scope: scope });
  if (error) throw new Error(error.message);
  return data;
}

export async function importAdministrationData(packageData, mode = "preview", previewJobId = null, previewMode = "merge") {
  const client = getSupabaseClient();
  if (mode !== "preview") {
    const { data, error } = await client.functions.invoke("admin-create-user", {
      body: { action: "import", packageData, mode, previewJobId },
    });
    if (error || data?.error) throw new Error(data?.error || error?.message || "Unable to apply the administration import.");
    return data.result;
  }
  const { data, error } = await client.rpc("rpc_admin_import_data", {
    p_package: packageData,
      p_mode: mode,
      p_preview_job_id: null,
      p_preview_mode: previewMode,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function createAdminUser(input) {
  const { data, error } = await getSupabaseClient().functions.invoke("admin-create-user", { body: input });
  if (error) throw new Error(error.message || "Unable to create the user.");
  if (!data?.user) throw new Error(data?.error || "Unable to create the user.");
  return data;
}

export async function createAdminTask(input) {
  const { data, error } = await getSupabaseClient().rpc("rpc_admin_create_task_v2", { p_task: input });
  if (error) throw new Error(error.message);
  return data;
}

export async function completeOnboardingStep(stepKey) {
  const { data, error } = await getSupabaseClient().rpc("rpc_update_onboarding_step", {
    p_step_key: stepKey,
    p_status: "completed",
  });
  if (error) throw new Error(error.message);
  return data;
}
