import { getExistingWorkspaceAccess, signIn } from "./auth.js";
import { pageUrl, readableError, routeForRole } from "./core.js";

export function registerLogin(Alpine) {
  Alpine.data("loginPage", () => ({
    email: "",
    password: "",
    showPassword: false,
    checking: true,
    loading: false,
    error: "",
    async init() {
      try {
        const access = await getExistingWorkspaceAccess();
        if (access) location.replace(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
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
        location.assign(pageUrl(import.meta.env.BASE_URL, routeForRole(access.role)));
      } catch (reason) {
        this.error = readableError(reason, "Unable to sign in.");
      } finally {
        this.loading = false;
      }
    },
    forgot() { this.error = "Ask an AOI administrator to reset your password."; },
  }));
}
