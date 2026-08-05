import { getSupabaseClient } from "./supabase.js";
import { isStrongPassword } from "./password-reminder.js";

export async function getSession() {
  const { data, error } = await getSupabaseClient().auth.getSession();
  if (error) throw new Error(error.message);
  return data.session;
}

export async function requireWorkspaceAccess() {
  const client = getSupabaseClient();
  let context = await client.rpc("rpc_current_user_context");
  if (!context.error && context.data) return context.data;

  const accepted = await client.rpc("rpc_accept_invitation");
  if (!accepted.error && accepted.data) return accepted.data;
  context = await client.rpc("rpc_current_user_context");
  if (context.error || !context.data) throw new Error("Your account is not assigned to the AOI workspace.");
  return context.data;
}

export async function signIn(email, password) {
  const client = getSupabaseClient();
  const { error } = await client.auth.signInWithPassword({
    email: String(email).trim().toLowerCase(),
    password,
  });
  if (error) throw new Error(error.message);

  try {
    return await requireWorkspaceAccess();
  } catch (reason) {
    await signOut();
    throw reason;
  }
}

export async function getExistingWorkspaceAccess() {
  const session = await getSession();
  if (!session) return null;
  try {
    return await requireWorkspaceAccess();
  } catch {
    await signOut();
    return null;
  }
}

export async function signOut() {
  await getSupabaseClient().auth.signOut();
}

export async function completePasswordChange(password) {
  if (!isStrongPassword(password)) throw new Error("Choose a password with at least 12 characters.");
  const client = getSupabaseClient();
  const { data, error } = await client.functions.invoke("admin-create-user", {
    body: { action: "complete_password_change", password },
  });
  if (error || data?.error) throw new Error(data?.error || error?.message || "Unable to change the password.");
  return data.access;
}

export async function requestPasswordReset(email, redirectTo) {
  const value = String(email || "").trim().toLowerCase();
  if (!value) throw new Error("Enter your email address first.");
  const { error } = await getSupabaseClient().auth.resetPasswordForEmail(value, { redirectTo });
  if (error) throw new Error(error.message);
}

export async function changePassword(password) {
  if (!isStrongPassword(password)) throw new Error("Choose a password with at least 12 characters.");
  const client = getSupabaseClient();
  const updated = await client.auth.updateUser({ password });
  if (updated.error) throw new Error(updated.error.message);
  const marked = await client.rpc("rpc_mark_password_changed");
  if (marked.error) throw new Error(marked.error.message);
  return await requireWorkspaceAccess();
}
