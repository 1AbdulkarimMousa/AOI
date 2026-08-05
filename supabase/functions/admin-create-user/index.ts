import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type AdminUserInput = {
  action?: "create" | "archive" | "restore" | "complete_password_change" | "import";
  userId?: string;
  replacementUserId?: string;
  reason?: string;
  departureDate?: string;
  displayName?: string;
  email?: string;
  password?: string;
  role?: "admin" | "intern";
  accessMethod?: "invite" | "temporary_password";
  locale?: "en" | "zh-CN";
  timezone?: string;
  phone?: string;
  managerId?: string;
  skills?: string[];
  availability?: string;
  startDate?: string;
  notes?: string;
  packageData?: Record<string, unknown>;
  mode?: "merge" | "full_restore";
  previewJobId?: string;
};

const configuredOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const allowedOrigins = new Set([
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "https://1abdulkarimmousa.github.io",
  ...configuredOrigins,
]);

function corsHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function json(origin: string, status: number, payload: Record<string, unknown>) {
  return Response.json(payload, { status, headers: corsHeaders(origin) });
}

async function cleanupProvisioning(adminClient: ReturnType<typeof createClient>, organizationId: string, userId: string) {
  const errors: string[] = [];
  for (const operation of [
    adminClient.from("staff_onboarding_steps").delete().eq("organization_id", organizationId).eq("user_id", userId),
    adminClient.from("staff_profiles").delete().eq("organization_id", organizationId).eq("user_id", userId),
    adminClient.from("organization_memberships").delete().eq("organization_id", organizationId).eq("user_id", userId),
    adminClient.from("profiles").delete().eq("id", userId),
  ]) {
    const result = await operation;
    if (result.error) errors.push(result.error.message);
  }
  const authResult = errors.length ? null : await adminClient.auth.admin.deleteUser(userId);
  if (authResult?.error) errors.push(authResult.error.message);
  return errors;
}

Deno.serve(async (request) => {
  const origin = request.headers.get("Origin") ?? "";
  if (!allowedOrigins.has(origin)) return Response.json({ error: "Origin not allowed." }, { status: 403 });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (request.method !== "POST") return json(origin, 405, { error: "Method not allowed." });

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json(origin, 401, { error: "Authentication required." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SB_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) return json(origin, 500, { error: "User administration is not configured." });

  const authClient = createClient(supabaseUrl, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: claimData, error: claimError } = await authClient.auth.getClaims(token);
  const callerId = claimData?.claims?.sub;
  if (claimError || !callerId) return json(origin, 401, { error: "Invalid or expired session." });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const userClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });

  let body: AdminUserInput;
  try {
    body = await request.json();
  } catch {
    return json(origin, 400, { error: "Request body must be valid JSON." });
  }
  const action = body.action ?? "create";

  if (action === "complete_password_change") {
    const password = String(body.password || "");
    if (password.length < 12) return json(origin, 400, { error: "Choose a password with at least 12 characters." });
    const { data: profile } = await adminClient.from("profiles").select("status,must_change_password").eq("id", callerId).maybeSingle();
    if (!profile?.must_change_password || !["active", "password_change_required"].includes(profile.status)) return json(origin, 409, { error: "This account does not require a password change." });
    const updated = await adminClient.auth.admin.updateUserById(callerId, { password });
    if (updated.error) return json(origin, 400, { error: updated.error.message });
    const completed = await adminClient.rpc("rpc_complete_password_change", { p_user_id: callerId });
    if (completed.error) return json(origin, 500, { error: "Password changed, but workspace activation must be retried." });
    return json(origin, 200, { access: completed.data });
  }

  const { data: membership, error: membershipError } = await adminClient
    .from("organization_memberships")
    .select("organization_id,is_owner")
    .eq("user_id", callerId)
    .eq("role", "admin")
    .eq("status", "active")
    .order("joined_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (membershipError || !membership) return json(origin, 403, { error: "Administrator permission is required." });
  const { data: callerProfile } = await adminClient.from("profiles").select("status,must_change_password").eq("id", callerId).maybeSingle();
  if (callerProfile?.status !== "active" || callerProfile.must_change_password) return json(origin, 403, { error: "Complete secure account activation before using Administration." });

  if (action === "import") {
    if (!body.packageData || !body.mode || !body.previewJobId) return json(origin, 400, { error: "Preview the administration package before applying it." });
    if (body.mode === "full_restore" && !membership.is_owner) return json(origin, 403, { error: "Only the organization owner can run a full restore." });
    const people = body.mode === "full_restore" && Array.isArray(body.packageData.people) ? body.packageData.people as Array<Record<string, unknown>> : [];
    const previous: Array<{ userId: string; banned: boolean }> = [];
    for (const person of people) {
      const userId = String(person.userId || "");
      if (!/^[0-9a-f-]{36}$/i.test(userId)) continue;
      const { data: current } = await adminClient.from("organization_memberships").select("status").eq("organization_id", membership.organization_id).eq("user_id", userId).maybeSingle();
      if (!current) continue;
      const shouldBan = ["archived", "disabled"].includes(String(person.membershipStatus || ""));
      const { count: otherActive } = await adminClient.from("organization_memberships").select("user_id", { count: "exact", head: true }).eq("user_id", userId).eq("status", "active").neq("organization_id", membership.organization_id);
      const desiredBan = shouldBan && !otherActive;
      previous.push({ userId, banned: ["archived", "disabled"].includes(current.status) && !otherActive });
      const authUpdate = await adminClient.auth.admin.updateUserById(userId, { ban_duration: desiredBan ? "876000h" : "none" });
      if (authUpdate.error) {
        for (const item of previous) await adminClient.auth.admin.updateUserById(item.userId, { ban_duration: item.banned ? "876000h" : "none" });
        return json(origin, 400, { error: `Unable to synchronize Auth access for ${userId}.` });
      }
    }
    const imported = await userClient.rpc("rpc_admin_import_data", { p_package: body.packageData, p_mode: body.mode, p_preview_job_id: body.previewJobId, p_preview_mode: body.mode });
    if (imported.error) {
      for (const item of previous) await adminClient.auth.admin.updateUserById(item.userId, { ban_duration: item.banned ? "876000h" : "none" });
      return json(origin, 400, { error: imported.error.message });
    }
    return json(origin, 200, { result: imported.data });
  }
  if (action === "archive") {
    if (!body.userId || !String(body.reason || "").trim()) return json(origin, 400, { error: "Choose a person and record an archive reason." });
    const { data, error } = await userClient.rpc("rpc_admin_archive_user", {
      p_user_id: body.userId,
      p_replacement_user_id: body.replacementUserId || null,
      p_reason: String(body.reason).trim(),
      p_departure_date: body.departureDate || new Date().toISOString().slice(0, 10),
    });
    if (error) return json(origin, 400, { error: error.message });
    const { count: activeMemberships } = await adminClient.from("organization_memberships").select("user_id", { count: "exact", head: true }).eq("user_id", body.userId).eq("status", "active");
    const banned = activeMemberships ? { error: null } : await adminClient.auth.admin.updateUserById(body.userId, { ban_duration: "876000h" });
    if (banned.error) return json(origin, 500, { error: "Work was archived, but Auth suspension needs administrator attention.", result: data });
    return json(origin, 200, { result: data });
  }

  if (action === "restore") {
    if (!body.userId) return json(origin, 400, { error: "Choose an archived person to restore." });
    const { data: target } = await adminClient.from("organization_memberships").select("role,status").eq("organization_id", membership.organization_id).eq("user_id", body.userId).maybeSingle();
    if (!target || target.status !== "archived") return json(origin, 404, { error: "That archived person does not belong to this organization." });
    if (target.role === "admin" && !membership.is_owner) return json(origin, 403, { error: "Only the organization owner can restore an administrator." });
    const existingAuth = await adminClient.auth.admin.getUserById(body.userId);
    const wasBanned = Boolean(existingAuth.data.user?.banned_until && new Date(existingAuth.data.user.banned_until).getTime() > Date.now());
    const unbanned = await adminClient.auth.admin.updateUserById(body.userId, { ban_duration: "none" });
    if (unbanned.error) return json(origin, 400, { error: "The Auth account could not be reactivated." });
    const { data, error } = await userClient.rpc("rpc_admin_restore_user", { p_user_id: body.userId });
    if (error) {
      await adminClient.auth.admin.updateUserById(body.userId, { ban_duration: wasBanned ? "876000h" : "none" });
      return json(origin, 400, { error: error.message });
    }
    return json(origin, 200, { result: data });
  }

  if (action !== "create") return json(origin, 400, { error: "Choose a valid user administration action." });

  const displayName = String(body.displayName ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const role = body.role;
  const accessMethod = body.accessMethod === "temporary_password" ? "temporary_password" : "invite";
  if (displayName.length < 2) return json(origin, 400, { error: "Enter a full name with at least two characters." });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(origin, 400, { error: "Enter a valid email address." });
  if (role !== "admin" && role !== "intern") return json(origin, 400, { error: "Choose a valid workspace role." });
  if (role === "admin" && !membership.is_owner) return json(origin, 403, { error: "Only the organization owner can add another administrator." });

  const generatedPassword = accessMethod === "temporary_password" ? (String(body.password || "") || "123456") : "";
  if (accessMethod === "temporary_password" && generatedPassword !== "123456" && generatedPassword.length < 10) return json(origin, 400, { error: "Temporary passwords must contain at least 10 characters." });

  const created = accessMethod === "invite"
    ? await adminClient.auth.admin.inviteUserByEmail(email, {
        data: { display_name: displayName },
        redirectTo: `${origin}${origin.includes("github.io") ? "/AOI" : ""}/login.html`,
      })
    : await adminClient.auth.admin.createUser({
        email,
        password: generatedPassword,
        email_confirm: true,
        user_metadata: { display_name: displayName },
      });
  if (created.error || !created.data.user) return json(origin, 400, { error: "Unable to create that account. The email may already be in use." });

  const userId = created.data.user.id;
  const invited = accessMethod === "invite";
  const initialStatus = invited ? "invited" : "password_change_required";
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: userId,
    display_name: displayName,
    login_identifier: email,
    locale: body.locale === "zh-CN" ? "zh-CN" : "en",
    must_change_password: !invited,
    status: initialStatus,
    password_reminder_seeded_at: accessMethod === "temporary_password" ? new Date().toISOString() : null,
  });
  const { error: membershipInsertError } = profileError
    ? { error: profileError }
    : await adminClient.from("organization_memberships").insert({
        organization_id: membership.organization_id,
        user_id: userId,
        role,
        status: initialStatus,
      });
  const skills = Array.isArray(body.skills) ? body.skills.map((skill) => String(skill).trim()).filter(Boolean) : [];
  const { error: staffError } = profileError || membershipInsertError
    ? { error: profileError || membershipInsertError }
    : await adminClient.from("staff_profiles").insert({
        organization_id: membership.organization_id,
        user_id: userId,
        phone: body.phone || null,
        timezone: body.timezone || "America/New_York",
        manager_id: body.managerId || null,
        skills,
        availability: body.availability || null,
        start_date: body.startDate || null,
        notes: body.notes || null,
      });

  if (profileError || membershipInsertError || staffError) {
    const cleanupErrors = await cleanupProvisioning(adminClient, membership.organization_id, userId);
    return json(origin, 500, { error: cleanupErrors.length ? "Account setup failed and cleanup needs administrator attention." : "The account could not be attached to the AOI workspace." });
  }

  const onboarding = await adminClient.from("staff_onboarding_steps").insert([
    { organization_id: membership.organization_id, user_id: userId, step_key: "secure_account", label: "Secure your account", sequence: 10 },
    { organization_id: membership.organization_id, user_id: userId, step_key: "review_workspace", label: "Review workspace responsibilities", sequence: 20 },
    { organization_id: membership.organization_id, user_id: userId, step_key: "review_data_handling", label: "Review data handling rules", sequence: 30 },
    { organization_id: membership.organization_id, user_id: userId, step_key: "log_crm_outcome", label: "Log CRM outcomes", sequence: 35 },
    { organization_id: membership.organization_id, user_id: userId, step_key: "file_first_eod", label: "File your first EOD brief", sequence: 40 },
  ]);
  if (onboarding.error) {
    const cleanupErrors = await cleanupProvisioning(adminClient, membership.organization_id, userId);
    return json(origin, 500, { error: cleanupErrors.length ? "Onboarding failed and cleanup needs administrator attention." : "The onboarding checklist could not be prepared." });
  }

  return json(origin, 201, {
    user: {
      user_id: userId,
      display_name: displayName,
      login_identifier: email,
      role,
      membership_status: initialStatus,
      joined_at: new Date().toISOString(),
    },
    accessMethod,
    temporaryPassword: generatedPassword || undefined,
  });
});
