# Phase 3 Security and Data Integrity

## Goal

Close remaining server-side authorization, validation, replay, and Auth/database
reconciliation gaps without changing the public survey contract or deleting historical
research records.

## Scope

- Restrict survey analysis to organization administrators, survey owners, or assignees.
- Force email and phone questions into restricted identifier storage.
- Bring branch-target, calculation-reference, and dependency-cycle checks into the effective
  database survey validator.
- Require an active, valid survey link and matching invitation during idempotent replay.
- Return explicit reconciliation-required responses when Auth changes succeed but database
  state or audit persistence fails, with a service-role retry action.
- Preserve actual Auth ban state during import compensation and refuse archive suspension when
  cross-organization membership counts cannot be read.
- Attempt every provisioning cleanup step, preserve PMF observation provenance on respondent or
  session deletion, and reject malformed legacy source URLs before validating constraints.

## Non-goals

- No shared temporary password fallback.
- No changes to `raw_data/`, credentials, or the public survey response schema.
- No destructive deletion of research evidence; invalid legacy URLs are nulled with audit-safe
  database updates, while provenance foreign keys become restrictive.

## Verification

Add migration/source-contract tests for each boundary, then run `npm run lint`, `npm test`,
`npm run build`, and `git diff --check` before committing the phase.
