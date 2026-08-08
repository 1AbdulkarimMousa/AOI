const REMINDER_DAYS = 7;

export function shouldShowPasswordReminder({ seeded = false, changedAt = null, snoozedUntil = null, now = new Date() } = {}) {
  if (!seeded || changedAt) return false;
  if (!snoozedUntil) return true;
  return new Date(snoozedUntil).getTime() <= new Date(now).getTime();
}

export function snoozeUntil(now = new Date()) {
  const date = new Date(now);
  date.setUTCDate(date.getUTCDate() + REMINDER_DAYS);
  return date;
}

export function isStrongPassword(password) {
  if (typeof password !== "string" || password.length < 14) return false;
  if (!/[A-Z]/.test(password)) return false;
  if (!/[a-z]/.test(password)) return false;
  if (!/[0-9]/.test(password)) return false;
  if (!/[^A-Za-z0-9]/.test(password)) return false;
  return true;
}
