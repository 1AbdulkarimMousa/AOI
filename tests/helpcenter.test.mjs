import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import {
  HELP_CENTER_ARTICLES,
  filterHelpArticles,
  searchHelpArticles,
  validateArticle,
} from "../src/js/helpcenter-data.js";

const root = new URL("../", import.meta.url);

test("seeds a bilingual PMF help library without synthetic research evidence", () => {
  assert.ok(HELP_CENTER_ARTICLES.length >= 8);
  assert.ok(HELP_CENTER_ARTICLES.every((article) => article.title.en && article.title.zh));
  assert.ok(HELP_CENTER_ARTICLES.every((article) => article.summary.en && article.summary.zh));
  assert.ok(HELP_CENTER_ARTICLES.every((article) => article.status === "published"));
  assert.ok(HELP_CENTER_ARTICLES.every((article) => !JSON.stringify(article).match(/respondent|interviewed|actual evidence/i)));
});

test("validates safe structured bilingual article blocks", () => {
  const article = {
    slug: "example",
    title: { en: "Example", zh: "示例" },
    summary: { en: "Summary", zh: "摘要" },
    body: {
      en: [{ type: "steps", title: "Steps", items: ["One", "Two"] }],
      zh: [{ type: "steps", title: "步骤", items: ["一", "二"] }],
    },
    category: "method",
    pmfLayer: "H1",
    audience: ["admin", "intern"],
    tags: ["need truth"],
  };

  assert.deepEqual(validateArticle(article), []);
  assert.match(validateArticle({ ...article, title: { en: "", zh: "示例" } }).join(" "), /English title/);
  assert.match(validateArticle({ ...article, body: { en: [{ type: "html", html: "<script>bad<\/script>" }], zh: article.body.zh } }).join(" "), /block type/);
});

test("searches bilingual article content and applies PMF filters", () => {
  const articles = [
    { slug: "h1", title: { en: "Need Truth", zh: "需求真实性" }, summary: { en: "Real jobs", zh: "真实任务" }, tags: ["H1"], category: "method", pmfLayer: "H1", status: "published" },
    { slug: "h5", title: { en: "Value Exchange", zh: "价值交换" }, summary: { en: "Price", zh: "价格" }, tags: ["pricing"], category: "method", pmfLayer: "H5", status: "published" },
    { slug: "draft", title: { en: "Draft", zh: "草稿" }, summary: { en: "Hidden", zh: "隐藏" }, tags: [], category: "method", pmfLayer: "H1", status: "draft" },
  ];

  assert.deepEqual(searchHelpArticles(articles, "真实性").map((article) => article.slug), ["h1"]);
  assert.deepEqual(filterHelpArticles(articles, { pmfLayer: "H5" }).map((article) => article.slug), ["h5"]);
  assert.deepEqual(filterHelpArticles(articles, { status: "published" }).map((article) => article.slug), ["h1", "h5"]);
});

test("wires the authenticated Help Center entry point and migration", async () => {
  const page = await readFile(new URL("helpcenter.html", root), "utf8");
  const config = await readFile(new URL("vite.config.js", root), "utf8");
  const controller = await readFile(new URL("src/js/helpcenter.js", root), "utf8");
  const migrations = await readdir(new URL("supabase/migrations/", root));
  const migrationNames = migrations.filter((name) => name.includes("help_center"));
  assert.ok(migrationNames.length, "Help Center migration must exist");
  const originalMigration = await readFile(new URL("supabase/migrations/20260805062711_help_center_library.sql", root), "utf8");
  const scopeMigration = await readFile(new URL("supabase/migrations/20260805143000_help_center_library.sql", root), "utf8");
  const migration = `${originalMigration}\n${scopeMigration}`;

  assert.match(page, /data-page="helpcenter"/);
  assert.match(page, /data-expected-role="(admin|intern)"/);
  assert.match(config, /helpcenter:\s*resolve/);
  assert.match(originalMigration, /create table if not exists public\.help_center_articles/);
  assert.doesNotMatch(originalMigration, /project_id/);
  assert.match(scopeMigration, /add column if not exists project_id/);
  assert.match(scopeMigration, /membership\.role = any\(help_center_articles\.audience\)/);
  assert.match(scopeMigration, /v_role = any\(article\.audience\)/);
  assert.match(controller, /saved\.status !== targetStatus[\s\S]*setHelpArticleStatus\(saved\.id, targetStatus, saved\.version\)/);
  assert.match(controller, /catch \(statusReason\)[\s\S]*this\.editorDraft = structuredClone\(saved\)/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on function public\.rpc_aoi_help_center_snapshot/);
  assert.match(migration, /grant execute on function public\.rpc_aoi_help_center_snapshot\(\) to authenticated/);
  assert.match(migration, /is_org_admin/);
});

test("keeps article selection synchronized with browser history", async () => {
  const [controller, template] = await Promise.all([
    readFile(new URL("src/js/helpcenter.js", root), "utf8"),
    readFile(new URL("src/js/helpcenter-template.js", root), "utf8"),
  ]);

  assert.match(controller, /window\.history\.pushState/);
  assert.match(controller, /addEventListener\("popstate"/);
  assert.match(controller, /closeArticle/);
  assert.match(controller, /searchParams\.delete\("article"\)/);
  assert.match(template, /@click="closeArticle\(\)"/);
});

test("supports global search shortcuts and every accepted reader block", async () => {
  const template = await readFile(new URL("src/js/helpcenter-template.js", root), "utf8");

  assert.match(template, /@keydown\.window\.k="handleSearchShortcut\(\$event\)"/);
  assert.match(template, /block\.type==='faq'/);
  assert.match(template, /block\.type==='related_article'/);
  assert.match(template, /selectArticleBySlug\(slug\)/);
});

test("reports publication success after closing and renders accurate featured status", async () => {
  const [controller, template] = await Promise.all([
    readFile(new URL("src/js/helpcenter.js", root), "utf8"),
    readFile(new URL("src/js/helpcenter-template.js", root), "utf8"),
  ]);

  assert.match(controller, /publicationNotice/);
  assert.match(controller, /Article published\./);
  assert.match(template, /x-show="publicationNotice"[^>]*role="status"/);
  assert.match(template, /:class="statusClass\(article\.status\)" x-text="article\.status"/);
});

test("gives Help editor tabs and modal complete keyboard semantics", async () => {
  const [controller, template] = await Promise.all([
    readFile(new URL("src/js/helpcenter.js", root), "utf8"),
    readFile(new URL("src/js/helpcenter-template.js", root), "utf8"),
  ]);

  assert.match(template, /role="tablist" aria-label="Help Center categories"/);
  assert.match(template, /role="tab"[^>]*:aria-selected="category==='all'"/);
  assert.match(template, /:inert="editorOpen"/);
  assert.match(template, /@keydown\.window\.tab="trapEditorFocus\(\$event\)"/);
  assert.match(controller, /editorReturnFocus/);
  assert.match(controller, /trapEditorFocus/);
  assert.match(controller, /returnFocus\?\.focus/);
});
