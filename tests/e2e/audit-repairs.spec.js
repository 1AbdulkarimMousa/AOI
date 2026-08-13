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
  await page.goto("/AOI/workspace.html?preview=1&view=research&tab=surveys");
  const rows = page.locator(".survey-library-row");
  await expect(rows).toHaveCount(1);

  await page.getByRole("textbox", { name: "Search surveys" }).fill("no matching survey");
  await expect(rows).toHaveCount(0);

  await page.getByRole("textbox", { name: "Search surveys" }).fill("");
  await page.getByRole("tab", { name: /Templates/ }).click();
  await expect(page.getByRole("tab", { name: /Templates/ })).toHaveAttribute("aria-selected", "true");
});

test("survey analysis tabs expose selected state", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=research&tab=surveys");
  await page.locator(".survey-library-row").click();
  await page.locator(".survey-command-bar").getByRole("tab", { name: "Analyze" }).click();
  await page.getByRole("tab", { name: "Questions" }).click();
  await expect(page.getByRole("tab", { name: "Questions" })).toHaveAttribute("aria-selected", "true");
});

test("CRM drawer receives and contains keyboard focus", async ({ page, isMobile }) => {
  test.skip(isMobile, "Desktop focus containment is covered independently from mobile navigation.");
  await page.goto("/AOI/workspace.html?preview=1&view=relationships&tab=contacts");
  await page.locator(".crm-directory-row").first().click();
  const dialog = page.getByRole("dialog", { name: /Contact record/ });
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Save contact");
  await expect.poll(() => page.evaluate(() => document.querySelector(".crm-drawer")?.contains(document.activeElement))).toBe(true);
  for (let index = 0; index < 12; index += 1) await page.keyboard.press("Tab");
  await expect.poll(() => page.evaluate(() => document.querySelector(".crm-drawer")?.contains(document.activeElement))).toBe(true);
});

test("contact deep links follow browser back and forward", async ({ page, isMobile }) => {
  test.skip(isMobile, "Desktop history contract avoids mobile drawer-navigation overlap.");
  await page.goto("/AOI/workspace.html?preview=1&view=today&tab=relationships");
  await page.locator(".crm-queue-row").first().click();
  await expect(page).toHaveURL(/view=relationships&tab=contacts&contact=/);
  await expect(page.getByRole("dialog", { name: /Contact record/ })).toBeVisible();

  await page.goBack();
  await expect(page).toHaveURL(/view=today&tab=relationships/);
  await expect(page.getByRole("dialog", { name: /Contact record/ })).toBeHidden();

  await page.goForward();
  await expect(page).toHaveURL(/view=relationships&tab=contacts&contact=/);
  await expect(page.getByRole("dialog", { name: /Contact record/ })).toBeVisible();
});

test("preview Recruitment remains embedded in Relationships", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=relationships&tab=recruitment");
  await expect(page).toHaveURL(/view=relationships&tab=recruitment/);
  await expect(page.getByRole("heading", { name: "Recruitment", exact: true })).toBeVisible();
  await expect(page).not.toHaveURL(/login\.html/);
});

test("Relationships and Outreach tabs support keyboard navigation", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=relationships&tab=contacts");
  const contacts = page.getByRole("tab", { name: "Contacts" });
  await contacts.focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Recruitment" })).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("End");
  await expect(page.getByRole("tab", { name: "Outreach" })).toHaveAttribute("aria-selected", "true");
  await page.getByRole("tab", { name: "Pipeline" }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Evidence" })).toHaveAttribute("aria-selected", "true");
});

test("Relationships routes contain narrow viewports and keep touch targets usable", async ({ page, isMobile }) => {
  test.skip(!isMobile, "Narrow viewport contract.");
  for (const route of [
    "contacts",
    "recruitment",
    "outreach&section=pipeline",
  ]) {
    await page.goto(`/AOI/workspace.html?preview=1&view=relationships&tab=${route}`);
    const containment = await mobileContainment(page);
    expect(containment.overflow, JSON.stringify(containment.offenders)).toBeLessThanOrEqual(1);
  }
});

test("mobile survey management has no page-level horizontal overflow", async ({ page, isMobile }) => {
  test.skip(!isMobile, "Mobile-only containment contract.");
  await page.goto("/AOI/workspace.html?preview=1&view=research&tab=surveys");
  await page.locator(".survey-library-row").click();
  await page.locator(".survey-command-bar").getByRole("tab", { name: "Analyze" }).click();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  const sidebarState = await page.evaluate(() => {
    const sidebar = document.querySelector(".sidebar");
    return { inert: sidebar?.inert, hidden: sidebar?.getAttribute("aria-hidden") };
  });
  expect(sidebarState).toEqual({ inert: true, hidden: "true" });
});

test("role-adaptive Today inbox reflows without horizontal overflow", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=today&tab=briefing");
  await expect(page.locator(".briefing-workspace").getByRole("heading", { level: 1 })).toBeVisible({ timeout: 15_000 });
  await expect(page.locator(".briefing-header-state").getByText("Preview only", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Needs attention" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "PMF evidence chain" })).toBeVisible();
  const containment = await mobileContainment(page);
  expect(containment.overflow, JSON.stringify(containment.offenders)).toBeLessThanOrEqual(1);
  await expect(page.getByRole("navigation", { name: "Work inbox views" })).toBeVisible();
});

test("Briefing routes factual PMF evidence directly to Analyze", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=today&tab=briefing");
  await page.locator(".briefing-pmf-list button").first().click();
  await expect(page).toHaveURL(/view=research&tab=analyze/);
  await expect(page.getByRole("tab", { name: "Analyze" })).toHaveAttribute("aria-selected", "true");
});

test("intern Briefing stays personal and preserves explicit preview provenance", async ({ page }) => {
  await page.goto("/AOI/interns.html?preview=1&view=today&tab=briefing");
  const briefing = page.locator(".briefing-workspace");
  await expect(briefing.getByRole("heading", { level: 1 })).toContainText(/item needs|assigned work is clear/i);
  await expect(briefing.locator(".briefing-header-state")).toContainText("Preview only");
  await expect(briefing.locator(".briefing-attention-row")).toHaveCount(1);
  await expect(briefing.locator(".briefing-attention-row")).toContainText("Assigned task needs follow-up");
});

test("Briefing actions retain 44px targets and explicit empty states", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=today&tab=briefing");
  for (const selector of [".briefing-pulse button", ".briefing-text-action", ".briefing-attention-row"]) {
    const box = await page.locator(selector).first().boundingBox();
    expect(box?.height || 0, selector).toBeGreaterThanOrEqual(44);
  }
  await page.evaluate(() => {
    const root = document.querySelector("[x-data]");
    const state = window.Alpine.$data(root);
    state.briefingState = { ...state.briefingState, pmfChain: [], generatedAt: new Date().toISOString() };
  });
  await expect(page.getByText("No PMF layers configured.")).toBeVisible();
});

test("Today inbox tolerates AAA text spacing overrides", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=today&tab=briefing");
  await page.addStyleTag({ content: "* { line-height: 1.5 !important; letter-spacing: .12em !important; word-spacing: .16em !important; } p { margin-bottom: 2em !important; }" });
  const containment = await mobileContainment(page);
  expect(containment.overflow, JSON.stringify(containment.offenders)).toBeLessThanOrEqual(1);
  await expect(page.getByRole("navigation", { name: "Work inbox views" })).toBeVisible();
});

async function mobileContainment(page) {
  return page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    offenders: [...document.querySelectorAll("body *")]
      .filter((element) => element.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
      .slice(0, 12)
      .map((element) => ({ tag: element.tagName, className: element.className, right: Math.round(element.getBoundingClientRect().right), width: Math.round(element.getBoundingClientRect().width) })),
  }));
}

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
