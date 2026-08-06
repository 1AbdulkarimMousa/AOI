import { loadHelpCenter, setHelpArticleStatus, upsertHelpArticle } from "./api.js";
import { getExistingWorkspaceAccess, signOut } from "./auth.js";
import { initials, pageUrl, readableError, routeForRole } from "./core.js";
import "../css/helpcenter.css";
import {
  HELP_CENTER_ARTICLES,
  blockTextValue,
  createArticleDraft,
  filterHelpArticles,
  searchHelpArticles,
  setBlockTextValue,
  sortHelpArticles,
  validateArticle,
} from "./helpcenter-data.js";

const LABELS = {
  en: {
    workspace: "Workspace", collect: "Collect", analyze: "Analyze", helpCenter: "Help Center", administration: "Administration",
    searchHelp: "Search help", admin: "Admin", intern: "Intern", preview: "Preview data", offline: "Offline", live: "Live library synced",
    eyebrow: "Internal PMF field guide", title: "Know what to do next.", subtitle: "Step-by-step Ambiloop PMF guidance for planning, collection, evidence quality, decisions, and safe team routines.",
    searchPlaceholder: "Search a task, PMF layer, workflow, or question…", clear: "Clear", articles: "articles", all: "All", start: "Start here", method: "PMF method", collection: "Collection", evidence: "Evidence quality", security: "Data handling",
    browse: "Browse", pmfPath: "PMF field manual", allGuides: "All guides", layer: "PMF layer", allLayers: "All five layers", adminTools: "Admin tools", allStatuses: "All statuses", published: "Published", draft: "Draft", archived: "Archived", newArticle: "+ New article",
    featuredEyebrow: "Recommended path", featuredTitle: "Begin with the essentials", resultNote: "Plans and standards are guidance, not collected evidence.", libraryEyebrow: "Guide library", libraryTitle: "Practical instructions by workflow", minRead: "min read", openGuide: "Open guide", noResults: "No guide matches this search.", noResultsCopy: "Try a broader term, another layer, or reset the filters.", resetFilters: "Reset filters",
    edit: "Edit", close: "Close", updated: "Updated", inThisGuide: "In this guide", related: "Related guides", previewFooter: "Preview mode · local-only Help Center data", internalFooter: "Internal PMF guidance · not medical advice",
    editArticle: "Edit article", editorCopy: "Maintain both languages and use structured blocks. Raw HTML is not accepted.", cancel: "Cancel", saving: "Saving…", saveDraft: "Save draft", publish: "Publish", archive: "Archive",
  },
  "zh-CN": {
    workspace: "工作空间", collect: "采集", analyze: "分析", helpCenter: "帮助中心", administration: "系统管理",
    searchHelp: "搜索帮助", admin: "管理员", intern: "实习生", preview: "预览数据", offline: "离线", live: "实时资料库已同步",
    eyebrow: "内部 PMF 实务指南", title: "清楚知道下一步。", subtitle: "面向 Ambiloop PMF 规划、采集、证据质量、决策和安全团队流程的分步指南。",
    searchPlaceholder: "搜索任务、PMF 层级、工作流或问题…", clear: "清除", articles: "篇指南", all: "全部", start: "从这里开始", method: "PMF 方法", collection: "研究采集", evidence: "证据质量", security: "数据处理",
    browse: "浏览", pmfPath: "PMF 实务手册", allGuides: "全部指南", layer: "PMF 层级", allLayers: "全部五个层级", adminTools: "管理员工具", allStatuses: "全部状态", published: "已发布", draft: "草稿", archived: "已归档", newArticle: "+ 新建指南",
    featuredEyebrow: "推荐路径", featuredTitle: "先掌握核心内容", resultNote: "计划和标准属于指导，不是已收集的证据。", libraryEyebrow: "指南资料库", libraryTitle: "按工作流组织的实用说明", minRead: "分钟阅读", openGuide: "打开指南", noResults: "没有匹配的指南。", noResultsCopy: "尝试更宽泛的关键词、其他层级，或重置筛选。", resetFilters: "重置筛选",
    edit: "编辑", close: "关闭", updated: "更新于", inThisGuide: "本指南内容", related: "相关指南", previewFooter: "预览模式 · 仅本地帮助中心数据", internalFooter: "内部 PMF 指导 · 非医疗建议",
    editArticle: "编辑指南", editorCopy: "请同时维护两种语言并使用结构化区块。不接受原始 HTML。", cancel: "取消", saving: "保存中…", saveDraft: "保存草稿", publish: "发布", archive: "归档",
  },
};

const LAYERS = [
  { code: "H1", name: "Need Truth" },
  { code: "H2", name: "Solution Gap" },
  { code: "H3", name: "Product Value" },
  { code: "H4", name: "Repeatability" },
  { code: "H5", name: "Value Exchange" },
];

function readingMinutes(article) {
  const words = JSON.stringify(article.body?.en || []).split(/\s+/).length;
  return article.readingMinutes || Math.max(3, Math.ceil(words / 190));
}

function normalizeArticle(article) {
  return {
    ...article,
    audience: article.audience || ["admin", "intern"],
    tags: article.tags || [],
    title: article.title || { en: article.titleEn || "", zh: article.titleZh || "" },
    summary: article.summary || { en: article.summaryEn || "", zh: article.summaryZh || "" },
    body: article.body || { en: article.bodyEn || [], zh: article.bodyZh || [] },
    readingMinutes: readingMinutes(article),
  };
}

export function registerHelpCenter(Alpine) {
  Alpine.data("helpCenterPage", () => ({
    access: null,
    ready: false,
    preview: false,
    error: "",
    articles: [],
    query: "",
    category: "all",
    pmfLayer: "all",
    status: "all",
    selectedArticle: null,
    editorOpen: false,
    editorDraft: createArticleDraft(),
    editorNotice: null,
    publicationNotice: null,
    editorReturnFocus: null,
    tagsText: "",
    saving: false,
    locale: localStorage.getItem("aoi-locale") === "zh-CN" ? "zh-CN" : "en",
    dark: localStorage.getItem("aoi-theme") === "dark",
    mobileNav: false,
    sidebarCollapsed: false,
    loginUrl: pageUrl(import.meta.env.BASE_URL, "login.html"),
    workspaceUrl: pageUrl(import.meta.env.BASE_URL, "workspace.html"),
    administrationUrl: pageUrl(import.meta.env.BASE_URL, "administration.html"),
    layers: LAYERS,
    initials,
    blockTextValue,
    setBlockTextValue,

    async init() {
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
      document.documentElement.lang = this.locale;
      window.addEventListener("popstate", () => this.selectFromUrl());
      const params = new URLSearchParams(location.search);
      if (params.get("preview") === "1") {
        const role = params.get("role") === "intern" ? "intern" : "admin";
        this.access = { role, displayName: role === "intern" ? "AOI Intern" : "AOI Administrator", organizationName: "HUGE DENTAL USA LLC" };
        this.articles = structuredClone(HELP_CENTER_ARTICLES).map(normalizeArticle);
        this.preview = true;
        this.ready = true;
        this.selectFromUrl();
        return;
      }
      try {
        const access = await getExistingWorkspaceAccess();
        if (!access) {
          location.replace(this.loginUrl);
          return;
        }
        if (access.mustChangePassword) {
          location.replace(this.loginUrl);
          return;
        }
        if (!["admin", "intern"].includes(access.role)) {
          location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
          return;
        }
        this.access = access;
        this.workspaceUrl = pageUrl(import.meta.env.BASE_URL, routeForRole(access.role));
        this.locale = localStorage.getItem("aoi-locale") || access.locale || "en";
        document.documentElement.lang = this.locale;
        await this.refresh();
        this.selectFromUrl();
      } catch (reason) {
        this.error = readableError(reason, "Unable to open the Help Center.");
      } finally {
        this.ready = true;
      }
    },

    get labels() { return LABELS[this.locale]; },
    get allArticles() {
      const readable = this.access?.role === "admin" ? this.articles : this.articles.filter((article) => article.status === "published");
      return sortHelpArticles(readable);
    },
    get visibleArticles() {
      const filtered = filterHelpArticles(this.allArticles, {
        category: this.category === "all" ? "" : this.category,
        pmfLayer: this.pmfLayer === "all" ? "" : this.pmfLayer,
        status: this.status === "all" || this.access?.role !== "admin" ? "" : this.status,
      });
      return searchHelpArticles(filtered, this.query);
    },
    get featuredArticles() { return this.visibleArticles.filter((article) => article.featured).slice(0, 3); },
    get libraryArticles() {
      const featured = new Set(this.featuredArticles.map((article) => article.slug));
      return this.visibleArticles.filter((article) => !featured.has(article.slug));
    },
    get currentBody() { return this.selectedArticle?.body?.[this.locale === "zh-CN" ? "zh" : "en"] || []; },

    text(value) { return value?.[this.locale === "zh-CN" ? "zh" : "en"] || value?.en || ""; },
    countCategory(category) { return this.allArticles.filter((article) => article.category === category).length; },
    labelForCategory(category) {
      return { start: this.labels.start, method: this.labels.method, collection: this.labels.collection, evidence: this.labels.evidence, security: this.labels.security }[category] || category;
    },
    statusClass(status) { return { published: "status-approved", draft: "status-partial", archived: "status-blocked" }[status] || "status-assigned"; },
    articleTitle(slug) { return this.text(this.articles.find((article) => article.slug === slug)?.title) || slug; },
    focusSearch() { this.$nextTick(() => this.$refs.search?.focus()); },
    handleSearchShortcut(event) {
      if (!event.metaKey && !event.ctrlKey) return;
      event.preventDefault();
      this.focusSearch();
    },
    toggleTheme() {
      this.dark = !this.dark;
      localStorage.setItem("aoi-theme", this.dark ? "dark" : "light");
      document.documentElement.dataset.theme = this.dark ? "dark" : "light";
    },
    toggleLocale() {
      this.locale = this.locale === "en" ? "zh-CN" : "en";
      localStorage.setItem("aoi-locale", this.locale);
      document.documentElement.lang = this.locale;
    },
    async logout() { await signOut(); location.replace(this.loginUrl); },

    async refresh() {
      this.error = "";
      try {
        const snapshot = await loadHelpCenter();
        this.articles = (snapshot?.articles || []).map(normalizeArticle);
      } catch (reason) {
        this.error = readableError(reason, "Unable to load Help Center articles.");
        if (!this.articles.length) throw reason;
      }
    },
    selectFromUrl() {
      const slug = new URLSearchParams(location.search).get("article");
      this.selectedArticle = slug ? this.allArticles.find((article) => article.slug === slug) || null : null;
    },
    selectArticle(article) {
      this.selectedArticle = article;
      const url = new URL(location.href);
      url.searchParams.set("article", article.slug);
      window.history.pushState({ article: article.slug }, "", url);
      this.$nextTick(() => document.querySelector(".helpcenter-reader")?.scrollIntoView({ behavior: "smooth", block: "start" }));
    },
    selectArticleBySlug(slug) {
      const article = this.allArticles.find((item) => item.slug === slug);
      if (article) this.selectArticle(article);
    },
    closeArticle() {
      if (!this.selectedArticle) return;
      this.selectedArticle = null;
      const url = new URL(location.href);
      url.searchParams.delete("article");
      window.history.pushState({}, "", url);
    },
    openEditor(article = null) {
      if (this.access?.role !== "admin") return;
      this.editorReturnFocus = document.activeElement;
      this.editorDraft = structuredClone(article || createArticleDraft());
      this.tagsText = (this.editorDraft.tags || []).join(", ");
      this.editorNotice = null;
      this.publicationNotice = null;
      this.editorOpen = true;
      this.$nextTick(() => document.querySelector(".help-editor-drawer button")?.focus());
    },
    closeEditor() {
      this.editorOpen = false;
      this.editorNotice = null;
      const returnFocus = this.editorReturnFocus;
      this.editorReturnFocus = null;
      this.$nextTick(() => returnFocus?.focus?.());
    },
    trapEditorFocus(event) {
      if (!this.editorOpen) return;
      const container = document.querySelector(".help-editor-drawer");
      if (!container) return;
      const focusable = [...container.querySelectorAll('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])')].filter((element) => element.offsetParent !== null);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    addEditorBlock(locale) { this.editorDraft.body[locale].push({ type: "steps", title: "", items: [] }); },
    removeEditorBlock(locale, index) {
      if (this.editorDraft.body[locale].length > 1) this.editorDraft.body[locale].splice(index, 1);
    },
    async saveEditor(targetStatus = "draft") {
      if (this.access?.role !== "admin") return;
      const payload = {
        ...structuredClone(this.editorDraft),
        status: targetStatus,
        tags: this.tagsText.split(",").map((tag) => tag.trim()).filter(Boolean),
      };
      const errors = validateArticle(payload);
      if (errors.length) {
        this.editorNotice = { tone: "error", text: errors.join(" ") };
        return;
      }
      this.saving = true;
      try {
        let saved;
        if (this.preview) {
          saved = normalizeArticle({ ...payload, id: payload.id || `preview-${Date.now()}`, version: Number(payload.version || 0) + 1, updatedAt: new Date().toISOString().slice(0, 10) });
        } else {
          saved = normalizeArticle(await upsertHelpArticle(payload, payload.version || null));
          if (saved.status !== targetStatus) {
            try {
              saved = normalizeArticle(await setHelpArticleStatus(saved.id, targetStatus, saved.version));
            } catch (statusReason) {
              const exists = this.articles.some((article) => article.id === saved.id || article.slug === saved.slug);
              this.articles = exists
                ? this.articles.map((article) => article.id === saved.id || article.slug === saved.slug ? saved : article)
                : [...this.articles, saved];
              this.selectedArticle = saved;
              this.editorDraft = structuredClone(saved);
              throw new Error(`Content saved as ${saved.status}. ${readableError(statusReason, "Unable to change article status.")}`);
            }
          }
        }
        const exists = this.articles.some((article) => article.id === saved.id || article.slug === saved.slug);
        this.articles = exists
          ? this.articles.map((article) => article.id === saved.id || article.slug === saved.slug ? saved : article)
          : [...this.articles, saved];
        this.selectedArticle = saved;
        this.editorDraft = structuredClone(saved);
        this.editorNotice = { tone: "success", text: targetStatus === "published" ? "Article published." : targetStatus === "archived" ? "Article archived." : "Draft saved." };
        if (targetStatus !== "draft") {
          this.publicationNotice = { tone: "success", text: this.editorNotice.text };
          this.closeEditor();
        }
      } catch (reason) {
        this.editorNotice = { tone: "error", text: readableError(reason, "Unable to save the article.") };
      } finally {
        this.saving = false;
      }
    },
    async changeStatus(status) {
      if (!this.editorDraft?.id || this.access?.role !== "admin") return this.saveEditor(status);
      this.saving = true;
      try {
        const saved = this.preview
          ? normalizeArticle({ ...this.editorDraft, status, version: Number(this.editorDraft.version || 0) + 1, updatedAt: new Date().toISOString().slice(0, 10) })
          : normalizeArticle(await setHelpArticleStatus(this.editorDraft.id, status, this.editorDraft.version));
        this.articles = this.articles.map((article) => article.id === saved.id ? saved : article);
        this.selectedArticle = saved;
        this.publicationNotice = { tone: "success", text: status === "published" ? "Article published." : status === "archived" ? "Article archived." : "Draft saved." };
        this.closeEditor();
      } catch (reason) {
        this.editorNotice = { tone: "error", text: readableError(reason, "Unable to change the article status.") };
      } finally {
        this.saving = false;
      }
    },
  }));
}
