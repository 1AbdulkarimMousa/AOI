import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const [aoi, helpcenter, participant] = await Promise.all([
  readFile(new URL("src/css/aoi.css", root), "utf8"),
  readFile(new URL("src/css/helpcenter.css", root), "utf8"),
  readFile(new URL("src/css/participant-tracker.css", root), "utf8"),
]);
const [app, auth, core, dialogManager, workspace] = await Promise.all([
  readFile(new URL("src/js/app.js", root), "utf8"),
  readFile(new URL("src/js/auth.js", root), "utf8"),
  readFile(new URL("src/js/core.js", root), "utf8"),
  readFile(new URL("src/js/dialog-manager.js", root), "utf8"),
  readFile(new URL("src/js/workspace.js", root), "utf8"),
]);

function tokenMap(block) {
  return Object.fromEntries([...block.matchAll(/--([\w-]+):\s*(#[\da-f]{6})\s*;/gi)].map((match) => [match[1], match[2]]));
}

function themeTokens(source) {
  const light = source.match(/:root\s*{([\s\S]*?)}/)?.[1] ?? "";
  const dark = source.match(/:root\[data-theme="dark"\]\s*{([\s\S]*?)}/)?.[1] ?? "";
  const lightTokens = tokenMap(light);
  return { light: lightTokens, dark: { ...lightTokens, ...tokenMap(dark) } };
}

function channel(value) {
  const normalized = value / 255;
  return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
}

function luminance(hex) {
  const channels = hex.match(/[\da-f]{2}/gi).map((value) => channel(Number.parseInt(value, 16)));
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(foreground, background) {
  const [lighter, darker] = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
}

test("light and dark semantic token pairs meet WCAG AAA for normal text", () => {
  const themes = themeTokens(aoi);
  const pairs = [
    ["ink", "bg"],
    ["ink", "surface"],
    ["ink-soft", "surface"],
    ["ink-faint", "surface"],
    ["on-accent", "orange"],
    ["orange-dark", "orange-soft"],
    ["teal", "teal-soft"],
    ["blue", "blue-soft"],
    ["rose", "rose-soft"],
    ["gold", "gold-soft"],
  ];

  for (const [themeName, tokens] of Object.entries(themes)) {
    assert.notEqual(tokens.surface.toLowerCase(), "#ffffff", `${themeName} surface must be tinted`);
    for (const [foreground, background] of pairs) {
      assert.ok(tokens[foreground] && tokens[background], `${themeName} must define ${foreground}/${background}`);
      assert.ok(
        contrast(tokens[foreground], tokens[background]) >= 7,
        `${themeName} ${foreground} on ${background} must meet 7:1`,
      );
    }
  }
});

test("interactive composites expose focus and 44px touch contracts", () => {
  assert.match(aoi, /--focus-ring:\s*#[\da-f]{6}/i);
  assert.match(aoi, /:where\(button, a\[href\], input, select, textarea, \[tabindex\][\s\S]*?:focus-visible[\s\S]*?outline:\s*3px solid var\(--focus-ring\)/);
  assert.match(aoi, /\.search-box:focus-within[\s\S]*?\.command-search:focus-within[\s\S]*?\.upload-drop:focus-within[\s\S]*?\.admin-upload:focus-within/);
  assert.match(aoi, /\.focus-row:focus-within[\s\S]*?\.admin-person-row:focus-within[\s\S]*?\.review-row:focus-within/);
  assert.match(aoi, /\.button,[\s\S]*?\.icon-button[\s\S]*?min-height:\s*44px/);
  assert.match(helpcenter, /\.help-language,[\s\S]*?\.help-icon-button[\s\S]*?min-height:\s*44px/);
  assert.match(participant, /\.participant-search:focus-within[\s\S]*?outline:\s*3px solid var\(--focus-ring\)/);
  assert.match(participant, /\.participant-controls select,[\s\S]*?min-height:\s*44px/);
  assert.doesNotMatch(aoi, /button\.collect-table-row:hover,\s*button\.collect-table-row:focus-visible\s*{[^}]*outline:\s*none/);
});

test("tablet administration and mobile content stay internally contained", () => {
  assert.match(aoi, /@media \(min-width:\s*761px\) and \(max-width:\s*1024px\)[\s\S]*?\.admin-directory\s*{[\s\S]*?overflow-x:\s*auto/);
  assert.match(aoi, /\.main-wrap\s*{[\s\S]*?grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(aoi, /\.content-area,[\s\S]*?\.content-frame[\s\S]*?min-width:\s*0/);
  assert.match(helpcenter, /\.help-main,[\s\S]*?\.helpcenter-layout[\s\S]*?min-width:\s*0/);
  assert.match(participant, /\.participant-tracker-shell\s*{[\s\S]*?grid-template-columns:\s*minmax\(0,\s*1fr\)/);
});

test("modals and drawers scroll within short dynamic viewports and safe areas", () => {
  assert.match(aoi, /\.modal-backdrop\s*{[\s\S]*?min-height:\s*100dvh[\s\S]*?overflow-y:\s*auto[\s\S]*?env\(safe-area-inset-top\)/);
  assert.match(aoi, /\.command-modal\s*{[\s\S]*?max-height:\s*calc\(100dvh/);
  assert.match(aoi, /\.task-drawer,[\s\S]*?\.admin-person-drawer[\s\S]*?height:\s*100dvh[\s\S]*?env\(safe-area-inset-bottom\)/);
  assert.match(helpcenter, /\.help-editor-backdrop\s*{[\s\S]*?min-height:\s*100dvh[\s\S]*?overflow-y:\s*auto/);
  assert.match(helpcenter, /\.help-editor,[\s\S]*?\.help-editor-drawer[\s\S]*?height:\s*100dvh[\s\S]*?env\(safe-area-inset-bottom\)/);
  assert.match(participant, /\.participant-drawer\s*{[\s\S]*?height:\s*100dvh[\s\S]*?env\(safe-area-inset-bottom\)/);
});

test("participant tracker uses shared dark-compatible tokens", () => {
  assert.doesNotMatch(participant, /var\(--(?:paper|muted)\b|(?:color|background):\s*(?:white|#fff(?:fff)?\b)/i);
  assert.match(participant, /:root\[data-theme="dark"\] \.participant-(?:tracker-shell|status)/);
  assert.match(participant, /\.participant-status\[data-status="scheduled"\][\s\S]*?var\(--teal-soft\)[\s\S]*?var\(--teal\)/);
});

test("motion, hierarchy, typography, and accent geometry stay restrained", () => {
  assert.equal((aoi.match(/@keyframes drawer-in/g) ?? []).length, 1, "drawer animation must have one definition");
  assert.doesNotMatch(aoi, /transition:\s*[^;]*(?:width|margin)/);
  assert.match(aoi, /@media \(prefers-reduced-motion:\s*reduce\)[\s\S]*?animation:\s*none !important[\s\S]*?transition:\s*none !important/);
  assert.match(aoi, /--font-size-caption:\s*0\.75rem/);
  assert.match(aoi, /\.hero-card,[\s\S]*?\.mission-card[\s\S]*?min-height:\s*220px/);
  assert.doesNotMatch(aoi, /grid-template-columns:\s*4px/);
  assert.doesNotMatch(helpcenter, /border-(?:left|right):\s*[2-9]px solid/);
  assert.match(helpcenter, /\.help-callout,[\s\S]*?\.help-example[\s\S]*?border:\s*1px solid var\(--blue\)/);
  assert.match(helpcenter, /\.helpcenter-hero\s*{[\s\S]*?min-height:\s*200px/);
  assert.match(participant, /\.participant-hero h1[\s\S]*?clamp\(2rem,\s*5vw,\s*3\.4rem\)/);
});

test("shared foundations normalize routes and protect async dialog state", () => {
  assert.equal(core.includes("export function pageUrl"), true);
  assert.equal(core.includes("export function routeForRole"), true);
  assert.match(auth, /at least 14 characters with upper\/lower case/);
  assert.match(workspace, /dashboardRefreshSequence/);
  assert.match(workspace, /sequence !== this\.dashboardRefreshSequence/);
  assert.match(dialogManager, /MutationObserver/);
  assert.match(dialogManager, /event\.key === "Escape"/);
  assert.match(dialogManager, /event\.key !== "Tab"/);
  assert.match(app, /registerDialogManager\(\)/);
  assert.match(aoi, /html\.dialog-open[\s\S]*overflow:\s*hidden/);
});

test("dialog visibility ignores dialogs inside hidden wrappers", () => {
  assert.match(dialogManager, /getClientRects\(\)\.length/);
});
