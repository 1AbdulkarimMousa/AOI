import { defineConfig, devices } from "@playwright/test";
import { existsSync } from "node:fs";

const systemChromium = "/run/current-system/sw/bin/chromium";
const launchOptions = !process.env.CI && existsSync(systemChromium)
  ? { executablePath: systemChromium }
  : {};

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "line",
  use: {
    baseURL: "http://127.0.0.1:4199",
    launchOptions,
    trace: "retain-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1186, height: 660 } } },
    { name: "mobile", use: { ...devices["Pixel 5"], viewport: { width: 390, height: 844 } } },
    { name: "mobile-320", use: { ...devices["Pixel 5"], viewport: { width: 320, height: 720 } } },
  ],
  webServer: {
    command: "GITHUB_ACTIONS=1 npm run preview -- --host 127.0.0.1 --port 4199",
    url: "http://127.0.0.1:4199/AOI/workspace.html?preview=1",
    reuseExistingServer: !process.env.CI && !process.env.GITHUB_ACTIONS,
  },
});
