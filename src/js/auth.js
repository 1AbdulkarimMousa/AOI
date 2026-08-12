import { getSupabaseClient } from "./supabase.js";
import { isStrongPassword } from "./password-reminder.js";

export class WorkspaceMembershipError extends Error {}

export async function getSession() {
  const { data, error } = await getSupabaseClient().auth.getSession();
  if (error) throw new Error(error.message);
  return data.session;
}

export async function requireWorkspaceAccess() {
  const client = getSupabaseClient();
  const context = await client.rpc("rpc_current_user_context");
  if (!context.error && context.data) return context.data;
  if (context.error) throw new Error(context.error.message || "Unable to verify workspace access.");
  throw new WorkspaceMembershipError("Your account is not assigned to the AOI workspace.");
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
    if (reason instanceof WorkspaceMembershipError) await signOut();
    throw reason;
  }
}

export async function getExistingWorkspaceAccess() {
  const session = await getSession();
  if (!session) return null;
  try {
    return await requireWorkspaceAccess();
  } catch (reason) {
    if (reason instanceof WorkspaceMembershipError) {
      await signOut();
      return null;
    }
    throw reason;
  }
}

export async function signOut() {
  await getSupabaseClient().auth.signOut();
}

export async function completePasswordChange(password, currentPassword = "", passwordCallback = null) {
  if (!isStrongPassword(password)) throw new Error("Choose a stronger password: at least 14 characters with upper/lower case, a digit, and a symbol.");
  const client = getSupabaseClient();
  const { data, error } = await client.functions.invoke("admin-create-user", {
    body: { action: "complete_password_change", password, currentPassword, passwordCallback },
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

export async function changePassword(password, currentPassword = "", passwordCallback = null) {
  if (!isStrongPassword(password)) throw new Error("Choose a stronger password: at least 14 characters with upper/lower case, a digit, and a symbol.");
  const client = getSupabaseClient();
  if (passwordCallback === "recovery") return completePasswordChange(password);
  if (passwordCallback === "invite" || passwordCallback === "signup") {
    const { data: claimData, error: claimError } = await client.auth.getClaims();
    const expectedMethod = passwordCallback === "invite" ? "invite" : "email/signup";
    const authMethods = Array.isArray(claimData?.claims?.amr) ? claimData.claims.amr : [];
    const verifiedCallback = authMethods.some((entry) => entry?.method === expectedMethod && Number.isInteger(entry?.timestamp) && entry.timestamp > 0);
    if (claimError || !verifiedCallback) throw new Error("The invitation session could not be verified. Open the latest invitation link and try again.");
    return completePasswordChange(password, "", passwordCallback);
  }
  const access = await requireWorkspaceAccess();
  if (access.mustChangePassword) return completePasswordChange(password, currentPassword);
  const current = String(currentPassword || "");
  if (!current) throw new Error("Enter your current password to confirm the change.");
  if (current === password) throw new Error("Choose a new password that differs from your current password.");
  const session = await getSession();
  const email = session?.user?.email;
  if (!email) throw new Error("Your session could not be verified. Sign in again.");
  const verificationClient = getSupabaseClient();
  const { data: verification, error: verificationError } = await verificationClient.auth.signInWithPassword({
    email,
    password: current,
  });
  if (verificationError || !verification.user) throw new Error("Your current password is incorrect.");
  const updated = await client.auth.updateUser({ password });
  if (updated.error) throw new Error(updated.error.message);
  const recorded = await client.rpc("rpc_record_password_changed_at");
  if (recorded.error) throw new Error("Password changed, but the reminder timestamp could not be saved.");
  return await requireWorkspaceAccess();
}
