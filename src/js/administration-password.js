export function createSelfPasswordDraft() {
  return {
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
    showPasswords: false,
  };
}

export function createResetPasswordDraft() {
  return {
    mode: "generated",
    temporaryPassword: "",
    confirmPassword: "",
    reason: "",
    showPasswords: false,
  };
}

export function validateSelfPasswordChange(input) {
  const errors = [];
  if (!input.currentPassword) errors.push("Enter your current password.");
  if (String(input.newPassword || "").length < 12) errors.push("New passwords must contain at least 12 characters.");
  if (input.newPassword !== input.confirmPassword) errors.push("New password confirmation does not match.");
  if (input.currentPassword && input.currentPassword === input.newPassword) errors.push("Choose a new password that differs from your current password.");
  return errors;
}

export function validatePasswordReset(input) {
  const errors = [];
  if (String(input.reason || "").trim().length < 3) errors.push("Record why this password is being reset.");
  if (input.mode === "custom") {
    if (String(input.temporaryPassword || "").length < 12) errors.push("Temporary passwords must contain at least 12 characters.");
    if (input.temporaryPassword !== input.confirmPassword) errors.push("Temporary password confirmation does not match.");
  }
  return errors;
}
