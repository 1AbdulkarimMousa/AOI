# AOI Project Operating Core Design

**Date:** 2026-08-12  
**Status:** Approved design  
**Source:** `131.md`, sections 1-21, 82, 147-148, 178-182, and 194-201

## Purpose

AOI will add a project operating core that connects accountable work, project health, milestones, blockers, risks, evidence, and decisions without becoming a generic board system.

This release builds on AOI's existing strengths:

- explicit ownership and next actions;
- organization and project isolation;
- authoritative server-side lifecycles;
- evidence provenance and visible contradiction;
- immutable decision snapshots;
- contextual comments, mentions, followers, handoffs, and inbox items;
- optimistic concurrency and honest failure states;
- append-only history;
- role-adaptive Today views.

The release must preserve all existing records, identifiers, scope, authorship, timestamps, consent history, attachments, and workflow history.

## Scope

### Included

- Explicit active organization and project selection.
- Administrator-managed projects and project membership.
- Project overview and health.
- Project milestones.
- Project blockers.
- Project risks.
- Evidence-backed project decisions.
- Immutable approved decision snapshots.
- Project-scoped comments, mentions, followers, handoffs, inbox items, and activity.
- Stable project and record deep links.
- Role-specific Today priorities for project work.
- Desktop, mobile, dark-mode, and touched-workflow WCAG 2.2 AAA behavior.

### Deferred

- Programs and portfolios.
- Legal-entity and intercompany workflows.
- Phases, deliverables, subtasks, and generic nested work.
- Task dependency types, lead/lag, critical path, float, baselines, and Gantt.
- Budgeting, costing, procurement, invoicing, and accounting.
- Delegated or configurable approval engines.
- Generic custom objects, fields, workflows, dashboards, and portals.
- A universal polymorphic business-object registry.

These remain strategic directions in `131.md`, not requirements for this release.

## Product Principles

1. Every actionable record has an owner, next action, and due date where applicable.
2. Every consequential state transition is validated server-side.
3. Every approved decision records the evidence state used at approval time.
4. Supporting and contradictory evidence receive equal visibility.
5. Comments and inbox actions support work but never implicitly approve or complete it.
6. The interface never guesses an ambiguous organization or project context.
7. Uncertain, stale, or failed operations remain visible.
8. Accountability measures work and outcomes, not invasive employee behavior.

## Roles

The release retains the current account model.

### Owner

- Has administrator capabilities.
- Can perform governance-sensitive project actions.
- Can approve or reject project decisions.
- Can override project archival blockers with a recorded reason where permitted.

### Administrator

- Creates and configures projects.
- Manages project membership.
- Creates and manages milestones, blockers, and risks.
- Reviews submitted milestones and decisions.
- Approves or rejects project decisions.
- Reviews escalations and project health.

### Intern

- Accesses only explicitly authorized projects.
- Updates assigned milestones.
- Creates or updates authorized blockers and risks.
- Drafts and submits decisions when assigned.
- Adds comments, mentions, evidence links, and handoff requests within source access.
- Cannot approve decisions or complete administrator review transitions.

No manager role is introduced in this release.

## Canonical Context

### Problem

AOI currently resolves an active organization and project independently in several RPCs. Deterministic ordering prevents random selection but does not provide one explicit context for users who can access multiple organizations or projects.

### Design

The platform will expose one canonical workspace context containing:

- authorized organizations;
- authorized projects for each organization;
- selected organization ID;
- selected project ID;
- role and owner status;
- whether selection is required.

The project switcher becomes functional rather than decorative.

### Context Rules

- A requested organization and project must be validated together.
- A project must belong to the selected organization.
- A non-administrator must have active project membership.
- An administrator may access active projects in an authorized organization.
- The selected context is persisted as a user preference only after validation.
- Stable URLs include project context where record identity alone is insufficient.
- If one valid context exists, AOI may select it automatically.
- If several valid contexts exist and no valid preference or URL context exists, AOI requires a choice.
- Snapshot RPCs and mutations consume the same validated context contract.
- Switching context with dirty edits requires confirmation.
- Unauthorized context IDs are treated as unavailable without leaking record details.

## Native Data Model

Dedicated native tables are preferred over JSON/EAV or a generic object engine. Explicit tables preserve constraints, RLS clarity, lifecycle integrity, and understandable migrations.

### Project Extensions

The existing `projects` record gains or exposes:

- objective;
- sponsor name or linked profile where appropriate;
- manager profile;
- planned start and finish;
- actual start and finish;
- health: `on_track`, `at_risk`, or `off_track`;
- lifecycle status;
- archive metadata;
- optimistic revision or updated timestamp.

Existing project IDs and rows remain unchanged. New fields are nullable or receive preservation-safe defaults.

### Project Membership

`project_members` records explicit project access and responsibility:

- organization ID;
- project ID;
- user ID;
- project responsibility;
- active status;
- assigned and archived timestamps;
- assigning actor.

Organization membership remains necessary but does not by itself grant intern access to every project.

### Milestones

`project_milestones` stores:

- organization and project scope;
- title and intended outcome;
- owner;
- planned and actual dates;
- progress percent;
- acceptance criteria;
- next action and due date;
- lifecycle status;
- review note;
- optimistic revision timestamps;
- created and updated actors.

Milestones are outcome records, not containers for a hidden dependency scheduler.

### Blockers

`project_blockers` stores:

- organization and project scope;
- title and description;
- optional source link to a milestone, task, or authorized research record;
- blocked-since timestamp;
- reporting actor;
- blocking party or description;
- resolution owner;
- expected resolution date;
- impact: `low`, `medium`, `high`, or `critical`;
- next action and due date;
- escalation state, reason, actor, and timestamp;
- lifecycle status;
- resolution note and timestamp;
- optimistic revision timestamps.

Resolution and reopening append history. Reopening never erases the previous resolution.

### Risks

`project_risks` stores:

- organization and project scope;
- risk statement;
- owner;
- probability from 1 to 5;
- impact from 1 to 5;
- server-calculated score;
- trigger or early-warning condition;
- mitigation;
- next action and due date;
- review date;
- lifecycle status;
- acceptance rationale where applicable;
- optimistic revision timestamps.

The browser cannot authoritatively set the risk score.

### Decisions

`project_decisions` stores the working decision record:

- organization and project scope;
- title and decision statement;
- owner and decision maker;
- alternatives considered;
- rationale;
- expected impact;
- lifecycle status;
- review guidance;
- submission and review actors and timestamps;
- optimistic revision timestamps.

Evidence links preserve:

- the linked native source;
- whether it supports or contradicts the proposal;
- relevance note;
- evidence eligibility at read and approval time.

`project_decision_snapshots` stores the immutable approved representation:

- complete decision content;
- alternatives, rationale, and impact;
- supporting and contradictory evidence projections;
- source identifiers and provenance;
- decision maker and approving actor;
- approval timestamp;
- project context;
- snapshot version;
- supersession relationship where applicable.

Approved snapshots cannot be edited or deleted. A correction requires a superseding decision.

### History

Append-only history tables record consequential transitions for milestones, blockers, risks, and decisions. Entries include:

- source ID;
- actor;
- action;
- prior and resulting state;
- note or reason;
- timestamp;
- relevant immutable metadata.

Routine presentation changes do not need noisy universal diffs, but governance transitions do.

## Lifecycle Contracts

### Projects

`planning → active → on_hold → completed → archived`

- Reopening an `on_hold` project returns it to `active`.
- Completion requires no unresolved critical blockers.
- Archival requires completion or an explicit administrator override reason.
- Archived projects are read-only except for governance-preserving restoration.

### Milestones

Primary path:

`draft → active → submitted → approved → completed`

Alternative states:

- `blocked`;
- `revision_requested`;
- `cancelled`.

Rules:

- Assigned members update `active` or `blocked` milestones.
- Submission requires a progress note and acceptance-criteria statement.
- Administrators request revision or approve.
- Completion follows approval and preserves review history.
- Stale updates fail without overwriting the user's draft.

### Blockers

`open → acknowledged → resolving → resolved`

- Any authorized actor may report a blocker within source access.
- Resolution requires a resolution note.
- A resolved blocker may be reopened with a reason.
- Escalation is an audited action, not merely a color change.
- Escalation does not silently transfer ownership.

### Risks

`identified → assessing → mitigating → monitoring → closed`

`accepted` is an owner/admin-controlled terminal outcome.

- Probability and impact remain constrained.
- Score is computed by the server.
- Acceptance requires rationale.
- Closing requires a note describing the outcome or retired exposure.
- Overdue reviews generate authorized inbox attention.

### Decisions

Primary path:

`draft → submitted → revision_requested → resubmitted → approved`

Alternative outcomes:

- `rejected`;
- `superseded`.

Rules:

- Drafts remain editable by the assigned owner and administrators.
- Submitted and resubmitted decisions are locked pending review.
- Revision requests require actionable guidance.
- Approval requires a decision statement, rationale, alternatives, impact, and at least one eligible evidence link.
- Supporting and contradictory evidence are both captured when present.
- Approval atomically creates the immutable snapshot.
- Rejection requires a reason.
- Supersession links the old and replacement decisions while preserving both snapshots.

## Evidence and Source Relationships

Existing task, research, survey, PMF, CRM, and EOD records remain authoritative. Project records link to them without copying mutable source rows into new operational tables.

At decision approval, AOI stores a self-contained evidence projection sufficient to explain the historical decision if the live source later changes or becomes inaccessible. This projection includes source identity, title or statement, stance, provenance, limitations, eligibility, and collection or approval timestamps where applicable.

Consent-sensitive research evidence must pass the latest applicable consent rules at approval time. Ineligible material cannot enter an approved project decision snapshot.

## Collaboration and Inbox

Milestones, blockers, risks, and decisions participate in AOI's contextual collaboration model.

Supported operations:

- comments;
- comment revisions;
- mentions;
- follows;
- reasoned handoffs;
- activity history;
- derived inbox items;
- stable source links.

New source types extend the existing source authorization and context contracts explicitly. This release does not introduce an unchecked polymorphic registry.

Inbox examples:

### Intern

- assigned milestone due soon;
- milestone revision requested;
- blocker resolution action due;
- mitigation review due;
- decision revision requested;
- mention or handoff.

### Administrator

- milestone awaiting review;
- overdue or critical blocker;
- escalated blocker;
- high risk with overdue review;
- decision awaiting review;
- project health deterioration;
- reconciliation failure.

Comments, follows, handoffs, and inbox resolution never perform source approval or completion. Source RPCs remain authoritative.

## Product Experience

### Navigation

Add **Projects** as a primary destination alongside Today, Relationships, Research, End-of-Day Brief, and Chat.

Project-local tabs:

- Overview;
- Milestones;
- Blockers & Risks;
- Decisions.

Canonical examples:

- `workspace.html?view=projects&project=<id>&tab=overview`
- `workspace.html?view=projects&project=<id>&tab=milestones&milestone=<id>`
- `workspace.html?view=projects&project=<id>&tab=blockers&blocker=<id>`
- `workspace.html?view=projects&project=<id>&tab=risks&risk=<id>`
- `workspace.html?view=projects&project=<id>&tab=decisions&decision=<id>`

Browser back and forward restore list/detail state. Closing a detail view restores focus to its source row.

### Project Switcher

The sidebar switcher displays the active organization and project. It supports:

- authorized organization grouping;
- project search when needed;
- lifecycle and health labels without color-only meaning;
- keyboard navigation;
- loading and unavailable states;
- dirty-edit confirmation before switching;
- stable selection after reload.

### Overview

The overview answers:

- What is this project trying to achieve?
- Who owns it?
- Is it on track?
- What milestone is next?
- What is blocked?
- Which risks need review?
- Which decisions await action?
- What changed recently?

It uses a calm project header, a compact milestone path, operational registers, and recent activity. It avoids a generic grid of interchangeable metric cards.

### Milestones

Desktop uses a milestone register with a persistent detail pane. Rows show outcome, owner, lifecycle, planned date, progress, and overdue or blocked state.

The detail pane places progress, acceptance criteria, checkpoint notes, review history, and the next valid action together.

Mobile uses a full-width register and focused detail screen. Controls retain at least 44px targets and do not require horizontal page scrolling.

### Blockers & Risks

One local workspace houses two semantically distinct registers. Filters include owner, severity or score, lifecycle, overdue state, and escalation.

Blocker details emphasize age, operational impact, resolution ownership, and the next action. Risk details emphasize probability, impact, trigger, mitigation, and review cadence.

### Decisions

The decision workspace presents:

- lifecycle and review state;
- statement and alternatives;
- rationale and impact;
- supporting evidence;
- contradictory evidence;
- limitations and provenance;
- review history;
- immutable approved snapshot.

Supporting and contradictory evidence use parallel hierarchy. Contradictory evidence is not visually diminished.

### Today Integration

Today remains personal and role-adaptive rather than becoming a duplicate project dashboard.

- Intern views prioritize assigned project actions.
- Administrator views prioritize reviews, escalations, and project health exceptions.
- Project items coexist with current task, research, relationship, EOD, and collaboration priorities.

## Visual Direction

This is a product workspace used during sustained daytime operations, often on ordinary office displays and mobile devices. Warm light surfaces remain primary, with complete dark mode for lower-light work.

The design follows the existing restrained system:

- orange for primary actions and active selection;
- teal for verified progress and resolved outcomes;
- rose for active risk and blocker severity;
- blue for information and review context;
- warm tinted neutrals for structure;
- gold only where an earned governance or momentum state warrants it.

State always includes text or symbols and never relies on color alone. The interface reuses existing buttons, forms, tables, badges, drawers/detail panes, notices, progress, navigation, and focus treatments.

The design avoids:

- decorative card grids;
- nested cards;
- modal-first CRUD;
- gradient text;
- glassmorphism;
- side-stripe accents;
- display typography in controls;
- decorative motion;
- unsupported predictive or AI-generated project conclusions.

## Authorization and Security

Every new operational table includes organization and project scope and enables RLS.

Access requires:

- an authenticated user;
- a confirmed Auth account;
- an active profile;
- completed password establishment;
- active organization membership;
- active project membership or administrator authority;
- lifecycle-appropriate source access.

Mutations use narrow RPCs with:

- server-derived actor and scope;
- explicit transition validation;
- expected revision or timestamp;
- row locking for consequential transitions;
- idempotency nonces for retryable operations;
- empty search paths for privileged functions;
- explicit grants and revocations;
- append-only history writes in the same transaction.

Browser clients never receive service-role credentials or unrestricted source rows.

## Error and Conflict Handling

- Validation errors identify the field and required correction.
- Authorization failures do not reveal whether an inaccessible record exists.
- Stale writes return a conflict and preserve the local draft for reconciliation.
- Retryable mutations reconcile idempotency keys before creating another write.
- Post-commit refresh failure is shown as a reconciliation warning, not a failed mutation.
- Project context failure blocks dependent snapshots rather than mixing data from different contexts.
- Failed inbox projection remains visible as a reconciliation item to administrators.
- Approved snapshots never enter an editable state.
- Archival blockers explain the unresolved records preventing archival.

## Preservation and Migration

The migration is additive and preservation-safe.

- Existing organization and project IDs remain stable.
- Existing project rows are extended in place.
- Existing records are not silently assigned to a different project.
- Existing users are not granted broad project access through backfill.
- Current single-project users may receive explicit membership matching their already-authorized project only when that mapping is deterministic and verified.
- Ambiguous memberships require administrator resolution.
- Existing tasks, research, EOD, chat, CRM, survey, consent, and Gate histories remain unchanged.
- Existing inbox, comment, follower, mention, and handoff records remain valid.
- No seed or migration resets passwords or collected data.

## Testing Strategy

### Domain Tests

- Context selection and dirty-switch decisions.
- Risk score calculation.
- Lifecycle transition matrices.
- Required notes, rationale, acceptance criteria, and evidence.
- Role-adaptive queue derivation.
- Stable route resolution.

### PostgreSQL Execution Tests

- Fresh migration execution in timestamp order.
- Representative populated upgrade preserving identity and scope.
- Multi-organization and multi-project isolation.
- Project membership authorization.
- RLS for every new table.
- Milestone submission, revision, approval, and completion.
- Blocker escalation, resolution, and reopening.
- Risk calculation, acceptance, review, and closure.
- Decision submission, revision, approval, rejection, and supersession.
- Snapshot immutability and self-contained evidence projection.
- Consent-ineligible evidence rejection.
- Optimistic concurrency and idempotency.
- Inbox derivation and source-driven resolution.
- Comment, mention, follow, and handoff source authorization.

### Browser Tests

- Project selection and reload persistence.
- Deep links and browser history.
- Desktop list/detail flows.
- 390px and 320px mobile flows.
- Focus trapping where dialogs remain necessary.
- List/detail focus restoration.
- Keyboard-only operation.
- Accessible names, roles, states, and live notices.
- Dark mode, browser zoom, text spacing, and reduced motion.
- No page-level horizontal overflow.
- Strict touched-workflow contrast and 44px target verification.

### Release Verification

- Lint, build, Node tests, PostgreSQL execution tests, and Playwright.
- Migration history inspection.
- Production backup or verified checkpoint.
- Linked dry run showing only intended migrations.
- Migration and Edge Function deployment where applicable.
- Production public and authenticated smoke checks.

## Delivery Sequence

1. Canonical organization and project context.
2. Project membership and project overview contract.
3. Milestone lifecycle and UI.
4. Blocker lifecycle, escalation, and UI.
5. Risk lifecycle, scoring, and UI.
6. Decision lifecycle, evidence links, immutable snapshots, and UI.
7. Collaboration source extensions and role-adaptive inbox.
8. Today integration, responsive/accessibility hardening, and release verification.

Each phase must remain executable and tested before the next phase builds on it.

## Acceptance Criteria

The release is complete when it demonstrates all of the following:

1. Users with multiple authorized projects explicitly select one context, and every snapshot and mutation uses that context.
2. Existing production data retains stable identity, scope, authorship, timestamps, attachments, consent, and lifecycle history.
3. Administrators create and govern projects while interns operate only within explicit project access.
4. Milestones support accountable progress, submission, review, revision, approval, and completion.
5. Blockers expose age, impact, resolution ownership, expected resolution, escalation, and audited resolution/reopening.
6. Risks expose server-calculated probability-impact score, mitigation, review cadence, acceptance rationale, and history.
7. Decisions preserve alternatives, rationale, impact, supporting evidence, contradictory evidence, and immutable approved snapshots.
8. Comments, mentions, follows, handoffs, and inbox actions remain contextual and cannot implicitly approve or complete source records.
9. Today shows role-correct project priorities without duplicating the project workspace.
10. Canonical deep links survive reload and browser navigation on desktop and mobile.
11. Touched workflows meet strict WCAG 2.2 AAA expectations through automated and manual verification.
12. Fresh and populated database tests, full CI, guarded deployment, and production smoke checks pass without unexpected skips or destructive changes.
