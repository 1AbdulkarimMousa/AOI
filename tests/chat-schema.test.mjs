import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

async function effectiveSchema() {
  const directory = new URL("supabase/migrations/", root);
  const files = (await readdir(directory)).filter((file) => file.endsWith(".sql")).sort();
  return (await Promise.all(files.map((file) => readFile(new URL(file, directory), "utf8")))).join("\n");
}

test("defines normalized organization-scoped chat and profile persistence", async () => {
  const schema = await effectiveSchema();

  assert.match(schema, /alter table public\.profiles add column if not exists job_title/);
  assert.match(schema, /avatar_key text/);
  assert.match(schema, /avatar_path text/);
  assert.match(schema, /create table public\.chat_conversations/);
  assert.match(schema, /create table public\.chat_conversation_members/);
  assert.match(schema, /create table public\.chat_messages/);
  assert.match(schema, /create table public\.chat_message_reactions/);
  assert.match(schema, /create table public\.chat_attachments/);
  assert.match(schema, /create table public\.chat_moderation_events/);
  assert.match(schema, /unique.*organization_id.*direct_key/is);
  assert.match(schema, /client_nonce uuid/);
});

test("derives chat identity and tenant scope in authenticated RPCs", async () => {
  const schema = await effectiveSchema();

  for (const name of [
    "rpc_aoi_chat_bootstrap",
    "rpc_aoi_chat_open_direct",
    "rpc_aoi_chat_messages",
    "rpc_aoi_chat_send",
    "rpc_aoi_chat_edit",
    "rpc_aoi_chat_delete",
    "rpc_aoi_chat_moderate",
    "rpc_aoi_chat_toggle_reaction",
    "rpc_aoi_chat_mark_read",
    "rpc_aoi_chat_search",
    "rpc_aoi_update_profile",
    "rpc_aoi_member_profile",
  ]) assert.match(schema, new RegExp(`create or replace function public\\.${name}`));

  assert.match(schema, /auth\.uid\(\)/);
  assert.match(schema, /CHAT_CONVERSATION_FORBIDDEN/);
  assert.match(schema, /CHAT_ADMIN_REQUIRED/);
  assert.match(schema, /grant execute on function public\.rpc_aoi_chat_bootstrap/);
  assert.match(schema, /revoke all on function public\.rpc_aoi_chat_bootstrap/);
});

test("enforces RLS, private storage, and authorized realtime channels", async () => {
  const schema = await effectiveSchema();

  assert.match(schema, /alter table public\.chat_messages enable row level security/);
  assert.match(schema, /chat_messages_participant_read/);
  assert.match(schema, /profiles_self_read/);
  assert.match(schema, /aoi-avatars/);
  assert.match(schema, /aoi-chat/);
  assert.match(schema, /storage\.objects/);
  assert.match(schema, /realtime\.messages/);
  assert.match(schema, /realtime\.topic\(\)/);
  assert.match(schema, /extension in \('presence', 'broadcast'\)/);
  assert.match(schema, /alter publication supabase_realtime add table public\.chat_messages/);
  assert.match(schema, /revoke all on public\.chat_messages from anon, authenticated/);
  assert.match(schema, /grant select on public\.chat_messages to authenticated/);
});

test("keeps member-directory and profile payloads free of login controls", async () => {
  const schema = await effectiveSchema();
  const bootstrap = schema.match(/create or replace function public\.rpc_aoi_chat_bootstrap[\s\S]*?\$\$;/i)?.[0] || "";
  const memberProfile = schema.match(/create or replace function public\.rpc_aoi_member_profile[\s\S]*?\$\$;/i)?.[0] || "";

  assert.doesNotMatch(bootstrap, /loginIdentifier|mustChangePassword/);
  assert.doesNotMatch(memberProfile, /loginIdentifier|mustChangePassword/);
  assert.match(schema, /drop policy if exists profiles_self_or_org_read/);
});

test("keeps private profile fields out of chat payloads and removed attachments unreadable", async () => {
  const schema = await effectiveSchema();
  const chatProfile = schema.match(/create or replace function private\.aoi_chat_profile[\s\S]*?\$\$;/i)?.[0] || "";
  const attachmentRead = schema.match(/create policy aoi_chat_attachment_read[\s\S]*?;\n/i)?.[0] || "";

  assert.match(chatProfile, /displayName|display_name/);
  assert.doesNotMatch(chatProfile, /phone|bio/);
  assert.match(schema, /private\.aoi_chat_profile\(profile\)/);
  assert.match(attachmentRead, /attachment\.deleted_at is null/);
  assert.match(attachmentRead, /not exists/);
});

test("supports eight avatars, attachment-only messages, and bilingual substring search", async () => {
  const schema = await effectiveSchema();

  assert.match(schema, /'rose', 'sand'/);
  assert.match(schema, /jsonb_array_length\(coalesce\(p_attachments/);
  assert.match(schema, /char_length\(v_body\) = 0/);
  assert.match(schema, /message\.body ilike/);
});

test("preserves administration owner and password-change context", async () => {
  const schema = await effectiveSchema();
  const contexts = [...schema.matchAll(/create or replace function public\.rpc_current_user_context[\s\S]*?\$\$;/gi)];
  const latest = contexts.at(-1)?.[0] || "";

  assert.match(latest, /'isOwner', membership\.is_owner/);
  assert.match(latest, /membership\.status in \('active', 'password_change_required'\)/);
  assert.match(latest, /profile\.status in \('active', 'password_change_required'\)/);
});

test("keeps self-service and administration contact profiles synchronized", async () => {
  const schema = await effectiveSchema();
  const updateProfile = schema.match(/create or replace function public\.rpc_aoi_update_profile[\s\S]*?\$\$;/i)?.[0] || "";

  assert.match(updateProfile, /update public\.staff_profiles/);
  assert.match(schema, /create or replace function private\.sync_aoi_profile_contact/);
  assert.match(schema, /create trigger sync_aoi_profile_contact/);
});

test("schema-qualifies moderation hashing under an empty search path", async () => {
  const schema = await effectiveSchema();
  const moderationFunctions = [...schema.matchAll(/create or replace function public\.rpc_aoi_chat_moderate[\s\S]*?\$\$;/gi)];
  const latest = moderationFunctions.at(-1)?.[0] || "";

  assert.match(latest, /extensions\.digest/);
  assert.doesNotMatch(latest, /encode\(digest\(/);
});

test("preserves shared private helpers and avoids realtime reaction delete leaks", async () => {
  const schema = await effectiveSchema();
  const toggles = [...schema.matchAll(/create or replace function public\.rpc_aoi_chat_toggle_reaction[\s\S]*?\$\$;/gi)];
  const latestToggle = toggles.at(-1)?.[0] || "";

  assert.match(schema, /grant usage on schema private to authenticated/);
  assert.match(schema, /removed_at timestamptz/);
  assert.match(latestToggle, /removed_at/);
  assert.doesNotMatch(latestToggle, /delete from public\.chat_message_reactions/);
});

test("limits peer avatars, enables moderation audit reads, and reconciles sends", async () => {
  const schema = await effectiveSchema();

  assert.match(schema, /create or replace function public\.aoi_profile_avatar_read_authorized/);
  const avatarPolicies = [...schema.matchAll(/create policy aoi_avatar_member_read[\s\S]*?\n\);/gi)];
  const latestAvatarPolicy = avatarPolicies.at(-1)?.[0] || "";
  assert.match(latestAvatarPolicy, /aoi_profile_avatar_read_authorized/);
  assert.doesNotMatch(latestAvatarPolicy, /from public\.profiles/);
  assert.match(schema, /grant select on public\.chat_moderation_events to authenticated/);
  assert.match(schema, /create or replace function public\.rpc_aoi_chat_message_by_nonce/);
  assert.match(schema, /grant execute on function public\.rpc_aoi_chat_message_by_nonce/);
  assert.match(schema, /aoi_chat_attachment_owner_or_admin_delete/);
});

test("avoids realtime refresh loops when read state is unchanged", async () => {
  const schema = await effectiveSchema();
  const readFunctions = [...schema.matchAll(/create or replace function public\.rpc_aoi_chat_mark_read[\s\S]*?\$\$;/gi)];
  const latestReadFunction = readFunctions.at(-1)?.[0] || "";

  assert.match(latestReadFunction, /v_message\.created_at > member\.last_read_at/);
});
