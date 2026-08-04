export function pageUrl(base, page) {
  const normalizedBase = `/${String(base || "/").replace(/^\/+|\/+$/g, "")}`;
  const prefix = normalizedBase === "/" ? "" : normalizedBase;
  return `${prefix}/${String(page).replace(/^\/+/, "")}`;
}

export function routeForRole(role) {
  if (role === "admin") return "workspace.html";
  if (role === "intern") return "interns.html";
  return "login.html";
}

export function csvCell(value) {
  let text = String(value ?? "");
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export function initials(name) {
  return String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("") || "AO";
}

export function readableError(reason, fallback) {
  if (!(reason instanceof Error)) return fallback;
  const value = reason.message;
  if (value.includes("TASK_TITLE_REQUIRED")) return "Enter a task title with at least three characters.";
  if (value.includes("ADMIN_REQUIRED")) return "Your administrator access could not be verified.";
  if (value.includes("ASSIGNEE_INVALID")) return "Choose an active AOI user for this task.";
  if (value.toLowerCase().includes("invalid login")) return "The email or password is incorrect.";
  return value || fallback;
}

export function clamp(value, min = 0, max = 100) {
  return Math.min(max, Math.max(min, Number(value) || 0));
}

export function scopePreviewDashboard(dashboard, role, displayName) {
  const copy = structuredClone(dashboard);
  if (role === "intern") copy.tasks = copy.tasks.filter((task) => task.ownerName === displayName);
  return copy;
}
