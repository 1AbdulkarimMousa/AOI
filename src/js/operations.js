import { csvCell, isSafeHttpUrl } from "./core.js";
import readXlsxFile from "read-excel-file";

const fields = [
  ["externalId", ["id", "external id"]],
  ["source", ["source"]],
  ["category", ["category"]],
  ["name", ["handle / name", "handle/name", "name", "handle"]],
  ["platforms", ["primary platform", "platforms", "platform"]],
  ["reach", ["reach", "reach / evidence", "followers"]],
  ["tier", ["tier"]],
  ["creatorType", ["creator type"]],
  ["contentFit", ["content fit", "fit"]],
  ["fitLevel", ["fit level"]],
  ["contactReadiness", ["contact readiness"]],
  ["contactChannel", ["contact channel"]],
  ["contactDetail", ["contact detail"]],
  ["sourceUrl", ["source url"]],
  ["pmfCandidate", ["pmf candidate"]],
  ["pmfRationale", ["pmf rationale"]],
  ["priorityScore", ["priority score"]],
  ["priorityBand", ["priority band"]],
  ["ownerName", ["owner", "owner name"]],
  ["outreachStatus", ["outreach status", "status"]],
  ["interestLevel", ["interest level"]],
  ["preferredCollaboration", ["preferred collaboration"]],
  ["deckIntroduced", ["deck introduced"]],
  ["pmfAsked", ["pmf asked"]],
  ["firstOutreach", ["first outreach"]],
  ["followUp1", ["follow up 1", "follow-up 1"]],
  ["followUp2", ["follow up 2", "follow-up 2"]],
  ["responseDate", ["response date"]],
  ["nextStep", ["next step"]],
  ["nextStepDue", ["next step due"]],
  ["notes", ["notes"]],
  ["sourceUpdatedOn", ["source updated on"]],
];

const legacyOutputKeys = new Set(["externalId", "category", "name", "platforms", "reach", "tier", "contactReadiness", "contactChannel", "contactDetail", "sourceUrl", "pmfCandidate", "ownerName", "outreachStatus", "firstOutreach", "nextStepDue"]);
const booleanFields = new Set(["pmfCandidate", "deckIntroduced", "pmfAsked"]);

function normalizeHeader(value) {
  return String(value || "").trim().replace(/([a-z])([A-Z])/g, "$1 $2").replace(/([A-Za-z])(\d)/g, "$1 $2").toLowerCase().replaceAll("_", " ");
}

function parseDelimited(text) {
  const source = String(text || "").replace(/^\uFEFF/, "");
  if (!source.trim()) return [];
  const firstLineEnd = source.search(/\r?\n/);
  const firstLine = firstLineEnd === -1 ? source : source.slice(0, firstLineEnd);
  const delimiter = firstLine.includes("\t") ? "\t" : ",";
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '"') {
      if (quoted && source[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === delimiter && !quoted) {
      row.push(cell.trim());
      cell = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && source[index + 1] === "\n") index += 1;
      row.push(cell.trim());
      if (row.some((value) => value !== "")) rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += character;
    }
  }
  row.push(cell.trim());
  if (row.some((value) => value !== "")) rows.push(row);
  return rows;
}

function valueFor(row, headerIndex, aliases) {
  const index = Object.entries(headerIndex).find(([, header]) => aliases.includes(header))?.[0];
  return index === undefined ? "" : String(row[Number(index)] || "").trim();
}

function hasField(headerIndex, aliases) {
  return Object.values(headerIndex).some((header) => aliases.includes(header));
}

function booleanValue(value) {
  return ["yes", "true", "1", "y"].includes(String(value).toLowerCase());
}

function parseCandidateMatrix(matrix) {
  if (!matrix.length) return { rows: [], errors: ["The import file is empty."] };
  const headerIndex = Object.fromEntries(matrix[0].map((value, index) => [index, normalizeHeader(value)]));
  const rows = [];
  const errors = [];

  matrix.slice(1).forEach((raw, offset) => {
    const line = offset + 2;
    const name = valueFor(raw, headerIndex, fields.find(([key]) => key === "name")[1]);
    if (!name) {
      errors.push(`Row ${line}: Handle / Name is required.`);
      return;
    }
    const candidate = {};
    for (const [key, aliases] of fields) {
      if (!legacyOutputKeys.has(key) && !hasField(headerIndex, aliases)) continue;
      const value = key === "name" ? name : valueFor(raw, headerIndex, aliases);
      candidate[key] = booleanFields.has(key) ? booleanValue(value) : key === "priorityScore" && value !== "" ? Number(value) : value;
    }
    if (candidate.sourceUrl && !isSafeHttpUrl(candidate.sourceUrl)) {
      errors.push(`Row ${line}: Source URL must use http or https.`);
      return;
    }
    rows.push(candidate);
  });

  return { rows, errors };
}

export function parseCandidateImport(text) {
  const cleanText = String(text || "").replace(/^\uFEFF/, "").trim();
  if (cleanText.startsWith("[") || cleanText.startsWith("{")) {
    try {
      const parsed = JSON.parse(cleanText);
      const records = Array.isArray(parsed) ? parsed : parsed.candidates;
      if (!Array.isArray(records)) return { rows: [], errors: ["JSON must contain an array of candidate records."] };
      return parseCandidateMatrix([
        fields.map(([key]) => key),
        ...records.map((record) => fields.map(([key]) => record[key] ?? "")),
      ]);
    } catch {
      return { rows: [], errors: ["The JSON file could not be parsed."] };
    }
  }
  return parseCandidateMatrix(parseDelimited(cleanText));
}

export async function parseCandidateFile(file, { readXlsx = readXlsxFile } = {}) {
  const extension = String(file?.name || "").split(".").pop().toLowerCase();
  if (extension === "xlsx") {
    const result = parseCandidateMatrix(await readXlsx(file));
    return { ...result, fileFormat: "xlsx" };
  }
  const text = await file.text();
  const result = parseCandidateImport(text);
  const fileFormat = extension === "json" ? "json" : text.includes("\t") ? "tsv" : "csv";
  return { ...result, fileFormat };
}

export function buildCandidateExport(candidates) {
  const keys = fields.map(([key]) => key);
  const csv = `\uFEFF${keys.join(",")}\r\n${candidates.map((candidate) => keys.map((key) => csvCell(candidate[key])).join(",")).join("\r\n")}`;
  return { csv, json: JSON.stringify(candidates, null, 2) };
}

export function buildRecommendations(input) {
  const recommendations = [];
  const requiredPool = Math.ceil((input.planningTarget || input.targetHigh) / input.conversionRate);
  const poolGap = Math.max(0, requiredPool - input.totalCandidates);
  const confirmationGap = Math.max(0, input.targetLow - input.confirmed);
  if (poolGap) {
    recommendations.push({
      id: "pool-gap",
      type: "pipeline",
      priority: "critical",
      title: "Rebuild the active prospect pool",
      reason: `${requiredPool} active prospects are needed at the assumed ${Math.round(input.conversionRate * 100)}% conversion rate; the current pool has ${input.totalCandidates}.`,
      action: `Add ${poolGap} qualified prospects before sending the next wave.`,
    });
  }
  if (confirmationGap) {
    recommendations.push({
      id: "confirmation-gap",
      type: "deadline",
      priority: "critical",
      title: "Protect the confirmation deadline",
      reason: `${confirmationGap} low-target confirmations are still missing for ${input.deadline}.`,
      action: "Prioritize high-score, contact-ready candidates and assign a dated follow-up.",
    });
  }
  input.categories.filter((category) => category.confirmed === 0 && category.contactReady < category.candidates).forEach((category) => {
    recommendations.push({
      id: `category-${category.name}`,
      type: "category",
      priority: "high",
      title: `Enrich ${category.name} coverage`,
      reason: `${category.candidates - category.contactReady} records in this category still need a verified contact route.`,
      action: "Assign contact research and require a source URL before outreach.",
    });
  });
  return recommendations;
}
