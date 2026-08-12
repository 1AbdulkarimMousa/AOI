export function decideSurveySubmitReplay(replay) {
  if (replay.error?.message === "SURVEY_RESPONSE_UNAVAILABLE") return { kind: "continue" };
  if (replay.error) return { kind: "error", message: replay.error.message };
  if (replay.data?.replayed) return { kind: "response", status: 200, payload: { data: replay.data } };
  return { kind: "error", message: "SURVEY_REPLAY_INVALID" };
}

export function surveyCorsHeaders(origin) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    Vary: "Origin",
  };
}
