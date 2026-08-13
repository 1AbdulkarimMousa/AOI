# Today Briefing Full-Stack Repair Implementation Plan

## Goal

Ship the approved action-first Today Briefing with authoritative role scope, derived project evidence, isolated failure handling, exact source navigation, responsive reflow, and touched-surface AAA verification.

## Phase 1: Failing Contracts

- Add a Briefing domain test for payload normalization, clamped display progress, role-aware copy, source destinations, and preview derivation.
- Add UI contract tests that reject the legacy hero, mission, seed metrics, confidence percentages, and ambiguous navigation.
- Add PostgreSQL execution coverage for selected-project scope, admin versus intern action rows, local-date overdue logic, consent-safe evidence, supported and unsupported sample sources, and seed-table independence.

## Phase 2: Authoritative Backend

- Extend sample plans with an explicit `source_kind` and optional `survey_asset_id`.
- Add one `security definer` selected-project `rpc_aoi_today_briefing` function with an empty search path and least-privilege grants.
- Derive attention, deadline, sample, PMF, evidence-theme, and recorded-activity projections from maintained records.
- Bound and deterministically order every returned list.
- Keep unsupported sample mappings null and omit unsupported confidence and change claims.

## Phase 3: Frontend State And Loading

- Add a focused Briefing domain module for normalization, preview projection, role copy, source destinations, and progress presentation.
- Add a narrow API wrapper independent from the existing multi-module dashboard loader.
- Add sequenced Briefing state to the workspace and preserve confirmed data during refresh errors.
- Stop authenticated initial and failed renders from exposing fallback dashboard fixtures.
- Keep the existing dashboard loader for workflows that still consume operations, PMF, CRM, Collect, EOD, and gamification snapshots.

## Phase 4: Action-First Product Experience

- Replace the legacy Briefing hero, mission, metrics, focus, PMF-confidence, activity, and signal card stack.
- Render role-aware live heading, factual pulse, attention queue, deadlines, sample progress, PMF evidence chain, themes, and recorded activity.
- Provide complete loading, empty, partial-error, stale, preview, and retry presentation.
- Route each item to its exact source workflow and explicitly route PMF and themes to Research / Analyze.
- Show authoritative detail loading and disable source actions until detail succeeds.

## Phase 5: Responsive And AAA Closure

- Implement the 12-column desktop hierarchy and strict single-column mobile reading order.
- Preserve 44px targets, visible focus, semantic lists/progress/status, live announcements, forced-colors meaning, reduced motion, text spacing, and dark-theme contrast.
- Add Playwright coverage for administrator and intern preview, keyboard flow, desktop, 390px, 320px, dark mode, text spacing, and horizontal overflow.

## Phase 6: Verification And Documentation

- Update README and the quality audit matrix with repaired and operationally unverified findings.
- Run focused red/green tests after each phase.
- Run `npm run lint`, `npm test`, `npm run test:e2e`, and diff checks.
- Review intended changes without reverting or modifying unrelated collaboration work.
- Report repository verification separately from linked Supabase deployment status.
