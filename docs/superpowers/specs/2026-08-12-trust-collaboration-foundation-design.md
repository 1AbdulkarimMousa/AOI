# AOI Trust and Collaboration Foundation Design

Date: 2026-08-12
Status: Approved design
Inputs: `summary.md`, `131.md`, `PRODUCT.md`, `DESIGN.md`, and `docs/quality/audit-matrix.md`

## Purpose

The first Business OS expansion tranche will make AOI trustworthy, role-adaptive, and collaborative before introducing the broad object catalog described in `131.md`. It will repair release-blocking execution and authorization defects, make Today an actionable role-specific workspace, and establish one contextual collaboration contract that future projects, suppliers, finance, assets, portals, and other business objects can reuse.

This tranche must preserve all existing collected data. It must not destructively replace, truncate, reseed, or silently reinterpret historical operational or research records.

## Product Direction

AOI remains an evidence-first research operations product while gaining a reusable Business OS foundation. The immediate product promise is:

> Every user sees the work that requires their attention, every action remains attached to its source record, and every consequential change is authorized, traceable, and recoverable.

The tranche prioritizes current roles: organization owner, administrator, and intern. The architecture may support future roles, but manager, member, contractor, customer, and supplier experiences are outside this tranche.

The primary collaboration surface is a contextual work inbox. Chat remains available for conversation but does not become the authoritative workflow or audit record.

## Scope

### Included

- Repair release-blocking migration, survey, authorization, consent, Gate, and identity-integrity defects required by the collaboration workflows.
- Establish one explicit authenticated organization and project context for touched APIs and views.
- Add role-adaptive Today priorities and actions for owners, administrators, and interns.
- Add a persisted contextual work inbox.
- Add a shared collaboration contract for comments, mentions, watchers, assignments, handoffs, activity history, and deep links.
- Expose administrator task review and intern revision workflows.
- Represent failures, stale writes, uncertain commits, and reconciliation requirements honestly.
- Bring all touched authenticated workflows to strict WCAG 2.2 AAA conformance.
- Add executable database, Edge Function, browser, accessibility, and data-preservation verification.
- Sanitize bundled public preview fixtures without changing live collected data.

### Excluded

- The complete universal object, workflow builder, finance, procurement, field service, asset, IoT, portal, marketplace, and integration catalog in `131.md`.
- New broad account-role catalogs.
- Chat-first workflow orchestration.
- Automated email, social, or WhatsApp delivery without a real provider and confirmation path.
- A platform-wide WCAG AAA claim before untouched surfaces complete the same audit.
- Destructive cleanup of historical data.

## Architecture

### Execution Integrity

The current platform cannot safely support new modules until its effective backend executes reliably. The tranche will:

- Make every migration apply successfully to a fresh disposable database.
- Make the effective workflow functions executable without brittle function-definition rewriting.
- Correct first-time public survey submission while preserving idempotent replay.
- Reject invalid invitation states during replay.
- Apply active organization, membership, profile, confirmation, and password-state predicates consistently.
- Prevent unauthorized peer administrator and owner credential operations.
- Prevent managed recruitment and respondent identity links from caller injection.
- Propagate post-conversion consent withdrawal to the respondent consent model.
- Exclude consent-ineligible evidence from authoritative PMF and Gate inputs.
- Restore valid administrator access to Gate creation.

The implementation must address effective behavior through new forward-only migrations and source changes. Historical migration files remain immutable.

### Canonical Active Context

Touched workflows will use one explicit active organization and project context rather than independently selecting qualifying rows. Context resolution must:

- Validate membership, organization, profile, email, and password lifecycle state.
- Return stable organization and project identifiers.
- Reject inaccessible requested contexts.
- Never silently transfer or reinterpret records between scopes.
- Preserve the selected context in stable URLs where safe.
- Provide a deterministic default only when exactly one valid choice or an explicitly ordered existing preference exists.
- Report ambiguous legacy context for user selection rather than guessing.

A full organization/project switcher may be delivered incrementally, but no touched data API may mix independently selected contexts.

### Contextual Work Inbox

The inbox consolidates actionable collaboration state without replacing source workflows. Inbox records contain:

- Organization and project scope.
- Recipient and optional recipient role.
- Source object type and stable source identifier.
- Deterministic event or deduplication key.
- Category: action, waiting, mention, following, resolved, or system attention.
- Reason and concise accessible summary.
- Priority and due state.
- Actor, requester, owner, and assignee where applicable.
- Read, snoozed, resolved, and created timestamps.
- Stable deep link and permitted source actions.

Inbox generation must be deterministic and safe to rerun. Source workflow actions remain authoritative. Marking an item read or resolved must not approve, submit, archive, or otherwise mutate its source object unless the user invokes an explicit authorized source action.

An inbox item resolves automatically when its underlying condition no longer applies. Historical resolution remains available for audit and recent-work context.

### Shared Collaboration Contract

Tasks, research, surveys, recruitment, EOD, and future business objects use consistent collaboration primitives:

- Contextual comments.
- Person mentions.
- Watchers or followers.
- Assignment and reassignment.
- Reasoned handoff.
- Append-only activity events.
- Stable deep links.
- Persisted reconciliation attention.

Each collaboration record carries organization, project, source object, actor, and timestamps. Authorization derives from access to the source record plus the specific action permission. A mention cannot grant access to a record the recipient cannot otherwise read.

Comments may be edited only through an auditable revision path. Deletion follows existing moderation and retention policy and must not silently remove required decision or workflow evidence.

## Role-Adaptive Today

Today opens on work requiring the current user's attention instead of generic metrics. Role adaptation changes priority, scope, explanations, and available actions.

### Organization Owner

The owner sees:

- Administrator and ownership governance actions.
- Security and authorization reconciliation.
- Consent and data-integrity risks.
- Escalated blockers and unresolved high-impact handoffs.
- Organization-level workload and operational health.
- Actions requiring owner-only authority.

### Administrator

Administrators see:

- Submitted tasks requiring approval or revision.
- Submitted research and survey review queues.
- Assignment and handoff requests.
- Recruitment and EOD attention.
- Team blockers, overdue next actions, and capacity risks.
- Items requiring owner escalation.

### Intern

Interns see:

- Assigned work ordered by urgency, dependency, and due state.
- Revision requests with reviewer guidance.
- Mentions and incoming handoffs.
- Approaching deadlines and unresolved blockers.
- Draft research or survey work requiring completion.
- Exact acceptance and submission criteria.

### Inbox Views

The inbox supports stable, deep-linkable views:

- Needs action.
- Waiting on others.
- Mentioned.
- Following.
- Recently resolved.
- System attention.

Filters and counts must use authorized persisted state rather than bundled fake records.

## Core Workflow Changes

### Task Review

Tasks retain the existing lifecycle. The tranche exposes authoritative administrator actions for submitted work:

- Approve with optional review note.
- Request revision with required actionable guidance.
- Complete approved work when the lifecycle requires a separate completion step.

Interns can edit the permitted checkpoint fields and resubmit revision-requested work. Stored expected hours and acceptance criteria appear in the task view. XP follows the explicitly verified completion policy selected during implementation and must not be awarded merely because an assignee bypasses review.

Task mutations use row locking or expected revisions so concurrent checkpoints cannot overwrite terminal state.

### Research Revision

Existing drafts hydrate into the correct editor using their stable IDs. Authorized assignees can update drafts and revision-requested records without creating duplicate source records. Resubmission requires the latest revision and preserves prior review guidance and activity history.

Server-side validation is authoritative for submitted records. Browser validation improves usability but cannot define integrity alone.

### Survey Submission And Review

First submission attempts normal authoritative submission when no completed idempotent replay exists. A valid replay returns the original committed result. Revoked, bounced, expired, mismatched, or otherwise invalid invitations cannot replay.

Intern survey recommendations require an explicit assignment path. Ordinary public submissions cannot appear in an intern queue until assigned through an authorized action or deterministic configured rule.

### Consent And Gates

Consent withdrawal remains append-only and preserves history. It restricts future sensitive access and authoritative analysis. Gate creation snapshots only approved, consent-eligible material and stores enough self-contained provenance to explain the decision after mutable labels or calculations change.

## Existing Data Preservation

### Non-Destructive Migration Policy

All schema changes are additive and forward-only unless a destructive operation receives separate explicit approval. The implementation must not:

- Truncate operational tables.
- Replace collected records with seed data.
- Regenerate stable record IDs.
- Rewrite original authorship or timestamps.
- Move records between organizations or projects automatically.
- Delete consent history, evidence, survey versions, responses, attachments, chat history, EOD history, tasks, or audits.
- Convert ambiguous historical values silently.

New constraints apply to future writes only when existing valid history cannot satisfy them. Historical lifecycle values remain readable. Where legacy records need normalization, the migration records original and normalized values or produces an administrator resolution queue.

### Backfill Rules

Inbox backfills include only qualifying unresolved conditions. Every derived item uses a deterministic key based on source record, condition, recipient, and relevant revision so rerunning the backfill cannot duplicate items.

Backfills must:

- Operate in bounded batches where volume warrants it.
- Preserve source rows unchanged.
- Record counts and failures.
- Be restartable.
- Quarantine ambiguous records for review.
- Avoid generating notifications for already resolved historical work.

### Preview Data

Bundled preview and fallback fixtures will be replaced with synthetic, anonymous records. This sanitization applies only to public static fixtures. Live or collected data must not be anonymized, deleted, or replaced as part of preview cleanup.

### Backup And Verification

Before production application, create and verify a restorable backup or database checkpoint. Migration verification compares pre-change and post-change:

- Row counts by canonical table and scope.
- Stable IDs.
- Foreign-key relationships.
- Original authorship and timestamps.
- Survey assets, versions, links, submissions, and answers.
- Respondents, consent history, sessions, evidence, and observations.
- Tasks, checkpoints, EOD records, chat, attachments, and audits.
- Storage metadata and sampled signed access.

Rollback is performed by restoring the verified backup, not by relying on destructive down-migrations.

## UI And Interaction Design

### Information Architecture

The existing sidebar, top bar, route hierarchy, theme, and bilingual structure remain. Today places the inbox first, followed by role-relevant operational context. It does not become a grid of decorative metrics.

Desktop uses a list-detail workspace with an inbox list and contextual detail surface. Mobile uses a focused list-to-detail navigation flow. Record detail combines:

- Source context and workflow state.
- Required next action.
- Owner, assignee, requester, due state, and priority.
- Acceptance criteria or review guidance.
- Evidence and attachments.
- Contextual discussion.
- Recent activity and history.
- Authorized actions.

Filters, selected records, and tabs use stable URL state. Browser history and deep links restore the same authorized context.

### Collaboration Interaction

- Mention controls expose names, roles, and enough context to avoid selecting the wrong person.
- Handoffs require a recipient, reason, and summary of unresolved work.
- Comment drafts remain scoped to the source record.
- Network retry retains the original nonce and uploads to prevent duplicates.
- Notifications explain why the recipient received them.
- Destructive or consequential actions show their effect before confirmation.
- Stale edits provide compare, reload, and retry choices.
- Empty states explain the queue and available next action.
- Loading uses stable skeletons rather than layout-shifting spinners.

### Visual Language

The UI follows `DESIGN.md`:

- Warm tinted light surfaces and a complete dark theme.
- Restrained orange primary action with semantic teal, blue, rose, gold, and purple roles.
- Geist Sans with Noto Sans SC and system fallbacks.
- Familiar controls with consistent default, hover, focus, active, disabled, loading, and error states.
- Calm information density without nested decorative cards.
- Motion limited to meaningful 150 to 250 millisecond state changes and disabled where reduced motion requires it.

## WCAG 2.2 AAA Requirements

Strict WCAG 2.2 AAA is a release requirement for touched authenticated workflows. The product must not claim platform-wide AAA until untouched surfaces pass the same audit.

Touched workflows require:

- Text contrast of at least 7:1 and large-text contrast of at least 4.5:1.
- Strong, visible, unobscured keyboard focus.
- Complete keyboard operation without timing-dependent input.
- Pointer targets at least 44 by 44 CSS pixels.
- Correct landmarks, headings, labels, descriptions, tables, and live regions.
- Text or semantic symbols in addition to color for every state.
- Correct page and fragment language metadata for English and Simplified Chinese.
- Contextual instructions and help for unfamiliar actions.
- Error identification, explanation, preservation, and correction guidance.
- Review and confirmation for consequential submissions and destructive actions.
- Concise status announcements without unexpected focus movement.
- Security timeout warning and extension where extending is safe.
- Authentication compatible with password managers and without unnecessary cognitive-function tests.
- Functional 320 CSS pixel reflow, 200 percent zoom, and supported text-spacing overrides.
- Reduced-motion-safe interaction.
- Consistent help placement and accessible support paths.

Automated accessibility tools are supporting evidence only. Release verification includes keyboard-only operation, screen-reader testing, zoom, text spacing, high-contrast review, and both supported languages.

## Reliability And Error Handling

- Retryable mutations use stable idempotency keys.
- Stale writes return enough current and attempted state for comparison.
- Partial privileged failures create persisted reconciliation items.
- Loading, empty, offline, denied, stale, uncertain, and failed states remain distinct.
- Notifications never imply source success without authoritative confirmation.
- Errors expose safe messages and diagnostic identifiers without leaking sensitive database details.
- Inbox derivation and reconciliation workers are idempotent.
- Realtime updates enhance responsiveness but do not replace durable state.
- Optimistic collaboration writes retain their nonce until commit status is certain.

## Testing Strategy

### Database And Migration

- Apply all migrations to a fresh disposable database.
- Apply the upgrade to a representative database containing existing collected data.
- Verify preservation checks and referential integrity before and after.
- Execute authorization matrices for owner, administrator, intern, archived, inactive, forced-password, unconfirmed, and cross-organization users.
- Execute consent withdrawal, Gate creation, task review, research revision, survey submission/replay, mention, handoff, and inbox-resolution workflows.
- Test concurrent mutations and stale revision rejection.

### Edge Functions

- Test allowed and denied origins.
- Test missing, invalid, expired, and wrong-role authentication.
- Test partial-failure reconciliation.
- Test first survey submission and valid and invalid replay paths.
- Test public error normalization and body limits.

### Frontend And Browser

- Run lint, unit/static tests, production build, executable backend tests, and Playwright.
- Cover desktop, tablet, Pixel-class mobile, and 320-pixel layouts.
- Cover owner, administrator, intern, anonymous survey, and invited survey sessions.
- Test deep links, browser history, offline transitions, network ambiguity, and two-tab concurrency.
- Test light and dark themes, English and Chinese, reduced motion, 200 percent zoom, text spacing, keyboard-only operation, and screen readers.
- Scan source, bundles, screenshots, and public fixtures for credentials and identifiable preview data.

## Release Gates

This tranche cannot ship with:

- A critical or high-severity defect in a touched workflow.
- A failed fresh migration or representative-data upgrade.
- Lost, duplicated, silently re-scoped, or silently reinterpreted collected data.
- Cross-tenant or unauthorized record access.
- Consent-ineligible evidence in authoritative analysis or new Gate snapshots.
- Unexpected skipped release E2E tests.
- A broken keyboard path or unmet AAA success criterion in touched workflows.
- Placeholder actions, fake persisted notifications, or unsupported delivery claims.
- An unverified backup restoration procedure.

## Delivery Phases

### Phase 1: Trust Baseline

- Repair migration execution.
- Repair survey submission and replay.
- Harden authentication, target authorization, identity integrity, and consent propagation.
- Establish canonical context for touched workflows.
- Add representative-data migration preservation harnesses.

### Phase 2: Authoritative Workflows

- Add administrator task review and concurrency protection.
- Add research draft edit and revision resubmission.
- Add explicit intern survey-review assignment.
- Repair Gate authorization and self-contained consent-eligible snapshots.

### Phase 3: Collaboration Foundation

- Add inbox persistence and deterministic derivation.
- Add comments, mentions, followers, handoffs, and activity contracts.
- Add persisted reconciliation items.
- Backfill only unresolved qualifying work.

### Phase 4: Role-Adaptive Today

- Replace fake notification state.
- Deliver owner, administrator, and intern inbox priorities.
- Add list-detail and mobile workflows, stable URLs, and accessible source actions.

### Phase 5: AAA And Release Gauntlet

- Consolidate shared accessible controls.
- Complete responsive, theme, bilingual, keyboard, screen-reader, zoom, and text-spacing repairs.
- Anonymize public preview fixtures.
- Run the full release and data-preservation gate.

## Future Extension

After this foundation is release-green, the next Business OS tranche should add a project operating core: projects, milestones, dependencies, blockers, risks, decisions, workload, and role-specific project views. Those objects will reuse the context, ownership, lifecycle, collaboration, inbox, evidence, and audit contracts established here.

The broader universal object and workflow platform in `131.md` remains a strategic direction, not an immediate implementation requirement.

## Acceptance Criteria

The design is complete when implementation can demonstrate that:

1. Existing collected data survives the upgrade with verified stable identity, scope, relationships, authorship, timestamps, and lifecycle history.
2. Every migration applies on a fresh database and upgrades a representative populated database.
3. Owner, administrator, and intern receive different authorized Today priorities from one durable collaboration model.
4. Inbox actions deep-link to their source and cannot falsely mutate source workflow state.
5. Task review, research revision, survey submission/replay, consent withdrawal, and Gate creation execute end to end.
6. Mentions, handoffs, comments, follows, activity, and reconciliation are contextual, auditable, and idempotent.
7. Touched workflows satisfy strict WCAG 2.2 AAA through automated and manual verification.
8. Release tests have no unexpected skips and no critical or high findings in touched workflows.
