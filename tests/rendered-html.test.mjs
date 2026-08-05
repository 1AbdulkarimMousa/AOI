import assert from "node:assert/strict";
import { access, readdir, readFile, stat } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const dist = new URL("../dist/", import.meta.url);

test("builds the AOI landing, login, workspace, administration, intern, and Help Center pages", async () => {
  const pages = await Promise.all([
    readFile(new URL("index.html", dist), "utf8"),
    readFile(new URL("login.html", dist), "utf8"),
    readFile(new URL("workspace.html", dist), "utf8"),
    readFile(new URL("interns.html", dist), "utf8"),
    readFile(new URL("administration.html", dist), "utf8"),
    readFile(new URL("helpcenter.html", dist), "utf8"),
  ]);
  const [landing, login, workspace, interns, administration, helpcenter] = pages;

  assert.match(landing, /<title>Ambiloop Ops \| Evidence to PMF Decisions<\/title>/i);
  assert.match(landing, /data-page="landing"/);
  assert.match(login, /Welcome back to the evidence trail/);
  assert.match(login, /Protected sign-in/);
  assert.match(workspace, /data-expected-role="admin"/);
  assert.match(interns, /data-expected-role="intern"/);
  assert.match(administration, /data-page="administration"/);
  assert.match(helpcenter, /data-page="helpcenter"/);
  assert.doesNotMatch(pages.join(""), /http-equiv="refresh"|__next|react-server-dom/i);
});

test("copies public assets and excludes browser secrets", async () => {
  await Promise.all([
    access(new URL("og-landing-v2.png", dist)),
    access(new URL("favicon.svg", dist)),
  ]);

  const assetNames = await readdir(new URL("assets/", dist));
  const javascript = await Promise.all(
    assetNames.filter((name) => name.endsWith(".js")).map((name) => readFile(new URL(`assets/${name}`, dist), "utf8")),
  );

  assert.doesNotMatch(javascript.join("\n"), /SUPABASE_SERVICE_ROLE_KEY|your-server-only-service-role-key/);
});

test("keeps every browser JavaScript chunk below 300 kB", async () => {
  const assetNames = await readdir(new URL("assets/", dist));
  const sizes = await Promise.all(
    assetNames.filter((name) => name.endsWith(".js")).map(async (name) => [name, (await stat(new URL(`assets/${name}`, dist))).size]),
  );
  const oversized = sizes.filter(([, size]) => size > 300_000);

  assert.deepEqual(oversized, []);
});

test("keeps environment examples public-client safe", async () => {
  const example = await readFile(new URL(".env.example", root), "utf8");
  assert.match(example, /VITE_SUPABASE_URL/);
  assert.match(example, /VITE_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(example, /NEXT_PUBLIC_/);
  assert.doesNotMatch(example, /SUPABASE_SERVICE_ROLE_KEY/);
});
