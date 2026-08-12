# Project Operating Core Implementation Plan

## Goal

Ship the approved project operating core as one preservation-safe release: canonical project context, project membership, milestones, blockers, risks, decisions, immutable approval snapshots, contextual collaboration, role-adaptive inbox items, and responsive project UX.

## Phase 1: Backend Contract Tests

- Add a disposable-PostgreSQL execution test with representative multi-project fixtures.
- Assert additive schema, RLS, grants, project isolation, and preservation.
- Assert context selection and active-project persistence.
- Assert milestone, blocker, risk, and decision lifecycle behavior.
- Assert stale-write handling, risk score calculation, required reasons, and immutable decision snapshots.
- Assert project source types work with comments, follows, handoffs, deep links, and inbox derivation.

## Phase 2: Project Core Migration

- Extend projects without changing existing IDs or scope.
- Add project preferences and project memberships with deterministic safe backfill.
- Add typed project milestone, blocker, risk, decision, evidence-link, snapshot, and history tables.
- Add project access helpers and RLS.
- Add canonical context, select-project, snapshot, detail, save, and transition RPCs.
- Extend contextual collaboration source contracts and inbox derivation.
- Revoke direct authenticated writes; grant narrow RPC execution.

## Phase 3: Frontend Domain Tests

- Add route resolution tests for Projects and record deep links.
- Add project domain tests for drafts, labels, risk score presentation, and role-valid actions.
- Add API and template contract tests before implementation.

## Phase 4: Projects Workspace

- Add Projects to primary navigation and command search.
- Make the project switcher show and change authorized context.
- Add Overview, Milestones, Blockers & Risks, and Decisions tabs.
- Add list/detail workflows with explicit empty, loading, error, stale, and saving states.
- Add administrator create/edit/review actions and member execution actions.
- Preserve stable URLs, browser navigation, and focus restoration.

## Phase 5: Today and Collaboration

- Surface project-derived inbox priorities in Today.
- Open project source links in the canonical Projects workspace.
- Reuse comments, mentions, follows, and handoffs without source-state mutation.
- Verify source lifecycle changes resolve derived inbox records.

## Phase 6: Release

- Run lint, all Node/PostgreSQL tests, Playwright, and diff checks.
- Review the full diff and preserve unrelated files.
- Commit and push.
- Inspect linked migration history and create a verified pre-deploy backup.
- Dry-run and apply only the intended migration.
- Verify remote history and deploy frontend through Pages CI.
- Smoke-test public and authenticated production paths where credentials are valid.
