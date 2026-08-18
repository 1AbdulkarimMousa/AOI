import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=eod");
  await expect(page.getByRole("heading", { name: "Close the day with a useful record." })).toBeVisible();
});

test("EOD form exposes linked errors and usable controls", async ({ page }) => {
  await page.getByRole("button", { name: "Submit brief" }).click();
  const summary = page.locator("#eod-error-summary");
  const movedOutcome = page.locator('.eod-layout [data-eod-field="movedOutcome"]');
  await expect(summary).toBeVisible();
  await expect(summary).toHaveAttribute("role", "alert");
  await expect(movedOutcome).toHaveAttribute("aria-invalid", "true");
  await expect(movedOutcome).toHaveAttribute("aria-errormessage", "eod-error-movedOutcome");
  await expect(movedOutcome).toHaveAttribute("aria-describedby", "eod-error-movedOutcome");
  await expect(page.locator("#eod-error-movedOutcome")).toHaveText("Add the tangible outcome that moved today.");
  await expect(page.locator("#eod-form-notice")).toHaveText("Review 11 required fields before submitting.");
  await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe("eod-error-summary");
  await summary.getByRole("button", { name: "Add the tangible outcome that moved today." }).click();
  await expect.poll(() => page.evaluate(() => document.activeElement?.dataset.eodField)).toBe("movedOutcome");
  await movedOutcome.fill("Completed a traceable synthesis.");
  await expect(movedOutcome).not.toHaveAttribute("aria-invalid", "true");
  await expect(page.locator("#eod-error-movedOutcome")).toBeHidden();
  await expect(summary).toBeVisible();
  await expect(page.locator("#eod-form-notice")).toHaveText("Review 10 required fields before submitting.");
});

test("EOD archive uses semantic columns and opens a named drawer", async ({ page }) => {
  const sidebarInitialInert = await page.locator("#workspace-sidebar").evaluate((element) => element.inert);
  const table = page.locator(".eod-report-table table");
  await expect(table).toBeVisible();
  await expect(table.getByRole("columnheader", { name: "Date" })).toBeVisible();
  const openKayla = table.getByRole("button", { name: /Open Kayla Tillmon EOD brief/ });
  await expect(openKayla).toBeVisible();
  await openKayla.click();
  const drawer = page.getByRole("dialog");
  await expect(drawer).toBeVisible();
  await expect(drawer).toHaveAttribute("aria-labelledby", "eod-record-title");
  await expect(drawer).toHaveAttribute("tabindex", "-1");
  await expect(drawer).toHaveJSProperty("tagName", "SECTION");
  await expect.poll(() => drawer.evaluate((element) => element.contains(document.activeElement))).toBe(true);
  await expect(page.locator("#workspace-sidebar")).toHaveJSProperty("inert", true);
  await expect(page.locator(".topbar")).toHaveJSProperty("inert", true);
  await page.keyboard.press("Escape");
  await expect(drawer).toBeHidden();
  await expect(page.locator("#workspace-sidebar")).toHaveJSProperty("inert", sidebarInitialInert);
  await expect(page.locator(".topbar")).toHaveJSProperty("inert", false);
});

test("administrator EOD validation identifies and focuses affected drawer fields", async ({ page }) => {
  await page.getByRole("button", { name: /Open Kayla Tillmon EOD brief/ }).first().click();
  const drawer = page.getByRole("dialog");
  const movedOutcome = drawer.getByLabel("What tangible outcome moved the project forward today?");
  await movedOutcome.fill("");
  await drawer.getByRole("button", { name: "Mark complete" }).click();

  const summary = drawer.locator("#eod-admin-error-summary");
  await expect(summary).toBeVisible();
  await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe("eod-admin-error-summary");
  await expect(movedOutcome).toHaveAttribute("aria-invalid", "true");
  await expect(movedOutcome).toHaveAttribute("aria-errormessage", "eod-admin-error-movedOutcome");
  await expect(movedOutcome).toHaveAttribute("aria-describedby", "eod-admin-error-movedOutcome");
  const reason = drawer.getByLabel("Edit or completion reason");
  await expect(reason).toHaveAttribute("aria-invalid", "true");
  await expect(reason).toHaveAttribute("aria-describedby", "eod-admin-error-adminReason");
  await summary.getByRole("button", { name: "Add the tangible outcome that moved today." }).click();
  await expect(movedOutcome).toBeFocused();
});

test("closing a nested command dialog returns focus to the EOD drawer", async ({ page }) => {
  await page.getByRole("button", { name: /Open Kayla Tillmon EOD brief/ }).first().click();
  const drawer = page.getByRole("dialog");
  const closeDrawer = drawer.getByRole("button", { name: "Close EOD record" });
  await expect(closeDrawer).toBeFocused();

  await page.keyboard.press("Control+k");
  const commandSearch = page.locator(".command-search");
  await expect(commandSearch).toBeVisible();
  await expect(commandSearch.locator("input")).toBeFocused();
  const commandBackdrop = commandSearch.locator("..").locator("..");
  await commandBackdrop.click({ position: { x: 5, y: 5 } });

  await expect(commandSearch).toBeHidden();
  await expect(drawer).toBeVisible();
  await expect(closeDrawer).toBeFocused();
});

test("EOD landmarks and archive filters expose unambiguous structure", async ({ page }) => {
  const requirementRail = page.locator(".eod-status-rail");
  await expect(requirementRail).toHaveJSProperty("tagName", "SECTION");
  await expect(requirementRail).toHaveAttribute("aria-label", "Submission requirements");

  const filters = page.locator(".eod-report-filters");
  await filters.getByLabel("Author").selectOption("m2");
  await filters.getByRole("button", { name: "Search" }).click();
  const reportRows = page.locator(".eod-report-table tbody tr");
  await expect(reportRows).toHaveCount(1);
  await expect(reportRows.first()).toContainText("Wen Tang");
  await expect(reportRows.first()).not.toContainText("Kayla Tillmon");
});

test("EOD background refresh keeps a usable draft mounted", async ({ page }) => {
  const refreshedSnapshot = await page.evaluate(() => {
    const state = window.Alpine.$data(document.querySelector('[x-data="workspacePage"]'));
    return { ...state.dailyEod, timezone: "Pacific/Honolulu" };
  });
  await page.route("**/rest/v1/rpc/rpc_aoi_daily_eod_snapshot", (route) => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ dailyEod: refreshedSnapshot }),
  }));
  const refreshState = await page.evaluate(async () => {
    const state = window.Alpine.$data(document.querySelector('[x-data="workspacePage"]'));
    state.dailyEodForm.movedOutcome = "Preserve this unfinished outcome.";
    state.dailyEodDirty = true;
    const refresh = state.refreshDailyEod({ preserveDraft: true });
    const during = { state: state.dailyEodState, refreshing: state.refreshingDailyEod };
    await refresh;
    return {
      result: await refresh,
      during,
      after: { state: state.dailyEodState, refreshing: state.refreshingDailyEod },
      movedOutcome: state.dailyEodForm.movedOutcome,
      timezone: state.dailyEod.timezone,
      error: state.dailyEodError,
    };
  });

  expect(refreshState.result).toBe(true);
  expect(refreshState.during).toEqual({ state: "ready", refreshing: true });
  expect(refreshState.after).toEqual({ state: "ready", refreshing: false });
  expect(refreshState.movedOutcome).toBe("Preserve this unfinished outcome.");
  expect(refreshState.timezone).toBe("Pacific/Honolulu");
  expect(refreshState.error).toBe("");
  await expect(page.getByRole("heading", { name: "Start today’s record" })).toBeVisible();
});

test("EOD remains contained under narrow reflow and AAA text spacing", async ({ page }) => {
  await page.addStyleTag({ content: "* { line-height: 1.5 !important; letter-spacing: .12em !important; word-spacing: .16em !important; } p { margin-bottom: 2em !important; }" });
  const containment = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    controls: [...document.querySelectorAll('.eod-page input:not([type="checkbox"]):not([type="radio"]), .eod-page select, .eod-page textarea, .eod-page button, .eod-page .eod-owner-options label, .eod-page .eod-status-options label')]
      .filter((element) => element.offsetParent !== null)
      .map((element) => ({ tag: element.tagName, type: element.getAttribute('type'), label: element.getAttribute('aria-label') || element.textContent?.trim().slice(0, 30), width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height })),
    clippedControls: [...document.querySelectorAll('.eod-form input, .eod-form select, .eod-form textarea, .eod-form button, .eod-report-filters input, .eod-report-filters select, .eod-report-filters button')]
      .filter((element) => element.offsetParent !== null)
      .map((element) => {
        const bounds = element.getBoundingClientRect();
        const container = element.closest('.eod-form, .eod-reports').getBoundingClientRect();
        return { label: element.getAttribute('aria-label') || element.textContent?.trim().slice(0, 30) || element.getAttribute('placeholder'), left: bounds.left, right: bounds.right, containerLeft: container.left, containerRight: container.right };
      })
      .filter((item) => item.left < item.containerLeft - 1 || item.right > item.containerRight + 1),
  }));
  expect(containment.overflow).toBeLessThanOrEqual(1);
  expect(containment.controls.filter((control) => control.height < 44 || control.width < 44)).toEqual([]);
  expect(containment.clippedControls).toEqual([]);

  await page.setViewportSize({ width: 1281, height: 800 });
  const intermediateClipping = await page.evaluate(() => [...document.querySelectorAll('.eod-form input, .eod-form select, .eod-form textarea, .eod-form button, .eod-report-filters input, .eod-report-filters select, .eod-report-filters button')]
    .filter((element) => element.offsetParent !== null)
    .map((element) => {
      const bounds = element.getBoundingClientRect();
      const container = element.closest('.eod-form, .eod-reports').getBoundingClientRect();
      return { label: element.getAttribute('aria-label') || element.textContent?.trim().slice(0, 30) || element.getAttribute('placeholder'), left: bounds.left, right: bounds.right, containerLeft: container.left, containerRight: container.right };
    })
    .filter((item) => item.left < item.containerLeft - 1 || item.right > item.containerRight + 1));
  expect(intermediateClipping).toEqual([]);
});

test("EOD actions remain visible in dark theme", async ({ page }) => {
  await page.evaluate(() => { document.documentElement.dataset.theme = "dark"; });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  const action = page.getByRole("button", { name: "Add evidence link" }).first();
  await expect(action).toBeVisible();
  const colors = await action.evaluate((element) => ({ color: getComputedStyle(element).color, background: getComputedStyle(element).backgroundColor }));
  expect(colors.color).not.toBe(colors.background);
});
