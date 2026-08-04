import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

import {
  csvCell,
  initials,
  pageUrl,
  readableError,
  routeForRole,
  scopePreviewDashboard,
} from "../src/js/core.js";

const root = new URL("../", import.meta.url);

test("defines all five static application entry pages", async () => {
  const entries = ["index.html", "login.html", "workspace.html", "interns.html", "administration.html"];
  const missing = [];

  for (const entry of entries) {
    try {
      await access(new URL(entry, root));
    } catch {
      missing.push(entry);
    }
  }

  assert.deepEqual(missing, []);
});

test("uses the static Alpine, Supabase, and Tailwind runtime", async () => {
  const pkg = JSON.parse(await readFile(new URL("package.json", root), "utf8"));

  assert.equal(pkg.scripts.build, "vite build");
  assert.ok(pkg.dependencies.alpinejs);
  assert.ok(pkg.dependencies["@supabase/supabase-js"]);
  assert.ok(pkg.dependencies.lucide);
  assert.ok(pkg.devDependencies.tailwindcss);
  assert.equal(pkg.dependencies.react, undefined);
  assert.equal(pkg.dependencies.next, undefined);
  assert.equal(pkg.dependencies.vinext, undefined);
});

test("configures Vite as a repository-relative multi-page build", async () => {
  const config = await readFile(new URL("vite.config.js", root), "utf8");

  assert.match(config, /base:\s*process\.env\.GITHUB_ACTIONS\s*\?\s*["']\/AOI\/["']/);
  assert.match(config, /index:\s*resolve/);
  assert.match(config, /login:\s*resolve/);
  assert.match(config, /workspace:\s*resolve/);
  assert.match(config, /interns:\s*resolve/);
  assert.match(config, /administration:\s*resolve/);
});

test("builds repository-relative page URLs", () => {
  assert.equal(pageUrl("/AOI/", "login.html"), "/AOI/login.html");
  assert.equal(pageUrl("/", "workspace.html"), "/workspace.html");
  assert.equal(pageUrl("/AOI", "/interns.html"), "/AOI/interns.html");
});

test("routes each workspace role to its protected page", () => {
  assert.equal(routeForRole("admin"), "workspace.html");
  assert.equal(routeForRole("intern"), "interns.html");
  assert.equal(routeForRole("unknown"), "login.html");
});

test("protects CSV exports from spreadsheet formulas", () => {
  assert.equal(csvCell("=IMPORTXML('bad')"), '"\'=IMPORTXML(\'bad\')"');
  assert.equal(csvCell('Research "signal"'), '"Research ""signal"""');
  assert.equal(csvCell(null), '""');
});

test("normalizes initials and known administrator errors", () => {
  assert.equal(initials("  Lina Chen "), "LC");
  assert.equal(initials(""), "AO");
  assert.equal(readableError(new Error("TASK_TITLE_REQUIRED"), "Fallback"), "Enter a task title with at least three characters.");
  assert.equal(readableError("bad", "Fallback"), "Fallback");
});

test("scopes synthetic intern previews to the selected intern", () => {
  const dashboard = {
    tasks: [
      { id: "1", ownerName: "Kayla Tillmon" },
      { id: "2", ownerName: "Wen Tang" },
    ],
    candidates: [
      { id: "c1", ownerName: "Kayla Tillmon" },
      { id: "c2", ownerName: "Wen Tang" },
    ],
    evidenceRecords: [
      { id: "e1", candidateId: "c1" },
      { id: "e2", candidateId: "c2" },
    ],
    dailyEod: { serverDate: "2026-08-04", teamToday: [], myBrief: null },
    dailyEodReportItems: [
      { id: "b1", authorName: "Kayla Tillmon", briefDate: "2026-08-04", workflowStatus: "submitted" },
      { id: "b2", authorName: "Wen Tang", briefDate: "2026-08-04", workflowStatus: "completed" },
    ],
  };

  assert.equal(scopePreviewDashboard(dashboard, "admin", "AOI Administrator").tasks.length, 2);
  assert.deepEqual(scopePreviewDashboard(dashboard, "intern", "Kayla Tillmon").tasks.map((task) => task.id), ["1"]);
  assert.deepEqual(scopePreviewDashboard(dashboard, "intern", "Kayla Tillmon").candidates.map((candidate) => candidate.id), ["c1"]);
  assert.deepEqual(scopePreviewDashboard(dashboard, "intern", "Kayla Tillmon").evidenceRecords.map((record) => record.id), ["e1"]);
  assert.deepEqual(scopePreviewDashboard(dashboard, "intern", "Kayla Tillmon").dailyEodReportItems.map((record) => record.id), ["b1"]);
  assert.equal(scopePreviewDashboard(dashboard, "intern", "Kayla Tillmon").dailyEod.myBrief.id, "b1");
  assert.equal(dashboard.tasks.length, 2);
});

test("wires every entry page to its Alpine controller", async () => {
  const [landing, login, workspace, interns, administration] = await Promise.all([
    readFile(new URL("index.html", root), "utf8"),
    readFile(new URL("login.html", root), "utf8"),
    readFile(new URL("workspace.html", root), "utf8"),
    readFile(new URL("interns.html", root), "utf8"),
    readFile(new URL("administration.html", root), "utf8"),
  ]);

  assert.match(landing, /data-page="landing"/);
  assert.match(landing, /x-data="landingPage"/);
  assert.doesNotMatch(landing, /http-equiv="refresh"/i);
  assert.match(login, /data-page="login"/);
  assert.match(login, /x-data="loginPage"/);
  assert.doesNotMatch(login, /http-equiv="refresh"/i);
  assert.match(workspace, /data-page="workspace"/);
  assert.match(workspace, /data-expected-role="admin"/);
  assert.match(interns, /data-page="workspace"/);
  assert.match(interns, /data-expected-role="intern"/);
  assert.match(administration, /data-page="administration"/);
  assert.match(administration, /data-expected-role="admin"/);
});

test("keeps Supabase access behind authenticated RPCs and an Edge Function", async () => {
  const api = await readFile(new URL("src/js/api.js", root), "utf8");
  const auth = await readFile(new URL("src/js/auth.js", root), "utf8");

  assert.match(api, /rpc\("rpc_aoi_demo_dashboard"\)/);
  assert.match(api, /rpc\("rpc_admin_list_users"\)/);
  assert.match(api, /rpc\("rpc_admin_create_task_v2"/);
  assert.match(api, /functions\.invoke\("admin-create-user"/);
  assert.match(auth, /rpc\("rpc_current_user_context"\)/);
  assert.match(auth, /await signOut\(\)/);
  assert.doesNotMatch(api + auth, /service[_-]?role/i);
});

test("ships role-aware workspace, localization, theme, and CSV behavior", async () => {
  const [controller, template, crmTemplate, styles] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/crm-template.js", root), "utf8"),
    readFile(new URL("src/css/aoi.css", root), "utf8"),
  ]);
  const workspaceMarkup = template + crmTemplate;

  assert.match(controller, /expectedRole/);
  assert.match(controller, /routeForRole/);
  assert.match(controller, /localStorage\.setItem\("aoi-locale"/);
  assert.match(controller, /localStorage\.setItem\("aoi-theme"/);
  assert.match(controller, /downloadCsv/);
   assert.match(template, /Overview/);
   assert.match(workspaceMarkup, /Today/);
   assert.match(workspaceMarkup, /CRM/);
  assert.match(template, /My work/);
  assert.match(template, /Research ops/);
  assert.match(template, /PMF validation/);
  assert.match(template, /Reports/);
  assert.match(template, /Team momentum/);
  assert.match(controller, /administration\.html/);
  assert.match(template, /class="admin-nav-group"/);
  assert.match(styles, /\.admin-nav-group\s*>\s*button/);
});

test("secures administrator user creation in a Supabase Edge Function", async () => {
  const [source, config] = await Promise.all([
    readFile(new URL("supabase/functions/admin-create-user/index.ts", root), "utf8"),
    readFile(new URL("supabase/config.toml", root), "utf8"),
  ]);

  assert.match(source, /Deno\.serve/);
  assert.match(source, /auth\.getClaims\(token\)/);
  assert.match(source, /organization_memberships/);
  assert.match(source, /\.eq\("role", "admin"\)/);
  assert.match(source, /\.eq\("status", "active"\)/);
  assert.match(source, /auth\.admin\.createUser/);
  assert.match(source, /auth\.admin\.deleteUser/);
  assert.match(source, /ALLOWED_ORIGINS/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin":\s*"\*"/);
  assert.match(config, /\[functions\.admin-create-user\]/);
  assert.match(config, /verify_jwt\s*=\s*false/);
});

test("includes the persisted outreach, evidence, and email operation contracts", async () => {
  const [api, template, operations, migration, emailMigration] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/operations.js", root), "utf8"),
    readFile(new URL("supabase/migrations/202608040001_outreach_operations.sql", root), "utf8"),
    readFile(new URL("supabase/migrations/202608040002_email_automation.sql", root), "utf8"),
  ]);

  assert.match(template, /KOL outreach command center/);
  assert.match(template, /Evidence & consent ledger/);
  assert.match(template, /Data portability/);
  assert.match(operations, /parseCandidateImport/);
  assert.match(operations, /buildRecommendations/);
  assert.match(api, /rpc_aoi_operations_snapshot/);
  assert.match(migration, /create table if not exists public\.candidates/);
  assert.match(migration, /rpc_aoi_upsert_candidate/);
  assert.match(migration, /audit_events/);
  assert.match(emailMigration, /email_deliveries/);
  assert.match(emailMigration, /ADMIN_APPROVAL_REQUIRED/);
});

test("ships persisted PMF collection, review, matrix, Gate, and private media workflows", async () => {
  const [api, controller, workspaceTemplate, pmfTemplate] = await Promise.all([
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/pmf-template.js", root), "utf8"),
  ]);
  const template = workspaceTemplate + pmfTemplate;

  assert.match(api, /rpc\("rpc_aoi_pmf_snapshot"\)/);
  assert.match(api, /rpc\("rpc_aoi_save_research_record"/);
  assert.match(api, /rpc\("rpc_aoi_review_research_record"/);
  assert.match(api, /rpc\("rpc_aoi_import_candidates"/);
  assert.match(api, /rpc\("rpc_aoi_create_gate_snapshot"/);
  assert.match(api, /\.storage\.from\(bucketId\)\.upload/);
  assert.match(controller, /validateResearchRecord/);
  assert.match(controller, /buildLayerMatrices/);
  assert.match(controller, /saveResearchRecord/);
  assert.match(controller, /reviewResearchRecord/);
  assert.match(template, /Guided collection/);
  assert.match(template, /Review queue/);
  assert.match(template, /Segment comparison matrix/);
  assert.match(template, /Prepare Gate snapshot/);
});

test("deploys only the static dist directory to GitHub Pages", async () => {
  const workflow = await readFile(new URL(".github/workflows/pages.yml", root), "utf8");

  assert.match(workflow, /actions\/configure-pages@v5/);
  assert.match(workflow, /actions\/upload-pages-artifact@v3/);
  assert.match(workflow, /actions\/deploy-pages@v4/);
  assert.match(workflow, /path:\s*dist/);
  assert.match(workflow, /VITE_SUPABASE_URL:\s*\$\{\{ vars\.VITE_SUPABASE_URL \}\}/);
  assert.match(workflow, /VITE_SUPABASE_PUBLISHABLE_KEY:\s*\$\{\{ vars\.VITE_SUPABASE_PUBLISHABLE_KEY \}\}/);
  assert.doesNotMatch(workflow, /SERVICE_ROLE/);
});

test("removes obsolete server-rendered and Cloudflare runtimes", async () => {
  const obsolete = [
    "app",
    "build",
    "db",
    "drizzle",
    "examples",
    "worker",
    ".openai",
    "next.config.ts",
    "drizzle.config.ts",
    "postcss.config.mjs",
    "worker-configuration.d.ts",
    "tsconfig.json",
    "public/index.html",
    "public/login.html",
  ];
  const remaining = [];

  for (const path of obsolete) {
    try {
      await access(new URL(path, root));
      remaining.push(path);
    } catch {
      // Expected: obsolete runtime path does not exist.
    }
  }

  assert.deepEqual(remaining, []);
});
