import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("replays completed responses before submit mutation", async () => {
  const source = await readFile(new URL("supabase/functions/survey-public/index.ts", root), "utf8");

  assert.match(
    source,
    /if \(action === "submit" && body\.submissionId && body\.resumeToken && body\.idempotencyKey\)/,
  );
  assert.match(source, /const replay = await client\.rpc\("rpc_aoi_public_survey_replay", \{/);
  assert.match(source, /p_submission_id: body\.submissionId,/);
  assert.match(source, /p_resume_token: body\.resumeToken,/);
  assert.match(source, /p_idempotency_key: body\.idempotencyKey,/);
  assert.match(source, /p_token: token,/);
  assert.match(source, /p_invitation_token: body\.invitationToken \|\| null,/);
  assert.match(source, /if \(replay\.error\)/);
  assert.match(source, /if \(replay\.data\?\.replayed\)/);
});

test("guards survey public actions and token shape early", async () => {
  const source = await readFile(new URL("supabase/functions/survey-public/index.ts", root), "utf8");

  assert.match(source, /action = body\.action;/);
  assert.match(source, /token = String\(body\.token \|\| ""\)/);
  assert.match(
    source,
    /if \(!action || !\["load", "start", "save", "submit", "upload"\]\.includes\(action\) || token\.length < 32 || token\.length > 128\)/,
  );
  assert.match(source, /return json\(origin, 400, \{ error: "Survey request is invalid\." \}\);/);
});

test("maps replay unavailable to 409 response contract", async () => {
  const source = await readFile(new URL("supabase/functions/survey-public/index.ts", root), "utf8");

  assert.match(source, /if \(replay\.error\) \{/);
  assert.match(source, /const error = publicError\(replay\.error\.message\);/);
  assert.match(source, /return json\(origin, error\.status, \{ error: error\.message, code: error\.code \}\);/);
  assert.match(
    source,
    /if \(message\.includes\("SURVEY_RESPONSE_UNAVAILABLE"\) \|\| message\.includes\("SURVEY_RESPONSE_LOCKED"\)\) return \{ status: 409, code: "SURVEY_RESPONSE_UNAVAILABLE", message: "This response can no longer be changed\." \};/,
  );
});
