import "../../css/surveys.css";
import { invokeSurveyPublic } from "../api.js";
import { getSupabaseClient } from "../supabase.js";
import { calculateSurveyFields, calculateSurveyScore, deterministicOrder, evaluateVisibility, renderPipedText, surveyQuestions, validateSurveyAnswers } from "./domain.js";

function tokenFromLocation() {
  return new URLSearchParams(location.hash.replace(/^#/, "")).get("token") || "";
}

function invitationTokenFromLocation() {
  return new URLSearchParams(location.hash.replace(/^#/, "")).get("invite") || "";
}

function storageKey(token) {
  return `aoi-survey-response:${token.slice(0, 16)}`;
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

    async init() {
      this.token = tokenFromLocation();
      this.invitationToken = invitationTokenFromLocation();
      if (this.token.length < 32) {
        this.error = "This survey link is unavailable.";
        this.loading = false;
        this.ready = true;
        return;
      }
      try {
        this.link = await invokeSurveyPublic("load", { token: this.token, invitationToken: this.invitationToken });
        this.definition = this.link.definition;
        this.locale = localStorage.getItem("aoi-survey-locale") === "zh-CN" ? "zh-CN" : this.definition.defaultLocale || "en";
        document.documentElement.lang = this.locale;
        const restored = globalThis.localStorage.getItem(storageKey(this.token));
        if (restored) {
          const saved = JSON.parse(restored);
          this.session = saved.session || null;
          this.answers = saved.answers || {};
          this.sectionIndex = Math.min(Number(saved.sectionIndex) || 0, Math.max(0, this.sections().length - 1));
          this.started = Boolean(this.session);
          this.consentAccepted = Boolean(saved.consentAccepted);
          this.idempotencyKey = saved.idempotencyKey || "";
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
      this.locale = this.locale === "en" ? "zh-CN" : "en";
      document.documentElement.lang = this.locale;
      localStorage.setItem("aoi-survey-locale", this.locale);
    },
    sections() {
      const sections = (this.definition?.blocks || []).filter((section) => section.type === "section");
      return this.definition?.settings?.randomizeSections && this.session
        ? deterministicOrder(sections, `${this.session.submissionId}:sections`)
        : sections;
    },
    surveyQuestions(definition = this.definition) { return surveyQuestions(definition || { blocks: [] }); },
    currentSection() { return this.sections()[this.sectionIndex] || null; },
    visibleQuestionIds() { return new Set(evaluateVisibility(this.definition, this.answers)); },
    currentQuestions() {
      const section = this.currentSection();
      const questions = (section?.blocks || []).filter((question) => question.type !== "hidden" && this.visibleQuestionIds().has(question.id));
      return section?.randomizeQuestions && this.session
        ? deterministicOrder(questions, `${this.session.submissionId}:${section.id}`)
        : questions;
    },
    questionOptions(question) {
      return question.randomizeOptions && this.session
        ? deterministicOrder(question.options || [], `${this.session.submissionId}:${question.id}:options`)
        : question.options || [];
    },
    allQuestions() { return surveyQuestions(this.definition || { blocks: [] }).filter((question) => question.type !== "hidden" && this.visibleQuestionIds().has(question.id)); },
    progress() { return this.sections().length ? Math.round((this.sectionIndex + (this.reviewing ? 1 : 0)) / this.sections().length * 100) : 0; },
    answerLabel(question, value) {
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
        this.session = await invokeSurveyPublic("start", {
          token: this.token,
          invitationToken: this.invitationToken,
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
      delete this.errors[questionId];
      this.persistLocal();
      this.scheduleSave();
    },
    toggleAnswer(questionId, value) {
      const selected = new Set(Array.isArray(this.answers[questionId]) ? this.answers[questionId] : []);
      if (selected.has(value)) selected.delete(value); else selected.add(value);
      this.setAnswer(questionId, [...selected]);
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
      this.saving = true;
      try {
        await invokeSurveyPublic("save", {
          token: this.token,
          invitationToken: this.invitationToken,
          submissionId: this.session.submissionId,
          resumeToken: this.session.resumeToken,
          answers: this.answers,
        });
        this.liveStatus = this.copy("saved");
      } catch {
        this.liveStatus = "Progress is stored on this device. Online save will retry.";
        window.clearTimeout(this.autosaveTimer);
        this.autosaveTimer = window.setTimeout(() => this.saveProgress(), 4000);
      } finally { this.saving = false; }
    },
    validateCurrentSection() {
      for (const question of this.currentQuestions().filter((item) => item.type === "ranking" && !this.answers[item.id])) this.answers[question.id] = this.rankingValues(question);
      const result = validateSurveyAnswers(this.definition, this.answers);
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
      } else {
        this.reviewing = true;
        window.scrollTo({ top: 0, behavior: "smooth" });
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
      this.liveStatus = "Preparing private upload…";
      try {
        const grant = await invokeSurveyPublic("upload", {
          token: this.token, invitationToken: this.invitationToken, submissionId: this.session.submissionId, resumeToken: this.session.resumeToken,
          questionId: question.id, fileName: file.name, contentType: file.type,
        });
        const { error } = await getSupabaseClient().storage.from("aoi-survey-uploads").uploadToSignedUrl(grant.path, grant.token, file, { contentType: file.type });
        if (error) throw error;
        this.setAnswer(question.id, { path: grant.path, name: file.name, type: file.type, size: file.size });
        this.liveStatus = "Private file uploaded.";
      } catch {
        this.errors[question.id] = "The file could not be uploaded.";
      } finally { event.target.value = ""; }
    },
    async submitResponse() {
      const validation = validateSurveyAnswers(this.definition, this.answers);
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
        await invokeSurveyPublic("submit", {
          token: this.token,
          invitationToken: this.invitationToken,
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
      } catch {
        this.error = "Your response could not be submitted. Your progress is still saved on this device.";
      } finally { this.submitting = false; }
    },
  }));
}
