# Daily EOD Brief Design

## Goal

Require every active AOI administrator and intern to submit one structured end-of-day brief each weekday. Keep the brief visible as a daily responsibility, let administrators review and complete submissions, and preserve a searchable report archive.

## Schedule And Compliance

- The brief is required Monday through Friday and due at 5:00 PM in the organization's configured timezone.
- The brief is visible throughout the workday. After the cutoff, an unsubmitted brief is marked overdue, but the user may still submit it.
- Submission satisfies the author's daily requirement. Administrative completion is a separate review state.
- Weekends do not create a requirement.
- The server derives the brief date, cutoff, author, role, organization, and project. Browser dates are display-only.

## Roles And Access

- Administrators and interns can create, save, submit, search, and read their own briefs.
- Every active administrator in the organization can read every brief, edit any workflow state with a required reason, and mark a submitted brief complete.
- Interns cannot read another user's brief or edit a completed brief.
- Administrators can search all briefs by user name and date. Interns are server-limited to their own history even if they manipulate browser filters.
- An administrator may complete their own brief. Completion records the administrator who performed the action.

## Data Model

Add `daily_eod_briefs` with organization, project, author, author-role snapshot, Engagement Manager, Person In Charge, and server-derived brief date. Enforce one row per project, author, and brief date.

The record stores these structured sections:

1. What Moved: tangible outcome, evidence gathered, deliverables completed, and key insight or discovery.
2. What's Blocked: current blocker, impact, and proposed solution. An explicit `None` is valid when there is no blocker.
3. What Needs You: one or more executive owners from Eason, Zhenzhen, and Mike, or `None`, plus a one-sentence request. Selecting `None` clears named owners.
4. What's On Tomorrow: exactly three non-empty priorities.
5. Status: one of `on_track`, `at_risk`, or `off_track`.
6. Evidence: one or more labeled URL entries with source type `onedrive`, `crm`, `evidence_log`, `participant_tracker`, or `other`.

Workflow state is `draft`, `submitted`, or `completed`. The record also stores submission time, completion actor/time, last editor, edit reason, creation time, and update time. `updated_at` is used as an optimistic-lock version.

Use the existing audit event system to capture submission, administrator edits, and completion. Administrator edits include the reason and before/after changed values.

## Database Interface

Expose the feature through authenticated RPCs rather than browser-authored scope fields:

- `rpc_aoi_daily_eod_snapshot()` returns the server workday, due/cutoff state, the caller's current brief, active-member choices, and role-scoped oversight summaries.
- `rpc_aoi_save_daily_eod_brief(payload, expected_updated_at)` creates or updates the caller's current-day draft and submits it when requested. It validates submitted content server-side.
- `rpc_aoi_admin_update_daily_eod_brief(brief_id, payload, edit_reason, expected_updated_at, action)` lets an active administrator update any organization brief. The explicit action is `save` or `complete`.
- `rpc_aoi_daily_eod_reports(filters, page, page_size)` returns a paginated, newest-first organization archive across current and completed projects. Administrators receive organization records; interns receive only their own. Every item retains its project code and name.

The table has RLS enabled. Active members can select their own records, active administrators can select organization records, and direct browser writes are not granted. RPC execution is revoked from public and anonymous roles and granted only to authenticated users.

## Interface

Add an `End-of-Day Brief` navigation item after `Today` for both roles.

- Today shows a reminder card with `Due by 5 PM`, `Overdue`, `Submitted for admin check`, or `Completed`.
- The navigation item shows an attention badge when the caller owes a brief. Administrators also see submitted records awaiting completion in their oversight count.
- The EOD page presents one focused four-section form matching the supplied template, followed by status and evidence.
- Users can save an incomplete draft. Submission requires every field, exactly three priorities, an executive-owner selection, and at least one valid evidence URL.
- Evidence rows have source, label, URL, add, and remove controls.
- Submitted records show on-time or late state and the submission timestamp.

Administrators additionally see an oversight queue with missing-today, submitted, and completed filters. They can open a record, edit it with a required reason, and mark it complete. The record displays its last editor and completion actor.

## Reports

Add an EOD archive section to the existing Reports area and link it to the EOD view.

- Administrator filters: author, Engagement Manager, Person In Charge, author role, date range, project status, and workflow state.
- Intern filters: date range, project status, and workflow state; results remain restricted to the signed-in author.
- Results are paginated and newest-first.
- Opening a result shows the complete brief, evidence links, submission/completion metadata, and audit history.

## Error Handling

- Drafts may be incomplete; submitted records may not.
- Validation errors remain inline and preserve entered values.
- A stale `updated_at` rejects the write and asks the user to reload, preventing silent overwrites between administrators.
- EOD snapshot and report failures show scoped retry states and do not prevent the rest of the workspace from loading.
- Preview mode uses synthetic records and local-only writes with an explicit preview notice.

## Responsive And Accessible Behavior

Reuse the existing panel, form, badge, review-row, dark-theme, focus, and reduced-motion vocabulary. Desktop uses a focused form plus compact status rail. Mobile stacks sections, evidence entries, oversight filters, and report results without shrinking tap targets. Statuses always include text and do not rely on color alone.

## Verification

- Pure tests cover validation, exactly-three priorities, executive-owner rules, URL validation, weekday/cutoff state, sorting, and due-state derivation.
- Schema tests cover the unique daily constraint, scoped foreign keys, RLS, RPC grants, server-derived dates, state transitions, stale-write rejection, and audit events.
- Browser contract tests cover shared navigation, reminders, admin-only oversight, report filters, preview role scoping, and built page output.
- Run `npm run build`, `npm run lint`, and `npm test` before delivery.
- Verify the migration against the linked Supabase project with security advisors and role-scoped RPC smoke queries when credentials and CLI access are available.

## Out Of Scope

- Email, SMS, or external reminder delivery.
- Weekend or holiday calendars beyond the weekday rule.
- A reusable generic form-template engine.
- Automatically generated ordinary task records.
- Direct evidence file uploads; the brief stores labeled links only.
