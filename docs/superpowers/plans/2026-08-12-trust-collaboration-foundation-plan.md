# AOI Trust and Collaboration Foundation Implementation Plan

Date: 2026-08-12
Design: `docs/superpowers/specs/2026-08-12-trust-collaboration-foundation-design.md`

## Delivery Rules

- Preserve every existing collected record, stable ID, scope, author, timestamp, attachment, and historical state.
- Use forward-only additive migrations after the latest effective migration.
- Write and run a failing behavior test before each production change.
- Treat source workflows as authoritative; inbox state never impersonates workflow completion.
- Require strict WCAG 2.2 AAA for touched authenticated UI.
- Do not deploy migrations until linked migration history, a dry run, and a verified backup are available.

## Slice 1: Trust Baseline

1. Extend the disposable Postgres test to prove sensitive historical survey values survive migrations while remaining unreadable to unauthorized users.
2. Remove destructive historical identifier redaction from the pending hardening migration and retain future inactive-identifier access controls.
3. Add an executable test showing invitation acceptance cannot activate a workspace before password establishment.
4. Add a final forward migration that replaces the invitation acceptance function with the required lifecycle behavior.
5. Verify fresh migration execution, auth lifecycle rules, survey first submission/replay, consent-safe PMF/Gates, and row preservation.

## Slice 2: Authoritative Task And Research Workflows

1. Add executable task lifecycle tests for submit, revision request, resubmit, approval, completion, role denial, required review guidance, and stale writes.
2. Add task review metadata/history, a detailed task read RPC, concurrency-safe assignee checkpoints, and administrator review RPCs.
3. Expose exact acceptance criteria and expected hours in the effective dashboard/task detail payload.
4. Add API/controller/template actions for task review and revision guidance.
5. Add executable research tests proving draft edits and revision resubmissions retain the same record ID, reject stale writes, and enforce assignment and server validation.
6. Add one update/resubmit RPC for the six existing research record types plus append-only review history.
7. Hydrate persisted records into existing collection forms and expose edit/resubmit actions.

## Slice 3: Durable Collaboration Foundation

1. Add executable schema and authorization tests for inbox items, comments, revisions, mentions, follows, handoffs, and generic activity.
2. Add additive collaboration tables with RLS, explicit grants, indexes, immutable scope/source fields, and deterministic dedupe keys.
3. Add narrow inbox snapshot/read/snooze/resolve and collaboration RPCs.
4. Derive inbox items transactionally from task/research/survey/EOD conditions and backfill only unresolved qualifying work.
5. Prove rerunning derivation does not duplicate records and cross-organization access is denied.

## Slice 4: Role-Adaptive Today

1. Add pure route/filter/order tests for inbox buckets and stable item/source URLs.
2. Add small `inbox.js` and `inbox-template.js` modules rather than expanding the monolithic workspace template.
3. Load inbox independently from the dashboard and expose owner/admin/intern priority explanations.
4. Replace fake bell notifications with the durable unread projection.
5. Add desktop list-detail and mobile list-to-detail behavior with browser history restoration.
6. Add comments, mentions, follows, and reasoned handoffs to the selected item's source context.

## Slice 5: Strict AAA And Release Gauntlet

1. Add failing token tests for 7:1 normal-text contrast in touched surfaces and correct the shared semantic pairs used there.
2. Add browser tests for 320px reflow, 200 percent zoom, text spacing, reduced motion, forced colors, keyboard operation, focus restoration, and status announcements.
3. Ensure 44px targets, explicit unread text/counts, bilingual labels, correct language metadata, and non-color state communication.
4. Replace identifiable public preview fixtures with synthetic anonymous data without touching live data.
5. Run lint, all tests, production build, complete Playwright matrix, diff checks, secret scan, and a focused code review.

## Commit And Deployment

1. Inspect status, diff, and recent history; stage only intended source, tests, migrations, design, plan, and quality documentation.
2. Commit with repository-style focused messages.
3. Push `main` to `origin`.
4. Confirm GitHub Pages deployment passes.
5. For Supabase, inspect linked migration history and dry-run the push. Require a verified backup/checkpoint before applying migrations.
6. Deploy changed Edge Functions with their existing JWT-verification mode only when credentials and linked project access are available.
7. Smoke test deployed login/recovery/invitation, owner/admin/intern access, survey submission/replay, task review, research revision, inbox, consent withdrawal, and Gate creation.
