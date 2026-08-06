import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships a dedicated public survey runner entry", async () => {
  await access(new URL("survey.html", root));
  const [html, app, config, runner, template] = await Promise.all([
    readFile(new URL("survey.html", root), "utf8"),
    readFile(new URL("src/js/app.js", root), "utf8"),
    readFile(new URL("vite.config.js", root), "utf8"),
    readFile(new URL("src/js/surveys/runner.js", root), "utf8"),
    readFile(new URL("src/js/surveys/runner-template.js", root), "utf8"),
  ]);

  assert.match(html, /data-page="survey"/);
  assert.match(html, /id="survey-app"/);
  assert.match(app, /page === "survey"/);
  assert.match(config, /survey:\s*resolve/);
  assert.match(runner, /registerSurveyRunner/);
  assert.match(runner, /localStorage/);
  assert.match(template, /aria-live="polite"/);
  assert.match(template, /Review your answers/);
  assert.match(template, /中文/);
});

test("adds a complete survey management workspace", async () => {
  const [workspace, template, controller, surveyTemplate, api, styles] = await Promise.all([
    readFile(new URL("src/js/workspace.js", root), "utf8"),
    readFile(new URL("src/js/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace.js", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/api.js", root), "utf8"),
    readFile(new URL("src/css/surveys.css", root), "utf8"),
  ]);

  assert.match(workspace, /id:\s*"surveys"/);
  assert.match(template, /surveyWorkspaceTemplate/);
  assert.match(controller, /createSurveyWorkspaceState/);
  for (const label of ["Survey library", "Form builder", "Distribution", "Response review", "Cross-tabs", "Import & export"]) {
    assert.match(surveyTemplate, new RegExp(label));
  }
  assert.match(api, /rpc_aoi_survey_library/);
  assert.match(api, /rpc_aoi_save_survey_draft/);
  assert.match(api, /survey-public/);
  assert.match(styles, /\.survey-builder-grid/);
  assert.match(styles, /@media \(max-width: 760px\)/);
  assert.doesNotMatch(surveyTemplate, /x-html/);
});

test("secures public survey operations in a dedicated Edge Function", async () => {
  const [source, config] = await Promise.all([
    readFile(new URL("supabase/functions/survey-public/index.ts", root), "utf8"),
    readFile(new URL("supabase/config.toml", root), "utf8"),
  ]);

  assert.match(source, /Deno\.serve/);
  assert.match(source, /load|start|save|submit/);
  assert.match(source, /SURVEY_LINK_UNAVAILABLE/);
  assert.match(source, /idempotency/i);
  assert.match(source, /ALLOWED_ORIGINS/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin":\s*"\*"/);
  assert.match(config, /\[functions\.survey-public\]/);
  assert.match(config, /verify_jwt\s*=\s*false/);
});
