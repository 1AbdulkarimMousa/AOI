import { getSupabaseClient } from "./supabase.js";

export async function getSession() {
  const { data, error } = await getSupabaseClient().auth.getSession();
  if (error) throw new Error(error.message);
  return data.session;
}

export async function requireWorkspaceAccess() {
  const { data, error } = await getSupabaseClient().rpc("rpc_current_user_context");
  if (error || !data) throw new Error("Your account is not assigned to the AOI workspace.");
  return data;
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
