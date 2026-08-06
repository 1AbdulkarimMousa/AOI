import { csvCell } from "../core.js";
import { surveyQuestions, validateSurveyDefinition } from "./domain.js";

async function sha256(value) {
  const data = new globalThis.TextEncoder().encode(value);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function exportSurveyPackage({ definition, name, metadata = {} }) {
  const validation = validateSurveyDefinition(definition);
  if (!validation.valid) throw new Error("SURVEY_DEFINITION_INVALID");
  const payload = { format: "aoi-survey", packageVersion: 1, name, metadata, definition };
  const checksum = await sha256(JSON.stringify(payload));
  return JSON.stringify({ ...payload, checksum }, null, 2);
}

export async function importSurveyPackage(source) {
  let parsed;
  try { parsed = JSON.parse(source); } catch { throw new Error("SURVEY_PACKAGE_INVALID"); }
  if (parsed?.format !== "aoi-survey" || parsed.packageVersion !== 1 || !parsed.checksum) throw new Error("SURVEY_PACKAGE_INVALID");
  const { checksum, ...payload } = parsed;
  if (await sha256(JSON.stringify(payload)) !== checksum) throw new Error("SURVEY_PACKAGE_CHECKSUM_INVALID");
  if (!validateSurveyDefinition(parsed.definition).valid) throw new Error("SURVEY_DEFINITION_INVALID");
  return payload;
}

function valueForCsv(value) {
  if (Array.isArray(value)) return value.join(" | ");
  if (value && typeof value === "object") return JSON.stringify(value);
  return value ?? "";
}

export function buildResponseCsv(definition, submissions = []) {
  const questions = surveyQuestions(definition);
  const columns = ["submissionId", "status", ...questions.map((question) => question.id)];
  const rows = submissions.map((submission) => columns.map((column) => {
    if (column === "submissionId") return csvCell(submission.submissionId);
    if (column === "status") return csvCell(submission.status);
    return csvCell(valueForCsv(submission.answers?.[column]));
  }).join(","));
  const codebookRows = questions.map((question) => [
    question.id,
    question.type,
    question.title?.en || "",
    question.title?.zh || "",
    question.required ? "yes" : "no",
  ].map(csvCell).join(","));
  return {
    wide: `\uFEFF${columns.join(",")}\r\n${rows.join("\r\n")}`,
    codebook: `\uFEFFquestionId,type,titleEn,titleZh,required\r\n${codebookRows.join("\r\n")}`,
  };
}
