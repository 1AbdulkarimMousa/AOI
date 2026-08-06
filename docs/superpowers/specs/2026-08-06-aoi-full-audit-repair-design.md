# AOI Full Audit Repair Design

## Goal

Repair AOI end to end while preserving the Vite multi-page, Alpine, and Supabase architecture. Every visible enabled control must perform a verified action, every persisted workflow must preserve data integrity, and the interface must meet WCAG 2.2 AA and remain usable from 320px upward.

## Architecture

- Resolve organization and project context once during authenticated bootstrap and pass it explicitly to reads and mutations.
- Centralize route parsing, aliases, deep links, browser history, and back/forward handling.
- Use one overlay contract for accessible naming, initial focus, focus trapping, Escape, focus return, inert background, scroll locking, and short-viewport scrolling.
- Sequence asynchronous requests so stale results cannot replace newer searches or selections.
- Keep preview mode for deterministic visual tests and use authenticated disposable fixtures for live acceptance.
- Apply database migrations and Edge Function changes when the defect is server-side rather than masking it in the browser.

## Workflow Design

- Make evidence balance, blockers, ownership, and the next valid action primary on Overview. Keep XP, streaks, missions, and badges as secondary cooperative progress.
- Make Today and CRM one accountable relationship workflow with an owner, due state, completeness, next action, and append-only activity.
- Replace synthetic task progress with a real checkpoint containing progress, evidence, note, blocker/status, and timestamp.
- Filter collection relationships by respondent, expose consent and provenance, validate source URLs, and clear values that are incompatible with the selected metric.
- Make every survey tab functional and complete every advertised question type and setting. Review, analysis, PMF promotion, and exports must resolve each response against its immutable version.
- Make administration onboarding use generated one-time credentials and make cross-system archival outcomes recoverable.
- Make Help Center article URLs, browser history, keyboard search, editing, and publication state consistent.

## Data Integrity And Security

- Transient backend failures preserve sessions and expose retry; only invalid membership signs out.
- Respondent/session relationships, observation value types, consent metadata, and safe HTTP(S) source links are enforced in the browser and database.
- Existing version-pinned survey links continue serving their immutable version after a replacement publishes.
- One complete survey validation contract is shared by builder, public runner, Edge Function, and database checks.
- Per-link embed origins are enforced after the global origin allowlist.
- Temporary credentials are cryptographically generated, displayed once, and require replacement.
- Partial Auth/database administration operations return an explicit recoverable state and support reconciliation.

## UI System

- Preserve the warm paper-like visual identity and restrained semantic color roles.
- Recalculate foreground/background token pairs for WCAG AA in light and dark themes.
- Use visible focus, 44px touch targets, semantic tabs/tables/progress, complete bilingual labels, and reduced-motion-safe scrolling.
- Remove page-level horizontal overflow at 320px. Dense tables use deliberate internal scrolling or stacked comparison layouts.
- Reduce nested cards, repeated hero metrics, side stripes, fixed blur, and layout-property animation.

## Verification

- Write a failing behavioral test before each repair.
- Add Playwright coverage for desktop, tablet, 390px, and 320px, keyboard-only use, dark mode, reduced motion, zoom, console errors, failed requests, and horizontal overflow.
- Run authenticated live flows with uniquely prefixed disposable Supabase records and remove all fixtures afterward.
- Release only when build, lint, unit/domain/schema tests, browser tests, live RLS/RPC/Storage/Edge Function tests, and the final browser audit pass with no P0/P1 findings.

## Approved Decisions

- Use a system-first phased repair rather than a frontend rewrite.
- Keep gamification but de-emphasize it below evidence and next actions.
- Implement the complete advertised survey suite rather than hiding unsupported options.
- Verify against live Supabase with disposable records.
