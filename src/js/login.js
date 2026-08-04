import { completePasswordChange, getExistingWorkspaceAccess, signIn } from "./auth.js";
import { pageUrl, readableError, routeForRole } from "./core.js";

export function registerLogin(Alpine) {
  Alpine.data("loginPage", () => ({
    email: "",
    password: "",
    showPassword: false,
    checking: true,
    loading: false,
    error: "",
    access: null,
    passwordSetup: false,
    newPassword: "",
    confirmPassword: "",
    async init() {
      try {
        const access = await getExistingWorkspaceAccess();
        if (access?.mustChangePassword) {
          this.access = access;
          this.passwordSetup = true;
        } else if (access) location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch {
        this.error = "Unable to check your session. You can still sign in.";
      } finally {
        this.checking = false;
      }
    },
    async submit() {
      this.error = "";
      this.loading = true;
      try {
        const access = await signIn(this.email, this.password);
        if (access.mustChangePassword) {
          this.access = access;
          this.password = "";
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
      if (this.newPassword !== this.confirmPassword) {
        this.error = "The passwords do not match.";
        return;
      }
      this.loading = true;
      try {
        const access = await completePasswordChange(this.newPassword);
        location.assign(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch (reason) {
        this.error = readableError(reason, "Unable to update your password.");
      } finally {
        this.loading = false;
      }
    },
    forgot() { this.error = "Ask an AOI administrator to reset your password."; },
  }));
}
