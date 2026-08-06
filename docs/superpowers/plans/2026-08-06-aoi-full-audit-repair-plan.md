# AOI Full Audit Repair Plan

## Phase 1: Test Foundation

Add behavioral tests for routing, overlays, mobile overflow, no-op controls, async races, validation parity, version-pinned surveys, secure onboarding, and live fixture cleanup. Replace broad container clicks and navigation waits with roles, labels, stable test IDs where necessary, and state assertions.

## Phase 2: Shared Foundations

Repair route state, explicit project context, transient-auth handling, request sequencing, overlay behavior, mobile navigation inertness, responsive tracks, semantic color/focus tokens, touch targets, and reduced-motion scrolling.

## Phase 3: Security And Data Integrity

Remove shared temporary passwords; enforce respondent/session, consent, observation, URL, survey version, distribution-origin, idempotency, and partial-operation reconciliation contracts in migrations and Edge Functions.

## Phase 4: Workspace Workflows

Repair EOD state preservation, local dates, PMF layer routing, evidence-backed task checkpoints, role-correct actions, mutation refreshes, Collect form routing and relationships, text observation ordering, EOD races, and lossless imports/exports.

## Phase 5: Survey Suite

Implement functional library and analysis tabs, complete advanced authoring, dirty-state protection, respondent preview, persistent distribution management, version-aware review and exports, type-aware analysis, runner settings, resume recovery, upload normalization, and mobile containment.

## Phase 6: Administration And Help Center

Repair lifecycle filters, one-time credentials, person-detail races, archive reconciliation, article history/deep links, global search shortcuts, block rendering, publication feedback, and modal keyboard behavior.

## Phase 7: UI/UX And Performance

Rebalance hierarchy toward evidence and next actions, de-emphasize gamification, remove false affordances, improve mobile information structure, finish bilingual/dark coverage, optimize assets, and reduce eager hidden DOM and expensive effects.

## Phase 8: Deploy And Verify

Run all local checks, apply linked Supabase migrations, deploy `admin-create-user` and `survey-public`, seed approved Wen survey data, commit intended files, push `main`, wait for GitHub Pages, and repeat desktop/mobile plus authenticated live acceptance. Clean up all disposable records and uploads.

## Release Criteria

- No unresolved P0 or P1 findings.
- Every visible enabled control has verified behavior.
- No page-level horizontal overflow at 320px.
- WCAG 2.2 AA contrast and keyboard operation.
- No uncaught console errors or unexplained first-party request failures.
- All advertised survey features pass authoring-to-analysis tests.
- Authenticated disposable workflows pass and clean up successfully.
