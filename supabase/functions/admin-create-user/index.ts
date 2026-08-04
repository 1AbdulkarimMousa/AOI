import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type CreateUserInput = {
  displayName?: string;
  email?: string;
  password?: string;
  role?: "admin" | "intern";
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
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    return json(origin, 500, { error: "User administration is not configured." });
  }

  const authClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: claimData, error: claimError } = await authClient.auth.getClaims(token);
  const callerId = claimData?.claims?.sub;
  if (claimError || !callerId) return json(origin, 401, { error: "Invalid or expired session." });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: membership, error: membershipError } = await adminClient
    .from("organization_memberships")
    .select("organization_id")
    .eq("user_id", callerId)
    .eq("role", "admin")
    .eq("status", "active")
    .order("joined_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (membershipError || !membership) return json(origin, 403, { error: "Administrator permission is required." });

  let body: CreateUserInput;
  try {
    body = await request.json();
  } catch {
    return json(origin, 400, { error: "Request body must be valid JSON." });
  }

  const displayName = String(body.displayName ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const role = body.role;

  if (displayName.length < 2) return json(origin, 400, { error: "Enter a full name with at least two characters." });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(origin, 400, { error: "Enter a valid email address." });
  if (password.length < 10) return json(origin, 400, { error: "Temporary passwords must contain at least 10 characters." });
  if (role !== "admin" && role !== "intern") return json(origin, 400, { error: "Choose a valid workspace role." });

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });
  if (createError || !created.user) return json(origin, 400, { error: "Unable to create that account. The email may already be in use." });

  const userId = created.user.id;
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: userId,
    display_name: displayName,
    login_identifier: email,
    locale: "en",
    must_change_password: true,
    status: "active",
  });
  const { error: membershipInsertError } = profileError
    ? { error: profileError }
    : await adminClient.from("organization_memberships").insert({
        organization_id: membership.organization_id,
        user_id: userId,
        role,
        status: "active",
      });

  if (profileError || membershipInsertError) {
    await adminClient.auth.admin.deleteUser(userId);
    return json(origin, 500, { error: "The account could not be attached to the AOI workspace." });
  }

  return json(origin, 201, {
    user: {
      user_id: userId,
      display_name: displayName,
      login_identifier: email,
      role,
      membership_status: "active",
      joined_at: new Date().toISOString(),
    },
  });
});
