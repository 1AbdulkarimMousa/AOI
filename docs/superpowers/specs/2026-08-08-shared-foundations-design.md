# Phase 2 Shared Foundations

## Goal

Make the shared application shell predictable under deep links, transient API failures,
rapid navigation, and narrow or keyboard-only use without rewriting the page-specific
workspaces.

## Scope

- Preserve the existing `core.js` page URL and role-route helpers as the single redirect
  contract and add regression coverage for them.
- Add explicit request sequencing to dashboard refreshes so an older response cannot replace
  newer state; preserve the last usable dashboard on transient refresh failures.
- Keep authentication sessions intact for transport/server errors, while still signing out
  for confirmed invalid membership or explicit logout.
- Standardize shared dialog behavior: escape handling, focus return, focus trapping, and
  `inert` background content for shell-level mobile navigation and drawers.
- Add shared responsive and reduced-motion contracts in `aoi.css` without changing the
  established warm visual language.
- Add focused tests for route normalization, refresh sequencing contracts, and shared
  accessibility tokens.

## Non-goals

- No database redesign or multi-project selector in this phase.
- No removal of bilingual content.
- No page-specific workflow changes unless required to consume a shared helper.
- No changes to `raw_data/` or deployment credentials.

## Verification

Run `npm run lint`, `npm test`, `npm run build`, and `git diff --check`. The phase is complete
only when all pass and the worktree contains no staged or committed `raw_data/` changes.
