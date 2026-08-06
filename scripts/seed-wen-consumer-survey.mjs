import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";
import { createClient } from "@supabase/supabase-js";

import { WEN_ACCOUNT } from "./intern-seed-data.mjs";
import {
  WEN_CONSUMER_SURVEY_ASSET_ID,
  buildWenConsumerOralHealthSurvey,
  decideWenConsumerSurveySeed,
} from "./wen-consumer-survey-data.mjs";

if (existsSync(".env.local")) loadEnvFile(".env.local");

const supabaseUrl = process.env.VITE_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!supabaseUrl || !serviceRoleKey) throw new Error("Supabase URL and service-role key are required.");

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function required(data, error, label) {
  if (error) throw new Error(`${label}: ${error.message}`);
  if (!data) throw new Error(`${label}: no record returned`);
  return data;
}

const { data: organization, error: organizationError } = await supabase
  .from("organizations")
  .select("id,slug")
  .eq("slug", "aoi-technologics")
  .single();
required(organization, organizationError, "Resolve AOI organization");

const { data: project, error: projectError } = await supabase
  .from("projects")
  .select("id,code")
  .eq("organization_id", organization.id)
  .eq("code", "AOI-PMF-01")
  .single();
required(project, projectError, "Resolve AOI PMF project");

const { data: wen, error: wenError } = await supabase
  .from("profiles")
  .select("id,display_name,login_identifier")
  .ilike("login_identifier", WEN_ACCOUNT.email)
  .single();
required(wen, wenError, "Resolve Wen profile");

const { data: membership, error: membershipError } = await supabase
  .from("organization_memberships")
  .select("role,status")
  .eq("organization_id", organization.id)
  .eq("user_id", wen.id)
  .eq("status", "active")
  .single();
required(membership, membershipError, "Resolve Wen membership");

const [{ data: asset, error: assetError }, { data: draft, error: draftError }, versionsResult, submissionsResult] = await Promise.all([
  supabase.from("survey_assets").select("id,organization_id,project_id,lifecycle_status,owner_id,assigned_to,created_by").eq("id", WEN_CONSUMER_SURVEY_ASSET_ID).maybeSingle(),
  supabase.from("survey_drafts").select("asset_id,definition,revision").eq("asset_id", WEN_CONSUMER_SURVEY_ASSET_ID).maybeSingle(),
  supabase.from("survey_versions").select("id", { count: "exact", head: true }).eq("asset_id", WEN_CONSUMER_SURVEY_ASSET_ID),
  supabase.from("survey_submissions").select("id", { count: "exact", head: true }).eq("asset_id", WEN_CONSUMER_SURVEY_ASSET_ID),
]);
if (assetError) throw new Error(`Read Wen survey asset: ${assetError.message}`);
if (draftError) throw new Error(`Read Wen survey draft: ${draftError.message}`);
if (versionsResult.error) throw new Error(`Count Wen survey versions: ${versionsResult.error.message}`);
if (submissionsResult.error) throw new Error(`Count Wen survey submissions: ${submissionsResult.error.message}`);

const definition = buildWenConsumerOralHealthSurvey();
const action = decideWenConsumerSurveySeed({
  asset,
  draft,
  versions: versionsResult.count ?? 0,
  submissions: submissionsResult.count ?? 0,
}, definition, { ownerId: wen.id, organizationId: organization.id, projectId: project.id });

if (action === "conflict") {
  throw new Error("Wen's consumer survey already contains edits, versions, responses, or a non-draft lifecycle. Refusing to overwrite it.");
}

if (action === "create") {
  const { error } = await supabase.from("survey_assets").insert({
    id: WEN_CONSUMER_SURVEY_ASSET_ID,
    organization_id: organization.id,
    project_id: project.id,
    asset_type: "survey",
    title: definition.title,
    description: definition.description,
    folder: "Consumer Research",
    tags: ["consumer", "oral-health", "Wen Tang", "seed:wen-consumer-oral-health-v1"],
    lifecycle_status: "draft",
    owner_id: wen.id,
    assigned_to: wen.id,
    created_by: wen.id,
  });
  if (error) throw new Error(`Create Wen survey asset: ${error.message}`);
}

if (["create", "repair_draft"].includes(action)) {
  const { error } = await supabase.from("survey_drafts").insert({
    asset_id: WEN_CONSUMER_SURVEY_ASSET_ID,
    organization_id: organization.id,
    project_id: project.id,
    revision: 1,
    definition,
    validation_errors: [],
    updated_by: wen.id,
  });
  if (error) throw new Error(`Create Wen survey draft: ${error.message}`);
}

console.log(JSON.stringify({
  action,
  assetId: WEN_CONSUMER_SURVEY_ASSET_ID,
  title: definition.title.en,
  author: WEN_ACCOUNT.displayName,
  ownerId: wen.id,
  lifecycleStatus: "draft",
  sections: definition.blocks.length,
  questions: definition.blocks.flatMap((section) => section.blocks).filter((block) => Number.isInteger(block.number)).length,
}, null, 2));
