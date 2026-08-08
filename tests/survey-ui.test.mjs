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

  assert.match(workspace, /\{ id: "research", label: "Research" \}/);
  assert.match(workspace, /researchTab:\s*"collect"/);
  assert.match(surveyTemplate, /view==='research' && researchTab==='surveys'/);
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

test("renders questionnaire content, attached Other fields, scale labels, and restricted identifiers", async () => {
  const [runner, runnerTemplate, workspaceTemplate, api] = await Promise.all([
    readFile(new URL("src/js/surveys/runner.js", root), "utf8"),
    readFile(new URL("src/js/surveys/runner-template.js", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace-template.js", root), "utf8"),
    readFile(new URL("src/js/api.js", root), "utf8"),
  ]);

  assert.match(runner, /setOtherText/);
  assert.match(runner, /surveyChoiceValues/);
  assert.match(runner, /definition\.locales\?\.includes\(savedLocale\)/);
  assert.match(runnerTemplate, /question\.type==='content'/);
  assert.match(runnerTemplate, /question\.other/);
  assert.match(runnerTemplate, /scaleLabels/);
  assert.match(runnerTemplate, /definition\.consent/);
  assert.match(workspaceTemplate, /Direct identifier/);
  assert.match(workspaceTemplate, /surveySelectedResponse\?\.identifiers/);
  assert.match(await readFile(new URL("src/js/surveys/workspace.js", root), "utf8"), /privacy\?\.classification !== "direct_identifier"/);
  assert.match(api, /surveyError\.fields/);
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
  assert.match(source, /p_token: token/);
  assert.match(source, /p_invitation_token: body\.invitationToken/);
  assert.match(source, /ALLOWED_ORIGINS/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin":\s*"\*"/);
  assert.match(config, /\[functions\.survey-public\]/);
  assert.match(config, /verify_jwt\s*=\s*false/);
});

test("wires survey workspace navigation, immutable versions, analysis, and preview controls", async () => {
  const [controller, template] = await Promise.all([
    readFile(new URL("src/js/surveys/workspace.js", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace-template.js", root), "utf8"),
  ]);

  assert.match(controller, /filteredSurveyAssets\(\)/);
  assert.match(controller, /surveyLibraryView/);
  assert.match(controller, /surveyLibraryFilter/);
  assert.match(template, /filteredSurveyAssets\(\)/);
  assert.match(template, /role="tablist"/);
  assert.match(template, /:aria-selected=/);
  assert.match(controller, /surveyAnalysisTab/);
  assert.match(controller, /surveyQuestionAggregate\(/);
  assert.match(template, /setSurveyAnalysisTab\(/);
  assert.match(controller, /response\.versionDefinition/);
  assert.match(controller, /reviewCurrentSurvey\(version,/);
  assert.match(controller, /publishCurrentSurvey\(version\)/);
  assert.match(controller, /surveyInvitationLinkId/);
  assert.match(controller, /openSurveyPreview\(\)/);
  assert.match(controller, /aoi-survey-preview:/);
  assert.match(controller, /pageUrl\(import\.meta\.env\.BASE_URL, "survey\.html"\)/);
  assert.doesNotMatch(template, /@click="window\.print\(\)">Preview/);
});

test("guards dirty survey navigation and keeps response selection coherent", async () => {
  const controller = await readFile(new URL("src/js/surveys/workspace.js", root), "utf8");

  assert.match(controller, /beforeunload/);
  assert.match(controller, /confirmSurveyNavigation/);
  assert.match(controller, /applySurveyWorkspace/);
  assert.match(controller, /surveySelectedResponse\?\.id/);
  assert.match(controller, /await this\.saveCurrentSurvey\(\)/);
  assert.match(controller, /surveyEditGeneration/);
  assert.match(controller, /surveyQueuedSave/);
  assert.match(controller, /surveyAssetRequestSequence/);
  assert.match(controller, /surveyAnalysisRequestSequence/);
});

test("honors runner presentation settings and recovers corrupt local resumes", async () => {
  const [runner, template] = await Promise.all([
    readFile(new URL("src/js/surveys/runner.js", root), "utf8"),
    readFile(new URL("src/js/surveys/runner-template.js", root), "utf8"),
  ]);

  assert.match(runner, /removeItem\(storageKey\(this\.token\)\)/);
  assert.match(runner, /showProgress/);
  assert.match(runner, /This survey preview is unavailable/);
  assert.match(runner, /allowReview/);
  assert.match(runner, /redirectUrl/);
  assert.match(runner, /surveyThemeClass/);
  assert.match(runner, /if \(this\.submitting \|\| this\.completed\) return/);
  assert.match(runner, /saveGeneration/);
  assert.match(runner, /saveQueued/);
  assert.match(runner, /submissionId: this\.session\?\.submissionId/);
  assert.match(template, /x-show="definition\.settings\?\.showProgress!==false"/);
  assert.match(template, /:class="surveyThemeClass\(\)"/);
  assert.match(runner, /blocks\.map\(\(block\) => block\.type === "content" \? block : questions\[questionIndex\+\+\]\)/);
  assert.match(template, /question\.type==='dropdown'[\s\S]*setChoiceAnswer\(question,\$event\.target\.value\)/);
});

test("enforces per-link embed origins and normalized upload metadata", async () => {
  const source = await readFile(new URL("supabase/functions/survey-public/index.ts", root), "utf8");

  assert.match(source, /allowedOrigins/);
  assert.match(source, /published\.mode === "embed"/);
  assert.match(source, /SURVEY_EMBED_ORIGIN_DENIED/);
  assert.match(source, /normalizeUploadMetadata/);
  assert.match(source, /extension/i);
});

test("contains survey layouts on narrow screens and exposes accessible dialogs", async () => {
  const [styles, template] = await Promise.all([
    readFile(new URL("src/css/surveys.css", root), "utf8"),
    readFile(new URL("src/js/surveys/workspace-template.js", root), "utf8"),
  ]);

  assert.match(styles, /\.survey-workspace\s*\{[\s\S]*min-width:\s*0/);
  assert.match(styles, /overflow-wrap:\s*anywhere/);
  assert.match(styles, /@media \(max-width: 420px\)/);
  assert.match(template, /role="dialog"/);
  assert.match(template, /@keydown\.escape/);
  assert.match(template, /aria-modal="true"/);
});
