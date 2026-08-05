export function isPasswordRecoveryUrl(value) {
  try {
    const url = new URL(String(value), "http://localhost");
    return url.searchParams.get("type") === "recovery" || new URLSearchParams(url.hash.slice(1)).get("type") === "recovery";
  } catch {
    return false;
  }
}
