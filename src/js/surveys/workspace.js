import "../../css/surveys.css";
import {
  createSurveyAsset,
  createSurveyInvitation,
  createSurveyLink,
  loadSurveyAnalysis,
  loadSurveyLibrary,
  loadSurveyWorkspace,
  publishSurveyVersion,
  promoteSurveyAnswer,
  reviewSurveySubmission,
  reviewSurveyVersion,
  saveSurveyDraft,
  submitSurveyVersion,
} from "../api.js";
import { pageUrl, readableError } from "../core.js";
import {
  cloneSurveyDefinition,
  createSurveyDefinition,
  createSurveyQuestion,
  surveyQuestions,
  validateSurveyDefinition,
} from "./domain.js";
import { buildResponseCsv, exportSurveyPackage, importSurveyPackage } from "./import-export.js";

export const SURVEY_QUESTION_TYPES = [
  ["short_text", "Short answer"], ["long_text", "Long answer"], ["number", "Number"],
  ["email", "Email"], ["phone", "Phone"], ["url", "URL"], ["date", "Date"], ["time", "Time"],
  ["single_choice", "Single choice"], ["multiple_choice", "Multiple choice"], ["dropdown", "Dropdown"],
  ["yes_no", "Yes / No"], ["rating", "Rating"], ["nps", "NPS"], ["likert", "Likert scale"],
  ["matrix_single", "Single-choice matrix"], ["matrix_multiple", "Multiple-choice matrix"],
  ["ranking", "Ranking"], ["upload", "File upload"], ["signature", "Signature"],
  ["consent", "Consent"], ["calculated", "Calculated field"], ["hidden", "Hidden variable"],
];

function demoDefinition() {
  const definition = createSurveyDefinition();
  definition.title = { en: "Concept value study", zh: "概念价值研究" };
  const need = createSurveyQuestion("single_choice");
  need.id = "demo-need";
  need.title = { en: "How often do you face this need?", zh: "您多久会遇到一次此类需求？" };
  need.required = true;
  need.options = [
    { id: "weekly", label: { en: "Weekly", zh: "每周" }, score: 3 },
    { id: "monthly", label: { en: "Monthly", zh: "每月" }, score: 2 },
    { id: "rarely", label: { en: "Rarely", zh: "很少" }, score: 0 },
  ];
  const value = createSurveyQuestion("rating");
  value.id = "demo-value";
  value.title = { en: "How valuable is this concept?", zh: "这个概念有多大价值？" };
  value.required = true;
  value.visibility = { all: [{ questionId: need.id, operator: "not_equals", value: "rarely" }] };
  value.pmfMapping = { layer: "H3", metricCode: "concept_value" };
  definition.blocks[0].blocks.push(need, value);
  return definition;
}

function demoWorkspace() {
  const definition = demoDefinition();
  return {
    asset: { id: "demo-survey", assetType: "survey", title: definition.title, description: definition.description, status: "published", tags: ["H3", "concept"] },
    draft: { revision: 4, definition, validationErrors: [], updatedAt: new Date().toISOString() },
    versions: [{ id: "demo-version", versionNumber: 1, status: "published", publishedAt: new Date().toISOString() }],
    links: [{ id: "demo-link", versionId: "demo-version", label: "Primary public study", mode: "public", identityMode: "anonymous", status: "active", responseCount: 86, maxResponses: 200 }],
    submissions: [
      { id: "response-1", status: "submitted", locale: "en", score: { percent: 82 }, qualityFlags: [], submittedAt: new Date().toISOString(), answers: { "demo-need": "weekly", "demo-value": 5 } },
      { id: "response-2", status: "approved", locale: "zh-CN", score: { percent: 68 }, qualityFlags: ["speeding"], submittedAt: new Date(Date.now() - 86400000).toISOString(), answers: { "demo-need": "monthly", "demo-value": 4 } },
    ],
  };
}

function download(name, type, value) {
  const url = URL.createObjectURL(new Blob([value], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  URL.revokeObjectURL(url);
}

function findBlock(definition, blockId) {
  for (const section of definition?.blocks || []) {
    if (section.id === blockId) return section;
    const question = (section.blocks || []).find((block) => block.id === blockId);
    if (question) return question;
  }
  return null;
}

export function createSurveyWorkspaceState() {
  return {
    surveyReady: false,
    surveyLoading: false,
    surveySaving: false,
    surveyDirty: false,
    surveyError: "",
    surveyNotice: null,
    surveyTab: "library",
    surveyLibrary: { assets: [], reviewCount: 0 },
    surveyLibraryQuery: "",
    surveyWorkspace: null,
    surveyDefinition: null,
    surveySelectedBlockId: null,
    surveyQuestionType: "short_text",
    surveyQuestionTypes: SURVEY_QUESTION_TYPES,
    surveyNew: { open: false, assetType: "survey", titleEn: "", titleZh: "" },
    surveyLinkForm: { label: "Primary link", mode: "public", identityMode: "anonymous", maxResponses: "", opensAt: "", closesAt: "" },
    surveyCreatedLink: null,
    surveyInvitationForm: { name: "", email: "" },
    surveyCreatedInvitation: null,
    surveyPopulation: "approved",
    surveyAnalysis: null,
    surveyReviewNotes: {},
    surveySelectedResponse: null,
    surveyPromotionSegment: "",
    surveyImportNotice: null,
    surveyAutosaveTimer: null,

    surveyText(value) { return value?.[this.locale === "zh-CN" ? "zh" : "en"] || value?.en || ""; },
    surveyQuestions() { return surveyQuestions(this.surveyDefinition || { blocks: [] }); },
    selectedSurveyBlock() { return findBlock(this.surveyDefinition, this.surveySelectedBlockId); },
    selectedSurveyQuestion() {
      const block = this.selectedSurveyBlock();
      return block?.type === "section" ? null : block;
    },
    activeSurveyVersion(status = null) {
      return (this.surveyWorkspace?.versions || []).find((version) => !status || version.status === status) || null;
    },
    surveyStatusTone(status) {
      if (["published", "approved"].includes(status)) return "status-approved";
      if (["submitted", "awaiting_approval", "in_review"].includes(status)) return "status-submitted";
      if (["rejected", "excluded", "revision_requested"].includes(status)) return "status-blocked";
      return "status-assigned";
    },

    async openSurveyWorkspace() {
      if (this.surveyReady || this.surveyLoading) return;
      this.surveyLoading = true;
      this.surveyError = "";
      try {
        this.surveyLibrary = this.preview ? {
          assets: [{ id: "demo-survey", assetType: "survey", title: { en: "Concept value study", zh: "概念价值研究" }, status: "published", tags: ["H3", "concept"], responseCount: 86, approvedCount: 64, draftRevision: 4, publishedVersion: 1, updatedAt: new Date().toISOString() }],
          reviewCount: 1,
        } : await loadSurveyLibrary();
        this.surveyReady = true;
      } catch (reason) {
        this.surveyError = readableError(reason, "Unable to load surveys.");
      } finally {
        this.surveyLoading = false;
      }
    },

    setSurveyTab(tab) {
      this.surveyTab = tab;
      if (tab === "analyze" && this.surveyWorkspace?.asset?.id) this.refreshSurveyAnalysis();
    },

    async openSurveyAsset(asset) {
      this.surveyLoading = true;
      this.surveyError = "";
      try {
        this.surveyWorkspace = this.preview ? demoWorkspace() : await loadSurveyWorkspace(asset.id);
        this.surveyDefinition = cloneSurveyDefinition(this.surveyWorkspace.draft.definition);
        this.surveySelectedBlockId = this.surveyDefinition.blocks[0]?.id || null;
        this.surveyTab = "builder";
        this.surveyDirty = false;
        this.surveyAnalysis = null;
      } catch (reason) {
        this.surveyError = readableError(reason, "Unable to open this survey.");
      } finally {
        this.surveyLoading = false;
      }
    },

    closeSurveyAsset() {
      this.surveyWorkspace = null;
      this.surveyDefinition = null;
      this.surveyTab = "library";
      this.surveyCreatedLink = null;
      this.surveyNotice = null;
    },

    async createSurveyFromForm() {
      if (!this.surveyNew.titleEn.trim() || !this.surveyNew.titleZh.trim()) {
        this.surveyNotice = { tone: "error", text: "Enter the English and Chinese titles." };
        return;
      }
      this.surveySaving = true;
      try {
        const definition = createSurveyDefinition();
        definition.title = { en: this.surveyNew.titleEn.trim(), zh: this.surveyNew.titleZh.trim() };
        const created = this.preview
          ? { id: "preview-new", revision: 1, definition }
          : await createSurveyAsset({ title: definition.title, assetType: this.surveyNew.assetType, definition });
        this.surveyNew = { open: false, assetType: "survey", titleEn: "", titleZh: "" };
        if (!this.preview) this.surveyLibrary = await loadSurveyLibrary();
        await this.openSurveyAsset({ id: created.id });
        if (this.preview && created.id === "preview-new") {
          this.surveyWorkspace = { asset: { id: created.id, assetType: "survey", title: definition.title, status: "draft" }, draft: created, versions: [], links: [], submissions: [] };
          this.surveyDefinition = definition;
        }
      } catch (reason) {
        this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to create the survey.") };
      } finally {
        this.surveySaving = false;
      }
    },

    selectSurveyBlock(blockId) { this.surveySelectedBlockId = blockId; },
    addSurveySection() {
      const section = createSurveyDefinition().blocks[0];
      section.title = { en: `Section ${this.surveyDefinition.blocks.length + 1}`, zh: `第${this.surveyDefinition.blocks.length + 1}部分` };
      this.surveyDefinition.blocks.push(section);
      this.surveySelectedBlockId = section.id;
      this.markSurveyDirty();
    },
    addSurveyQuestion(type = this.surveyQuestionType) {
      let section = this.selectedSurveyBlock();
      if (!section || section.type !== "section") section = this.surveyDefinition.blocks.find((item) => item.blocks?.some((block) => block.id === this.surveySelectedBlockId)) || this.surveyDefinition.blocks[0];
      const question = createSurveyQuestion(type);
      section.blocks.push(question);
      this.surveySelectedBlockId = question.id;
      this.markSurveyDirty();
    },
    duplicateSurveyQuestion(question) {
      const section = this.surveyDefinition.blocks.find((item) => item.blocks?.some((block) => block.id === question.id));
      const copy = cloneSurveyDefinition(question);
      copy.id = `question-${globalThis.crypto.randomUUID()}`;
      copy.title = { en: `${copy.title.en} copy`, zh: `${copy.title.zh}副本` };
      section.blocks.splice(section.blocks.findIndex((block) => block.id === question.id) + 1, 0, copy);
      this.surveySelectedBlockId = copy.id;
      this.markSurveyDirty();
    },
    removeSurveyQuestion(question) {
      const section = this.surveyDefinition.blocks.find((item) => item.blocks?.some((block) => block.id === question.id));
      if (!section) return;
      section.blocks = section.blocks.filter((block) => block.id !== question.id);
      this.surveySelectedBlockId = section.id;
      this.markSurveyDirty();
    },
    moveSurveyQuestion(question, direction) {
      const section = this.surveyDefinition.blocks.find((item) => item.blocks?.some((block) => block.id === question.id));
      const index = section?.blocks.findIndex((block) => block.id === question.id) ?? -1;
      const target = index + direction;
      if (!section || index < 0 || target < 0 || target >= section.blocks.length) return;
      [section.blocks[index], section.blocks[target]] = [section.blocks[target], section.blocks[index]];
      this.markSurveyDirty();
    },
    addSurveyOption(question) {
      question.options ||= [];
      question.options.push({ id: `option-${globalThis.crypto.randomUUID()}`, label: { en: `Option ${question.options.length + 1}`, zh: `选项${question.options.length + 1}` }, score: 0 });
      this.markSurveyDirty();
    },
    removeSurveyOption(question, optionId) {
      if (question.options.length <= 2) return;
      question.options = question.options.filter((option) => option.id !== optionId);
      this.markSurveyDirty();
    },
    setSurveyVisibility(question, sourceId, value) {
      question.visibility = sourceId ? { all: [{ questionId: sourceId, operator: "equals", value }] } : null;
      this.markSurveyDirty();
    },
    normalizeSelectedSurveyQuestion() {
      const question = this.selectedSurveyQuestion();
      if (!question) return;
      const defaults = createSurveyQuestion(question.type);
      if (["single_choice", "multiple_choice", "dropdown", "yes_no", "ranking"].includes(question.type) && (!Array.isArray(question.options) || question.options.length < 2)) question.options = defaults.options;
      if (["matrix_single", "matrix_multiple"].includes(question.type)) {
        if (!question.rows?.length) question.rows = defaults.rows;
        if (!question.columns?.length) question.columns = defaults.columns;
      }
      if (["rating", "nps", "likert"].includes(question.type) && (question.validation?.min === undefined || question.validation?.max === undefined)) question.validation = defaults.validation;
      if (question.type === "calculated" && !question.calculation) question.calculation = { operator: "sum", questionIds: [] };
      question.pmfMapping ||= { layer: "", metricCode: "" };
    },
    markSurveyDirty() {
      this.normalizeSelectedSurveyQuestion();
      this.surveyDirty = true;
      this.surveyNotice = { tone: "info", text: "Unsaved changes" };
      window.clearTimeout(this.surveyAutosaveTimer);
      if (!this.preview) this.surveyAutosaveTimer = window.setTimeout(() => this.saveCurrentSurvey(), 1200);
    },
    async saveCurrentSurvey() {
      if (!this.surveyWorkspace || this.surveySaving) return false;
      if (!this.surveyDirty) return true;
      const validation = validateSurveyDefinition(this.surveyDefinition);
      if (!validation.valid) {
        this.surveyNotice = { tone: "error", text: `${validation.errors.length} definition issue(s) must be fixed before approval.` };
      }
      this.surveySaving = true;
      try {
        if (this.preview) {
          this.surveyWorkspace.draft.revision += 1;
          this.surveyWorkspace.draft.definition = cloneSurveyDefinition(this.surveyDefinition);
        } else {
          const result = await saveSurveyDraft(this.surveyWorkspace.asset.id, this.surveyDefinition, this.surveyWorkspace.draft.revision);
          this.surveyWorkspace.draft.revision = result.revision;
          this.surveyWorkspace.draft.updatedAt = result.updatedAt;
        }
        this.surveyDirty = false;
        this.surveyNotice = { tone: validation.valid ? "success" : "warning", text: validation.valid ? "Draft saved" : "Draft saved with validation issues" };
        return true;
      } catch (reason) {
        this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to save the draft.") };
        return false;
      } finally {
        this.surveySaving = false;
      }
    },
    async submitCurrentSurvey() {
      const validation = validateSurveyDefinition(this.surveyDefinition);
      if (!validation.valid) {
        this.surveyNotice = { tone: "error", text: `Resolve ${validation.errors.length} validation issue(s) before submitting.` };
        return;
      }
      if (!await this.saveCurrentSurvey()) return;
      this.surveySaving = true;
      try {
        if (this.preview) {
          this.surveyWorkspace.versions.unshift({ id: "preview-submitted", versionNumber: this.surveyWorkspace.versions.length + 1, status: "submitted", submittedAt: new Date().toISOString() });
          this.surveyWorkspace.asset.status = "awaiting_approval";
        } else {
          await submitSurveyVersion(this.surveyWorkspace.asset.id, this.surveyWorkspace.draft.revision);
          this.surveyWorkspace = await loadSurveyWorkspace(this.surveyWorkspace.asset.id);
        }
        this.surveyNotice = { tone: "success", text: "Version submitted for administrator approval." };
      } catch (reason) {
        this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to submit the version.") };
      } finally { this.surveySaving = false; }
    },
    async reviewCurrentSurvey(action) {
      const version = this.activeSurveyVersion("submitted");
      if (!version) return;
      try {
        if (this.preview) version.status = action === "approve" ? "approved" : "rejected";
        else {
          await reviewSurveyVersion(version.id, action, "Reviewed in the survey workspace.");
          this.surveyWorkspace = await loadSurveyWorkspace(this.surveyWorkspace.asset.id);
        }
        this.surveyNotice = { tone: "success", text: `Version ${action}d.` };
      } catch (reason) { this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to review the version.") }; }
    },
    async publishCurrentSurvey() {
      const version = this.activeSurveyVersion("approved");
      if (!version) return;
      try {
        if (this.preview) version.status = "published";
        else {
          await publishSurveyVersion(version.id);
          this.surveyWorkspace = await loadSurveyWorkspace(this.surveyWorkspace.asset.id);
        }
        this.surveyNotice = { tone: "success", text: "The immutable survey version is published." };
      } catch (reason) { this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to publish the survey.") }; }
    },
    async createCurrentSurveyLink() {
      if (this.surveyLinkForm.identityMode === "identified" && this.surveyLinkForm.mode !== "invited") {
        this.surveyLinkForm.mode = "invited";
        this.surveyNotice = { tone: "info", text: "Identified collection uses single-use invitations, so the channel was changed to invited." };
      }
      const version = this.activeSurveyVersion("published");
      if (!version) {
        this.surveyNotice = { tone: "error", text: "Publish an approved version before creating a link." };
        return;
      }
      try {
        const result = this.preview ? { id: "preview-link", token: "preview-survey-token-000000000000000000000000", mode: this.surveyLinkForm.mode, identityMode: this.surveyLinkForm.identityMode, status: "active" }
          : await createSurveyLink(version.id, {
              ...this.surveyLinkForm,
              settings: { maxResponses: this.surveyLinkForm.maxResponses, opensAt: this.surveyLinkForm.opensAt, closesAt: this.surveyLinkForm.closesAt, allowedOrigins: this.surveyLinkForm.mode === "embed" ? [location.origin] : [] },
            });
        this.surveyCreatedLink = { ...result, url: `${location.origin}${pageUrl(import.meta.env.BASE_URL, "survey.html")}#token=${result.token}` };
        this.surveyNotice = { tone: "success", text: "Secure link created. The token is shown only now." };
      } catch (reason) { this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to create the link.") }; }
    },
    async copySurveyLink() {
      if (!this.surveyCreatedLink?.url) return;
      await navigator.clipboard.writeText(this.surveyCreatedLink.url);
      this.surveyNotice = { tone: "success", text: "Survey link copied." };
    },
    async createCurrentSurveyInvitation() {
      if (!this.surveyCreatedLink?.id || !this.surveyInvitationForm.email.trim()) return;
      try {
        const result = this.preview ? { id: "preview-invitation", token: `invite-${globalThis.crypto.randomUUID().replaceAll("-", "")}`, status: "queued" }
          : await createSurveyInvitation(this.surveyCreatedLink.id, this.surveyInvitationForm.name, this.surveyInvitationForm.email);
        this.surveyCreatedInvitation = {
          ...result,
          url: `${location.origin}${pageUrl(import.meta.env.BASE_URL, "survey.html")}#token=${result.token}&invite=${result.token}`,
        };
        this.surveyNotice = { tone: "success", text: "Unique invitation created. Copy it before leaving this view." };
      } catch (reason) {
        this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to create the invitation.") };
      }
    },
    async copySurveyInvitation() {
      if (!this.surveyCreatedInvitation?.url) return;
      await navigator.clipboard.writeText(this.surveyCreatedInvitation.url);
      this.surveyNotice = { tone: "success", text: "Unique invitation link copied." };
    },
    async reviewCurrentResponse(response, action) {
      try {
        if (this.preview) response.status = action === "start_review" ? "in_review" : action === "approve" ? "approved" : action === "exclude" ? "excluded" : response.status;
        else {
          await reviewSurveySubmission(response.id, action, this.surveyReviewNotes[response.id] || "");
          this.surveyWorkspace = await loadSurveyWorkspace(this.surveyWorkspace.asset.id);
        }
      } catch (reason) { this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to review the response.") }; }
    },
    async promoteMappedSurveyAnswers(response) {
      const mapped = this.surveyQuestions().filter((question) => question.pmfMapping?.metricCode && response.answers?.[question.id] !== undefined);
      const segmentCode = this.surveyPromotionSegment || this.data.segments?.[0]?.code;
      if (response.status !== "approved" || !mapped.length || !segmentCode) {
        this.surveyNotice = { tone: "error", text: "Approve the response, choose a segment, and map at least one answered question." };
        return;
      }
      try {
        if (!this.preview) {
          for (const question of mapped) await promoteSurveyAnswer(response.id, question.id, question.pmfMapping.metricCode, segmentCode);
        }
        this.surveyNotice = { tone: "success", text: `${mapped.length} mapped answer(s) promoted with survey provenance.` };
      } catch (reason) {
        this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to promote mapped answers.") };
      }
    },
    async refreshSurveyAnalysis() {
      if (!this.surveyWorkspace?.asset?.id) return;
      try {
        this.surveyAnalysis = this.preview ? {
          population: this.surveyPopulation, starts: 92, completed: 86, completionRate: 93,
          statusCounts: { submitted: 21, in_review: 1, approved: 64 },
          questions: [{ questionId: "demo-need", count: 64, values: ["weekly", "weekly", "monthly", "rarely"] }, { questionId: "demo-value", count: 57, values: [5, 4, 4, 3, 5] }], qualityFlags: [{ submissionId: "response-2", flags: ["speeding"] }],
        } : await loadSurveyAnalysis(this.surveyWorkspace.asset.id, this.surveyPopulation);
      } catch (reason) { this.surveyNotice = { tone: "error", text: readableError(reason, "Unable to load analysis.") }; }
    },
    surveyQuestionSummary(questionId) { return this.surveyAnalysis?.questions?.find((item) => item.questionId === questionId) || { count: 0, values: [] }; },
    surveyValueBreakdown(questionId) {
      const values = this.surveyQuestionSummary(questionId).values || [];
      const counts = new Map();
      for (const value of values) {
        const label = Array.isArray(value) ? value.join(" | ") : typeof value === "object" ? JSON.stringify(value) : String(value);
        counts.set(label, (counts.get(label) || 0) + 1);
      }
      return [...counts].map(([label, count]) => ({ label, count, percent: values.length ? Math.round(count / values.length * 100) : 0 })).sort((a, b) => b.count - a.count);
    },
    async exportCurrentSurveyPackage() {
      const source = await exportSurveyPackage({ definition: this.surveyDefinition, name: this.surveyText(this.surveyDefinition.title), metadata: { assetId: this.surveyWorkspace.asset.id } });
      download("survey.aoi.json", "application/json", source);
    },
    exportCurrentSurveyResponses() {
      const exported = buildResponseCsv(this.surveyDefinition, (this.surveyWorkspace.submissions || []).map((response) => ({ submissionId: response.id, status: response.status, answers: response.answers })));
      download("survey-responses.csv", "text/csv;charset=utf-8", exported.wide);
      download("survey-codebook.csv", "text/csv;charset=utf-8", exported.codebook);
    },
    async importSurveyDefinition(event) {
      const file = event.target.files?.[0];
      if (!file) return;
      try {
        const imported = await importSurveyPackage(await file.text());
        this.surveyDefinition = imported.definition;
        this.surveySelectedBlockId = imported.definition.blocks[0]?.id;
        this.markSurveyDirty();
        this.surveyImportNotice = { tone: "success", text: `Validated ${imported.name}. Review before saving.` };
      } catch (reason) {
        this.surveyImportNotice = { tone: "error", text: readableError(reason, "This survey package is invalid.") };
      } finally { event.target.value = ""; }
    },
  };
}
