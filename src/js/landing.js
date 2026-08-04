const copy = {
  en: {
    navProduct: "Product", navMethod: "PMF method", navSecurity: "Security", login: "Log in", openWorkspace: "Open workspace",
    eyebrow: "AOI research operations", headlineA: "Turn every research signal into a", headlineB: "confident PMF decision.",
    subhead: "Plan the work, recruit the right people, trace every piece of evidence, and move five PMF Gates with a shared source of truth.",
    primaryCta: "Enter Ambiloop Ops", secondaryCta: "Explore the workflow", trusted: "Built for focused research teams",
    sectionEyebrow: "One operating rhythm", sectionHeadline: "From assignment to evidence to decision, without spreadsheet archaeology.",
    sectionCopy: "Each workflow keeps owners, source records, counterevidence, revisions, and approvals connected so the team always knows what happens next.",
    featureOne: "Make the next action obvious", featureOneCopy: "Interns get a prioritized work queue with acceptance checks, due dates, feedback, and supporting records in one place.",
    featureTwo: "Keep conclusions traceable", featureTwoCopy: "Every hypothesis shows supporting evidence, counterevidence, strength, limitations, and the decision it informs.",
    featureThree: "Move Gates with confidence", featureThreeCopy: "Admins review readiness across Need Truth, Solution Gap, Product Value, Repeatability, and Value Exchange.",
    workflowEyebrow: "The Ambiloop loop", workflowHeadline: "A calmer way to run high-accountability research.",
    securityEyebrow: "Private by design", securityHeadline: "Sensitive research stays behind roles, policies, and audit trails.",
    securityCopy: "Direct identifiers remain separate from analysis. Admin actions are checked server-side, and Supabase row-level rules protect workspace data.",
    finalHeadline: "Give every research week a clear finish line.", finalCopy: "Sign in to AOI and move from work queue to evidence trail to PMF decision.", finalCta: "Log in to Ambiloop Ops",
  },
  "zh-CN": {
    navProduct: "产品", navMethod: "PMF 方法", navSecurity: "安全", login: "登录", openWorkspace: "打开工作空间",
    eyebrow: "AOI 研究运营", headlineA: "将每个研究信号转化为", headlineB: "可信的 PMF 决策。",
    subhead: "规划工作、招募合适对象、追踪每条证据，并用一个共享事实来源推进五个 PMF 闸门。",
    primaryCta: "进入 Ambiloop 运营台", secondaryCta: "了解工作流程", trusted: "为专注的研究团队打造",
    sectionEyebrow: "统一运营节奏", sectionHeadline: "从分配到证据再到决策，无需在电子表格中考古。",
    sectionCopy: "每个流程都连接负责人、来源记录、反证、修订和审批，让团队始终知道下一步。",
    featureOne: "让下一步一目了然", featureOneCopy: "实习生在一处获得带验收检查、截止日期、反馈和支持记录的优先工作队列。",
    featureTwo: "让结论可追溯", featureTwoCopy: "每个假设都显示支持证据、反证、强度、局限及其影响的决策。",
    featureThree: "有信心地推进闸门", featureThreeCopy: "管理员评审需求真实性、方案缺口、产品价值、可重复性和价值交换的就绪度。",
    workflowEyebrow: "Ambiloop 循环", workflowHeadline: "运行高责任研究的更从容方式。",
    securityEyebrow: "隐私优先设计", securityHeadline: "敏感研究受角色、政策和审计轨迹保护。",
    securityCopy: "直接身份信息与分析数据分离。管理员操作在服务器端验证，Supabase 行级规则保护工作空间数据。",
    finalHeadline: "让每个研究周都有明确终点。", finalCopy: "登录 AOI，从工作队列走到证据轨迹，再到 PMF 决策。", finalCta: "登录 Ambiloop 运营台",
  },
};

export function registerLanding(Alpine) {
  Alpine.data("landingPage", () => ({
    locale: localStorage.getItem("aoi-locale") === "zh-CN" ? "zh-CN" : "en",
    mobileOpen: false,
    get c() { return copy[this.locale]; },
    toggleLocale() {
      this.locale = this.locale === "en" ? "zh-CN" : "en";
      localStorage.setItem("aoi-locale", this.locale);
      document.documentElement.lang = this.locale;
    },
    init() { document.documentElement.lang = this.locale; },
  }));
}
