export function buildAnalysisQuestions(summaries = []) {
  const seen = new Set();
  return summaries.flatMap((summary) => {
    if (!summary?.definition || summary.definition.privacy?.classification === "direct_identifier") return [];
    const key = `${summary.versionId || "unknown"}:${summary.questionId}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ ...summary.definition, versionId: summary.versionId, analysisKey: key }];
  });
}

export function analysisValues(summaries = [], question = {}) {
  return summaries
    .filter((summary) => summary.questionId === question.id && summary.versionId === question.versionId)
    .flatMap((summary) => summary.values || []);
}

export function canReviewSurveyResponse(role, status, action) {
  if (role === "admin") return ["start_review", "approve", "reject", "exclude", "request_revision"].includes(action)
    && (action === "start_review" ? status === "submitted" : ["submitted", "in_review"].includes(status));
  return role === "intern" && status === "submitted" && ["start_review", "recommend_approve", "recommend_reject"].includes(action);
}

export function shouldConfirmSurveyRoute(isSurveyWorkspaceActive, targetIsSurveyWorkspace, dirty) {
  return Boolean(isSurveyWorkspaceActive && dirty && !targetIsSurveyWorkspace);
}
