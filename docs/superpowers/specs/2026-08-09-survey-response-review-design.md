# Survey Response Review Design

## Goal

Make the survey response-review queue usable at operational scale by adding triage filters and guarded bulk moderation without weakening the existing per-response authorization, immutable-version, or audit behavior.

## Scope

The change is limited to the authenticated survey workspace. It covers queue search and filters, visible-row selection, bulk approval, bulk exclusion, refresh/reconciliation, and regression tests. Individual response review, review notes, restricted identifier display, immutable definition lookup, and PMF promotion remain supported as they are today.

No database migration or new RPC is required.

## Design

### Queue State

The workspace controller will own transient review state:

- `surveyReviewQuery`: case-insensitive queue search text.
- `surveyReviewStatus`: `all` or one response status.
- `surveyReviewVersion`: `all` or one immutable version number.
- `surveySelectedResponseIds`: IDs selected for bulk actions.

Derived helpers will return filtered responses and status counts. Queue search may match the response ID, locale, status, or version label. Direct identifiers will never be included in queue search or row summaries.

Selection is reconciled against the filtered response IDs whenever filters or workspace data change. Changing the survey or reloading the workspace clears selection. “Select visible” only selects currently filtered responses; “clear selection” removes all selected IDs.

### Queue UI

The response-review sidebar will gain:

- Search input.
- Status filter.
- Immutable version filter.
- Status count summary.
- Select-visible and clear-selection controls.
- Selection count and bulk-action controls.

Each response row will expose a checkbox and retain its current status, version, locale, timestamp, and score summary. Checkbox interaction will not open or replace the selected response.

### Bulk Moderation

Bulk actions will support `approve` and `exclude`, matching the existing individual actions. Actions are administrator/reviewer guarded by the existing workspace access rules.

Before execution, the controller will require a non-empty selection and ask for confirmation containing the action and number of responses. It will invoke the existing `reviewSurveySubmission(responseId, action, note)` helper once per selected response. This preserves the server-side transition checks and one audit event per response.

The operation will continue through all selected IDs. The workspace will reload afterward so successful transitions and stale rows reconcile with server state. The notice will report the number succeeded and failed; failures will include the server-readable error when available. A partial failure will not be represented as complete success.

Bulk operations will not promote PMF answers, modify notes, expose identifiers, or bypass immutable response definitions.

### Individual Review Compatibility

Selecting a row still loads its full response in the detail pane. Existing start-review, approve, exclude, notes, restricted-identifier, and PMF-promotion controls remain unchanged. After an individual transition, the selected ID is retained only if the refreshed response remains in the current filtered queue; otherwise the detail selection is cleared safely.

## Error Handling

- Invalid or unauthorized transitions remain server errors and are reported per response.
- A failed refresh must not discard the current response object or claim that the bulk operation completed successfully.
- Empty queues and no-match filters render an explicit empty state.
- Bulk controls are disabled while an operation is in progress to prevent duplicate submissions.
- Selection state is cleared after a successful refresh and reconciled after a partial failure.

## Testing

Add focused tests that verify:

- Search, status, and immutable-version filters produce the expected queue.
- Status counts are calculated from the full response set and remain accurate when filters are applied.
- Select-visible and clear-selection operate only on response IDs.
- Bulk approval and exclusion call the existing review helper for each selected response.
- One failed response does not prevent other selected responses from being attempted.
- Partial results report success and failure counts and trigger a workspace refresh.
- Selection and detail state reconcile after filters, individual transitions, and reloads.
- Existing identifier isolation and immutable-version review behavior remain intact.

## Non-Goals

- Server-side pagination.
- A new bulk SQL RPC.
- Changes to response transition rules or reviewer permissions.
- Bulk PMF promotion.
- Editing submitted answers.
