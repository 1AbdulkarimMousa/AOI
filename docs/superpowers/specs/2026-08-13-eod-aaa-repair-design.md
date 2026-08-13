# EOD AAA Repair Design

## Goal

Repair `workspace.html?view=eod` into a dependable end-of-day closeout workflow for administrators and interns. The work must remove the current data blockers, protect unfinished work, restore organization-wide reporting, and bring the EOD surface to formal WCAG 2.2 AAA quality where applicable without redesigning unrelated workspace areas.

## Scope

This is a focused full repair of the existing EOD subsystem:

- Supabase snapshot, save, administrator update, report, and audit contracts.
- EOD controller state, project switching, concurrency, and unsaved-draft recovery.
- The daily brief, administrator queue, archive, and record drawer.
- EOD-specific responsive, theme, accessibility, and browser behavior.
- Regression coverage for database, domain, UI, and end-to-end behavior.

The repair preserves the existing warm paper-like visual system, restrained orange actions, semantic status colors, and shared workspace components. It does not restructure unrelated workspace features.

## Confirmed Decisions

- The EOD archive covers the entire organization across current and completed projects.
- Historical submitted records imported without evidence URLs may be completed with an explicit warning and a required administrator reason. The system must not invent evidence.
- This repair keeps the EOD interface in English. Full Simplified Chinese translation is intentionally deferred.
- Unsaved EOD work receives local recovery plus destructive-navigation warnings.
- The surface targets formal WCAG 2.2 AAA criteria where applicable, including 7:1 normal-text contrast and robust reflow and text-spacing behavior.
- The implementation is a focused full repair rather than a frontend-only patch or subsystem rewrite.

## Blocking Defects

### First Brief Creation

The final snapshot RPC does not return the selected project ID when the caller has no existing brief. The browser consequently omits `scopeProjectId`, and the save RPC rejects the request with `EOD_SCOPE_CHANGED`.

The snapshot contract must always return the selected `projectId`, including when `myBrief` is null. First-time users must be able to save an incomplete draft and submit a valid brief.

### Organization Archive

The final report RPC references `daily_eod_audit_events.project_id`, but that column does not exist. The archive therefore fails at runtime.

The report query must scope audit events through their organization and brief identity. The resulting archive must be organization-wide across current and completed projects, role-scoped so administrators see organization records and interns see only their own records.

## User Workflow

### Daily Brief

The page remains one focused structured brief rather than a dashboard grid. The main column contains ownership, daily outcomes, blockers, executive support, exactly three next-workday priorities, project status, and labeled evidence URLs.

Submission requirements are communicated before submission and at the affected fields. Drafts may remain incomplete. Submission uses server-authoritative validation and requires all normal fields, exactly three priorities, a valid executive-owner choice, and at least one labeled HTTP or HTTPS evidence URL.

The form shows complete submission date, time, and organization timezone. Completed records are read-only for their author.

### Unsaved Work

Edits are stored locally under a scope composed of user ID, project ID, and server brief date. Local persistence is debounced and never crosses scope boundaries.

When a same-scope local draft is newer or differs from the loaded server record, the page offers explicit recovery. It never silently overwrites server data. Saving successfully clears the matching local recovery entry.

Sidebar navigation, browser history, project switching, logout, and browser close warn before discarding unsaved changes. A confirmed project switch clears the visible old scope and loads the new project before enabling EOD editing.

### Administrator Oversight

Administrators can filter today’s team by all, missing, submitted, and completed. The selected filter is programmatically exposed. Rows without a brief remain non-actionable and clearly state that the member is waiting.

Opening a brief shows the full record, exact timestamps, linked evidence, edit/completion controls, and audit history. Administrator changes require a reason. Completing an ordinary submitted brief still requires valid content.

An imported historical submission that lacks evidence shows a prominent `Evidence unavailable in imported record` warning. An administrator may complete it only with an explicit reason. The completion event records that the evidence exception was used. This exception applies only to qualifying legacy records and cannot be used to submit new briefs or remove evidence from current records.

### Archive

The archive searches all organization projects, including completed projects. Administrators can distinguish author, Engagement Manager, Person In Charge, author role, date range, project state, workflow state, and project. Interns receive only their own records regardless of manipulated browser filters.

The archive is newest-first and paginated. At wide widths it uses semantic table relationships. At narrow widths it becomes labeled stacked records rather than retaining a 780-pixel pseudo-table.

Opening a result loads the complete record and detailed audit history. List responses contain only summary audit metadata needed by the archive, avoiding repeated before-and-after snapshots in every row.

## Client State

EOD uses explicit snapshot states:

- `uninitialized`: no live EOD request has completed.
- `loading`: the current scope is being fetched.
- `ready`: the current snapshot is usable.
- `empty`: a valid scope has no current brief or no archive results.
- `failed`: the request failed and a scoped retry is available.

Live users never see preview fallback people, dates, or records while EOD is uninitialized or failed. Preview mode continues to use synthetic local records and remains visibly identified as preview data.

Snapshot and report requests retain sequence guards so late responses cannot overwrite newer scope data. A project change invalidates current EOD snapshot and archive state, then refreshes both. Same-scope dirty values are preserved only when an automatic refresh does not change the project or server workday.

Stale-write recovery keeps the user’s local form, fetches the latest server record, and offers explicit choices to inspect the latest version or restore the local draft for reconciliation.

## Validation And Errors

Domain validation returns field-addressable errors plus a concise summary. Each invalid control receives `aria-invalid` and a linked error description. Submission focuses a summary, and activation of a summary item focuses the associated control. The first invalid control is focused after the announcement when appropriate.

Network and server failures stay scoped to the snapshot, form action, administrator action, or archive. Loading and saving controls expose busy and disabled states without making unrelated content unavailable. Existing values remain intact after a failed write.

The server remains authoritative for role, organization, project, date, cutoff, workflow transition, evidence exception, and optimistic-lock validation.

## Accessibility And Visual Treatment

The physical scene is a researcher closing a full workday on a normal office display, often tired and scanning dense evidence under moderate ambient light. The existing warm light theme remains primary, with the existing complete dark theme for lower-light work.

The repair is a precision pass rather than a new aesthetic:

- Raise EOD control and body typography from the current 7 to 11 pixel range to readable product sizes. Form controls use at least 16 pixels where mobile browser auto-zoom would otherwise occur.
- Normal text targets at least 7:1 contrast. Large text follows the applicable AAA threshold.
- Unfocused control boundaries and meaningful non-text UI target at least 3:1 contrast.
- Replace surface-invisible ghost action styling with the shared visible action vocabulary.
- Preserve semantic status text alongside color.
- Keep every pointer target at least 44 by 44 CSS pixels where the AAA target-size criterion applies.
- Use visible, consistent focus indicators in light and dark themes.
- Avoid nested decorative cards, gradient text, glass effects, colored side stripes, and decorative motion.

The record drawer has a stable accessible name, focus containment, Escape closure, inert background content, and focus restoration. Notices use status or alert semantics based on urgency. Loading regions expose `aria-busy` and usable skeleton or loading copy.

The EOD interface remains English in this repair. When the shell is set to Simplified Chinese, the EOD region must declare English as its language so assistive technology pronounces it correctly. Complete EOD translation is a separate future scope.

## Responsive Behavior

- At wide desktop widths, the form and sticky requirement rail remain side by side.
- Before the evidence row can clip, the rail moves inline and form sections reflow.
- At tablet widths, ownership and ordinary two-column groups use available space without fixed minimums that cause clipping.
- At 320 and 375 pixels, all form groups, evidence fields, actions, filters, and archive records stack without page-level horizontal overflow.
- Date inputs and long URLs may shrink or wrap without widening the page.
- At 200 percent zoom and under WCAG text-spacing overrides, controls remain reachable and labels remain associated.
- Reduced-motion mode removes drawer and state-transition animation.

## Database Changes

Add one forward-only migration that replaces the final affected EOD RPC definitions and introduces only schema metadata needed to identify qualifying legacy evidence exceptions.

The migration must:

- Return `projectId` from `rpc_aoi_daily_eod_snapshot()` for every valid selected-project scope.
- Restore an executable organization-wide `rpc_aoi_daily_eod_reports()` implementation.
- Remove the invalid dependency on an audit `project_id` column.
- Keep intern results author-scoped at the database layer.
- Support distinct author, manager, PIC, project, project-state, workflow-state, and date filters.
- Return summarized archive rows and load detailed audit history for an opened record without duplicating large snapshots across the page.
- Define and enforce the narrow legacy-evidence completion exception.
- Preserve RLS, authenticated-only RPC grants, organization boundaries, optimistic locking, audit provenance, and first-submission lateness.

Existing migrations are not rewritten because they may already be deployed.

## Verification

Implementation follows test-driven development. Every behavioral repair begins with a regression test that fails for the expected reason.

### Domain Tests

- Structured validation maps each error to its field and preserves concise messages.
- Exactly three priorities and executive-owner exclusivity remain enforced.
- Local draft keys are isolated by user, project, and server date.
- Local recovery never crosses scope and clears after a successful save.
- Legacy evidence exceptions cannot qualify current or ordinary records.

### Database Execution Tests

- A user with `myBrief = null` receives `projectId` and can save a first draft.
- The organization report RPC executes successfully on a fresh final schema.
- Administrators receive multiple current and completed projects; interns receive only their records.
- Every report filter is independently enforced.
- Audit joins do not require a nonexistent project column.
- Ordinary submitted records still require evidence.
- A qualifying legacy submitted record can be completed with a reason, and the exception is audited.
- Missing reasons, stale versions, cross-organization IDs, and invalid transitions are rejected.

### Browser Tests

- First draft save and valid submission.
- Inline error summary, field linkage, and first-invalid-field focus.
- Loading, snapshot failure, archive failure, empty results, and retries.
- Project switching invalidates old EOD state and reports.
- Navigation, unload warning, local recovery, and stale-write reconciliation.
- Administrator filters, legacy warning, audited edit, and completion.
- Semantic archive reading and record drawer keyboard behavior.
- Light and dark themes.
- 320, 375, 768, 1024, and desktop widths.
- No page-level horizontal overflow.
- Keyboard-only operation, 200 percent zoom, AAA text contrast checks, WCAG text-spacing overrides, and reduced motion.
- No uncaught page, console, network, or accessibility errors in tested flows.

### Final Commands

Run the focused EOD tests during development, then complete:

```text
npm run build
npm run lint
npm test
npm run test:e2e
```

Run the executable Supabase migration tests against a fresh database when PostgreSQL tooling is available.

## Out Of Scope

- Complete Simplified Chinese translation of the EOD feature.
- External email, SMS, or push reminders.
- Weekend or organization-holiday configuration beyond the existing weekday rule.
- Evidence file uploads.
- A generic form-builder framework.
- Refactoring unrelated workspace controllers or visual systems.
