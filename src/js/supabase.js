import { createClient } from "@supabase/supabase-js";

let browserClient;

export function getSupabaseClient() {
  const url = import.meta.env.VITE_SUPABASE_URL;
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !key) throw new Error("SUPABASE_NOT_CONFIGURED");
  if (!browserClient) {
    browserClient = createClient(url, key, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: "aoi-ambiloop-auth",
      },
    });
  }
  return browserClient;
}
