const passwordEstablishmentTypes = new Set(["recovery", "invite", "signup"]);

export function passwordEstablishmentType(value) {
  try {
    const url = new URL(String(value), "http://localhost");
    const type = url.searchParams.get("type") || new URLSearchParams(url.hash.slice(1)).get("type");
    return passwordEstablishmentTypes.has(type) ? type : null;
  } catch {
    return null;
  }
}

export function isPasswordRecoveryUrl(value) {
  return passwordEstablishmentType(value) === "recovery";
}
