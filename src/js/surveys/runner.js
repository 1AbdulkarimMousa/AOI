import "../../css/surveys.css";
import { invokeSurveyPublic } from "../api.js";
import { getSupabaseClient } from "../supabase.js";
import { calculateSurveyFields, calculateSurveyScore, deterministicOrder, evaluateVisibility, renderPipedText, surveyChoiceValues, surveyOtherText, surveyQuestions, validateSurveyAnswers } from "./domain.js";

function tokenFromLocation() {
  return new URLSearchParams(location.hash.replace(/^#/, "")).get("token") || "";
}

function invitationTokenFromLocation() {
  return new URLSearchParams(location.hash.replace(/^#/, "")).get("invite") || "";
}

function storageKey(token) {
  return `aoi-survey-response:${token.slice(0, 16)}`;
}

function embedOrigin() {
  if (globalThis.location === globalThis.parent?.location) return "";
  try { return new URL(document.referrer).origin; } catch { return ""; }
}

export function registerSurveyRunner(Alpine) {
  Alpine.data("surveyRunner", () => ({
    ready: false,
    loading: true,
    saving: false,
    submitting: false,
    started: false,
    reviewing: false,
    completed: false,
    error: "",
    liveStatus: "",
    token: "",
    invitationToken: "",
    link: null,
    definition: null,
    locale: "en",
    sectionIndex: 0,
    answers: {},
    errors: {},
    session: null,
    consentAccepted: false,
    idempotencyKey: "",
    autosaveTimer: null,
    preview: false,
    saveGeneration: 0,
    savedGeneration: 0,
    saveQueued: false,
    savePromise: null,

    async init() {
      const previewId = new URLSearchParams(location.search).get("preview");
      if (previewId) {
        try {
          const previewDefinition = localStorage.getItem(`aoi-survey-preview:${previewId}`);
          if (!previewDefinition) throw new Error("preview unavailable");
          this.preview = true;
          this.token = `preview-${previewId}`;
          this.definition = JSON.parse(previewDefinition);
          this.link = { versionId: "preview", identityMode: "preview" };
          this.locale = this.definition.defaultLocale || "en";
          document.documentElement.lang = this.locale;
        } catch {
          this.error = "This survey preview is unavailable.";
        } finally {
          this.loading = false;
          this.ready = true;
        }
        return;
      }
      this.token = tokenFromLocation();
      this.invitationToken = invitationTokenFromLocation();
      if (this.token.length < 32) {
        this.error = "This survey link is unavailable.";
        this.loading = false;
        this.ready = true;
        return;
      }
      try {
        this.link = await invokeSurveyPublic("load", { token: this.token, invitationToken: this.invitationToken, embedOrigin: embedOrigin() });
        this.definition = this.link.definition;
        const savedLocale = localStorage.getItem("aoi-survey-locale");
        this.locale = this.definition.locales?.includes(savedLocale) ? savedLocale : this.definition.defaultLocale || "en";
        document.documentElement.lang = this.locale;
        const restored = globalThis.localStorage.getItem(storageKey(this.token));
        if (restored) try {
          const saved = JSON.parse(restored);
          this.session = saved.session || null;
          this.answers = saved.answers && typeof saved.answers === "object" ? saved.answers : {};
          this.sectionIndex = Math.min(Number(saved.sectionIndex) || 0, Math.max(0, this.sections().length - 1));
          this.started = Boolean(this.session?.submissionId && this.session?.resumeToken);
          this.consentAccepted = Boolean(saved.consentAccepted);
          this.idempotencyKey = saved.idempotencyKey || "";
          if (!this.started && saved.session) throw new Error("invalid session");
        } catch {
          globalThis.localStorage.removeItem(storageKey(this.token));
          this.session = null;
          this.answers = {};
          this.sectionIndex = 0;
          this.started = false;
          this.idempotencyKey = "";
          this.liveStatus = "Saved progress was corrupt and has been reset safely.";
        }
      } catch {
        this.error = "This survey link is unavailable.";
      } finally {
        this.loading = false;
        this.ready = true;
      }
    },

    text(value) {
      const localized = value?.[this.locale === "zh-CN" ? "zh" : "en"] || value?.en || "";
      return renderPipedText(localized, this.definition || { blocks: [] }, this.answers, this.locale);
    },
    copy(key) {
      const values = {
        en: { start: "Start survey", next: "Next section", back: "Back", review: "Review answers", submit: "Submit response", required: "This question is required.", saved: "Progress saved", saving: "Saving…" },
        "zh-CN": { start: "开始问卷", next: "下一部分", back: "返回", review: "检查答案", submit: "提交答案", required: "此问题为必填项。", saved: "进度已保存", saving: "正在保存…" },
      };
      return values[this.locale]?.[key] || values.en[key] || key;
    },
    switchLocale() {
      if (!(this.definition?.locales || []).includes("zh-CN")) return;
      this.locale = this.locale === "en" ? "zh-CN" : "en";
      document.documentElement.lang = this.locale;
      localStorage.setItem("aoi-survey-locale", this.locale);
    },
    surveyThemeClass() {
      const accent = ["orange", "teal", "purple"].includes(this.definition?.theme?.accent) ? this.definition.theme.accent : "orange";
      const density = this.definition?.theme?.density === "compact" ? "compact" : "comfortable";
      return `survey-theme-${accent} survey-density-${density}`;
    },
    showProgress() { return this.definition?.settings?.showProgress !== false; },
    sections() {
      const sections = (this.definition?.blocks || []).filter((section) => section.type === "section");
      return this.definition?.settings?.randomizeSections && this.session
        ? deterministicOrder(sections, `${this.session.submissionId}:sections`)
        : sections;
    },
    surveyQuestions(definition = this.definition) { return surveyQuestions(definition || { blocks: [] }); },
    surveyChoiceValues(value) { return surveyChoiceValues(value); },
    surveyOtherText(value) { return surveyOtherText(value); },
    currentSection() { return this.sections()[this.sectionIndex] || null; },
    visibleQuestionIds() { return new Set(evaluateVisibility(this.definition, this.answers)); },
    currentBlocks() {
      const section = this.currentSection();
      const blocks = (section?.blocks || []).filter((block) => block.type === "content" || block.type !== "hidden" && this.visibleQuestionIds().has(block.id));
      if (!section?.randomizeQuestions || !this.session) return blocks;
      const questions = deterministicOrder(blocks.filter((block) => block.type !== "content"), `${this.session.submissionId}:${section.id}`);
      let questionIndex = 0;
      return blocks.map((block) => block.type === "content" ? block : questions[questionIndex++]);
    },
    currentQuestions() { return this.currentBlocks().filter((block) => block.type !== "content"); },
    questionOptions(question) {
      return question.randomizeOptions && this.session
        ? deterministicOrder(question.options || [], `${this.session.submissionId}:${question.id}:options`)
        : question.options || [];
    },
    allQuestions() { return surveyQuestions(this.definition || { blocks: [] }).filter((question) => question.type !== "hidden" && this.visibleQuestionIds().has(question.id)); },
    progress() { return this.sections().length ? Math.round((this.sectionIndex + (this.reviewing ? 1 : 0)) / this.sections().length * 100) : 0; },
    answerLabel(question, value) {
      if (["single_choice", "multiple_choice", "dropdown", "yes_no"].includes(question.type)) {
        const labels = surveyChoiceValues(value).map((selected) => this.text((question.options || []).find((option) => option.id === selected)?.label) || selected);
        if (surveyOtherText(value)) labels.push(surveyOtherText(value));
        return labels.join(", ") || "No answer";
      }
      if (Array.isArray(value)) return value.map((item) => this.answerLabel(question, item)).join(", ");
      if (value && typeof value === "object") {
        if (value.name) return value.name;
        return Object.entries(value).map(([rowId, selection]) => `${rowId}: ${Array.isArray(selection) ? selection.join(", ") : selection}`).join("; ");
      }
      const option = (question.options || []).find((item) => item.id === value);
      return option ? this.text(option.label) : value === undefined || value === "" ? "No answer" : String(value);
    },
    persistLocal() {
      globalThis.localStorage.setItem(storageKey(this.token), JSON.stringify({ session: this.session, answers: this.answers, sectionIndex: this.sectionIndex, consentAccepted: this.consentAccepted, idempotencyKey: this.idempotencyKey }));
    },

    async begin() {
      this.error = "";
      this.loading = true;
      try {
        this.session = this.preview ? {
          submissionId: `preview-${globalThis.crypto.randomUUID()}`,
          resumeToken: "preview",
          status: "in_progress",
        } : await invokeSurveyPublic("start", {
          token: this.token,
          invitationToken: this.invitationToken,
          embedOrigin: embedOrigin(),
          locale: this.locale,
          consent: { accepted: this.consentAccepted, locale: this.locale, shownAt: new Date().toISOString(), versionId: this.link.versionId },
        });
        this.started = true;
        this.persistLocal();
        await this.$nextTick();
        document.querySelector(".survey-runner-question input, .survey-runner-question textarea, .survey-runner-question select")?.focus();
      } catch {
        this.error = "The survey could not be started. Please try again.";
      } finally { this.loading = false; }
    },
    setAnswer(questionId, value) {
      this.answers[questionId] = value;
      this.answers = calculateSurveyFields(this.definition, this.answers);
      this.saveGeneration += 1;
      delete this.errors[questionId];
      this.persistLocal();
      this.scheduleSave();
    },
    isChoiceSelected(question, optionId) {
      return surveyChoiceValues(this.answers[question.id]).includes(optionId);
    },
    setChoiceAnswer(question, optionId) {
      const value = question.other?.optionId === optionId
        ? { value: optionId, otherText: surveyOtherText(this.answers[question.id]) }
        : optionId;
      this.setAnswer(question.id, value);
    },
    toggleAnswer(question, optionId) {
      const selected = new Set(surveyChoiceValues(this.answers[question.id]));
      const exclusive = new Set(question.validation?.exclusiveOptionIds || []);
      if (selected.has(optionId)) selected.delete(optionId);
      else {
        if (exclusive.has(optionId)) selected.clear();
        else for (const value of exclusive) selected.delete(value);
        if (question.validation?.maxSelections && selected.size >= Number(question.validation.maxSelections)) {
          this.errors[question.id] = `Choose up to ${question.validation.maxSelections} option(s).`;
          return;
        }
        selected.add(optionId);
      }
      const values = [...selected];
      this.setAnswer(question.id, question.other?.optionId && selected.has(question.other.optionId)
        ? { values, otherText: surveyOtherText(this.answers[question.id]) }
        : values);
    },
    setOtherText(question, value) {
      const selected = surveyChoiceValues(this.answers[question.id]);
      this.setAnswer(question.id, question.type === "multiple_choice"
        ? { values: selected, otherText: value }
        : { value: selected[0] || question.other.optionId, otherText: value });
    },
    rankingValues(question) {
      const current = this.answers[question.id];
      return Array.isArray(current) && current.length ? current : this.questionOptions(question).map((option) => option.id);
    },
    moveRanking(question, optionId, direction) {
      const values = [...this.rankingValues(question)];
      const index = values.indexOf(optionId);
      const target = index + direction;
      if (index < 0 || target < 0 || target >= values.length) return;
      [values[index], values[target]] = [values[target], values[index]];
      this.setAnswer(question.id, values);
    },
    setMatrixAnswer(question, rowId, columnId, checked) {
      const matrix = { ...(this.answers[question.id] || {}) };
      if (question.type === "matrix_single") matrix[rowId] = columnId;
      else {
        const values = new Set(Array.isArray(matrix[rowId]) ? matrix[rowId] : []);
        if (checked) values.add(columnId); else values.delete(columnId);
        matrix[rowId] = [...values];
      }
      this.setAnswer(question.id, matrix);
    },
    scheduleSave() {
      window.clearTimeout(this.autosaveTimer);
      this.liveStatus = this.copy("saving");
      this.autosaveTimer = window.setTimeout(() => this.saveProgress(), 800);
    },
    async saveProgress() {
      if (!this.session || this.completed || this.submitting) return;
      if (this.preview) {
        this.liveStatus = this.copy("saved");
        this.persistLocal();
        return;
      }
      if (this.saving) {
        this.saveQueued = true;
        await this.savePromise;
        if (this.saveGeneration > this.savedGeneration) return this.saveProgress();
        return;
      }
      const generation = this.saveGeneration;
      const answers = structuredClone(this.answers);
      this.saving = true;
      this.saveQueued = false;
      this.savePromise = (async () => {
        try {
        await invokeSurveyPublic("save", {
          token: this.token,
          invitationToken: this.invitationToken,
          embedOrigin: embedOrigin(),
          submissionId: this.session.submissionId,
          resumeToken: this.session.resumeToken,
          answers,
        });
        this.savedGeneration = Math.max(this.savedGeneration, generation);
        if (generation === this.saveGeneration) this.liveStatus = this.copy("saved");
        } catch (reason) {
        if (reason?.fields) this.errors = { ...this.errors, ...reason.fields };
        this.liveStatus = "Progress is stored on this device. Online save will retry.";
        window.clearTimeout(this.autosaveTimer);
        this.autosaveTimer = window.setTimeout(() => this.saveProgress(), 4000);
        }
      })();
      await this.savePromise;
      this.savePromise = null;
      this.saving = false;
      if (this.saveQueued && this.saveGeneration > this.savedGeneration) return this.saveProgress();
    },
    validateCurrentSection() {
      for (const question of this.currentQuestions().filter((item) => item.type === "ranking" && !this.answers[item.id])) this.answers[question.id] = this.rankingValues(question);
      const result = validateSurveyAnswers(this.definition, this.answers, { submissionId: this.session?.submissionId });
      const ids = new Set(this.currentQuestions().map((question) => question.id));
      this.errors = Object.fromEntries(Object.entries(result.errors).filter(([questionId]) => ids.has(questionId)));
      return Object.keys(this.errors).length === 0;
    },
    async nextSection() {
      if (!this.validateCurrentSection()) {
        this.liveStatus = `${Object.keys(this.errors).length} question(s) need attention.`;
        await this.$nextTick();
        document.querySelector(".survey-runner-question.has-error input, .survey-runner-question.has-error textarea, .survey-runner-question.has-error select")?.focus();
        return;
      }
      await this.saveProgress();
      if (this.sectionIndex < this.sections().length - 1) {
        this.sectionIndex += 1;
        this.persistLocal();
        window.scrollTo({ top: 0, behavior: "smooth" });
      } else if (this.definition?.settings?.allowReview !== false) {
        this.reviewing = true;
        window.scrollTo({ top: 0, behavior: "smooth" });
      } else {
        await this.submitResponse();
      }
    },
    previousSection() {
      if (this.reviewing) this.reviewing = false;
      else this.sectionIndex = Math.max(0, this.sectionIndex - 1);
      this.persistLocal();
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    editQuestion(question) {
      const index = this.sections().findIndex((section) => section.blocks?.some((item) => item.id === question.id));
      this.sectionIndex = Math.max(0, index);
      this.reviewing = false;
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    async uploadFile(question, event) {
      const file = event.target.files?.[0];
      if (!file || file.size > 15 * 1024 * 1024) {
        this.errors[question.id] = "Choose an allowed file smaller than 15 MB.";
        return;
      }
      if (this.preview) {
        this.setAnswer(question.id, { path: `${this.session.submissionId}/${question.id}/${encodeURIComponent(file.name)}`, name: file.name, type: file.type, size: file.size });
        this.liveStatus = "Preview file selected; nothing was uploaded.";
        event.target.value = "";
        return;
      }
      this.liveStatus = "Preparing private upload…";
      try {
        const grant = await invokeSurveyPublic("upload", {
          token: this.token, invitationToken: this.invitationToken, submissionId: this.session.submissionId, resumeToken: this.session.resumeToken,
          embedOrigin: embedOrigin(), questionId: question.id, fileName: file.name, contentType: file.type,
        });
        const { error } = await getSupabaseClient().storage.from("aoi-survey-uploads").uploadToSignedUrl(grant.path, grant.token, file, { contentType: grant.contentType });
        if (error) throw error;
        this.setAnswer(question.id, { path: grant.path, name: grant.fileName, type: grant.contentType, size: file.size });
        this.liveStatus = "Private file uploaded.";
      } catch {
        this.errors[question.id] = "The file could not be uploaded.";
      } finally { event.target.value = ""; }
    },
    async submitResponse() {
      if (this.submitting || this.completed) return;
      const validation = validateSurveyAnswers(this.definition, this.answers, { submissionId: this.session?.submissionId });
      if (!validation.valid) {
        this.errors = validation.errors;
        const first = this.allQuestions().find((question) => validation.errors[question.id]);
        if (first) this.editQuestion(first);
        return;
      }
      this.submitting = true;
      this.error = "";
      try {
        this.idempotencyKey ||= globalThis.crypto.randomUUID();
        this.persistLocal();
        if (!this.preview) await invokeSurveyPublic("submit", {
          token: this.token,
          invitationToken: this.invitationToken,
          embedOrigin: embedOrigin(),
          submissionId: this.session.submissionId,
          resumeToken: this.session.resumeToken,
          answers: this.answers,
          idempotencyKey: this.idempotencyKey,
          score: calculateSurveyScore(this.definition, this.answers),
          consent: { accepted: this.consentAccepted, locale: this.locale, versionId: this.link.versionId, submittedAt: new Date().toISOString() },
        });
        this.completed = true;
        this.reviewing = false;
        globalThis.localStorage.removeItem(storageKey(this.token));
        window.scrollTo({ top: 0, behavior: "smooth" });
        const redirectUrl = this.preview ? "" : this.definition?.completion?.redirectUrl;
        if (redirectUrl) {
          const redirect = new URL(redirectUrl);
          if (["http:", "https:"].includes(redirect.protocol)) window.setTimeout(() => location.assign(redirect.href), 1200);
        }
      } catch (reason) {
        if (reason?.fields && Object.keys(reason.fields).length) {
          this.errors = reason.fields;
          const first = this.allQuestions().find((question) => reason.fields[question.id]);
          if (first) this.editQuestion(first);
        }
        this.error = "Your response could not be submitted. Your progress is still saved on this device.";
      } finally { this.submitting = false; }
    },
  }));
}
