import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = new URL("../supabase/migrations/20260805123000_repair_auth_context.sql", import.meta.url);

test("workspace context keeps temporary accounts in the password setup flow", async () => {
  const sql = await readFile(migration, "utf8");

  assert.match(sql, /membership\.status in \('active', 'password_change_required'\)/i);
  assert.match(sql, /profile\.status in \('active', 'password_change_required'\)/i);
  assert.match(sql, /mustChangePassword/i);
  assert.match(sql, /grant execute on function public\.rpc_current_user_context\(\) to authenticated/i);
});
