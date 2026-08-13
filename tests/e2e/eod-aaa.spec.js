import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=eod");
  await expect(page.getByRole("heading", { name: "Close the day with a useful record." })).toBeVisible();
});

test("EOD form exposes linked errors and usable controls", async ({ page }) => {
  await page.getByRole("button", { name: "Submit brief" }).click();
  const summary = page.locator("#eod-error-summary");
  await expect(summary).toBeVisible();
  await expect(summary).toHaveAttribute("role", "alert");
  await expect(page.locator('.eod-layout [data-eod-field="movedOutcome"]')).toHaveAttribute("aria-invalid", "true");
  await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe("eod-error-summary");
  await summary.getByRole("button", { name: "Add the tangible outcome that moved today." }).click();
  await expect.poll(() => page.evaluate(() => document.activeElement?.dataset.eodField)).toBe("movedOutcome");
});

test("EOD archive uses semantic columns and opens a named drawer", async ({ page }) => {
  const table = page.locator(".eod-report-table table");
  await expect(table).toBeVisible();
  await expect(table.getByRole("columnheader", { name: "Date" })).toBeVisible();
  await table.getByRole("button").first().click();
  const drawer = page.getByRole("dialog");
  await expect(drawer).toBeVisible();
  await expect(drawer).toHaveAttribute("aria-labelledby", "eod-record-title");
  await expect.poll(() => drawer.evaluate((element) => element.contains(document.activeElement))).toBe(true);
  await page.keyboard.press("Escape");
  await expect(drawer).toBeHidden();
});

test("EOD remains contained under narrow reflow and AAA text spacing", async ({ page }) => {
  await page.addStyleTag({ content: "* { line-height: 1.5 !important; letter-spacing: .12em !important; word-spacing: .16em !important; } p { margin-bottom: 2em !important; }" });
  const containment = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    controls: [...document.querySelectorAll('.eod-page input:not([type="checkbox"]):not([type="radio"]), .eod-page select, .eod-page textarea, .eod-page button, .eod-page .eod-owner-options label, .eod-page .eod-status-options label')]
      .filter((element) => element.offsetParent !== null)
      .map((element) => ({ tag: element.tagName, type: element.getAttribute('type'), label: element.getAttribute('aria-label') || element.textContent?.trim().slice(0, 30), width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height })),
  }));
  expect(containment.overflow).toBeLessThanOrEqual(1);
  expect(containment.controls.filter((control) => control.height < 44 && control.width < 44)).toEqual([]);
});

test("EOD actions remain visible in dark theme", async ({ page }) => {
  await page.evaluate(() => { document.documentElement.dataset.theme = "dark"; });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  const action = page.getByRole("button", { name: "Add evidence link" }).first();
  await expect(action).toBeVisible();
  const colors = await action.evaluate((element) => ({ color: getComputedStyle(element).color, background: getComputedStyle(element).backgroundColor }));
  expect(colors.color).not.toBe(colors.background);
});
