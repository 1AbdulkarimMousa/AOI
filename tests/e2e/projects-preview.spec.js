import { expect, test } from "@playwright/test";

test("preview projects route supports register and detail deep links", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&project=demo-project&tab=milestones&milestone=preview-milestone-1");
  await expect(page.getByRole("tablist", { name: "Project sections" })).toBeVisible();
  await expect(page.getByRole("tab", { name: "Milestones" })).toHaveAttribute("aria-selected", "true");
  await expect(page.locator(".project-detail-pane")).toContainText("Pilot readiness checkpoint");
  await page.getByRole("button", { name: "Close detail" }).click();
  await expect(page).not.toHaveURL(/milestone=/);
});

test("preview project switcher and mobile project workspace remain usable", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&tab=decisions");
  await expect(page.getByLabel("Active project")).toHaveValue("demo-project");
  await page.locator(".project-register-row").first().click();
  await expect(page.getByText("Supporting evidence", { exact: true })).toBeVisible();
  await expect(page.getByText("Contradictory evidence", { exact: true })).toBeVisible();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
});

test("preview admin can exercise inline project configuration without persistence", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&tab=overview");
  await page.getByRole("button", { name: "Configure project" }).click();
  await expect(page.getByRole("heading", { name: "Configure project" })).toBeVisible();
  await expect(page.locator(".project-admin-pane").getByText("Preview only", { exact: false })).toBeVisible();
  await page.getByLabel("Project objective").fill("Updated preview objective");
  await page.getByRole("button", { name: "Save project" }).click();
  await expect(page.getByText("Updated preview objective")).toBeVisible();
});

test("preview intern does not receive project administration controls", async ({ page }) => {
  await page.goto("/AOI/interns.html?preview=1&view=projects&tab=overview");
  await expect(page.getByRole("button", { name: "Create project" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Configure project" })).toHaveCount(0);
});

test("project tabs support arrows, dark mode, zoom, and text spacing", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&tab=overview");
  const overview = page.getByRole("tab", { name: "Overview" });
  await overview.focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Milestones" })).toBeFocused();
  await expect(page.getByRole("tab", { name: "Milestones" })).toHaveAttribute("aria-selected", "true");
  await page.evaluate(() => localStorage.setItem("aoi-theme", "dark"));
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  const viewport = page.viewportSize();
  await page.setViewportSize({ width: Math.max(320, Math.floor(viewport.width / 2)), height: viewport.height });
  await page.evaluate(() => {
    document.body.style.letterSpacing = "0.12em";
    document.body.style.wordSpacing = "0.16em";
    document.body.style.lineHeight = "1.7";
  });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
});
