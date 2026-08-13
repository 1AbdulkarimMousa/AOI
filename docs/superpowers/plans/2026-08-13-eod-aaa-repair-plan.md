# EOD AAA Repair Implementation Plan

## 1. Database Contracts

- Add executable regression coverage for first-brief scope and organization-wide reports.
- Add a forward-only migration that returns `projectId`, repairs the audit join, restores organization-wide filtering, and supports the audited legacy-evidence completion exception.
- Verify grants, role scope, current/completed projects, and first save on a disposable PostgreSQL database.

## 2. Domain And Recovery

- Change EOD validation to return field-addressable errors while preserving the existing message-list API.
- Add scope-safe local draft key, serialization, comparison, and legacy-record eligibility helpers.
- Cover each helper with a failing unit test before implementation.

## 3. Controller Lifecycle

- Add explicit snapshot loading/ready/failed state and prevent live fallback data from rendering as EOD content.
- Add debounced local recovery, recovery actions, navigation/unload warnings, and successful-save cleanup.
- Invalidate and refresh EOD snapshot/reports during project changes.
- Add field-error focus and summary behavior while preserving stale-write recovery.

## 4. Semantic Responsive UI

- Add labeled fields, inline errors, a focusable error summary, busy states, accessible filters, visible actions, and exact timestamps.
- Replace the archive pseudo-table with a semantic table that becomes labeled stacked records on narrow screens.
- Add an explicit imported-evidence warning and English language boundary.
- Move EOD-specific typography, contrast, target sizing, reflow, dark theme, reduced motion, and forced-colors repair into a focused stylesheet.

## 5. Verification And Delivery

- Add EOD Playwright coverage for mobile reflow, text spacing, theme, validation focus, filters, drawer focus, and recovery behavior.
- Run build, lint, unit tests, database execution tests, and E2E tests.
- Review the final diff for unrelated work, stage only intended EOD changes, commit, push, deploy through the repository's configured path, and verify the deployed page.
