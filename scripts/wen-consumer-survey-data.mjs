export const WEN_CONSUMER_SURVEY_ASSET_ID = "51000000-0000-4000-8000-000000000001";

const en = (value) => ({ en: value });
const option = (id, label) => ({ id, label: en(label), score: 0 });

function question(number, id, type, title, settings = {}) {
  return {
    id,
    number,
    type,
    title: en(title),
    description: en(settings.description || ""),
    required: settings.required ?? true,
    options: settings.options || [],
    rows: settings.rows || [],
    columns: settings.columns || [],
    validation: settings.validation || {},
    visibility: settings.visibility || null,
    scoring: { weight: 1 },
    randomizeOptions: false,
    pmfMapping: { layer: "", metricCode: "" },
    ...(settings.other ? { other: settings.other } : {}),
    ...(settings.scaleLabels ? { scaleLabels: settings.scaleLabels } : {}),
    ...(settings.privacy ? { privacy: { classification: settings.privacy } } : {}),
  };
}

function choice(number, id, title, labels, settings = {}) {
  return question(number, id, settings.multiple ? "multiple_choice" : "single_choice", title, {
    ...settings,
    options: labels.map(([value, label]) => option(value, label)),
  });
}

function other(optionId = "other") {
  return { optionId, required: true, label: en("Please specify") };
}

function scale(number, id, title, minimum, maximum, minimumLabel, maximumLabel) {
  return question(number, id, "rating", title, {
    validation: { min: minimum, max: maximum, integer: true },
    scaleLabels: { min: en(minimumLabel), max: en(maximumLabel) },
  });
}

function section(id, title, blocks, description = "") {
  return { id, type: "section", title: en(title), description: en(description), blocks };
}

const canonicalDefinition = {
  schemaVersion: 1,
  locales: ["en"],
  defaultLocale: "en",
  title: en("Consumer Oral Health Survey"),
  description: en("For adults responsible for their own or their family's oral health. This survey takes approximately 10 minutes. All questions are about you and your household - there are no right or wrong answers."),
  metadata: {
    author: "Wen Tang",
    estimatedMinutes: 10,
    audience: "Adults responsible for their own or their family's oral health",
    seedKey: "wen-consumer-oral-health-survey-v1",
  },
  settings: { presentation: "sections", showProgress: true, allowReview: true, randomizeSections: false },
  theme: { accent: "orange", density: "comfortable", logoUrl: "" },
  consent: {
    required: true,
    title: en("Research consent"),
    statement: en("I understand that my response will be reviewed and analyzed for the research purpose described in this survey."),
  },
  scoring: { enabled: false, bands: [] },
  quotas: [],
  completion: { message: en("Thank you - your answers directly shape what gets built, and what doesn't."), redirectUrl: "" },
  blocks: [
    section("part-1-about-you", "Part 1 - About You", [
      question(1, "q01_full_name", "short_text", "Full Name", { privacy: "direct_identifier" }),
      question(2, "q02_address", "short_text", "Address", { privacy: "direct_identifier", validation: { maxLength: 300 } }),
      choice(3, "q03_gender", "Gender", [["male", "Male"], ["female", "Female"], ["non_binary", "Non-binary"], ["prefer_not", "Prefer not to say"], ["other", "Other"]], { other: other() }),
      question(4, "q04_age", "number", "Age", { validation: { min: 18, max: 120, integer: true } }),
      question(5, "q05_email", "email", "Email", { privacy: "direct_identifier", validation: { maxLength: 254 } }),
      question(6, "q06_phone", "phone", "Phone Number", { privacy: "direct_identifier", validation: { minLength: 7, maxLength: 30 } }),
      choice(7, "q07_age_group", "Which age group are you in?", [["18_24", "18-24"], ["25_34", "25-34"], ["35_44", "35-44"], ["45_54", "45-54"], ["55_plus", "55 or older"]]),
      choice(8, "q08_household", "Which best describes your household?", [["single", "Single, living alone"], ["couple", "Couple, no children at home"], ["children_under_12", "Family with children under 12"], ["teenagers", "Family with teenagers"], ["multi_generational", "Multi-generational household"], ["other", "Other"]], { other: other() }),
      choice(9, "q09_children_at_home", "Do you have children under 18 living at home?", [["no", "No"], ["yes", "Yes, please list their ages"]]),
      question(10, "q10_children_ages", "short_text", "Please enter the age(s) of your child(ren).", { required: true, description: "Skip if no children.", visibility: { all: [{ questionId: "q09_children_at_home", operator: "equals", value: "yes" }] }, validation: { maxLength: 150 } }),
      choice(11, "q11_household_income", "What is your approximate annual household income?", [["under_50k", "Under $50,000"], ["50k_80k", "$50,000 - $80,000"], ["80k_120k", "$80,000 - $120,000"], ["120k_200k", "$120,000 - $200,000"], ["over_200k", "Over $200,000"], ["prefer_not", "Prefer not to say"]], { required: false }),
      choice(12, "q12_dental_conditions", "Do any of the following apply to you or an immediate family member?", [["orthodontic_treatment", "Currently in orthodontic treatment (braces or clear aligners)"], ["dental_implants", "One or more dental implants"], ["periodontal_disease", "Periodontal (gum) disease under a dentist's care"], ["cosmetic_work", "Cosmetic dental work worth more than $1,000"], ["child_orthodontic_evaluation", "A child approaching or in an orthodontic evaluation"], ["none", "None of these"]], { multiple: true, validation: { exclusiveOptionIds: ["none"] } }),
      choice(13, "q13_health_style", "Which statement sounds most like you?", [["active_tracker", "I actively track health data (sleep, steps, heart rate, apps)"], ["health_conscious", "I'm health-conscious but don't track anything"], ["reactive", "I deal with health issues when they come up"], ["professional_led", "I mostly rely on professionals to tell me how I'm doing"]]),
    ]),
    section("part-2-current-routine", "Part 2 - Your Current Oral Health Routine", [
      choice(14, "q14_brushing_frequency", "How often do you brush your teeth?", [["twice_or_more", "Twice a day or more"], ["once_daily", "Once a day"], ["few_weekly", "A few times a week"], ["less_often", "Less often"]]),
      choice(15, "q15_regular_products", "Which of these do you use regularly?", [["electric_toothbrush", "Electric toothbrush"], ["manual_toothbrush", "Manual toothbrush"], ["dental_floss", "Dental floss"], ["water_flosser", "Water flosser"], ["mouthwash", "Mouthwash"], ["tongue_scraper", "Tongue scraper"], ["whitening", "Whitening products"], ["other", "Other"]], { multiple: true, other: other() }),
      scale(16, "q16_cleaning_confidence", "How confident are you that your daily cleaning is actually working?", 1, 10, "Not at all confident", "Completely confident"),
      choice(17, "q17_self_exam_frequency", "How often do you actually look inside your own mouth - beyond a glance while brushing?", [["daily", "Daily"], ["weekly", "Weekly"], ["monthly", "Monthly"], ["rarely", "Rarely"], ["never", "Never"]]),
      choice(18, "q18_closer_look_triggers", "What would prompt you to take a closer look at your teeth or gums?", [["pain", "Pain or sensitivity"], ["bleeding", "Bleeding when brushing or flossing"], ["feels_different", "Something feels different"], ["visible_issue", "A visible spot, stain, or crack"], ["bad_breath", "Bad breath"], ["appointment", "An upcoming dental appointment"], ["other", "Other"]], { multiple: true, other: other() }),
    ]),
    section("part-3-visits-costs-insurance", "Part 3 - Dental Visits, Costs & Insurance", [
      choice(19, "q19_last_visit", "When was your last dental visit?", [["under_6_months", "Within the last 6 months"], ["6_12_months", "6-12 months ago"], ["1_2_years", "1-2 years ago"], ["over_2_years", "More than 2 years ago"]]),
      choice(20, "q20_insurance", "Do you currently have dental insurance?", [["good_coverage", "Yes, with good coverage"], ["limited_coverage", "Yes, but coverage is limited"], ["none", "No dental insurance"], ["not_sure", "Not sure"]]),
      choice(21, "q21_delayed_for_cost", "In the past 3 years, have you delayed or declined a dental treatment because of cost?", [["yes", "Yes"], ["no", "No"], ["not_sure", "Not sure"]]),
      choice(22, "q22_between_visit_knowledge", "Between dental visits, how do you know whether your teeth and gums are healthy?", [["do_not_know", "I don't really know"], ["wait_for_symptoms", "I wait for pain or symptoms"], ["mirror", "I check in the bathroom mirror"], ["next_visit", "I find out at my next dental visit"], ["ask_dentist", "I ask my dentist between visits"], ["other", "Other"]], { multiple: true, other: other() }),
      scale(23, "q23_problem_worry", "How much do you worry about a dental problem developing between check-ups?", 1, 5, "Never think about it", "Worry about it often"),
    ]),
    section("part-4-existing-solutions", "Part 4 - Existing Solutions", [
      choice(24, "q24_camera_experience", "Have you ever bought - or considered buying - an oral or dental camera for home use?", [["bought", "Yes, I bought one"], ["considered", "I considered it but didn't buy"], ["heard_not_considered", "I'd heard of them but never considered one"], ["never_heard", "I'd never heard of them before today"]]),
      choice(25, "q25_camera_decision_factors", "If you bought or considered one: what mattered most in your decision?", [["image_quality", "Image quality"], ["ease_of_use", "Ease of use"], ["app_features", "App and software features"], ["price", "Price"], ["dentist_recommendation", "A dentist's recommendation"], ["buyer_reviews", "Reviews from other buyers"]], { multiple: true, required: true, validation: { maxSelections: 2 }, visibility: { any: [{ questionId: "q24_camera_experience", operator: "equals", value: "bought" }, { questionId: "q24_camera_experience", operator: "equals", value: "considered" }] } }),
      question(26, "q26_camera_disappointment", "long_text", "If you bought one and stopped using it - what disappointed you or got in the way?", { required: false, description: "Skip if not applicable.", visibility: { all: [{ questionId: "q24_camera_experience", operator: "equals", value: "bought" }] }, validation: { maxLength: 1500 } }),
    ]),
    section("part-5-concept-reaction", "Part 5 - Concept Reaction", [
      {
        id: "concept-products",
        type: "content",
        title: en("PLEASE READ - Two products designed to work together"),
        description: en("1. A small home oral camera - about the size of an electric toothbrush - that lets you capture clear images of your own teeth and gums in a couple of minutes, comfortably, one-handed.\n\n2. A companion app that organizes those images over time, shows you what has changed, helps you build better care habits, and lets you securely share images with your dentist between visits.\n\nThe products never diagnose anything and never replace your dentist - they give you visibility between professional visits."),
      },
      scale(27, "q27_concept_appeal", "Setting aside whether you would buy it - how appealing is this idea to you personally?", 1, 5, "Not at all appealing", "Very appealing"),
      choice(28, "q28_concerns", "What, if anything, concerns you about it?", [["correct_use", "Using it correctly"], ["trusting_view", "Trusting what I see"], ["privacy", "Privacy of my images"], ["cost", "Cost"], ["time", "Finding the time"], ["not_needed", "I don't think I need it"], ["nothing", "Nothing concerns me"], ["other", "Other"]], { multiple: true, validation: { exclusiveOptionIds: ["nothing"] }, other: other() }),
      question(29, "q29_camera_app_understanding", "long_text", "In your own words - what is the camera for, and what is the app for?", { description: "This tests clarity of the concept, not the respondent.", validation: { maxLength: 1500 } }),
      choice(30, "q30_wanted_first", "Which would you personally want first?", [["camera", "The camera only"], ["app", "The app only"], ["both", "Both together"], ["neither", "Neither"], ["not_sure", "Not sure"]]),
      choice(31, "q31_realistic_frequency", "How often would you realistically use something like this?", [["daily", "Daily"], ["weekly", "Weekly"], ["monthly", "Monthly"], ["before_appointments", "Only before dental appointments"], ["never", "Never"]]),
      choice(32, "q32_household_users", "Who in your household would you use it for?", [["self", "Myself"], ["partner", "My spouse or partner"], ["children", "My children"], ["aging_parents", "Aging parents"], ["no_one", "No one"]], { multiple: true, validation: { exclusiveOptionIds: ["no_one"] } }),
    ]),
    section("part-6-ai-privacy", "Part 6 - AI & Data Privacy", [
      scale(33, "q33_ai_comfort", "The app may include AI that helps organize, compare, and explain your images in plain language. It never diagnoses disease. How comfortable are you with that?", 1, 10, "Very uncomfortable", "Very comfortable"),
      question(34, "q34_ai_functions", "matrix_single", "Which of these AI functions would you be comfortable with?", {
        rows: [
          option("organize_timeline", "Organizing my images into a timeline"),
          option("compare_changes", "Comparing images to show changes over time"),
          option("reminders", "Reminding me about care and check-ups"),
          option("hygiene_tips", "Suggesting brushing and hygiene tips"),
          option("see_dentist", "Flagging \"consider seeing your dentist\""),
          option("plain_explanation", "Explaining in plain language what an image shows"),
        ],
        columns: [option("comfortable", "Comfortable"), option("not_sure", "Not sure"), option("not_comfortable", "Not comfortable")],
      }),
      scale(35, "q35_online_storage_comfort", "How comfortable are you with your mouth images being stored securely online so you can access them over time?", 1, 5, "Very uncomfortable", "Very comfortable"),
      choice(36, "q36_hipaa_effect", "Does knowing the data is handled to HIPAA standards - the same data-security standard hospitals use - change your answer?", [["much_more", "Much more comfortable"], ["somewhat_more", "Somewhat more comfortable"], ["no_change", "No change"], ["less", "Less comfortable"]]),
      choice(37, "q37_biggest_privacy_concern", "What is your single biggest privacy concern?", [["breach", "Hackers or data breaches"], ["insurance", "Insurance companies gaining access"], ["employers", "Employers gaining access"], ["company_misuse", "The company misusing my data"], ["none", "I have no real privacy concerns"], ["other", "Other"]], { other: other() }),
    ]),
    section("part-7-purchase-pricing", "Part 7 - Purchase Interest & Pricing", [
      choice(38, "q38_payment_approach", "If a product like this existed, which payment approach would you prefer?", [["hardware_free_app", "One-time hardware purchase, with a free app"], ["optional_subscription", "Hardware plus an optional premium subscription"], ["family_bundle", "A family bundle covering the whole household"], ["dentist_office", "Provided through my dentist's office"], ["insurance", "Covered or reimbursed by dental insurance"]]),
      choice(39, "q39_device_value", "If using it helped you avoid just one expensive dental treatment - for example a $1,500 root canal - what would a device like this be worth to you?", [["under_50", "Under $50"], ["50_99", "$50 - $99"], ["100_149", "$100 - $149"], ["150_249", "$150 - $249"], ["250_plus", "$250 or more"], ["none", "I would not buy it at any price"]]),
      choice(40, "q40_monthly_premium", "What would you pay per month for optional premium app features (deeper analysis, more storage, family profiles)?", [["nothing", "Nothing - free features only"], ["under_5", "Under $5 / month"], ["5_10", "$5 - $10 / month"], ["over_10", "More than $10 / month"]]),
      choice(41, "q41_purchase_confidence", "What would most increase your confidence to buy?", [["dentist", "A recommendation from my dentist"], ["clinical_validation", "Published clinical validation"], ["regulatory", "Clear regulatory status (FDA-registered device)"], ["independent_reviews", "Strong independent reviews"], ["guarantee", "A money-back guarantee"], ["lower_price", "A lower price"], ["try_in_person", "Seeing and trying it in person"]], { multiple: true, validation: { maxSelections: 3 } }),
    ]),
    section("part-8-final-thoughts", "Part 8 - Final Thoughts", [
      question(42, "q42_perfect_product", "long_text", "If you could design the perfect oral health product, what is the one thing it would do for you?", { validation: { maxLength: 1500 } }),
      choice(43, "q43_prototype_interest", "Would you be interested in testing an early prototype or hearing about launch?", [["no", "No, thanks"], ["maybe", "Maybe - keep me posted"], ["yes", "Yes, please leave your email below"]]),
      question(44, "q44_launch_email", "email", "If yes, leave an email.", { privacy: "direct_identifier", visibility: { all: [{ questionId: "q43_prototype_interest", operator: "equals", value: "yes" }] }, validation: { maxLength: 254 } }),
    ]),
  ],
};

export function buildWenConsumerOralHealthSurvey() {
  return structuredClone(canonicalDefinition);
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

export function decideWenConsumerSurveySeed(state, canonical = canonicalDefinition, expected = {}) {
  if (!state.asset) return "create";
  if (expected.ownerId && (state.asset.owner_id !== expected.ownerId || state.asset.assigned_to !== expected.ownerId || state.asset.created_by !== expected.ownerId)) return "conflict";
  if (expected.organizationId && state.asset.organization_id !== expected.organizationId) return "conflict";
  if (expected.projectId && state.asset.project_id !== expected.projectId) return "conflict";
  if ((state.versions || 0) > 0 || (state.submissions || 0) > 0 || state.asset.lifecycle_status && state.asset.lifecycle_status !== "draft") return "conflict";
  if (!state.draft) return "repair_draft";
  return stableJson(state.draft.definition) === stableJson(canonical) ? "noop" : "conflict";
}
