# Shared AAA Accessibility Foundation Design

**Date:** 2026-08-13

**Status:** Approved design

**Source context:** `summary.md`, `131.md`, `PRODUCT.md`, `DESIGN.md`, the quality audit matrix, and the current eight-entry Vite application

## Purpose

Establish one durable accessibility foundation across every AOI entry page before expanding the Business OS. The release repairs systemic keyboard, timeout, language, focus, target-size, contrast, reflow, and status-announcement problems without using an accessibility overlay or claiming that automated checks alone prove WCAG 2.2 AAA conformance.

The release applies to:

- `index.html`;
- `login.html`;
- `workspace.html`;
- `interns.html`;
- `administration.html`;
- `helpcenter.html`;
- `Participant_Recruitment_Tracker.html`;
- `survey.html`.

AOI remains a calm, evidence-first operations product. Accessibility repairs must preserve its established warm light theme, complete dark theme, role-aware workflows, responsive information density, and honest system-state behavior.

## Product Outcome

Every user can enter, understand, navigate, and operate AOI's shared page structure with a keyboard, screen reader, browser zoom, text-spacing overrides, reduced motion, or forced colors. Authenticated users receive an accessible warning before inactivity logout and can repeatedly extend the session without losing unsaved work merely because they need more time.

The active product presentation is English-only for this release. Existing Chinese strings, structured content, and stored preferences remain available in the code and data for future localization, but no active interface offers a language switch or renders mixed product chrome.

The release creates a testable foundation and route evidence matrix. It does not make a platform-wide AAA claim until every applicable route-specific success criterion and required manual check has evidence.

## Scope

### Included

- A first-focusable skip link on all eight entries.
- One stable, correctly named main landmark per page.
- Shared focus behavior for meaningful view and route changes.
- Shared accessible status and error announcements.
- A testable inactivity warning, countdown, extension, and expiry controller.
- Shared tablist keyboard and focus behavior.
- English-only active page and interface metadata.
- Removal of visible locale controls while retaining dormant localization data.
- Shared contrast, focus, target-size, reduced-motion, forced-color, text-spacing, zoom, and reflow foundations.
- Route-by-route repair of violations exposed while adopting the shared foundation.
- Automated and manual accessibility evidence recorded per route.
- Documentation that distinguishes tested behavior from deployed behavior and targeted conformance from verified conformance.

### Deferred

- Completing or restoring Chinese product copy.
- Destructively removing Chinese translations or stored locale preferences.
- A user-configurable accessibility overlay or settings panel.
- New Business OS domains, workload planning, scheduling, finance, procurement, assets, or field operations.
- Survey feature expansion beyond accessibility repairs required by the shared foundation.
- Platform-wide WCAG 2.2 AAA conformance claims before manual evidence is complete.

## Guiding Decisions

1. Repair source semantics and interaction behavior rather than injecting an overlay.
2. Implement shared primitives first, then repair route-specific exceptions.
3. Preserve user work and announce uncertain state honestly.
4. Use familiar browser and product interaction patterns.
5. Keep keyboard focus predictable; do not move it for passive refreshes.
6. Treat 44 by 44 CSS pixels as the enhanced target baseline unless spacing provides an equivalent target area and the exception is documented.
7. Retain structured localization data even though active presentation is English-only.
8. Automated tools support, but never replace, keyboard, screen-reader, zoom, contrast, and forced-color review.
9. Accessibility evidence is route-specific and state-specific.
10. Existing project collaboration work and unrelated worktree changes must remain intact.

## Foundation Architecture

### Shared Accessibility Module

Add a focused shared frontend module, expected to be `src/js/accessibility.js`, that owns reusable accessibility behavior rather than page business state.

Responsibilities:

- enforce active English document metadata;
- provide a controlled status-announcement API;
- focus the appropriate heading or content region after meaningful route changes;
- manage reusable tablist keyboard behavior;
- expose small pure helpers that can be tested without a browser;
- register and clean up global listeners without duplication.

The module must not rewrite arbitrary DOM after render, guess labels, synthesize missing form semantics, or act as a compliance overlay. Templates remain responsible for correct headings, labels, descriptions, relationships, reading order, and error association.

### Entry Page Contract

Every HTML entry includes:

- `<html lang="en">`;
- a first-focusable **Skip to main content** link;
- exactly one stable `main` landmark with `id="main-content"`;
- a descriptive page title;
- a responsive viewport declaration;
- a structure that remains valid before Alpine initialization.

Pages that inject their templates through `app.js` must preserve the stable main target. The skip destination cannot depend on a delayed query for an arbitrary element.

### Focus Contract

Focus moves only when the user's context materially changes:

- opening a modal or modal drawer;
- closing a modal or drawer and returning to its trigger;
- navigating to a new top-level view or a deeply linked record;
- following a skip link;
- presenting an error summary that requires immediate correction.

Focus does not move for:

- filtering;
- autosave;
- realtime refresh;
- background reconciliation;
- status announcements;
- successful inline collaboration actions.

Meaningful route changes focus a stable page or view heading with temporary `tabindex="-1"` where necessary. The browser URL, visual view, heading, and focused context must agree.

### Status And Error Announcements

The shared announcement API supports two channels:

- polite status for loading completion, saved state, filtering results, and nonurgent reconciliation;
- assertive alert for blocking validation, authorization, timeout, or failed commit states.

Repeated messages are deduplicated. Rapid countdown and progress changes are throttled so screen readers are not flooded. Visible status remains the source of truth; live regions supplement rather than replace visible feedback.

Errors must:

- use plain corrective language;
- remain visible until resolved or dismissed;
- identify the affected workflow or field;
- use `aria-describedby` or an error-summary link where practical;
- never rely on color alone;
- preserve user input after known, stale, or uncertain failures.

## Inactivity And Session Extension

### Policy

Authenticated protected pages retain the existing 30-minute inactivity limit. At 25 minutes of inactivity, AOI opens an accessible warning with a five-minute countdown.

The warning provides:

- remaining time in visible text;
- **Stay signed in** as the primary action;
- **Sign out now** as the secondary action;
- a concise explanation that unsaved local work may be lost after sign-out;
- visible and announced failure recovery.

Users may extend the session repeatedly. There is no arbitrary extension limit.

### State Model

The controller has explicit states:

```text
active -> warning -> extending -> active
                   -> extension_failed -> extending
                   -> expired -> signing_out -> signed_out
                   -> signing_out -> signed_out
```

Rules:

- meaningful activity updates the inactivity deadline while in `active`;
- passive mouse movement alone must not create continuous high-frequency storage writes;
- opening the warning stops ordinary activity events from silently dismissing it;
- **Stay signed in** performs an explicit session refresh or authoritative session check before resetting the deadline;
- Escape may activate **Stay signed in** only when extension is currently available and the result is equivalent to that visible action;
- extension failure keeps the warning open and offers Retry and Sign out;
- expiration signs out and redirects honestly;
- duplicate intervals and listeners are prevented and cleaned up;
- visibility changes recalculate from timestamps rather than trusting a paused timer;
- multiple AOI tabs do not silently contradict the authenticated session state.

The timeout warning is a true modal because it blocks continued authenticated work. It uses the shared dialog manager for focus trapping, background inertness, Escape behavior, and focus restoration after successful extension.

### Testability

Time, storage, authentication, navigation, and event registration are injected or isolated behind testable boundaries. Unit tests use a fake clock and deterministic events rather than waiting in real time.

## English-Only Presentation

### Active Behavior

- `document.documentElement.lang` is always `en`.
- Product chrome, system messages, labels, errors, navigation, and date formatting use English.
- Landing, workspace, administration, Help Center, profile, and other visible locale switchers are removed.
- Profile language selection is not shown while the product is English-only.
- Stored profile or local-storage locale values do not change active presentation.
- New or edited product copy in this release is English.

### Preservation

- Existing Chinese translation objects remain in source.
- Existing structured bilingual survey and Help Center fields remain in data contracts.
- Existing profile locale values are not bulk overwritten.
- User-entered names, research, evidence, survey responses, and historical content are not translated or erased.
- Known non-English user content receives fragment-level language metadata when the language is available from the record.

This is a reversible presentation policy, not a destructive localization migration.

## Tab And Composite Widget Contract

The shared tab controller implements the WAI-ARIA tab pattern consistently:

- one `tablist` with an accessible name;
- each tab has `role="tab"`, a stable ID, `aria-controls`, and accurate `aria-selected`;
- each panel has `role="tabpanel"`, `aria-labelledby`, and stable identity;
- only the active tab participates in the ordinary tab order;
- `ArrowLeft` and `ArrowRight` move between tabs;
- `Home` and `End` move to the first and last tab;
- focus and selection behavior are consistent across routes;
- orientation is declared where vertical behavior exists;
- hidden panels are not focusable or exposed as active content.

Existing workspace, project, outreach, survey, administration, Help Center, and recruitment tab implementations must adopt the contract or document why a control is not actually a tab interface.

Other composites such as menus, listboxes, grids, and command palettes retain their correct native or ARIA-specific keyboard patterns and must not be forced through the tab controller.

## Visual And CSS Foundation

### Physical Scene

AOI is used for sustained evidence review and operational work on ordinary office displays in daytime, with occasional mobile and lower-light use. Warm light surfaces remain primary and the complete dark theme remains available.

### Contrast

- Ordinary text targets at least 7:1 contrast.
- Large text targets at least 4.5:1 contrast.
- Focus indicators, control boundaries, graphical state indicators, and essential icons target at least 3:1 against adjacent colors.
- Disabled controls remain understandable without implying availability.
- Supporting and contradictory evidence retain equal readability.
- Every interactive and semantic state is communicated with text, shape, iconography, or programmatic state in addition to color.

Contrast tests must evaluate actual rendered foreground/background combinations, including hover, focus, selected, disabled, error, warning, success, dark theme, and composited surfaces. Token-pair tests alone are insufficient.

### Typography

- Product body and control text retain Geist Sans, Noto Sans SC, and system fallbacks.
- Dense metadata is resized to a readable floor instead of preserving 7 to 9 pixel text.
- Hierarchy uses size and weight rather than faint low-contrast text.
- Prose remains within approximately 65 to 75 characters where practical.
- At 200% browser zoom, essential actions and text remain visible without two-dimensional page scrolling.

### Targets And Focus

- Primary controls and isolated pointer targets are at least 44 by 44 CSS pixels.
- Inline text links and controls with sufficient surrounding spacing may use documented equivalent spacing exceptions.
- Focus indicators are visible in light, dark, and forced-color modes.
- Focus is never removed without an accessible replacement.
- Hover-only actions become visible on focus and remain available without precise pointer movement.

### Reflow And Spacing

- The page does not overflow horizontally at 320 CSS pixels.
- Wide data tables may scroll within a named, keyboard-accessible region.
- Text-spacing overrides do not clip, overlap, or hide content or controls.
- Fixed and sticky regions do not cover focused content.
- Mobile drawers are inert and hidden from assistive technology when closed.

### Motion And Forced Colors

- Existing 150 to 250 millisecond state transitions remain purposeful.
- `prefers-reduced-motion: reduce` removes nonessential transitions and smooth scrolling.
- Forced-color styles preserve control boundaries, selected state, focus, errors, links, and essential icons.
- No information depends on background images, gradients, or animation.

## Route Adoption

### Landing

- Remove the language switch and multilingual product claim.
- Add skip navigation and main identity.
- Preserve readable marketing hierarchy at zoom and narrow widths.
- Verify all calls to action, navigation, and footer links by keyboard.

### Login

- Add skip navigation.
- Associate validation and recovery errors with their fields and summary.
- Verify callback, recovery, temporary-password, loading, and failed-auth states.
- Prevent status changes from moving focus unnecessarily.

### Workspace And Intern Workspace

- Share the same entry and accessibility foundation.
- Adopt the tab contract across primary and nested workspaces.
- Preserve role-specific content and project collaboration behavior.
- Repair heading, drawer, notification, command palette, project detail, chat, EOD, and form semantics exposed by route testing.
- Remove locale controls from the shell and profile editor.

### Administration

- Adopt skip, main, tabs, status, and timeout behavior.
- Repair people, work, data, archive, audit, and guide workflows found by automated and manual checks.
- Ensure tables and dense registers use named local scrolling rather than page overflow.

### Help Center

- Replace unreadably small metadata and rebalance affected layouts.
- Preserve article hierarchy, table of contents, search, authoring, and publishing semantics.
- Keep bilingual data fields dormant where required by the existing storage contract, while presenting active system controls in English.

### Recruitment Tracker

- Adopt shared entry, timeout, focus, status, and tab behavior.
- Verify the focused editor drawer, register controls, stage information, and embedded workspace variant.
- Accessibility repair does not broaden recruitment lifecycle permissions or claim transition enforcement that remains deferred.

### Survey Runner

- Add skip and main structure without loading authenticated session behavior.
- Verify consent, question groups, matrices, ranking, upload, review, errors, progress, and submission states.
- User-authored non-English survey content remains permitted and receives available language metadata.
- Accessibility repair does not represent unresolved secure embed restrictions or other survey product gaps as fixed.

## Security And Privacy

- The session extension path uses the existing authenticated Supabase client and never exposes credentials.
- Warning and announcement content contains no sensitive record data.
- English-only presentation does not overwrite user content or profile data.
- Skip links and stable landmarks introduce no data access.
- Accessibility testing against live data must use authorized test accounts and privacy-safe fixtures.
- Preview fixtures touched during route repair must be clearly synthetic.

## Error And Conflict Handling

- Accessibility initialization failure must not prevent page business logic from loading.
- A failed route focus action leaves the current focus intact and records a testable diagnostic in development.
- A missing or duplicate main landmark fails tests rather than being patched silently.
- Timeout extension failure preserves the modal and user choice.
- Authenticated expiry never claims local drafts were saved.
- Announcements do not convert uncertain commits into success.
- Route-specific stale-write and retry behavior remains authoritative.

## Testing Strategy

Implementation follows red-green-refactor. Every production behavior begins with a failing test that demonstrates the intended contract.

### Static And Unit Tests

- all eight entries have English metadata, skip navigation, and one stable main landmark;
- no active locale controls remain;
- locale preferences do not alter active English presentation;
- status messages are classified, deduplicated, and throttled;
- route focus changes occur only for meaningful context changes;
- tab navigation supports arrows, Home, End, roving focus, and accurate panel relationships;
- inactivity warning starts at 25 minutes and expires at 30 minutes;
- successful extension resets the deadline;
- extension failure preserves warning state;
- visibility changes and cleanup are deterministic;
- generated output contains no accessibility overlay or service-role material.

### Browser Tests

Run route matrices for desktop, mobile, and 320 CSS pixels:

- skip-link visibility and destination;
- keyboard-only access to every primary workflow;
- one main landmark and logical heading structure;
- meaningful route focus and trigger focus restoration;
- tab and composite-widget keyboard patterns;
- timeout warning, countdown, extension, retry, and expiry with a controlled clock;
- visible and announced validation, success, and failure states;
- 200% zoom and 320px reflow;
- WCAG text-spacing overrides;
- light and dark rendered contrast;
- reduced motion;
- forced colors;
- no page-level horizontal overflow;
- no hidden or inert content in the active focus order.

### Manual Evidence

Record evidence per route and important state for:

- keyboard-only navigation;
- NVDA with Firefox or Chrome on an available Windows environment;
- VoiceOver with Safari on an available Apple environment;
- browser zoom and responsive reflow;
- forced-colors or operating-system high contrast;
- focus visibility and focus order;
- timeout comprehension and operation;
- form errors and status announcements;
- cognitive clarity, consistent help, and nonredundant entry expectations;
- light and dark contrast spot checks using measured rendered colors.

Unavailable platform combinations are recorded as explicit residual verification gaps, not silently marked passed.

### Release Commands

Run at minimum:

```bash
npm run lint
npm test
npm run test:e2e
git diff --check
```

Database execution tests remain part of the full release gate even though this slice should not require a database migration. Existing expected live-auth skips must be inventoried; new required accessibility tests cannot be silently skipped.

## Evidence Matrix

The quality matrix gains a current accessibility registry with one row per route and state group. Each row records:

- applicable WCAG 2.2 success criteria;
- automated test evidence;
- keyboard evidence;
- screen-reader and browser combination;
- zoom, text-spacing, dark-theme, and forced-color evidence;
- known exceptions;
- repository status;
- deployed-production status;
- verifier and date.

Status language must distinguish:

- `targeted`: included in the design but not yet verified;
- `automated green`: automated checks pass;
- `manual green`: required manual checks pass;
- `blocked`: an environment or external verification dependency remains;
- `verified`: all applicable evidence for the stated route and state is complete.

Only verified rows may support a conformance statement.

## Delivery Sequence

1. Add failing entry-page and English-only presentation contracts.
2. Implement skip navigation, stable main landmarks, and active English initialization.
3. Add failing inactivity-controller tests and implement warning, extension, failure, expiry, and cleanup.
4. Add failing shared tab and announcement tests and implement the shared primitives.
5. Repair shared CSS contrast, target, focus, typography, reflow, motion, and forced-color foundations test-first.
6. Adopt and repair landing and login.
7. Adopt and repair workspace and intern workspace.
8. Adopt and repair administration and Help Center.
9. Adopt and repair recruitment tracker and survey runner.
10. Run the complete browser matrix, record manual evidence, update documentation, and verify the release gate.

Each step must remain green before the next broad adoption step begins.

## Acceptance Criteria

The release is complete when:

1. All eight entries expose a first-focusable skip link and exactly one stable main landmark.
2. Product presentation and document metadata are consistently English with no visible language controls.
3. Existing Chinese strings, structured content, and profile preferences remain preserved for future localization.
4. Protected pages warn five minutes before the 30-minute inactivity limit.
5. Users can repeatedly extend a session, explicitly sign out, recover from extension failure, and understand remaining time with keyboard and assistive technology.
6. Every adopted tab interface follows one complete keyboard and ARIA contract.
7. Meaningful route changes place focus predictably while passive updates do not steal focus.
8. Visible statuses and errors are also announced appropriately without flooding assistive technology.
9. Rendered text, controls, focus, and essential graphical states satisfy the specified contrast targets in light and dark themes.
10. Essential controls meet the enhanced target-size baseline or have a documented equivalent-spacing exception.
11. Every route reflows at 320 CSS pixels and 200% zoom without page-level horizontal scrolling or hidden essential actions.
12. Text-spacing, reduced-motion, and forced-color modes preserve meaning and operation.
13. Required automated tests, lint, database suites, E2E, and diff checks pass without new unexpected skips.
14. The route evidence matrix records completed manual checks and explicit residual gaps.
15. Documentation describes the release as AAA-targeted unless all applicable success criteria have complete manual evidence.
16. Existing project collaboration behavior and unrelated worktree changes remain intact.

## Prioritized Platform Roadmap

This foundation precedes, but does not replace, the remaining repairs and Business OS development identified in `summary.md` and `131.md`.

### P0: Release Trust

1. Verify credential rotation and old-credential revocation through the security runbook.
2. Verify linked Supabase migration history and create a restorable checkpoint.
3. Apply outstanding migrations and prove frontend/backend revision parity.
4. Run authenticated owner, administrator, intern, and public-survey smoke tests without silent environment skips.

### P1: Existing Product Integrity

1. Complete route-specific accessibility evidence after the shared foundation.
2. Close remaining authorization, consent, identifier, and Gate integrity findings with executable database tests.
3. Repair chat draft scope and uncertain-commit retry behavior.
4. Repair Help Center authoring runtime failures.
5. Sanitize remaining public preview fixtures.
6. Make CI run lint, backend execution tests, E2E, and explicit skip accounting on pull requests and release pushes.

### P2: Complete Existing Product Promises

1. Finish survey reviewer assignment, hidden variables, qualitative coding, true cross-tabs, QR generation, and honest embed restrictions.
2. Enforce recruitment lifecycle transitions and withdrawal propagation server-side.
3. Implement or remove placeholder PMF, recruitment, and workload reports.
4. Replace unsupported outreach-delivery implications with confirmed provider behavior or explicit manual state.
5. Add scoped cross-domain search and named evidence/source linking.

### P3: Role-Adapted Work

1. Add **My Commitments** for interns and members.
2. Add **Team Load**, unassigned work, reviews, blockers, and at-risk capacity for administrators.
3. Add explicit weekly availability and authoritative estimated effort.
4. Reuse existing handoff and source-authoritative assignment behavior.
5. Defer timesheets, billable rates, optimization, and surveillance-style activity tracking.

### P4: Project Execution Expansion

1. Add typed dependencies and distinguish them from blockers.
2. Add phases, deliverables, subtasks, and checklists only where demonstrated workflows require them.
3. Add baselines, schedule variance, Gantt, critical path, and scenario planning only after dependency and capacity contracts are proven.

### P5: Controlled Business OS Expansion

Prioritize typed domains with demonstrated operational demand:

- documents and executable SOPs;
- confirmed external communication delivery;
- commercial pipeline;
- procurement;
- resource management;
- field service and assets.

Each domain requires a dedicated object model, authorization contract, lifecycle, evidence and history rules, collaboration integration, accessibility acceptance, migration plan, and release evidence. Generic object, workflow, dashboard, portal, and low-code builders remain deferred until repeated typed-domain patterns justify them.

## Success Measure

The foundation succeeds when accessibility is no longer repaired independently in every feature. New AOI workflows inherit predictable page entry, focus, announcements, tabs, timeout behavior, contrast, target sizing, reflow, motion, and evidence requirements by default. Future role-adapted work and Business OS modules can then expand on a trustworthy shared interaction layer rather than multiplying known barriers.
