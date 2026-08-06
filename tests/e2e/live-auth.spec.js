import { expect, test } from "@playwright/test";

const liveUrl = process.env.AOI_LIVE_URL;
const email = process.env.AOI_TEST_EMAIL;
const password = process.env.AOI_TEST_PASSWORD;

test("authenticated production workspace reaches live survey data", async ({ page }) => {
  test.skip(!liveUrl || !email || !password, "Live AOI credentials are required.");
  const runtimeErrors = [];
  page.on("pageerror", (error) => runtimeErrors.push(error.message));

  await page.goto(new URL("login.html", liveUrl).href);
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Log in" }).click();
  await expect(page).toHaveURL(/(?:workspace|interns)\.html/, { timeout: 20_000 });
  await expect(page.locator(".app-shell")).toBeVisible();

  const research = page.getByRole("button", { name: "Research" });
  if (await research.count()) {
    await research.click();
    await page.getByRole("tab", { name: "Surveys", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Build evidence people can trust." })).toBeVisible();
    await expect(page.locator(".survey-library-row").first()).toBeVisible();
  }

  expect(runtimeErrors, runtimeErrors.join("\n")).toEqual([]);
});
