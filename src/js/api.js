import { getSupabaseClient } from "./supabase.js";

export async function loadDashboard() {
  const client = getSupabaseClient();
  const [dashboard, operations, pmf, crm, collect, gamification] = await Promise.all([
    client.rpc("rpc_aoi_demo_dashboard"),
    client.rpc("rpc_aoi_operations_snapshot"),
    client.rpc("rpc_aoi_pmf_snapshot"),
    client.rpc("rpc_aoi_crm_snapshot"),
    client.rpc("rpc_aoi_collect_snapshot"),
    client.rpc("rpc_aoi_gamification_summary"),
  ]);
  if (dashboard.error || !dashboard.data) throw new Error(`SUPABASE_DASHBOARD_FAILED:${dashboard.error?.code ?? "UNKNOWN"}`);
  if (operations.error) throw new Error(`SUPABASE_OPERATIONS_FAILED:${operations.error.code ?? "UNKNOWN"}`);
  if (pmf.error) throw new Error(`SUPABASE_PMF_FAILED:${pmf.error.code ?? "UNKNOWN"}`);
  if (crm.error) throw new Error(`SUPABASE_CRM_FAILED:${crm.error.code ?? "UNKNOWN"}`);
  if (collect.error) throw new Error(`SUPABASE_COLLECT_FAILED:${collect.error.code ?? "UNKNOWN"}`);
  if (gamification.error) throw new Error(`SUPABASE_GAMIFICATION_FAILED:${gamification.error.code ?? "UNKNOWN"}`);
  return { ...dashboard.data, ...operations.data, ...pmf.data, ...crm.data, collect: collect.data, gamification: gamification.data };
}

export async function loadTodayBriefing(projectId = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_today_briefing", { p_project_id: projectId });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadCrmSnapshot() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_crm_snapshot");
  if (error) throw new Error(error.message);
  return data || {};
}

export async function loadOperationsSnapshot() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_operations_snapshot");
  if (error) throw new Error(error.message);
  return data || {};
}

export async function loadInbox(bucket = "needs_action", projectId = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_inbox_snapshot", {
    p_bucket: bucket,
    p_project_id: projectId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadProjectContext() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_project_context");
  if (error) throw new Error(error.message);
  return data;
}

export async function selectProjectContext(projectId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_select_project", { p_project_id: projectId });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadProjectSnapshot(projectId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_project_snapshot", { p_project_id: projectId });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadProjectRecordDetail(recordType, recordId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_project_record_detail", {
    p_record_type: recordType,
    p_record_id: recordId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function saveProjectRecord(recordType, payload, recordId = null, expectedUpdatedAt = null, clientNonce = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_save_project_record", {
    p_record_type: recordType,
    p_payload: payload,
    p_record_id: recordId,
    p_expected_updated_at: expectedUpdatedAt,
    p_client_nonce: clientNonce,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function transitionProjectRecord(recordType, recordId, action, note, expectedUpdatedAt, clientNonce = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_transition_project_record", {
    p_record_type: recordType,
    p_record_id: recordId,
    p_action: action,
    p_note: note,
    p_expected_updated_at: expectedUpdatedAt,
    p_client_nonce: clientNonce,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function adminSaveProject(payload, projectId = null, expectedUpdatedAt = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_admin_save_project", {
    p_payload: payload,
    p_project_id: projectId,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function setProjectMember(projectId, userId, active, responsibility, expectedUpdatedAt = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_admin_set_project_member", {
    p_project_id: projectId,
    p_user_id: userId,
    p_active: active,
    p_responsibility: responsibility,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function transitionProject(projectId, action, note, expectedUpdatedAt) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_transition_project", {
    p_project_id: projectId,
    p_action: action,
    p_note: note,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function markInboxRead(itemId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_mark_inbox_read", { p_item_id: itemId });
  if (error) throw new Error(error.message);
  return data;
}

function collaborationRpcError(error) {
  const reason = new Error(error?.message || "Collaboration request failed.");
  reason.code = error?.code;
  reason.details = error?.details;
  reason.hint = error?.hint;
  return reason;
}

export async function loadInboxItemDetail(itemId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_inbox_item_detail", { p_item_id: itemId });
  if (error) throw collaborationRpcError(error);
  return data;
}

export async function createWorkComment(sourceType, sourceId, body, clientNonce, mentionedUserIds = []) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_create_work_comment", {
    p_source_type: sourceType,
    p_source_id: sourceId,
    p_body: body,
    p_client_nonce: clientNonce,
    p_mentioned_user_ids: mentionedUserIds,
  });
  if (error) throw collaborationRpcError(error);
  return data;
}

export async function reviseWorkComment(commentId, body, changeReason) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_revise_work_comment", {
    p_comment_id: commentId,
    p_body: body,
    p_change_reason: changeReason,
  });
  if (error) throw collaborationRpcError(error);
  return data;
}

export async function followWorkSource(sourceType, sourceId, follow = true) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_follow_work_source", {
    p_source_type: sourceType,
    p_source_id: sourceId,
    p_follow: follow,
  });
  if (error) throw collaborationRpcError(error);
  return data;
}

export async function handoffWork(sourceType, sourceId, toUserId, reason, clientNonce) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_handoff_work", {
    p_source_type: sourceType,
    p_source_id: sourceId,
    p_to_user_id: toUserId,
    p_reason: reason,
    p_client_nonce: clientNonce,
  });
  if (error) throw collaborationRpcError(error);
  return data;
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

export async function saveResearchRecord(recordType, payload) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_save_research_record", {
    p_record_type: recordType,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function updateResearchRecord(recordType, recordId, payload, expectedUpdatedAt, action) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_update_research_record", {
    p_record_type: recordType,
    p_record_id: recordId,
    p_payload: payload,
    p_expected_updated_at: expectedUpdatedAt,
    p_action: action,
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

export async function reviewResearchRecord(recordType, recordId, action, notes = "", expectedUpdatedAt = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_review_research_record", {
    p_record_type: recordType,
    p_record_id: recordId,
    p_action: action,
    p_notes: notes,
    p_expected_updated_at: expectedUpdatedAt,
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

export async function loadSurveyLibrary() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_survey_library");
  if (error) throw new Error(error.message);
  return data ?? { assets: [], reviewCount: 0 };
}

export async function createSurveyAsset({ title, assetType = "survey", definition = null, sourceAssetId = null }) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_create_survey", {
    p_title: title,
    p_asset_type: assetType,
    p_definition: definition,
    p_source_asset_id: sourceAssetId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadSurveyWorkspace(assetId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_survey_workspace", { p_asset_id: assetId });
  if (error) throw new Error(error.message);
  return data;
}

export async function saveSurveyDraft(assetId, definition, expectedRevision) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_save_survey_draft", {
    p_asset_id: assetId,
    p_definition: definition,
    p_expected_revision: expectedRevision,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function submitSurveyVersion(assetId, expectedRevision) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_submit_survey_version", {
    p_asset_id: assetId,
    p_expected_revision: expectedRevision,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function reviewSurveyVersion(versionId, action, notes = "") {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_review_survey_version", {
    p_version_id: versionId,
    p_action: action,
    p_notes: notes,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function publishSurveyVersion(versionId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_publish_survey", { p_version_id: versionId });
  if (error) throw new Error(error.message);
  return data;
}

export async function createSurveyLink(versionId, input = {}) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_create_survey_link", {
    p_version_id: versionId,
    p_label: input.label || "Primary link",
    p_mode: input.mode || "public",
    p_identity_mode: input.identityMode || "anonymous",
    p_settings: input.settings || {},
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function createSurveyInvitation(linkId, recipientName, recipientEmail) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_create_survey_invitation", {
    p_link_id: linkId,
    p_recipient_name: recipientName,
    p_recipient_email: recipientEmail,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function updateSurveyLinkStatus(linkId, status) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_update_survey_link_status", { p_link_id: linkId, p_status: status });
  if (error) throw new Error(error.message);
  return data;
}

export async function revokeSurveyInvitation(invitationId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_revoke_survey_invitation", { p_invitation_id: invitationId });
  if (error) throw new Error(error.message);
  return data;
}

export async function reviewSurveySubmission(submissionId, action, notes = "") {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_review_survey_submission", {
    p_submission_id: submissionId,
    p_action: action,
    p_notes: notes,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function promoteSurveyAnswer(submissionId, questionId, metricCode, segmentCode) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_promote_survey_answer", {
    p_submission_id: submissionId,
    p_question_id: questionId,
    p_metric_code: metricCode,
    p_segment_code: segmentCode,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadSurveyAnalysis(assetId, population = "approved") {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_survey_analysis", {
    p_asset_id: assetId,
    p_population: population,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function invokeSurveyPublic(action, payload = {}) {
  const { data, error } = await getSupabaseClient().functions.invoke("survey-public", {
    body: { action, ...payload },
  });
  if (error || data?.error) {
    const surveyError = new Error(data?.error || error.message);
    surveyError.code = data?.code || "SURVEY_REQUEST_FAILED";
    surveyError.fields = data?.fields || {};
    throw surveyError;
  }
  return data?.data;
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
  if (error || data?.error || data?.reconciliationAction) {
    const reason = new Error(data?.error || data?.message || error?.message || "Unable to update the user.");
    reason.reconciliationRequired = Boolean(data?.reconciliationRequired);
    reason.reconciliationAction = data?.reconciliationAction || "";
    throw reason;
  }
  return data;
}

export async function changeOwnAdministrationPassword(input) {
  try {
    return await runAdministrationUserAction("change_own_password", input);
  } catch (reason) {
    if (reason.reconciliationAction === "reconcile_own_password") return runAdministrationUserAction("reconcile_own_password", {});
    throw reason;
  }
}

export async function resetAdministrationUserPassword(userId, input) {
  return runAdministrationUserAction("reset_user_password", {
    userId,
    resetMode: input.mode,
    password: input.mode === "custom" ? input.temporaryPassword : undefined,
    reason: input.reason,
  });
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

export async function loadTaskDetail(taskId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_task_detail", { p_task_id: taskId });
  if (error) throw new Error(error.message);
  return data;
}

export async function updateTaskCheckpoint(taskId, progress, status = null, note = null, expectedUpdatedAt) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_update_task_checkpoint", {
    p_task_id: taskId,
    p_progress: progress,
    p_status: status,
    p_note: note,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function reviewTask(taskId, action, note, expectedUpdatedAt) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_review_task", {
    p_task_id: taskId,
    p_action: action,
    p_note: note,
    p_expected_updated_at: expectedUpdatedAt,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function snoozePasswordReminder(until) {
  const { data, error } = await getSupabaseClient().rpc("rpc_snooze_password_reminder", { p_until: until });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadParticipantTracker() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_participant_tracker_snapshot");
  if (error) throw new Error(error.message);
  return data;
}

export async function saveParticipantRecruitment(payload) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_upsert_participant_recruitment", { p_payload: payload });
  if (error) throw new Error(error.message);
  return data;
}

export async function convertParticipantToRespondent(recruitmentId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_convert_recruitment_to_respondent", {
    p_recruitment_id: recruitmentId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadCollectRecordDetail(recordType, recordId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_collect_record_detail", {
    p_record_type: recordType,
    p_record_id: recordId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadHelpCenter() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_help_center_snapshot");
  if (error) throw new Error(error.message);
  return data;
}

export async function upsertHelpArticle(article, expectedVersion = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_help_center_upsert_article", {
    p_article: article,
    p_expected_version: expectedVersion,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function setHelpArticleStatus(articleId, status, expectedVersion = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_help_center_set_status", {
    p_article_id: articleId,
    p_status: status,
    p_expected_version: expectedVersion,
  });
  if (error) throw new Error(error.message);
  return data;
}

function rpcError(error, fallback) {
  if (error) throw new Error(error.message || fallback);
}

export async function loadChatBootstrap() {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_bootstrap");
  rpcError(error, "Unable to load chat.");
  return data;
}

export async function openDirectChat(memberId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_open_direct", { p_member_id: memberId });
  rpcError(error, "Unable to open the conversation.");
  return data;
}

export async function loadChatMessages(conversationId, before = null, limit = 50) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_messages", {
    p_conversation_id: conversationId,
    p_before: before,
    p_limit: limit,
  });
  rpcError(error, "Unable to load messages.");
  return data || [];
}

export async function persistChatMessage(conversationId, body, { clientNonce, replyToId = null, attachments = [] } = {}) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_send", {
    p_conversation_id: conversationId,
    p_body: body,
    p_client_nonce: clientNonce || globalThis.crypto.randomUUID(),
    p_reply_to_id: replyToId,
    p_attachments: attachments,
  });
  rpcError(error, "Unable to send the message.");
  return data;
}

export async function loadChatMessageByNonce(conversationId, clientNonce) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_message_by_nonce", {
    p_conversation_id: conversationId,
    p_client_nonce: clientNonce,
  });
  rpcError(error, "Unable to reconcile the message.");
  return data || null;
}

export async function editChatMessage(messageId, body) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_edit", { p_message_id: messageId, p_body: body });
  rpcError(error, "Unable to edit the message.");
  return data;
}

export async function deleteChatMessage(messageId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_delete", { p_message_id: messageId });
  rpcError(error, "Unable to delete the message.");
  return data;
}

export async function moderateChatMessage(messageId, reason) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_moderate", {
    p_message_id: messageId,
    p_reason: reason,
    p_action: "remove",
  });
  rpcError(error, "Unable to moderate the message.");
  return data;
}

export async function toggleChatReaction(messageId, reaction) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_toggle_reaction", {
    p_message_id: messageId,
    p_reaction: reaction,
  });
  rpcError(error, "Unable to update the reaction.");
  return data;
}

export async function markChatRead(conversationId, messageId = null) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_mark_read", {
    p_conversation_id: conversationId,
    p_message_id: messageId,
  });
  rpcError(error, "Unable to update read state.");
  return data;
}

export async function searchChatMessages(query, conversationId = null, limit = 50) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_chat_search", {
    p_query: query,
    p_conversation_id: conversationId,
    p_limit: limit,
  });
  rpcError(error, "Unable to search messages.");
  return data || [];
}

export async function updateProfile(profile) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_update_profile", { p_profile: profile });
  rpcError(error, "Unable to save your profile.");
  return data;
}

export async function loadMemberProfile(memberId) {
  const { data, error } = await getSupabaseClient().rpc("rpc_aoi_member_profile", { p_member_id: memberId });
  rpcError(error, "Unable to load the member profile.");
  return data;
}

function safeFileName(name, fallback) {
  return String(name || fallback).replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || fallback;
}

export async function uploadAvatar(file, organizationId, userId) {
  const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file.type];
  if (!extension) throw new Error("Unsupported profile photo type.");
  const objectPath = `${organizationId}/${userId}/${globalThis.crypto.randomUUID()}.${extension}`;
  const { error } = await getSupabaseClient().storage.from("aoi-avatars").upload(objectPath, file, {
    cacheControl: "900",
    contentType: file.type,
    upsert: false,
  });
  rpcError(error, "Unable to upload the profile photo.");
  return { objectPath };
}

export async function removeAvatarObject(objectPath) {
  if (!objectPath) return;
  const { error } = await getSupabaseClient().storage.from("aoi-avatars").remove([objectPath]);
  rpcError(error, "Unable to remove the profile photo.");
}

export async function createAvatarSignedUrls(paths, expiresIn = 900) {
  const uniquePaths = [...new Set((paths || []).filter(Boolean))];
  if (!uniquePaths.length) return {};
  const { data, error } = await getSupabaseClient().storage.from("aoi-avatars").createSignedUrls(uniquePaths, expiresIn);
  rpcError(error, "Unable to load profile photos.");
  return Object.fromEntries((data || []).filter((item) => item.signedUrl).map((item) => [item.path, item.signedUrl]));
}

export async function uploadChatAttachment(file, organizationId, conversationId, userId) {
  const name = safeFileName(file.name, "attachment");
  const objectPath = `${organizationId}/${conversationId}/${userId}/${globalThis.crypto.randomUUID()}-${name}`;
  const { error } = await getSupabaseClient().storage.from("aoi-chat").upload(objectPath, file, {
    cacheControl: "300",
    contentType: file.type,
    upsert: false,
  });
  rpcError(error, "Unable to upload the attachment.");
  return { objectPath, fileName: file.name, mimeType: file.type, sizeBytes: file.size };
}

export async function removeChatAttachments(paths) {
  const objectPaths = (paths || []).filter(Boolean);
  if (!objectPaths.length) return;
  const { error } = await getSupabaseClient().storage.from("aoi-chat").remove(objectPaths);
  rpcError(error, "Unable to remove the attachment.");
}

export async function createChatAttachmentUrl(objectPath, expiresIn = 300) {
  const { data, error } = await getSupabaseClient().storage.from("aoi-chat").createSignedUrl(objectPath, expiresIn);
  rpcError(error, "Unable to open the attachment.");
  return data.signedUrl;
}
