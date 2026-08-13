import { expect, test } from "@playwright/test";

test("preview projects route supports register and detail deep links", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&project=demo-project&tab=milestones&milestone=preview-milestone-1");
  await expect(page.getByRole("tablist", { name: "Project sections" })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("tab", { name: "Milestones" })).toHaveAttribute("aria-selected", "true");
  await expect(page.locator(".project-detail-pane")).toContainText("Event readiness checkpoint");
  await page.getByRole("button", { name: "Close detail" }).click();
  await expect(page).not.toHaveURL(/milestone=/);
});

test("project record collaboration uses named accessible controls", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=projects&project=demo-project&tab=decisions&decision=preview-decision-1");
  const collaboration = page.locator(".project-detail-pane .collaboration");
  await expect(collaboration.getByRole("heading", { name: "Collaboration" })).toBeVisible();
  await expect(collaboration.getByText("Avery Example")).toBeVisible();
  const follow = collaboration.getByRole("button", { name: "Unfollow updates" });
  await expect(follow).toHaveAttribute("aria-pressed", "true");
  await follow.click();
  await expect(collaboration.getByRole("button", { name: "Follow updates" })).toHaveAttribute("aria-pressed", "false");
  await collaboration.getByRole("textbox", { name: "Contextual comment" }).fill("Keep the synthetic access limitation visible in the final readout.");
  await collaboration.getByRole("button", { name: "Add comment" }).click();
  await expect(collaboration.getByText("Keep the synthetic access limitation visible in the final readout.")).toBeVisible();
  await collaboration.getByLabel("Handoff to").selectOption("m1");
  await collaboration.getByLabel("Handoff reason").fill("Please verify the alternate route before governance review.");
  await collaboration.getByRole("button", { name: "Send reasoned handoff" }).click();
  await expect(collaboration.getByText("Reasoned handoff sent.")).toBeVisible();
});

test("Today reuses compact collaboration without raw identifiers", async ({ page }) => {
  await page.goto("/AOI/workspace.html?preview=1&view=today");
  await page.locator(".inbox-row").first().click();
  const detail = page.locator(".inbox-detail");
  await expect(detail.getByRole("heading", { name: "Recent collaboration" })).toBeVisible();
  await expect(detail.getByLabel("Handoff to")).toBeVisible();
  await expect(detail.getByText(/UUID|recipient ID/i)).toHaveCount(0);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
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
