import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8").catch(() => "");

test("ships shared chat navigation and a responsive collaboration workspace", async () => {
  const [controller, shell, chatTemplate, styles] = await Promise.all([
    read("src/js/workspace.js"),
    read("src/js/workspace-template.js"),
    read("src/js/chat-template.js"),
    read("src/css/aoi.css"),
  ]);

  assert.match(controller, /id: "chat"/);
  assert.match(controller, /initializeChat/);
  assert.match(controller, /destroyChat/);
  assert.match(shell, /chatTemplate/);
  assert.match(shell, /totalChatUnread/);
  assert.match(chatTemplate, /view==='chat'/);
  assert.match(chatTemplate, /chat-conversation-list/);
  assert.match(chatTemplate, /chat-message-list/);
  assert.match(chatTemplate, /sendChatMessage/);
  assert.match(chatTemplate, /openDirectConversation/);
  assert.match(chatTemplate, /replyToMessage/);
  assert.match(chatTemplate, /toggleMessageReaction/);
  assert.match(chatTemplate, /moderateMessage/);
  assert.match(styles, /\.chat-layout/);
  assert.match(styles, /@media \(max-width: 760px\)[\s\S]*\.chat-layout/);
});

test("ships self-service profiles with photo and preset avatar choices", async () => {
  const [controller, profileController, shell, profileTemplate, api, styles] = await Promise.all([
    read("src/js/workspace.js"),
    read("src/js/profile.js"),
    read("src/js/workspace-template.js"),
    read("src/js/profile-template.js"),
    read("src/js/api.js"),
    read("src/css/aoi.css"),
  ]);

  assert.match(controller, /createProfileState/);
  assert.match(profileController, /openProfileEditor/);
  assert.match(profileController, /saveProfile/);
  assert.match(shell, /profileTemplate/);
  assert.match(shell, /accountMenuOpen/);
  assert.match(profileTemplate, /t\('uploadPhoto'\)/);
  assert.match(profileTemplate, /t\('presetAvatar'\)/);
  assert.match(profileTemplate, /t\('jobTitle'\)/);
  assert.match(profileTemplate, /t\('timezone'\)/);
  assert.match(api, /rpc_aoi_update_profile/);
  assert.match(api, /aoi-avatars/);
  assert.match(styles, /\.profile-drawer/);
});

test("uses authenticated realtime, upload rollback, and preview safeguards", async () => {
  const [chat, api] = await Promise.all([read("src/js/chat.js"), read("src/js/api.js")]);

  assert.match(chat, /postgres_changes/);
  assert.match(chat, /private:\s*true/);
  assert.match(chat, /presence/);
  assert.match(chat, /broadcast/);
  assert.match(chat, /removeChannel/);
  assert.match(chat, /this\.preview/);
  assert.match(api, /aoi-chat/);
  assert.match(api, /\.remove\(\[objectPath\]\)/);
  assert.match(api, /createSignedUrl/);
  assert.match(api, /rpc_aoi_chat_message_by_nonce/);
});

test("refreshes on selection and reconnect while guarding duplicate sends", async () => {
  const [chat, workspace] = await Promise.all([read("src/js/chat.js"), read("src/js/workspace.js")]);
  const template = await read("src/js/chat-template.js");

  assert.match(chat, /if \(this\.chatSending\) return/);
  assert.match(chat, /await this\.refreshChatMessages\(conversationId\)/);
  assert.match(chat, /status === "SUBSCRIBED"[\s\S]*refreshChatBootstrap/);
  assert.match(chat, /loadChatMessageByNonce/);
  assert.match(chat, /initializeChat[\s\S]*refreshChatMessages[\s\S]*markSelectedChatRead/);
  assert.match(chat, /scheduleChatRefresh[\s\S]*refreshChatMessages[\s\S]*markSelectedChatRead/);
  assert.match(chat, /status === "SUBSCRIBED"[\s\S]*refreshChatMessages[\s\S]*markSelectedChatRead/);
  assert.doesNotMatch(chat, /markChatRead\([^;]+\.catch\(\(\) => \{\}\)/);
  assert.match(chat, /markSelectedChatRead[\s\S]*this\.view !== "chat"/);
  assert.match(chat, /matchMedia\("\(max-width: 760px\)"\)[\s\S]*chatMobileThreadOpen/);
  assert.match(workspace, /view === "chat"[\s\S]*initializeChat\(\)[\s\S]*markSelectedChatRead/);
  assert.match(template, /chatSending \|\| preview/);
});

test("keeps typing conversation-private and provides profile keyboard lifecycle", async () => {
  const [chat, profile, shell, profileTemplate] = await Promise.all([
    read("src/js/chat.js"), read("src/js/profile.js"), read("src/js/workspace-template.js"), read("src/js/profile-template.js"),
  ]);

  assert.match(chat, /selectedChatConversationId/);
  assert.doesNotMatch(chat, /conversationId:\s*this\.selectedChatConversationId,\s*typing/);
  assert.match(profile, /trapProfileFocus/);
  assert.match(profile, /profileReturnFocus/);
  assert.match(shell, /profileOpen && closeProfileEditor/);
  assert.match(profileTemplate, /@keydown\.tab/);
  assert.match(profileTemplate, /aria-label/);
});

test("includes English and Simplified Chinese chat and profile labels", async () => {
  const translations = await read("src/js/i18n.js");

  assert.match(translations, /chat:\s*"Chat"/);
  assert.match(translations, /chat:\s*"聊天"/);
  assert.match(translations, /editProfile:\s*"Edit profile"/);
  assert.match(translations, /editProfile:\s*"编辑个人资料"/);
});
