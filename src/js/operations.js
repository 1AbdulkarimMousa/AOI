import { csvCell } from "./core.js";

const fields = [
  ["externalId", ["id", "external id"]],
  ["category", ["category"]],
  ["name", ["handle / name", "handle/name", "name", "handle"]],
  ["platforms", ["primary platform", "platforms", "platform"]],
  ["reach", ["reach", "reach / evidence", "followers"]],
  ["tier", ["tier"]],
  ["contactReadiness", ["contact readiness"]],
  ["contactChannel", ["contact channel"]],
  ["contactDetail", ["contact detail"]],
  ["sourceUrl", ["source url"]],
  ["pmfCandidate", ["pmf candidate"]],
  ["ownerName", ["owner"]],
  ["outreachStatus", ["outreach status", "status"]],
  ["firstOutreach", ["first outreach"]],
  ["nextStepDue", ["next step due"]],
];

function normalizeHeader(value) {
  return String(value || "").trim().replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase().replaceAll("_", " ");
}

function splitDelimitedLine(line, delimiter) {
  const cells = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === delimiter && !quoted) {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += character;
    }
  }
  cells.push(cell.trim());
  return cells;
}

function parseDelimited(text) {
  const lines = String(text || "").replace(/^\uFEFF/, "").split(/\r?\n/).filter((line) => line.trim());
  if (!lines.length) return [];
  const delimiter = lines[0].includes("\t") ? "\t" : ",";
  return lines.map((line) => splitDelimitedLine(line, delimiter));
}

function valueFor(row, headerIndex, aliases) {
  const index = Object.entries(headerIndex).find(([, header]) => aliases.includes(header))?.[0];
  return index === undefined ? "" : String(row[Number(index)] || "").trim();
}

function booleanValue(value) {
  return ["yes", "true", "1", "y"].includes(String(value).toLowerCase());
}

export function parseCandidateImport(text) {
  const cleanText = String(text || "").replace(/^\uFEFF/, "").trim();
  if (cleanText.startsWith("[") || cleanText.startsWith("{")) {
    try {
      const parsed = JSON.parse(cleanText);
      const records = Array.isArray(parsed) ? parsed : parsed.candidates;
      if (!Array.isArray(records)) return { rows: [], errors: ["JSON must contain an array of candidate records."] };
      const matrix = [fields.map(([key]) => key), ...records.map((record) => fields.map(([key]) => record[key] ?? ""))];
      const normalized = parseCandidateImport(matrix.map((row) => row.join("\t")).join("\n"));
      return normalized;
    } catch {
      return { rows: [], errors: ["The JSON file could not be parsed."] };
    }
  }
  const matrix = parseDelimited(cleanText);
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
    rows.push({
      externalId: valueFor(raw, headerIndex, fields[0][1]),
      category: valueFor(raw, headerIndex, fields[1][1]),
      name,
      platforms: valueFor(raw, headerIndex, fields[3][1]),
      reach: valueFor(raw, headerIndex, fields[4][1]),
      tier: valueFor(raw, headerIndex, fields[5][1]),
      contactReadiness: valueFor(raw, headerIndex, fields[6][1]),
      contactChannel: valueFor(raw, headerIndex, fields[7][1]),
      contactDetail: valueFor(raw, headerIndex, fields[8][1]),
      sourceUrl: valueFor(raw, headerIndex, fields[9][1]),
      pmfCandidate: booleanValue(valueFor(raw, headerIndex, fields[10][1])),
      ownerName: valueFor(raw, headerIndex, fields[11][1]),
      outreachStatus: valueFor(raw, headerIndex, fields[12][1]),
      firstOutreach: valueFor(raw, headerIndex, fields[13][1]),
      nextStepDue: valueFor(raw, headerIndex, fields[14][1]),
    });
  });

  return { rows, errors };
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
