import { expect, test } from "@playwright/test";

const runtimeErrors = new WeakMap();

test.beforeEach(async ({ page }) => {
  const errors = [];
  runtimeErrors.set(page, errors);
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error" && !message.text().includes("Failed to load resource")) errors.push(message.text());
  });
  page.on("response", (response) => {
    const type = response.request().resourceType();
    if (response.status() >= 400 && ["document", "script", "stylesheet", "fetch", "xhr"].includes(type)) {
      errors.push(`${response.status()} ${response.url()}`);
    }
  });
});

test.afterEach(async ({ page }) => {
  const errors = runtimeErrors.get(page) || [];
  expect(errors, errors.join("\n")).toEqual([]);
});

test("survey library search and views change visible results", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=surveys");
  const rows = page.locator(".survey-library-row");
  await expect(rows).toHaveCount(1);

  await page.getByRole("textbox", { name: "Search surveys" }).fill("no matching survey");
  await expect(rows).toHaveCount(0);

  await page.getByRole("textbox", { name: "Search surveys" }).fill("");
  await page.getByRole("tab", { name: /Templates/ }).click();
  await expect(page.getByRole("tab", { name: /Templates/ })).toHaveAttribute("aria-selected", "true");
});

test("survey analysis tabs expose selected state", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=surveys");
  await page.locator(".survey-library-row").click();
  await page.getByRole("tab", { name: "Analyze" }).click();
  await page.getByRole("tab", { name: "Questions" }).click();
  await expect(page.getByRole("tab", { name: "Questions" })).toHaveAttribute("aria-selected", "true");
});

test("CRM drawer receives and contains keyboard focus", async ({ page, isMobile }) => {
  test.skip(isMobile, "Desktop focus containment is covered independently from mobile navigation.");
  await page.goto("/AOI/workspace.html?preview=1&view=crm");
  await page.locator(".crm-directory-row").first().click();
  const dialog = page.getByRole("dialog", { name: /Contact record/ });
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Save contact");
  await expect.poll(() => page.evaluate(() => document.querySelector(".crm-drawer")?.contains(document.activeElement))).toBe(true);
  for (let index = 0; index < 12; index += 1) await page.keyboard.press("Tab");
  await expect.poll(() => page.evaluate(() => document.querySelector(".crm-drawer")?.contains(document.activeElement))).toBe(true);
});

test("mobile survey management has no page-level horizontal overflow", async ({ page, isMobile }) => {
  test.skip(!isMobile, "Mobile-only containment contract.");
  await page.goto("/AOI/workspace.html?preview=1&view=surveys");
  await page.locator(".survey-library-row").click();
  await page.getByRole("tab", { name: "Analyze" }).click();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  const sidebarState = await page.evaluate(() => {
    const sidebar = document.querySelector(".sidebar");
    return { inert: sidebar?.inert, hidden: sidebar?.getAttribute("aria-hidden") };
  });
  expect(sidebarState).toEqual({ inert: true, hidden: "true" });
});

test("administration directory remains reachable at tablet width", async ({ page, isMobile }) => {
  test.skip(isMobile, "Tablet contract uses the desktop project.");
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto("/AOI/administration.html?preview=1");
  await page.getByRole("tab", { name: "People" }).click();
  const directory = page.locator(".admin-directory:visible").first();
  await expect(directory).toBeVisible();
  const containment = await directory.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth,
    overflowX: getComputedStyle(element).overflowX,
  }));
  expect(containment.scrollWidth === containment.clientWidth || containment.overflowX === "auto").toBe(true);
});

test("dark mode and reduced motion remain usable at browser zoom", async ({ page, isMobile }) => {
  test.skip(isMobile, "Desktop project covers zoom while mobile projects cover narrow reflow.");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/AOI/workspace.html?preview=1");
  await page.getByRole("button", { name: "Dark mode" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.evaluate(() => { document.body.style.zoom = "2"; });
  await expect(page.locator(".main-wrap")).toBeVisible();
  const motion = await page.locator(".progress-fill").first().evaluate((element) => getComputedStyle(element).transitionDuration);
  expect(["0s", "0.001s"]).toContain(motion);
});
