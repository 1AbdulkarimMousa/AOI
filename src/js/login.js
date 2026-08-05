import { changePassword, getExistingWorkspaceAccess, requestPasswordReset, signIn, signOut } from "./auth.js";
import { isPasswordRecoveryUrl } from "./login-flow.js";
import { pageUrl, readableError, routeForRole } from "./core.js";

export function registerLogin(Alpine) {
  Alpine.data("loginPage", () => ({
    email: "",
    password: "",
    currentPassword: "",
    showPassword: false,
    checking: true,
    loading: false,
    error: "",
    message: "",
    access: null,
    passwordSetup: false,
    recovery: false,
    newPassword: "",
    confirmPassword: "",
    async init() {
      try {
        this.recovery = isPasswordRecoveryUrl(location.href);
        if (this.recovery) {
          this.passwordSetup = true;
          return;
        }
        const access = await getExistingWorkspaceAccess();
        if (access?.mustChangePassword) {
          await signOut();
          this.message = "Sign in again with your temporary password to replace it.";
        } else if (access) location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch {
        this.error = "Unable to check your session. You can still sign in.";
      } finally {
        this.checking = false;
      }
    },
    async submit() {
      this.error = "";
      this.message = "";
      this.loading = true;
      try {
        const access = await signIn(this.email, this.password);
        if (access.mustChangePassword) {
          this.access = access;
          this.currentPassword = this.password;
          this.passwordSetup = true;
        } else location.assign(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch (reason) {
        this.error = readableError(reason, "Unable to sign in.");
      } finally {
        this.loading = false;
      }
    },
    async changePassword() {
      this.error = "";
      this.message = "";
      if (this.newPassword !== this.confirmPassword) {
        this.error = "The passwords do not match.";
        return;
      }
      this.loading = true;
      try {
        const access = await changePassword(this.newPassword, this.currentPassword);
        location.assign(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch (reason) {
        this.error = readableError(reason, "Unable to update your password.");
      } finally {
        this.loading = false;
      }
    },
    async forgot() {
      this.error = "";
      this.message = "";
      if (!this.email.trim()) {
        this.error = "Enter your email address first.";
        return;
      }
      this.loading = true;
      try {
        const redirectTo = new URL(`${import.meta.env.BASE_URL || "/"}login.html`, location.origin).toString();
        await requestPasswordReset(this.email, redirectTo);
        this.message = "If an AOI account exists for that email, a password reset link is on its way.";
      } catch (reason) {
        this.error = readableError(reason, "Unable to send a password reset email.");
      } finally {
        this.loading = false;
      }
    },
  }));
}
