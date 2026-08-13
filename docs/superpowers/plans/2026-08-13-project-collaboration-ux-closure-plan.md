# Project Collaboration UX Closure Implementation Plan

## Goal

Ship the approved project-first collaboration experience without changing authoritative source lifecycles: named collaborators, contextual comments and mentions, follow/unfollow, auditable comment revisions, reasoned handoffs, compact Today parity, and touched-flow AAA verification.

## Phase 1: Failing Contracts

- Add collaboration domain tests for normalization, recipient eligibility, follow state, source-keyed nonces, and compact/full projections.
- Extend project and inbox UI contracts for shared methods, named selectors, revision controls, and removal of raw UUID fields.
- Extend PostgreSQL execution coverage for projections, authorization, idempotency, revisions, follow/unfollow, and lifecycle isolation.

## Phase 2: Backend Projection

- Add one forward-only migration with no new tables.
- Build a private, source-authorized collaboration projection over existing comments, revisions, mentions, followers, and handoffs.
- Extend project record detail with full collaboration state.
- add a recipient-authorized selected-inbox-item detail RPC with compact collaboration state.
- Extend administrator project snapshots with eligible organization members.
- Require a meaningful responsibility when activating a project member.

## Phase 3: Shared Frontend Model

- Add one collaboration module for normalization, source aliases, drafts, mention selection, follow state, nonces, revisions, errors, and reconciliation.
- Add API wrappers for inbox detail and comment revision while preserving useful Supabase error metadata.
- Integrate project and Today controllers through the same methods.
- Preserve drafts and nonces until authoritative success; refresh source detail and Today after mutations.

## Phase 4: Product Experience

- Add the full collaboration thread and controls to milestone, blocker, risk, and decision details before lifecycle actions.
- Render compact recent collaboration in Today.
- Replace handoff and project-member UUID inputs with named authorized-member controls.
- Use an accessible native checkbox group for mentions and inline editing for comment revisions.
- Keep collaboration notices separate from source lifecycle notices.

## Phase 5: Privacy And AAA Closure

- Replace touched preview names, organizations, and scenarios with clearly synthetic fixtures.
- Share preview collaboration state between Today and Projects without calling live services.
- Add responsive, focus, forced-color, dark-theme, reduced-motion, text-spacing, and live-status styling.
- Extend Playwright coverage for keyboard operation, 320px reflow, follow/unfollow, named handoff, and revision cancellation.

## Phase 6: Documentation And Release

- Update README and the audit matrix with repaired versus operationally unverified findings.
- Run lint, build/Node/PostgreSQL tests, Playwright, and diff checks.
- Review all intended changes and preserve unrelated worktree files.
- Commit and push the implementation.
- Verify GitHub Actions and Pages deployment.
- Inspect linked Supabase state and apply the migration only if credentials, migration history, and a restorable backup are verifiably available.
