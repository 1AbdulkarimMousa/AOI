const BLOCK_TYPES = new Set(["intro", "callout", "steps", "checklist", "table", "do_dont", "example", "faq", "related_article"]);

const copy = (en, zh) => ({ en, zh });

function article(slug, category, pmfLayer, audience, sequence, titleEn, titleZh, summaryEn, summaryZh, tags, bodyEn, bodyZh, featured = false) {
  return {
    slug,
    category,
    pmfLayer,
    audience,
    sequence,
    status: "published",
    featured,
    readingMinutes: Math.max(3, Math.round(bodyEn.length / 2)),
    title: copy(titleEn, titleZh),
    summary: copy(summaryEn, summaryZh),
    tags,
    body: { en: bodyEn, zh: bodyZh },
    updatedAt: "2026-08-05",
    version: 1,
  };
}

export const HELP_CENTER_ARTICLES = [
  article(
    "start-here-pmf-workflow", "start", null, ["admin", "intern"], 1,
    "Start here: the PMF workflow", "从这里开始：PMF 工作流",
    "A short path from a weekly question to a defensible PMF decision.", "从每周问题到可辩护 PMF 决策的简明路径。",
    ["onboarding", "workflow", "start here"],
    [
      { type: "intro", text: "AOI helps the team plan work, collect traceable records, challenge assumptions, and decide what to do next. It is an internal research-operations system, not a clinical record or medical advice product." },
      { type: "steps", title: "Use this order", items: ["Read the current weekly question and evidence standard.", "Recruit or select the right segment and situation.", "Capture the source, behavior, limitation, and consent state.", "Review supporting and contradictory records together.", "Recommend one next action and move the decision through the appropriate Gate."] },
      { type: "checklist", title: "You are ready to move on when", items: ["The question is specific enough to falsify.", "Every important claim has a source or session reference.", "Counterevidence is visible instead of hidden.", "The next action has an owner and a due date."] },
      { type: "callout", tone: "gold", title: "Core habit", text: "Do not try to prove the team right. Build the smallest record that helps the team find out what is true." },
    ],
    [
      { type: "intro", text: "AOI 帮助团队规划工作、收集可追溯记录、挑战假设，并决定下一步。它是内部研究运营系统，不是临床记录系统，也不是医疗建议产品。" },
      { type: "steps", title: "按这个顺序使用", items: ["阅读当前每周问题和证据标准。", "选择正确的细分人群和具体情境。", "记录来源、行为、局限和同意状态。", "同时检查支持证据和反证。", "提出一个下一步行动，并将决策推进到相应闸门。"] },
      { type: "checklist", title: "满足以下条件后再继续", items: ["问题足够具体，可以被证伪。", "每个重要主张都有来源或会话引用。", "反证清晰可见，没有被隐藏。", "下一步行动有负责人和截止日期。"] },
      { type: "callout", tone: "gold", title: "核心习惯", text: "不要试图证明团队是对的。建立最小而完整的记录，帮助团队找出事实。" },
    ],
    true,
  ),
  article(
    "pmf-five-layers", "method", null, ["admin", "intern"], 2,
    "The five PMF layers", "五个 PMF 层级",
    "Understand what each layer proves, what it does not prove, and when to advance.", "了解每一层要证明什么、不能证明什么，以及何时推进。",
    ["H1", "H2", "H3", "H4", "H5", "framework"],
    [
      { type: "table", title: "The validation chain", columns: ["Layer", "Question", "Evidence focus"], rows: [["H1 · Need Truth", "Is the need real and consequential?", "Frequency, significance, visibility, actionability"], ["H2 · Solution Gap", "Where do current solutions fail?", "Workarounds, failure points, switching readiness"], ["H3 · Product Value", "Does Ambiloop complete the job better?", "Capture, compare, understand, act"], ["H4 · Repeatability", "Will value return after novelty fades?", "Natural triggers, Week 1/2/4 reuse, friction"], ["H5 · Value Exchange", "Will people make a real commitment?", "Price, offer fit, subscription, deposit, purchase"]] },
      { type: "steps", title: "How to use the layers", items: ["Start with the narrowest segment and situation.", "Collect the evidence required by the current layer.", "Do not use a later-layer result to cover an earlier-layer gap.", "Record the decision as validated, provisional, partial, contradicted, or insufficient."] },
      { type: "callout", tone: "blue", title: "Important", text: "A strong product demo cannot prove that the need is important. A positive price answer cannot prove repeat use." },
    ],
    [
      { type: "table", title: "验证链", columns: ["层级", "核心问题", "证据重点"], rows: [["H1 · 需求真实性", "需求是否真实且后果重要？", "频率、重要性、可见性、可行动性"], ["H2 · 方案缺口", "现有方案在哪些地方失败？", "替代行为、失败点、转换意愿"], ["H3 · 产品价值", "Ambiloop 是否更好地完成任务？", "捕捉、对比、理解、行动"], ["H4 · 可重复性", "新鲜感消失后还会产生价值吗？", "自然触发、第 1/2/4 周复用、阻力"], ["H5 · 价值交换", "用户是否愿意做出真实承诺？", "价格、报价匹配、订阅、定金、购买"]] },
      { type: "steps", title: "如何使用层级", items: ["从最窄的细分人群和情境开始。", "收集当前层级要求的证据。", "不要用后续层级的结果掩盖前一层的缺口。", "将决策记录为已验证、暂定、部分验证、被反驳或证据不足。"] },
      { type: "callout", tone: "blue", title: "重要提醒", text: "优秀的产品演示不能证明需求重要。积极的价格回答也不能证明用户会持续使用。" },
    ],
    true,
  ),
  article(
    "weekly-question-to-plan", "method", null, ["admin", "intern"], 3,
    "Turn a weekly question into a research plan", "把每周问题变成研究计划",
    "Define the hypothesis, evidence standard, sample, owner, and readout before fieldwork begins.", "在开始执行前定义假设、证据标准、样本、负责人和汇报方式。",
    ["weekly question", "hypothesis", "sample plan"],
    [
      { type: "steps", title: "Five planning moves", items: ["Write one MECE question connected to one PMF layer.", "State what would support the hypothesis and what would contradict it.", "Choose the people or sources that can answer the question.", "Set minimum and maximum sample targets, timing, and owner.", "Define the decision that the evidence will unlock."] },
      { type: "do_dont", title: "Make the question testable", do: ["Ask about a recent situation and action.", "Name the segment and context.", "Define the threshold before reviewing results."], avoid: ["Ask whether people like the idea in general.", "Mix five unrelated questions into one.", "Change the success rule after seeing the data."] },
      { type: "example", title: "Useful framing", text: "For adult orthodontic patients, do visible hygiene changes between visits create enough concern and action to justify repeat monitoring?" },
    ],
    [
      { type: "steps", title: "五个计划动作", items: ["写一个与一个 PMF 层级相连、且互不重叠的问题。", "说明哪些结果支持假设，哪些结果会反驳假设。", "选择能够回答问题的人或来源。", "设定最小和最大样本、时间安排和负责人。", "明确证据将解锁哪一个决策。"] },
      { type: "do_dont", title: "让问题可验证", do: ["询问最近发生的情境和采取的行动。", "明确细分人群和上下文。", "在查看结果前定义阈值。"], avoid: ["泛泛询问用户是否喜欢想法。", "把五个无关问题混在一起。", "看到数据后再改变成功标准。"] },
      { type: "example", title: "有效表述", text: "对于成年正畸患者，复诊间隔期可见的口腔卫生变化是否会产生足够的担忧和行动，从而支持持续监测？" },
    ],
  ),
  article(
    "capture-a-session", "collection", null, ["admin", "intern"], 4,
    "Capture a research session", "记录研究会话",
    "Record real behavior and the most recent incident before interpreting what it means.", "先记录真实行为和最近事件，再解释它意味着什么。",
    ["session", "JTBD", "current behavior"],
    [
      { type: "steps", title: "Before you submit", items: ["Choose the segment, PMF layer, method, and session date.", "Write what the person does today, not what you hope they will do.", "Record a recent incident with enough detail to verify it later.", "Describe the current action or workaround.", "State the unmet need and the limitations of the session."] },
      { type: "callout", tone: "orange", title: "Use neutral language", text: "Write: 'They searched online and waited for the next visit.' Do not write: 'They need Ambiloop.' The first is a record; the second is an interpretation." },
      { type: "checklist", title: "Submission check", items: ["The session is linked to the correct segment.", "The unmet need is specific.", "The note includes a limitation.", "Consent allows the planned research use."] },
    ],
    [
      { type: "steps", title: "提交前检查", items: ["选择细分人群、PMF 层级、方法和会话日期。", "记录当下真实行为，而不是你希望用户采取的行为。", "详细记录最近一次事件，确保之后可以核对。", "描述当前行动或替代方案。", "说明未满足的需求和本次会话的局限。"] },
      { type: "callout", tone: "orange", title: "使用中性语言", text: "写：‘对方在网上搜索，并等到下一次复诊。’不要写：‘对方需要 Ambiloop。’前者是记录，后者是解释。" },
      { type: "checklist", title: "提交检查", items: ["会话连接到了正确的细分人群。", "未满足需求足够具体。", "记录包含局限。", "同意状态允许计划中的研究用途。"] },
    ],
  ),
  article(
    "write-strong-evidence", "evidence", null, ["admin", "intern"], 5,
    "Write evidence that can survive review", "写出经得起评审的证据",
    "A useful evidence record is precise, sourced, balanced, and honest about uncertainty.", "有用的证据记录应当准确、有来源、平衡，并诚实面对不确定性。",
    ["evidence", "strength", "limitations", "counterevidence"],
    [
      { type: "table", title: "Evidence strength", columns: ["Strength", "Meaning", "Use"], rows: [["1", "Opinion or preference", "Generate a question; do not conclude"], ["2", "Reported past behavior", "Useful directional signal"], ["3", "Observable or verifiable behavior", "Strong decision input"], ["4", "Product or payment behavior", "Highest commercial weight"]] },
      { type: "steps", title: "Record the complete chain", items: ["Name the finding in one precise sentence.", "Quote or summarize the source without adding meaning.", "Mark supporting, contradicting, or neutral.", "Choose the strength that matches the source.", "Add the limitation and decision relevance."] },
      { type: "callout", tone: "red", title: "Never hide counterevidence", text: "Every hypothesis must carry both supporting and contradicting records. If the evidence is mixed, the decision should say so." },
    ],
    [
      { type: "table", title: "证据强度", columns: ["强度", "含义", "用途"], rows: [["1", "观点或偏好", "生成问题，不得直接下结论"], ["2", "过去行为的自述", "有方向性的信号"], ["3", "可观察或可验证行为", "强决策输入"], ["4", "产品或支付行为", "最高商业权重"]] },
      { type: "steps", title: "记录完整链条", items: ["用一句准确的话命名发现。", "引用或概括来源，不要添加额外含义。", "标记为支持、反驳或中性。", "选择与来源匹配的强度。", "补充局限和决策相关性。"] },
      { type: "callout", tone: "red", title: "不要隐藏反证", text: "每个假设都必须同时拥有支持记录和反驳记录。如果证据混合，决策也应明确说明。" },
    ],
    true,
  ),
  article(
    "sample-plan-and-recruitment", "collection", null, ["admin", "intern"], 6,
    "Build a sample plan without overclaiming", "建立样本计划，避免过度推断",
    "Use the planned, minimum, maximum, actual, and completion fields consistently.", "一致使用计划数、最小数、最大数、实际数和完成率字段。",
    ["sample", "recruitment", "segments"],
    [
      { type: "steps", title: "Plan each sample row", items: ["Name the PMF layer and sample category.", "Define who qualifies and where the source comes from.", "Set a minimum for decision usefulness and a maximum for diminishing returns.", "Record the planned count and owner.", "Update actual count and completion continuously during execution."] },
      { type: "do_dont", title: "Protect sample quality", do: ["Use stable IDs in analytical sheets.", "Track source, consent, stage, and status.", "Call out geographic or referral bias."], avoid: ["Treat a friend sample as primary PMF evidence.", "Count the same new sample twice.", "Fill a count before the record exists."] },
    ],
    [
      { type: "steps", title: "规划每一行样本", items: ["写明 PMF 层级和样本类别。", "定义资格标准和来源。", "设定有决策价值的最小数，以及收益递减后的最大数。", "记录计划数量和负责人。", "在执行期间持续更新实际数量和完成率。"] },
      { type: "do_dont", title: "保护样本质量", do: ["在分析表中使用稳定 ID。", "跟踪来源、同意状态、阶段和状态。", "明确地理或转介绍偏差。"], avoid: ["把朋友样本当作主要 PMF 证据。", "重复计算同一个新样本。", "在记录尚不存在时填写数量。"] },
    ],
  ),
  article(
    "product-and-price-testing", "collection", "H3", ["admin", "intern"], 7,
    "Run product-value and price tests", "执行产品价值和价格测试",
    "Measure the Capture, Compare, Understand, Act chain before asking whether a price feels acceptable.", "先衡量捕捉、对比、理解、行动链条，再询问用户是否接受价格。",
    ["H3", "H5", "price", "product event"],
    [
      { type: "steps", title: "Product-value sequence", items: ["Log the trigger and target user.", "Record whether capture produced a valid image.", "Record whether comparison was used and understood.", "Record the value obtained and action taken.", "Log friction, assistance, and anything shared with a professional."] },
      { type: "steps", title: "Value-exchange sequence", items: ["Show one clearly defined offer and price anchor.", "Record purchase intent and reasonable price range.", "Ask which offer fits: hardware-only, basic app, or family plan.", "Record the primary objection without arguing.", "Give real commitment the highest weight: deposit, preorder, purchase, or paid retention."] },
      { type: "callout", tone: "gold", title: "Avoid the hypothetical trap", text: "Intent is directional. A paid commitment is stronger evidence than a positive answer about a future purchase." },
    ],
    [
      { type: "steps", title: "产品价值顺序", items: ["记录触发因素和目标用户。", "记录是否成功捕捉到有效图像。", "记录是否使用并理解了对比。", "记录获得的价值和采取的行动。", "记录阻力、所需协助以及是否分享给专业人士。"] },
      { type: "steps", title: "价值交换顺序", items: ["展示一个清晰定义的报价和价格锚点。", "记录购买意愿和合理价格区间。", "询问哪种报价匹配：仅硬件、基础应用或家庭计划。", "不争辩，记录主要异议。", "真实承诺权重最高：定金、预购、购买或付费留存。"] },
      { type: "callout", tone: "gold", title: "避免假设陷阱", text: "意愿只能提供方向。真实付费承诺比对未来购买的积极回答更强。" },
    ],
  ),
  article(
    "repeatability-home-use", "method", "H4", ["admin", "intern"], 8,
    "Test repeatability, not novelty", "测试可重复性，而不是新鲜感",
    "Design the home-use cohort around natural triggers, Week 1/2/4 reuse, repeated value, and friction.", "围绕自然触发、第 1/2/4 周复用、重复价值和阻力设计家庭使用队列。",
    ["H4", "repeatability", "home use"],
    [
      { type: "steps", title: "Set the repeat-use test", items: ["Identify the event that naturally brings the person back.", "Define what value should appear in Week 1, Week 2, and Week 4.", "Log every product event, including failed or abandoned sessions.", "Ask what changed, what action followed, and whether the user would repeat.", "Measure ongoing burden: operation, cleaning, charging, connection, and time."] },
      { type: "checklist", title: "A repeatable use case has", items: ["A clear trigger outside the study prompt.", "A reason to return after the first session.", "A repeated value that is not just curiosity.", "A routine burden low enough to sustain.", "A meaningful retention or stopping reason."] },
    ],
    [
      { type: "steps", title: "设置重复使用测试", items: ["确定自然带来再次使用的事件。", "定义第 1、2、4 周应出现的价值。", "记录每次产品事件，包括失败或放弃的会话。", "询问发生了什么变化、采取了什么行动，以及是否愿意再次使用。", "衡量持续负担：操作、清洁、充电、连接和时间。"] },
      { type: "checklist", title: "可重复使用场景应具备", items: ["研究提示之外的清晰触发因素。", "第一次使用后再次返回的理由。", "不只是好奇心的重复价值。", "足够低、可以维持的日常负担。", "有意义的留存或停止原因。"] },
    ],
  ),
  article(
    "gate-decision-and-readout", "method", null, ["admin", "intern"], 9,
    "Prepare a Gate decision and weekly readout", "准备闸门决策和每周汇报",
    "Turn the evidence balance into one honest decision, one implication, and one next action.", "把证据平衡转化为一个诚实决策、一个影响和一个下一步行动。",
    ["Gate", "readout", "decision"],
    [
      { type: "steps", title: "Write the readout", items: ["State what we learned in plain language.", "Explain why it matters to the PMF layer and priority segment.", "Show the strongest support and strongest contradiction.", "Name the sample, methodology, and limitations.", "Recommend Go, Revise, Stop, or Insufficient evidence with one next action."] },
      { type: "do_dont", title: "Make the decision useful", do: ["Keep the decision tied to evidence.", "Say what would change your mind.", "Give the next owner a concrete deliverable."], avoid: ["Use confidence as a substitute for sample quality.", "Call a plan a result.", "End with 'do more research' without a focused question."] },
      { type: "callout", tone: "teal", title: "Decision standard", text: "A Gate snapshot freezes the approved readout; it does not make weak evidence strong." },
    ],
    [
      { type: "steps", title: "编写汇报", items: ["用清晰语言说明我们学到了什么。", "解释它为什么影响 PMF 层级和优先细分人群。", "展示最强支持和最强反证。", "说明样本、方法和局限。", "用一个下一步行动提出 Go、Revise、Stop 或证据不足。"] },
      { type: "do_dont", title: "让决策有用", do: ["让决策始终连接证据。", "说明什么结果会改变你的判断。", "给下一位负责人一个具体交付物。"], avoid: ["用信心替代样本质量。", "把计划称为结果。", "用没有重点的问题结束：‘继续研究’。"] },
      { type: "callout", tone: "teal", title: "决策标准", text: "闸门快照冻结已批准的汇报内容，但不会让薄弱证据变强。" },
    ],
    true,
  ),
  article(
    "data-handling-and-ai", "security", null, ["admin", "intern"], 10,
    "Handle research data and AI responsibly", "负责任地处理研究数据和 AI",
    "Protect identifiers, consent, confidential materials, and the boundary between assistance and judgment.", "保护身份信息、同意记录、机密材料，并区分辅助工具和人的判断。",
    ["security", "consent", "AI", "confidentiality"],
    [
      { type: "checklist", title: "Before you save or share", items: ["Use a stable ID in analytical records instead of a personal name.", "Check the latest consent before using recordings, images, quotes, or recontact.", "Keep source links and confidential files inside approved systems.", "Separate facts, participant statements, assumptions, and interpretation.", "Do not make medical, regulatory, pricing, or contractual claims without authorization."] },
      { type: "do_dont", title: "Use AI carefully", do: ["Brainstorm structure or improve language for approved non-confidential material.", "Verify every source and conclusion independently.", "Adapt drafts to the actual PMF question."], avoid: ["Upload confidential research to an unapproved tool.", "Use AI output as primary research.", "Present generated text as original evidence or judgment."] },
      { type: "callout", tone: "red", title: "Escalate early", text: "If consent, confidentiality, or authorization is unclear, pause the action and ask an administrator." },
    ],
    [
      { type: "checklist", title: "保存或分享前", items: ["在分析记录中使用稳定 ID，而不是个人姓名。", "使用录音、图像、引文或再次联系前检查最新同意状态。", "将来源链接和机密文件保留在批准的系统内。", "区分事实、参与者陈述、假设和解释。", "未经授权，不得提出医疗、监管、价格或合同承诺。"] },
      { type: "do_dont", title: "谨慎使用 AI", do: ["为已批准的非机密材料头脑风暴结构或改进语言。", "独立核验每个来源和结论。", "将草稿适配到真实 PMF 问题。"], avoid: ["将机密研究上传到未批准的工具。", "用 AI 输出替代一手研究。", "把生成文本当作原创证据或判断。"] },
      { type: "callout", tone: "red", title: "尽早升级", text: "如果同意、保密或授权不明确，请暂停操作并询问管理员。" },
    ],
  ),
];

function present(value) {
  return value !== undefined && value !== null && String(value).trim() !== "";
}

function blockText(block) {
  return JSON.stringify(block || {}).toLowerCase();
}

export function validateArticle(value = {}) {
  const errors = [];
  if (!present(value.slug)) errors.push("Slug is required.");
  if (!present(value.title?.en)) errors.push("English title is required.");
  if (!present(value.title?.zh)) errors.push("Chinese title is required.");
  if (!present(value.summary?.en)) errors.push("English summary is required.");
  if (!present(value.summary?.zh)) errors.push("Chinese summary is required.");
  if (!present(value.category)) errors.push("Category is required.");
  if (value.pmfLayer !== null && value.pmfLayer !== undefined && !/^H[1-5]$/.test(value.pmfLayer)) errors.push("PMF layer must be H1 through H5.");
  for (const locale of ["en", "zh"]) {
    if (!Array.isArray(value.body?.[locale]) || !value.body[locale].length) errors.push(`${locale} body needs at least one block.`);
    for (const block of value.body?.[locale] || []) {
      if (!BLOCK_TYPES.has(block.type)) errors.push("Body contains an unsupported block type.");
      if (/<\/?[a-z][^>]*>/i.test(blockText(block))) errors.push("Body blocks cannot contain raw HTML.");
    }
  }
  return [...new Set(errors)];
}

function searchableArticleText(article) {
  return JSON.stringify({
    title: article.title,
    summary: article.summary,
    tags: article.tags,
    category: article.category,
    pmfLayer: article.pmfLayer,
    body: article.body,
  }).toLowerCase();
}

export function searchHelpArticles(articles = [], query = "") {
  const term = String(query || "").trim().toLowerCase();
  if (!term) return articles;
  return articles.filter((article) => searchableArticleText(article).includes(term));
}

export function filterHelpArticles(articles = [], filters = {}) {
  return articles.filter((article) => {
    if (filters.status && article.status !== filters.status) return false;
    if (filters.category && article.category !== filters.category) return false;
    if (filters.pmfLayer && article.pmfLayer !== filters.pmfLayer) return false;
    if (filters.audience && !article.audience?.includes(filters.audience)) return false;
    return true;
  });
}

export function sortHelpArticles(articles = []) {
  return [...articles].sort((a, b) => Number(a.sequence || 0) - Number(b.sequence || 0) || String(a.title?.en || "").localeCompare(String(b.title?.en || "")));
}

export function createArticleDraft() {
  return {
    slug: "",
    category: "method",
    pmfLayer: null,
    audience: ["admin", "intern"],
    sequence: 99,
    status: "draft",
    featured: false,
    title: { en: "", zh: "" },
    summary: { en: "", zh: "" },
    tags: [],
    body: {
      en: [{ type: "intro", text: "" }],
      zh: [{ type: "intro", text: "" }],
    },
    updatedAt: new Date().toISOString().slice(0, 10),
    version: 0,
  };
}

export function blockTextValue(block, key = "items") {
  const value = block?.[key];
  return Array.isArray(value) ? value.join("\n") : String(value || "");
}

export function setBlockTextValue(block, key, value) {
  if (["items", "do", "avoid"].includes(key)) block[key] = String(value || "").split("\n").map((item) => item.trim()).filter(Boolean);
  else block[key] = String(value || "");
  return block;
}
