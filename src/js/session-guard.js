import { getSupabaseClient } from "./supabase.js";
import { pageUrl } from "./core.js";

const PROTECTED_PAGES = new Set(["workspace", "administration", "helpcenter", "participant-tracker"]);
const IDLE_LIMIT_MS = 30 * 60 * 1000;
const STORAGE_KEY = "aoi-last-active-at";
const POLL_MS = 60 * 1000;

function isProtectedPage(page) {
  return PROTECTED_PAGES.has(page);
}

export function registerSessionGuard(page) {
  if (!isProtectedPage(page)) return;
  const client = getSupabaseClient();

  client.auth.onAuthStateChange((event) => {
    if (event === "SIGNED_OUT") {
      try {
        location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
      } catch {}
    }
  });

  let lastActivity = Date.now();
  try {
    const stored = Number(window.sessionStorage.getItem(STORAGE_KEY));
    if (Number.isFinite(stored) && stored > 0) lastActivity = stored;
  } catch {}
  try {
    window.sessionStorage.setItem(STORAGE_KEY, String(lastActivity));
  } catch {}

  const recordActivity = () => {
    lastActivity = Date.now();
    try {
      window.sessionStorage.setItem(STORAGE_KEY, String(lastActivity));
    } catch {}
  };

  for (const eventName of ["mousemove", "keydown", "touchstart", "click", "scroll"]) {
    window.addEventListener(eventName, recordActivity, { passive: true });
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) return;
    if (Date.now() - lastActivity > IDLE_LIMIT_MS) {
      client.auth.signOut().finally(() => {
        try {
          location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
        } catch {}
      });
      return;
    }
    recordActivity();
  });

  window.setInterval(() => {
    if (Date.now() - lastActivity > IDLE_LIMIT_MS) {
      client.auth.signOut().finally(() => {
        try {
          location.replace(pageUrl(import.meta.env.BASE_URL, "login.html"));
        } catch {}
      });
    }
  }, POLL_MS);
}
