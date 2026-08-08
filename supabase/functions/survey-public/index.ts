import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { validateSurveyPayload } from "../_shared/survey-validation.js";

type SurveyAction = "load" | "start" | "save" | "submit" | "upload";

type SurveyRequest = {
  action?: SurveyAction;
  token?: string;
  invitationToken?: string;
  locale?: "en" | "zh-CN";
  submissionId?: string;
  resumeToken?: string;
  answers?: Record<string, unknown>;
  consent?: Record<string, unknown>;
  score?: Record<string, unknown>;
  idempotencyKey?: string;
  fileName?: string;
  contentType?: string;
  questionId?: string;
};

const configuredOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const allowedOrigins = new Set([
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "https://1abdulkarimmousa.github.io",
  ...configuredOrigins,
]);

const allowedUploadTypes = new Set(["application/pdf", "image/jpeg", "image/png", "text/plain", "text/csv"]);

function corsHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function json(origin: string, status: number, payload: Record<string, unknown>) {
  return Response.json(payload, { status, headers: corsHeaders(origin) });
}

function safeName(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 100) || "survey-upload";
}

const uploadFormats = new Map([
  ["pdf", { extension: "pdf", contentType: "application/pdf" }],
  ["jpg", { extension: "jpg", contentType: "image/jpeg" }],
  ["jpeg", { extension: "jpg", contentType: "image/jpeg" }],
  ["png", { extension: "png", contentType: "image/png" }],
  ["txt", { extension: "txt", contentType: "text/plain" }],
  ["csv", { extension: "csv", contentType: "text/csv" }],
]);

function normalizeUploadMetadata(fileName: string, suppliedType: string) {
  const safe = safeName(fileName);
  const sourceExtension = safe.includes(".") ? safe.split(".").pop()!.toLowerCase() : "";
  const byExtension = uploadFormats.get(sourceExtension);
  const byType = [...uploadFormats.values()].find((format) => format.contentType === suppliedType.toLowerCase());
  const format = byExtension ?? byType;
  if (!format || byExtension && byType && byExtension.contentType !== byType.contentType) return null;
  const baseName = safe.replace(/\.[^.]+$/, "") || "survey-upload";
  return { fileName: `${baseName}.${format.extension}`, extension: format.extension, contentType: format.contentType };
}

function publicError(message = "") {
  if (message.includes("SURVEY_LINK_UNAVAILABLE")) return { status: 404, code: "SURVEY_LINK_UNAVAILABLE", message: "This survey link is unavailable." };
  if (message.includes("SURVEY_INVITATION")) return { status: 404, code: "SURVEY_INVITATION_REQUIRED", message: "This invitation is unavailable or has already been used." };
  if (message.includes("SURVEY_RESPONSE_CAPACITY_REACHED")) return { status: 409, code: "SURVEY_RESPONSE_CAPACITY_REACHED", message: "This survey has reached its response limit." };
  if (message.includes("SURVEY_RESPONSE_UNAVAILABLE") || message.includes("SURVEY_RESPONSE_LOCKED")) return { status: 409, code: "SURVEY_RESPONSE_UNAVAILABLE", message: "This response can no longer be changed." };
  if (message.includes("SURVEY_IDEMPOTENCY_REQUIRED")) return { status: 400, code: "SURVEY_SUBMISSION_INVALID", message: "The submission could not be verified." };
  if (message.includes("SURVEY_EMBED_ORIGIN_DENIED")) return { status: 403, code: "SURVEY_EMBED_ORIGIN_DENIED", message: "This survey cannot be embedded on this origin." };
  return { status: 400, code: "SURVEY_REQUEST_INVALID", message: "The survey request could not be completed." };
}

async function readLimitedJson(request: Request, maximumBytes = 1_048_576) {
  if (!request.body) throw new Error("REQUEST_BODY_REQUIRED");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximumBytes) {
      await reader.cancel();
      throw new Error("REQUEST_TOO_LARGE");
    }
    chunks.push(value);
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(body));
}

Deno.serve(async (request) => {
  const origin = request.headers.get("Origin") ?? "";
  if (!allowedOrigins.has(origin)) return Response.json({ error: "Origin not allowed." }, { status: 403 });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (request.method !== "POST") return json(origin, 405, { error: "Method not allowed." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json(origin, 503, { error: "Survey collection is not configured." });

  let body: SurveyRequest;
  try {
    body = await readLimitedJson(request);
  } catch (reason) {
    if (reason instanceof Error && reason.message === "REQUEST_TOO_LARGE") return json(origin, 413, { error: "Request is too large." });
    return json(origin, 400, { error: "Request body must be valid JSON." });
  }

  const action = body.action;
  const token = String(body.token || "");
  if (!action || !["load", "start", "save", "submit", "upload"].includes(action) || token.length < 32 || token.length > 128) {
    return json(origin, 400, { error: "Survey request is invalid." });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  let result: { data: unknown; error: { message: string } | null };
  let published: Record<string, unknown> | null = null;

  if (action === "submit" && body.submissionId && body.resumeToken && body.idempotencyKey) {
    const replay = await client.rpc("rpc_aoi_public_survey_replay", {
      p_submission_id: body.submissionId,
      p_resume_token: body.resumeToken,
      p_idempotency_key: body.idempotencyKey,
    });
    if (replay.error) {
      const error = publicError(replay.error.message);
      return json(origin, error.status, { error: error.message, code: error.code });
    }
    if (replay.data?.replayed) return json(origin, 200, { data: replay.data });
  }

  const loaded = await client.rpc("rpc_aoi_public_survey_load", { p_token: token, p_invitation_token: body.invitationToken || null });
  if (loaded.error) {
    const error = publicError(loaded.error.message);
    return json(origin, error.status, { error: error.message, code: error.code });
  }
  published = loaded.data as Record<string, unknown>;
  if (published.mode === "embed") {
    const linkOrigins = Array.isArray(published.allowedOrigins) ? published.allowedOrigins : [];
    if (!linkOrigins.includes(origin)) {
      const error = publicError("SURVEY_EMBED_ORIGIN_DENIED");
      return json(origin, error.status, { error: error.message, code: error.code });
    }
  }

  if (action === "load") {
    result = loaded;
  } else if (action === "start") {
    result = await client.rpc("rpc_aoi_public_survey_start", {
      p_token: token,
      p_invitation_token: body.invitationToken || null,
      p_locale: body.locale === "zh-CN" ? "zh-CN" : "en",
      p_consent: body.consent ?? {},
    });
  } else if (action === "save") {
    if (!published) return json(origin, 404, { error: "This survey link is unavailable.", code: "SURVEY_LINK_UNAVAILABLE" });
    const validation = validateSurveyPayload(published.definition, body.answers ?? {}, { partial: true, submissionId: body.submissionId });
    if (!validation.valid) return json(origin, 422, { error: "One or more answers are invalid.", code: "SURVEY_ANSWERS_INVALID", fields: validation.errors });
    result = await client.rpc("rpc_aoi_public_survey_save", {
      p_token: token,
      p_invitation_token: body.invitationToken || null,
      p_submission_id: body.submissionId,
      p_resume_token: body.resumeToken,
      p_answers: validation.answers,
    });
  } else if (action === "submit") {
    if (!published) return json(origin, 404, { error: "This survey link is unavailable.", code: "SURVEY_LINK_UNAVAILABLE" });
    const validation = validateSurveyPayload(published.definition, body.answers ?? {}, { submissionId: body.submissionId });
    if (!validation.valid || body.consent?.accepted !== true) return json(origin, 422, { error: "Complete every required answer and consent before submitting.", code: "SURVEY_ANSWERS_INVALID", fields: validation.errors });
    result = await client.rpc("rpc_aoi_public_survey_submit", {
      p_token: token,
      p_invitation_token: body.invitationToken || null,
      p_submission_id: body.submissionId,
      p_resume_token: body.resumeToken,
      p_answers: validation.answers,
      p_idempotency_key: body.idempotencyKey,
      p_score: validation.score,
      p_consent: body.consent ?? {},
    });
  } else {
    if (!published) return json(origin, 404, { error: "This survey link is unavailable.", code: "SURVEY_LINK_UNAVAILABLE" });
    const upload = normalizeUploadMetadata(String(body.fileName || ""), String(body.contentType || ""));
    if (!upload || !allowedUploadTypes.has(upload.contentType)) return json(origin, 400, { error: "This file type or extension is not allowed." });
    const uploadQuestion = (published.definition as { blocks?: Array<{ blocks?: Array<{ id?: string; type?: string }> }> }).blocks?.flatMap((section) => section.blocks ?? []).find((question) => question.id === body.questionId);
    if (uploadQuestion?.type !== "upload") return json(origin, 400, { error: "This upload field is unavailable." });
    const validation = await client.rpc("rpc_aoi_public_survey_upload_authorize", {
      p_token: token,
      p_invitation_token: body.invitationToken || null,
      p_submission_id: body.submissionId,
      p_resume_token: body.resumeToken,
    });
    if (validation.error) result = validation;
    else {
      const path = `${validation.data.submissionId}/${body.questionId}/${crypto.randomUUID()}-${upload.fileName}`;
      const signed = await client.storage.from("aoi-survey-uploads").createSignedUploadUrl(path);
      result = signed.error ? { data: null, error: signed.error } : { data: { path, token: signed.data.token, signedUrl: signed.data.signedUrl, fileName: upload.fileName, contentType: upload.contentType }, error: null };
    }
  }

  if (result.error) {
    const error = publicError(result.error.message);
    return json(origin, error.status, { error: error.message, code: error.code });
  }
  return json(origin, 200, { data: result.data });
});
