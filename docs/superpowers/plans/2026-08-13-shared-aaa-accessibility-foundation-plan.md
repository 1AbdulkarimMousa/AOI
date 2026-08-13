# Shared AAA Accessibility Foundation Implementation Plan

**Date:** 2026-08-13

**Design:** `docs/superpowers/specs/2026-08-13-shared-aaa-accessibility-foundation-design.md`

**Goal:** Establish shared, testable accessibility behavior across all eight AOI entries, use English for active product presentation while preserving localization data, and produce route-specific evidence without making a premature platform-wide WCAG 2.2 AAA claim.

**Architecture:** Add a small `accessibility.js` module for page initialization, announcements, meaningful focus movement, and tab keyboard behavior. Refactor `session-guard.js` into an injectable inactivity controller and render one shared timeout dialog. Keep semantics in source templates and HTML rather than applying runtime overlays. Adopt the shared contracts route by route.

**Technology:** Vite 8, Alpine.js 3, browser JavaScript modules, Tailwind CSS 4, custom CSS, Node test runner, Playwright, Supabase Auth.

## Working Rules

- Follow red-green-refactor for every behavior change.
- Run the focused failing test before editing production code.
- Use forward-compatible, additive changes; no database migration is expected.
- Preserve current project collaboration behavior and tests.
- Never stage `summary.md`, `131.md`, `deno.lock`, or `raw_data/`.
- Do not remove Chinese source strings, bilingual business data, or stored locale fields.
- Do not add an accessibility overlay or claim platform-wide AAA conformance from automated checks.
- Keep one implementation commit per coherent batch where practical.

## Task 0: Stabilize The Existing Collaboration Baseline

The completed collaboration slice overlaps `src/css/aoi.css`, `src/js/workspace.js`, project templates, and Playwright tests. Commit it before accessibility edits so later diffs are isolated.

**Include:**

- `README.md`
- `docs/quality/audit-matrix.md`
- `playwright.config.js`
- `src/css/aoi.css`
- `src/js/api.js`
- `src/js/collaboration.js`
- `src/js/inbox-template.js`
- `src/js/projects-template.js`
- `src/js/projects.js`
- `src/js/workspace.js`
- `supabase/migrations/20260813011721_project_collaboration_ux_closure.sql`
- `tests/collaboration-domain.test.mjs`
- `tests/collaboration-execution.test.mjs`
- `tests/e2e/audit-repairs.spec.js`
- `tests/e2e/projects-preview.spec.js`
- `tests/inbox-ui.test.mjs`
- `tests/project-operating-core-execution.test.mjs`
- `tests/projects-domain.test.mjs`
- `tests/projects-ui.test.mjs`
- collaboration design and plan documents

**Step 1: Verify the intended baseline**

Run:

```bash
npm run lint
npm test
npm run test:e2e
git diff --check
```

Expected: lint passes, 322 or more Node tests pass, expected credential-gated live tests are inventoried, Playwright collaboration coverage passes, and no whitespace errors exist.

**Step 2: Stage only the listed files and inspect**

Run `git status --short`, `git diff --cached --check`, and `git diff --cached --stat`.

Expected: `summary.md`, `131.md`, `deno.lock`, and `raw_data/` remain unstaged.

**Step 3: Commit**

```bash
git commit -m "feat(workspace): close project collaboration UX"
```

Do not push until the accessibility release gate unless explicitly requested earlier.

## Task 1: Add Failing Eight-Entry Accessibility Contracts

**Files:**

- Create: `tests/accessibility-entry.test.mjs`
- Modify: `tests/static-app.test.mjs`
- Test: `tests/accessibility-entry.test.mjs`

**Step 1: Write failing tests**

For all eight entries assert:

- file exists;
- `<html lang="en">` exists;
- descriptive title and viewport metadata exist;
- the first interactive element is a skip link to `#main-content`;
- exactly one `<main id="main-content">` exists in the entry shell;
- no visible locale-switch control or multilingual product claim exists;
- the application mount remains inside the main landmark.

Update the obsolete six-page static-app wording and list to all eight entries. Replace the existing assertion that workspace persists active locale with assertions that active presentation is English and localization data remains available.

**Step 2: Verify RED**

```bash
node --test tests/accessibility-entry.test.mjs tests/static-app.test.mjs
```

Expected: failures identify missing skip links/main IDs, template-level duplicate mains, visible language controls, and the stale six-page contract.

## Task 2: Implement Stable Entry Structure And English Initialization

**Files:**

- Create: `src/js/accessibility.js`
- Modify: `src/js/app.js`
- Modify: `index.html`
- Modify: `login.html`
- Modify: `workspace.html`
- Modify: `interns.html`
- Modify: `administration.html`
- Modify: `helpcenter.html`
- Modify: `Participant_Recruitment_Tracker.html`
- Modify: `survey.html`
- Modify: `src/js/workspace-template.js`
- Modify: `src/js/administration-template.js`
- Modify: `src/js/helpcenter-template.js`
- Modify: `src/js/participant-tracker-template.js`
- Modify: `src/js/surveys/runner-template.js`
- Test: `tests/accessibility-entry.test.mjs`
- Test: `tests/rendered-html.test.mjs`

**Step 1: Add the minimal entry structure**

- Put a skip link before application chrome in every HTML entry.
- Put the application mount inside one `<main id="main-content" tabindex="-1">`.
- Convert injected loading, unavailable, and ready-state template `<main>` elements to `div` or `section` containers with suitable labels.
- Ensure no nested or duplicate main landmarks are created after Alpine initialization.

**Step 2: Add English presentation initialization**

Implement and export pure helpers from `accessibility.js`:

```js
export const ACTIVE_PRODUCT_LOCALE = "en";
export function initializeEnglishPresentation(documentRef = document) {}
```

The initializer sets document language and is idempotent. Register it before page-specific controller initialization in `app.js`.

**Step 3: Verify GREEN**

```bash
node --test tests/accessibility-entry.test.mjs tests/static-app.test.mjs tests/rendered-html.test.mjs
```

Expected: all entry and built-structure contracts pass.

**Step 4: Commit**

```bash
git commit -m "feat(a11y): add stable page entry structure"
```

## Task 3: Make Active Product Presentation English-Only

**Files:**

- Modify: `index.html`
- Modify: `src/js/landing.js`
- Modify: `src/js/workspace-template.js`
- Modify: `src/js/workspace.js`
- Modify: `src/js/profile-template.js`
- Modify: `src/js/profile.js`
- Modify: `src/js/administration-template.js`
- Modify: `src/js/administration.js`
- Modify: `src/js/helpcenter-template.js`
- Modify: `src/js/helpcenter.js`
- Modify: `src/js/surveys/runner-template.js`
- Modify: `src/js/surveys/runner.js`
- Modify: `tests/profile.test.mjs`
- Modify: `tests/administration.test.mjs`
- Modify: `tests/helpcenter.test.mjs`
- Modify: `tests/survey-ui.test.mjs`
- Test: `tests/accessibility-entry.test.mjs`

**Step 1: Write failing preservation tests**

Assert:

- stored `aoi-locale` does not change product chrome from English;
- visible locale switches are absent;
- profile and administration save payloads preserve existing stored locale values even though the fields are hidden;
- `i18n.js`, Help Center bilingual fields, and survey bilingual schemas remain present;
- non-English survey content can still render with record-level language metadata when selected by the survey definition rather than by product chrome.

**Step 2: Verify RED**

```bash
node --test tests/accessibility-entry.test.mjs tests/profile.test.mjs tests/administration.test.mjs tests/helpcenter.test.mjs tests/survey-ui.test.mjs
```

Expected: existing switchers and locale initialization violate the active-English contract.

**Step 3: Implement the presentation policy**

- Remove locale buttons and selectors from active templates.
- Remove multilingual marketing claims that are no longer true.
- Make page controllers use English for system copy and formatting.
- Keep original stored locale in profile and staff payloads unless the user changes it through a future supported interface.
- Separate survey content language from product chrome language where they currently share one variable.
- Do not delete Chinese translation objects or validation/data fields.

**Step 4: Verify GREEN**

Run the focused command from Step 2.

**Step 5: Commit**

```bash
git commit -m "feat(i18n): use English product presentation"
```

## Task 4: Drive The Inactivity State Machine With Unit Tests

**Files:**

- Create: `tests/session-guard.test.mjs`
- Modify: `src/js/session-guard.js`
- Test: `tests/session-guard.test.mjs`

**Step 1: Write failing pure state tests**

Design an injectable controller API and test:

- active state starts with a 30-minute deadline;
- warning begins at 25 minutes;
- countdown derives from timestamps;
- meaningful activity updates the active deadline without writing on every mousemove;
- ordinary activity does not silently dismiss an open warning;
- explicit successful extension returns to active and resets the deadline;
- extension failure enters a retryable warning state;
- expiry signs out once;
- **Sign out now** signs out once;
- visibility restoration recalculates current state;
- cleanup removes listeners and scheduled work;
- multiple-tab storage updates reconcile the latest valid activity/session state.

Use injected clock, scheduler, storage, authentication, event target, and navigation fakes.

**Step 2: Verify RED**

```bash
node --test tests/session-guard.test.mjs
```

Expected: module does not expose the controller and warning states do not exist.

**Step 3: Implement the minimal controller**

Keep browser registration as a thin adapter around the tested controller. Prefer one scheduler driven by timestamps over multiple competing intervals.

**Step 4: Verify GREEN**

```bash
node --test tests/session-guard.test.mjs
```

Expected: deterministic tests pass with no real waiting.

## Task 5: Render And Integrate The Session Warning Dialog

**Files:**

- Modify: `src/js/session-guard.js`
- Modify: `src/js/dialog-manager.js`
- Modify: `src/js/app.js`
- Modify: `src/css/aoi.css`
- Create: `tests/e2e/accessibility-session.spec.js`
- Modify: `tests/ui-foundations.test.mjs`
- Test: `tests/session-guard.test.mjs`
- Test: `tests/e2e/accessibility-session.spec.js`

**Step 1: Add failing DOM and browser contracts**

Assert the warning:

- is a named modal dialog;
- displays remaining time;
- exposes **Stay signed in** and **Sign out now**;
- receives and contains focus;
- makes background content inert;
- supports Escape as an explicit extension only when available;
- restores focus after successful extension;
- keeps focus and draft context after extension failure;
- signs out and redirects on expiry;
- is absent from landing, login, preview-only, and public survey flows.

Use a test-only clock/control boundary, not 25 minutes of wall-clock waiting.

**Step 2: Verify RED**

```bash
node --test tests/session-guard.test.mjs tests/ui-foundations.test.mjs
npx playwright test tests/e2e/accessibility-session.spec.js --project=desktop
```

**Step 3: Implement dialog integration**

- Render one shared dialog from the session adapter.
- Mark the primary extension action for timeout-specific Escape handling.
- Let `dialog-manager.js` own focus trapping, inertness, and restoration.
- Do not add a second manual Tab trap.
- Announce countdown changes at controlled intervals rather than every second.

**Step 4: Verify GREEN**

Run the commands from Step 2.

**Step 5: Commit**

```bash
git commit -m "feat(auth): add accessible session extension"
```

## Task 6: Add Shared Announcement And Focus Helpers

**Files:**

- Create or modify: `tests/accessibility.test.mjs`
- Modify: `src/js/accessibility.js`
- Modify: `src/js/app.js`
- Modify: `src/css/aoi.css`
- Test: `tests/accessibility.test.mjs`

**Step 1: Write failing tests**

Test:

- polite and assertive channels;
- repeated-message deduplication;
- rapid-message throttling;
- visible message text remains authoritative;
- meaningful route changes focus a stable target;
- passive updates do not move focus;
- temporary `tabindex` cleanup preserves native focusability;
- repeated registration remains idempotent and cleanup removes listeners.

**Step 2: Verify RED**

```bash
node --test tests/accessibility.test.mjs
```

**Step 3: Implement minimal helpers**

Provide explicit calls from route controllers rather than a DOM mutation observer that guesses when focus should move.

**Step 4: Verify GREEN and commit**

```bash
node --test tests/accessibility.test.mjs
git commit -m "feat(a11y): add focus and status primitives"
```

## Task 7: Add And Adopt The Shared Tab Contract

**Files:**

- Modify: `src/js/accessibility.js`
- Modify: `tests/accessibility.test.mjs`
- Modify: `src/js/workspace-template.js`
- Modify: `src/js/crm-template.js`
- Modify: `src/js/outreach-template.js`
- Modify: `src/js/projects-template.js`
- Modify: `src/js/projects.js`
- Modify: `src/js/surveys/workspace-template.js`
- Modify: `src/js/administration-template.js`
- Modify: `src/js/helpcenter-template.js`
- Modify: `src/js/pmf-template.js`
- Modify: relevant route controllers
- Modify: relevant route unit/static tests
- Create: `tests/e2e/accessibility-tabs-focus.spec.js`

**Step 1: Write failing shared navigation tests**

Test arrows, Home, End, wrapping, disabled/hidden tabs, roving tabindex, orientation, selected state, panel IDs, and focus behavior.

**Step 2: Verify RED**

```bash
node --test tests/accessibility.test.mjs
```

**Step 3: Implement the shared tab helper**

Expose a small pure navigation function and a DOM event adapter. Do not force toolbars, filters, menus, or listboxes into the tab pattern.

**Step 4: Adopt one route family at a time**

Order:

1. Projects and blocker/risk subtabs.
2. Today, Research, Relationships, Outreach, Collect, and PMF layers.
3. Survey library, workspace, and analysis.
4. Administration and person details.
5. Help Center categories only if they represent mutually exclusive panels; otherwise change them to a named filtering group.

For each family:

- add stable tab/panel IDs;
- add `aria-controls` and `aria-labelledby`;
- use roving `tabindex`;
- route keyboard events through the shared helper;
- run its focused tests before proceeding.

**Step 5: Browser verification**

```bash
npx playwright test tests/e2e/accessibility-tabs-focus.spec.js --project=desktop
```

**Step 6: Regression verification**

```bash
node --test tests/projects-ui.test.mjs tests/projects-domain.test.mjs tests/administration-ui.test.mjs tests/helpcenter.test.mjs tests/survey-ui.test.mjs tests/crm-outreach.test.mjs tests/participant-tracker.test.mjs
npx playwright test tests/e2e/projects-preview.spec.js tests/e2e/audit-repairs.spec.js
```

**Step 7: Commit**

```bash
git commit -m "feat(a11y): standardize tab navigation"
```

## Task 8: Harden Shared CSS Foundations

**Files:**

- Modify: `tests/ui-foundations.test.mjs`
- Modify: `src/css/aoi.css`
- Create: `tests/e2e/accessibility-visual-modes.spec.js`
- Test: `tests/ui-foundations.test.mjs`

**Step 1: Add failing CSS and browser contracts**

Cover:

- skip-link hidden and focused states;
- visible focus in light, dark, and forced colors;
- 44px isolated targets and documented inline exceptions;
- no `outline: 0` without an equivalent `:focus-visible` or `:focus-within` treatment;
- reduced-motion removal of nonessential transitions and smooth scroll;
- forced-color control boundaries, selection, links, errors, and icons;
- readable shared metadata floor;
- named local scrolling for wide data rather than page overflow.

**Step 2: Verify RED**

```bash
node --test tests/ui-foundations.test.mjs
npx playwright test tests/e2e/accessibility-visual-modes.spec.js --project=desktop
```

**Step 3: Implement minimal shared styles**

Use existing semantic tokens and component vocabulary. Do not globally magnify the interface or add user-facing overlay controls.

**Step 4: Verify GREEN and commit**

```bash
node --test tests/ui-foundations.test.mjs
npx playwright test tests/e2e/accessibility-visual-modes.spec.js --project=desktop
git commit -m "fix(a11y): harden shared visual foundations"
```

## Task 9: Repair Landing And Login

**Files:**

- Modify: `index.html`
- Modify: `login.html`
- Modify: `src/js/landing.js`
- Modify: `src/js/login.js`
- Modify: `src/css/aoi.css`
- Modify: `tests/login-password-reset.test.mjs`
- Create: `tests/e2e/accessibility-entry.spec.js`
- Create or modify: `tests/e2e/accessibility-routes.spec.js`

**Step 1: Write failing browser tests**

Cover:

- skip-link destination and focus;
- keyboard access to navigation and calls to action;
- landing mobile-menu names, state, target size, and focus containment;
- login labels, instructions, errors, callback, recovery, temporary-password, loading, and failure states;
- English-only copy;
- 320px, 200% zoom, text spacing, dark mode, reduced motion, and page overflow.

**Step 2: Verify RED**

```bash
npx playwright test tests/e2e/accessibility-entry.spec.js tests/e2e/accessibility-routes.spec.js --project=desktop
npx playwright test tests/e2e/accessibility-routes.spec.js --project=mobile-320
```

**Step 3: Repair the routes**

Associate errors with fields and summaries, resize undersized controls, preserve clear heading order, and prevent sticky/fixed UI from covering focus.

**Step 4: Verify GREEN and commit**

```bash
node --test tests/login-password-reset.test.mjs tests/accessibility-entry.test.mjs
npx playwright test tests/e2e/accessibility-entry.spec.js tests/e2e/accessibility-routes.spec.js --project=desktop --project=mobile-320
git commit -m "fix(a11y): repair landing and login routes"
```

## Task 10: Repair Workspace And Intern Workspace

**Files:**

- Modify: `src/js/workspace.js`
- Modify: `src/js/workspace-template.js`
- Modify: workspace domain templates as violations require
- Modify: `src/css/aoi.css`
- Modify: workspace and collaboration tests
- Modify: accessibility E2E specs

**Step 1: Add failing route tests**

Cover role-specific preview routes for:

- skip and main behavior;
- primary and nested tab keyboard behavior;
- command palette, account menu, inbox, project detail, task drawer, collaboration forms, CRM, research, survey workspace, EOD, and chat focus behavior;
- meaningful route heading focus and trigger restoration;
- status/error announcements;
- 320px, 200% zoom, text spacing, dark, reduced motion, forced colors, and no page overflow;
- closed sidebar/drawers absent from focus order.

**Step 2: Verify RED**

```bash
npx playwright test tests/e2e/accessibility-routes.spec.js tests/e2e/accessibility-tabs-focus.spec.js --project=desktop --project=mobile-320
```

**Step 3: Repair incrementally**

Keep project collaboration source behavior unchanged. Reuse shared dialog, tab, status, and focus contracts rather than adding more route-specific global handlers.

**Step 4: Verify GREEN**

```bash
node --test tests/workspace-consolidation.test.mjs tests/workspace-repair.test.mjs tests/projects-ui.test.mjs tests/inbox-ui.test.mjs tests/collaboration-domain.test.mjs tests/survey-ui.test.mjs
npx playwright test tests/e2e/accessibility-routes.spec.js tests/e2e/accessibility-tabs-focus.spec.js tests/e2e/projects-preview.spec.js --project=desktop --project=mobile-320
```

**Step 5: Commit**

```bash
git commit -m "fix(a11y): repair role workspaces"
```

## Task 11: Repair Administration And Help Center

**Files:**

- Modify: `src/js/administration.js`
- Modify: `src/js/administration-template.js`
- Modify: `src/js/helpcenter.js`
- Modify: `src/js/helpcenter-template.js`
- Modify: `src/css/aoi.css`
- Modify: `src/css/helpcenter.css`
- Modify: `tests/administration-ui.test.mjs`
- Modify: `tests/administration.test.mjs`
- Modify: `tests/helpcenter.test.mjs`
- Modify: accessibility E2E specs

**Step 1: Add failing tests**

Administration coverage:

- section and person-detail navigation;
- directory local scrolling and named regions;
- forms, validation, destructive confirmations, archive/handoff, and status announcements;
- focus restoration and timeout integration.

Help Center coverage:

- search, category/filter semantics, article headings and table of contents;
- authoring and publishing dialogs/forms;
- runtime `structuredClone` regression;
- readable metadata floor and target sizing;
- content reflow and table handling.

**Step 2: Verify RED**

```bash
node --test tests/administration-ui.test.mjs tests/administration.test.mjs tests/helpcenter.test.mjs
npx playwright test tests/e2e/accessibility-routes.spec.js --project=desktop --project=mobile-320
```

**Step 3: Repair and rebalance**

Replace 7 to 9 pixel operational metadata with readable typography and adjust spacing/layout rather than shrinking other content. Preserve bilingual Help Center data fields despite English product chrome.

**Step 4: Verify GREEN and commit**

Run the commands from Step 2, then:

```bash
git commit -m "fix(a11y): repair admin and help routes"
```

## Task 12: Repair Recruitment Tracker And Survey Runner

**Files:**

- Modify: `src/js/participant-tracker.js`
- Modify: `src/js/participant-tracker-template.js`
- Modify: `src/css/participant-tracker.css`
- Modify: `src/js/surveys/runner.js`
- Modify: `src/js/surveys/runner-template.js`
- Modify: `src/css/surveys.css`
- Modify: `tests/participant-tracker.test.mjs`
- Modify: `tests/survey-ui.test.mjs`
- Modify: `tests/survey-domain.test.mjs`
- Modify: accessibility E2E specs

**Step 1: Add failing route tests**

Recruitment:

- register controls, stage information, editor drawer focus, embedded and standalone variants;
- timeout only on authenticated standalone use;
- named local overflow and 44px targets.

Survey runner:

- consent, every rendered question family, required/error state, matrix/ranking keyboard paths, upload, review, progress, and submission;
- non-English authored survey content language metadata;
- no authenticated timeout dialog;
- 320px, 200% zoom, text spacing, reduced motion, forced colors, and local scrolling.

Do not represent unresolved survey embed, assignment, hidden-field, coding, cross-tab, or QR features as repaired.

**Step 2: Verify RED**

```bash
node --test tests/participant-tracker.test.mjs tests/survey-ui.test.mjs tests/survey-domain.test.mjs
npx playwright test tests/e2e/accessibility-routes.spec.js --project=desktop --project=mobile-320
```

**Step 3: Repair routes and verify GREEN**

Run the commands from Step 2 after implementation.

**Step 4: Commit**

```bash
git commit -m "fix(a11y): repair recruitment and surveys"
```

## Task 13: Add Evidence Registry And Release Documentation

**Files:**

- Modify: `docs/quality/audit-matrix.md`
- Create: `docs/quality/accessibility-evidence.md`
- Modify: `README.md`
- Modify: `.github/workflows/pages.yml` if required to enforce existing lint/test expectations
- Test: documentation/static contract tests

**Step 1: Add failing documentation contracts**

Require one evidence row per entry route with:

- applicable criteria;
- automated status;
- manual keyboard status;
- screen-reader/browser status;
- zoom/text-spacing/dark/forced-color status;
- residual gaps;
- repository and production status;
- verifier and date.

Use the status vocabulary: `targeted`, `automated green`, `manual green`, `blocked`, and `verified`.

**Step 2: Record evidence honestly**

Mark unavailable NVDA, VoiceOver, forced-color, or production combinations as blocked. Do not infer manual evidence from Playwright.

**Step 3: Update release language**

Use **AAA-targeted** unless every applicable route row is verified. Preserve known security rotation, Supabase deployment, and live-auth blockers.

**Step 4: Verify and commit**

```bash
node --test tests/*.test.mjs
git diff --check
git commit -m "docs(a11y): record route verification evidence"
```

## Task 14: Full Verification And Review

**Step 1: Run focused regressions**

```bash
node --test tests/accessibility-entry.test.mjs tests/accessibility.test.mjs tests/session-guard.test.mjs tests/ui-foundations.test.mjs
node --test tests/projects-ui.test.mjs tests/inbox-ui.test.mjs tests/collaboration-domain.test.mjs tests/administration-ui.test.mjs tests/helpcenter.test.mjs tests/participant-tracker.test.mjs tests/survey-ui.test.mjs
```

**Step 2: Run full automated gate**

```bash
npm run lint
npm test
npm run test:e2e
git diff --check
```

Expected:

- lint passes;
- all Node and disposable PostgreSQL tests pass;
- all required accessibility projects pass;
- credential-gated live tests are explicitly inventoried;
- no new required test is skipped;
- no runtime console errors, page-level overflow, or accessibility contract failures remain.

**Step 3: Inspect the final diff**

Run `git status --short`, `git diff --stat`, and focused diffs for every shared file. Confirm unrelated untracked files remain excluded.

**Step 4: Request code review**

Review for behavioral regressions, incomplete route adoption, false AAA claims, localization-data loss, duplicate focus traps, timeout race conditions, and missing tests.

**Step 5: Resolve findings test-first**

Every discovered defect receives a failing regression test before the fix.

## Task 15: Release And Production Verification

Only after Task 14 is green:

1. Push the complete commit series to `origin/main` when requested.
2. Monitor the GitHub Pages workflow through completion.
3. Verify all eight deployed entries load the intended hashed assets and stable main structure.
4. Run public deployed smoke tests for landing, login, preview routes, and survey shell.
5. Run authenticated owner, administrator, and intern checks only when deployment credentials are available.
6. Verify the linked Supabase migration history and apply the pending collaboration migration only after a restorable checkpoint and authentication are available.
7. Update production status separately from repository status.

Do not mark production verified if frontend/backend revisions differ or if required live roles remain untested.
