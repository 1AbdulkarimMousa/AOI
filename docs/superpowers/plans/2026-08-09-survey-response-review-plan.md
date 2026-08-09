# Survey Response Review Implementation Plan

## Context

Implement the approved design in `docs/superpowers/specs/2026-08-09-survey-response-review-design.md`.

The current workspace already exposes `reviewSurveySubmission()` in `src/js/api.js` and individual review transitions in `src/js/surveys/workspace.js`. The implementation should reuse those paths and add no database migration.

## Work Items

### 1. Add review queue state and derived helpers

Files:

- `src/js/surveys/workspace.js`

Changes:

- Add `surveyReviewQuery`, `surveyReviewStatus`, `surveyReviewVersion`, `surveySelectedResponseIds`, and `surveyBulkReviewing` to the Alpine state.
- Add `filteredSurveyResponses()` that filters `surveyWorkspace.submissions` by query, status, and immutable version number.
- Add `surveyReviewStatusCounts()` based on the complete submission list, not the filtered list.
- Add selection helpers for toggling one response, selecting visible rows, clearing selection, and reconciling IDs after workspace/filter changes.
- Reconcile or clear selection in `applySurveyWorkspace()`, `openSurveyAsset()`, `closeSurveyAsset()`, and after individual review refreshes.
- Keep queue search limited to response ID, locale, status, and version metadata.

Verification:

- Ensure filtered results preserve response object references needed by the detail pane.
- Ensure selections contain only response IDs and cannot expose identifier payloads.

### 2. Implement guarded bulk moderation

Files:

- `src/js/surveys/workspace.js`

Changes:

- Add `bulkReviewSurveyResponses(action)` for `approve` and `exclude`.
- Filter selected IDs against current responses and `canReviewSurveyResponse()` before invoking the server helper.
- Require administrator/reviewer authorization and an active selection.
- Confirm the action with the number of responses using the existing confirmation pattern.
- Invoke `reviewSurveySubmission(response.id, action, notes)` sequentially for each eligible response, preserving one server transition and audit record per response.
- Continue after individual failures and collect success/error results.
- Reload the workspace after the operation, reconcile detail selection, and publish a success, partial-success, or failure notice.
- Disable duplicate bulk operations while `surveyBulkReviewing` is true.

Verification:

- Preview mode updates local statuses without RPC calls.
- Invalid status transitions are skipped or reported rather than sent blindly.
- A single failed response does not prevent later selected responses from running.

### 3. Extend the response-review template

Files:

- `src/js/surveys/workspace-template.js`

Changes:

- Add a queue toolbar with search, status filter, version filter, status counts, and selection controls.
- Render rows from `filteredSurveyResponses()`.
- Add checkbox controls with click propagation stopped so selecting a row does not change the detail response.
- Add selected-count, approve, exclude, and clear controls.
- Preserve the existing detail panel, notes field, identifier panel, individual actions, and PMF promotion control.
- Add an explicit no-match empty state.
- Keep accessible labels and `aria-pressed`/`aria-selected` state for queue controls.

Verification:

- Bulk controls are visibly disabled during the operation or when no rows are selected.
- Queue rows still expose status, version, locale, timestamp, and score without direct identifiers.

### 4. Add focused regression coverage

Files:

- `tests/survey-ui.test.mjs`
- Add a focused pure-helper test file only if controller helpers cannot be tested through the existing static-contract style.

Tests:

- Assert the controller exposes queue filters, selection reconciliation, and bulk review orchestration.
- Assert the template exposes search/status/version controls, row checkboxes, visible selection, bulk approve/exclude actions, and an empty state.
- Assert the existing review RPC remains the path used for moderation.
- Assert immutable-version response lookup and direct-identifier isolation remain present.

### 5. Verify and review

Commands:

```bash
npm test -- --runInBand
git diff --check
```

If the project build is available without external credentials, also run the repository build command and inspect the generated survey workspace bundle. Review the final diff for unintended changes and leave the pre-existing untracked `raw_data/` directory untouched.

## Sequencing

1. Add state and pure derived/selection helpers.
2. Add bulk orchestration and refresh/error handling.
3. Update the review template.
4. Add regression tests.
5. Run tests, diff checks, and final review.

## Risks and Mitigations

- **Partial bulk failure:** continue per response and report counts; never claim full success.
- **Stale selected IDs:** reconcile against refreshed submissions and filtered IDs.
- **Unauthorized transitions:** retain `canReviewSurveyResponse()` checks and server RPC authorization.
- **Identifier leakage:** keep queue summaries and filtering fields metadata-only.
- **Immutable-version mismatch:** continue using each selected response's existing version payload for detail review.
