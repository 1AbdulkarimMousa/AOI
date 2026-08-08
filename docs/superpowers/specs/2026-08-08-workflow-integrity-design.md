# Phase 4 Workflow Integrity

## Goal

Keep operational workflow screens aligned with persisted ownership, consent, evidence,
project scope, and export/import semantics.

## Scope

- Preserve respondent IDs when Collect follow-on forms are opened.
- Exclude withdrawn, declined, expired, or otherwise non-consented respondent-bound evidence
  from PMF analysis while retaining unlinked aggregate observations.
- Scope CRM snapshots to the current user's assigned contacts for non-admin users.
- Make task checkpoint transitions role-aware and require meaningful checkpoint notes for
  completion or resubmission.
- Make formula-safe CSV export/import lossless for the exporter-owned leading guard.
- Scope EOD reports to the active project and remove or disable no-op/role-invalid actions.
- Keep existing optimistic refresh and audit patterns; no schema-wide rewrite.

## Non-goals

- No new PMF scoring model or gamification redesign.
- No deletion of historical records or `raw_data/` changes.
- No changes to the public survey runner.

## Verification

Add focused regression tests for each workflow boundary, then run `npm run lint`, `npm test`,
`npm run build`, and `git diff --check` before committing.
