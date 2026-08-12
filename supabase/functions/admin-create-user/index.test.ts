function assertEquals(actual: unknown, expected: unknown) {
  if (!Object.is(actual, expected)) throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
}

const originalServe = Deno.serve;
Object.defineProperty(Deno, "serve", {
  configurable: true,
  value: () => ({
    addr: { hostname: "127.0.0.1", port: 0, transport: "tcp" },
    finished: Promise.resolve(),
    ref() {},
    shutdown: () => Promise.resolve(),
    unref() {},
  }),
});
const policy = await import("./index.ts") as Record<string, unknown>;
Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });

Deno.test("accepts only an explicit recovery AMR entry", () => {
  assertEquals(typeof policy.hasRecoveryAuthentication, "function");
  const hasRecoveryAuthentication = policy.hasRecoveryAuthentication as (value: unknown) => boolean;
  assertEquals(hasRecoveryAuthentication([{ method: "recovery", timestamp: 1_786_291_200 }]), true);
  assertEquals(hasRecoveryAuthentication([{ method: "recovery" }]), false);
  assertEquals(hasRecoveryAuthentication([{ method: "password", timestamp: 1_786_291_200 }]), false);
  assertEquals(hasRecoveryAuthentication({ method: "recovery", timestamp: 1_786_291_200 }), false);
  assertEquals(hasRecoveryAuthentication("recovery"), false);
});

Deno.test("non-owner administrators cannot reset privileged targets", () => {
  assertEquals(typeof policy.canAdministratorResetTarget, "function");
  const canAdministratorResetTarget = policy.canAdministratorResetTarget as (callerIsOwner: boolean, target: { is_owner: boolean; role: string }) => boolean;
  assertEquals(canAdministratorResetTarget(false, { is_owner: true, role: "admin" }), false);
  assertEquals(canAdministratorResetTarget(false, { is_owner: false, role: "admin" }), false);
  assertEquals(canAdministratorResetTarget(false, { is_owner: false, role: "intern" }), true);
  assertEquals(canAdministratorResetTarget(false, { is_owner: false, role: "" }), false);
  assertEquals(canAdministratorResetTarget(false, { is_owner: true, role: "intern" }), false);
  assertEquals(canAdministratorResetTarget(true, { is_owner: true, role: "admin" }), true);
});

Deno.test("active recovery does not depend on must_change_password", () => {
  assertEquals(typeof policy.passwordCompletionMode, "function");
  const passwordCompletionMode = policy.passwordCompletionMode as (profile: { status: string; must_change_password: boolean }, recovery: boolean, verifiedCallback?: boolean) => string;
  assertEquals(passwordCompletionMode({ status: "active", must_change_password: false }, true), "recovery");
  assertEquals(passwordCompletionMode({ status: "active", must_change_password: false }, false), "denied");
  assertEquals(passwordCompletionMode({ status: "password_change_required", must_change_password: true }, false), "temporary");
  assertEquals(passwordCompletionMode({ status: "invited", must_change_password: false }, true), "denied");
  assertEquals(passwordCompletionMode({ status: "invited", must_change_password: true }, false, true), "invitation");
});
