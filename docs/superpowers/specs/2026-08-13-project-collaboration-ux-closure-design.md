# Project Collaboration UX Closure Design

**Date:** 2026-08-13
**Status:** Approved for implementation planning
**Source context:** `summary.md`, `131.md`, `PRODUCT.md`, `DESIGN.md`, the Trust and Collaboration Foundation, and the Project Operating Core

## Purpose

Close the gap between AOI's authoritative collaboration backend and its daily project experience. Milestones, blockers, risks, and decisions already support contextual comments, revisions, mentions, follows, reasoned handoffs, activity, and derived inbox items. The project interface does not expose those capabilities directly, while Today still asks users for raw UUIDs and cannot represent a complete follow or conversation state.

This slice makes collaboration usable beside the work it concerns. It does not create another chat system, replace source lifecycles, or introduce the universal business-object registry described as a long-term possibility in `131.md`.

## Product Outcome

An authorized project member can open a milestone, blocker, risk, or decision and:

- understand the current conversation without leaving the record;
- add a contextual comment and mention authorized collaborators;
- inspect whether a comment was edited and review its revision trail;
- follow or unfollow future changes;
- hand unresolved work to an authorized person by name, with required context;
- see clear success, retry, stale, and authorization states;
- complete every collaboration action with a keyboard and at narrow viewport widths.

Today remains a role-adaptive triage surface. It presents a compact form of the same collaboration state and sends users to the source record for full context.

## Guiding Decisions

1. Project records are the primary collaboration surface.
2. Project records and Today share one frontend collaboration behavior model but render it at different densities.
3. Existing collaboration tables and RPCs remain authoritative.
4. Collaboration actions never approve, complete, resolve, reject, or otherwise transition the source record.
5. Recipient filtering in the browser improves usability but never replaces server authorization.
6. Important failures and uncertain commits remain visible and retryable.
7. This work targets strict WCAG 2.2 AAA acceptance for the touched workflows without claiming platform-wide conformance.
8. Preview fixtures touched by this work use clearly synthetic people and organizations.

## Current Gap

The backend contract in `20260812101805_contextual_work_inbox.sql` supports comments, comment revisions, mentions, follows, and reasoned handoffs. `20260812141620_project_operating_core.sql` connects project records to that contract and project detail responses already include comments.

The current browser experience remains incomplete:

- `projects-template.js` does not render project comments or collaboration controls;
- `inbox-template.js` requests a handoff recipient UUID;
- the inbox comment form cannot select mentions;
- Follow updates always writes `true` and cannot unfollow;
- comment revision RPC support has no browser API or interface;
- existing comments are not visible in the selected Today item;
- project member addition requests an organization member ID;
- preview project data contains identifiable or operational-looking names and brands.

## Experience Architecture

### Shared Collaboration Model

Add a focused frontend module that owns collaboration presentation state and pure transformations. It normalizes:

- source type and source ID;
- authorized active collaborators;
- comments and comment authors;
- edited and revision metadata;
- selected mention recipients;
- current-user follow state;
- handoff recipient and reason;
- stable mutation nonces;
- loading, success, retry, stale, and access-denied notices.

The module does not own source lifecycle state. Project and Today controllers call existing API functions through this model and refresh their authoritative source projections after successful mutations.

### Full Project Presentation

The project record detail pane adds a **Collaboration** section after record content, evidence, snapshots, and review history, but before lifecycle controls. This ordering keeps discussion close to its context while preserving a visible boundary between collaboration and authoritative transitions.

The section contains:

1. A compact header with conversation count and Follow or Unfollow.
2. A chronological thread with author, role where useful, timestamp, body, edited state, and revision access.
3. An empty state that explains what belongs in a contextual comment.
4. A comment composer with a multi-select mention control populated from eligible project members.
5. A reasoned handoff form with a named recipient selector and required reason.
6. Inline status and retry controls.

The interface must not use raw user IDs. IDs remain values behind human-readable controls.

### Compact Today Presentation

The selected Today item uses the same normalized state and mutation behavior, with a smaller presentation:

- current Follow or Unfollow state;
- the latest relevant comments with a link to full history;
- a comment composer with the same mention selector;
- the same named handoff selector;
- an explicit Open source record primary action.

Today does not duplicate comment revision editing. It links to the source record for full thread governance.

### Project Membership Repair

Project configuration replaces the organization-member UUID input with an eligible organization-member selector. The selector displays name and role and excludes people who cannot be activated in the project. Responsibility remains required.

## Interaction Details

### Comments

- Comments are displayed oldest to newest so the thread reads naturally.
- The newest activity remains visible after a successful add without forcing page navigation.
- Empty or whitespace-only comments are rejected in the browser and server.
- A successful mutation clears the body and mention selection only after authoritative confirmation.
- An uncertain commit preserves the body, selections, and nonce and offers Retry and Refresh.
- Comment revision is available only where the current authorization contract allows it.
- Revision access shows previous content, revision author, reason, and timestamp without replacing current content.

### Mentions

- The picker includes only active authorized collaborators returned by the source projection.
- The current user may be omitted because self-mention creates no useful notification.
- Selection is keyboard-operable and exposes selected names as removable tokens or equivalent standard controls.
- The submitted payload contains user IDs, but the interface never asks users to read or enter them.
- If authorization changes before submission, the server rejection is presented as an actionable recipient error and the draft remains intact.

### Follow State

- The control label always describes the next action: Follow or Unfollow.
- The current state is available to assistive technology through text and pressed state where appropriate.
- A failed toggle restores the prior visual state and announces the failure.
- Following affects derived inbox behavior only; it does not change source ownership or lifecycle.

### Handoffs

- Recipient options include active authorized collaborators other than the current user.
- The reason requires at least 12 meaningful characters, matching the existing server contract.
- Copy explains that a handoff transfers expected follow-up, not ownership or approval authority unless the source lifecycle separately changes it.
- The handoff remains auditable and creates the appropriate derived inbox item.
- Duplicate nonce retries must not create duplicate handoffs.

### Comment Revision

- The user starts revision from the comment's actions.
- Editing occurs inline in the thread rather than in a modal.
- A revision reason is required.
- Cancel restores the current authoritative text.
- Saved revisions refresh the comment and its revision metadata.

## Data Contract

Existing collaboration tables remain the source of truth. A forward-only migration may extend project and inbox source-detail projections to return the minimum presentation data needed:

- `comments[]` with stable ID, body, author ID, author display name, created time, edited time, and revision count;
- `isFollowing` for the current user;
- `eligibleCollaborators[]` with user ID, display name, role, and active state;
- recent handoff state when it helps explain why the current item exists;
- revision details through an authorized narrow RPC or an existing detail response.

The implementation should prefer extending existing detail RPCs over adding a broad generic endpoint. It must not expose organization members who lack source access.

## Authorization

Server rules remain authoritative for every read and mutation:

- source access is checked for the caller;
- mention and handoff recipients must be active and authorized for the source project;
- cross-organization and cross-project recipients are rejected;
- inactive profiles or memberships are rejected;
- comment revision follows authorship and administrative rules already defined by the collaboration contract;
- collaboration cannot invoke source lifecycle transitions;
- service-role behavior remains explicit and is not granted to ordinary clients.

Browser option filtering is a usability feature only. Tests must prove that crafted requests cannot bypass server checks.

## Failure And Reconciliation

Every mutation distinguishes:

- validation failure;
- authorization or stale-recipient failure;
- known server rejection;
- network failure before commit;
- uncertain commit after request dispatch;
- confirmed success.

Retryable comment and handoff mutations retain their original nonce. The interface must not claim success until the authoritative response or refresh confirms it. Refresh reconciles the collaboration thread, follow state, source detail, and affected Today bucket.

Notices use inline `role="status"` or `role="alert"` semantics according to urgency. Focus stays in the user's workflow unless an error summary or conflict requires action.

## Accessibility Acceptance

The touched collaboration workflows target WCAG 2.2 AAA where applicable:

- all actions are keyboard complete with logical focus order;
- visible focus is at least as distinguishable as the existing product focus treatment;
- interactive targets are at least 44 by 44 CSS pixels where spacing does not provide an equivalent target area;
- names, roles, follow state, edited state, errors, and selection state do not depend on color;
- controls have programmatic names, descriptions, and state;
- status changes are announced without moving focus unnecessarily;
- thread reading order matches visual order;
- text and non-text contrast are verified in light and dark themes;
- content reflows at 320 CSS pixels and at 200% zoom without hidden actions or horizontal page scrolling;
- text remains usable with WCAG text-spacing overrides;
- reduced-motion preferences are respected;
- mention selection, revision editing, and handoff completion are usable with screen readers;
- closed drawers or panels are not focusable or exposed as active content.

Automated tests support but do not replace manual keyboard, screen-reader, zoom, forced-color, and contrast verification. The release evidence must state which manual checks were completed and list residual gaps.

## Privacy-Safe Preview

Touched project and inbox previews must use obviously synthetic data:

- fictional organization and project names;
- fictional people not derived from employees, customers, or research participants;
- non-sensitive scenarios;
- a persistent Preview only label;
- no mutation against live services.

Examples should demonstrate supporting and contradictory evidence without implying medical, clinical, or externally delivered conclusions.

## Testing Strategy

Implementation follows red-green-refactor.

### Unit And Contract Tests

- normalize comments, collaborators, revisions, and follow state;
- preserve nonces across retryable failures;
- clear drafts only after confirmed success;
- generate Follow and Unfollow behavior from authoritative state;
- exclude current, inactive, and unauthorized recipient options;
- preserve source lifecycle state after collaboration actions;
- verify project and Today templates expose names rather than raw-ID inputs;
- verify synthetic preview fixtures.

### PostgreSQL Execution Tests

- authorized project members can comment and mention an eligible member;
- inactive, cross-project, and cross-organization recipients are rejected;
- duplicate comment and handoff nonce replay is idempotent;
- follow and unfollow both persist and derive the expected inbox state;
- comment revision preserves earlier content and audit metadata;
- collaboration does not transition the source record;
- detail projections do not leak ineligible collaborators or comments.

### Browser Tests

- administrator and intern can use the allowed project collaboration actions;
- project record thread and Today compact state reconcile after mutations in preview or controlled fixtures;
- keyboard-only comment, mention, follow, revision, and handoff paths work;
- focus remains predictable when opening and closing record details;
- 320px and mobile layouts expose all actions without page overflow;
- dark mode, text spacing, reduced motion, and status announcements remain usable;
- no raw UUID entry is visible in touched workflows.

### Release Commands

Run at minimum:

```bash
npm run lint
npm test
npm run test:e2e
```

If the linked Supabase environment is available, apply migrations only after a verified backup or checkpoint and run authenticated owner, administrator, and intern smoke tests against matching frontend and backend revisions.

## Documentation Repair

Update documentation with the implementation:

- mark repaired August 9 and August 10 findings as superseded rather than deleting their history;
- document Projects and the durable work inbox in `README.md`;
- distinguish repository-tested behavior from deployed-production verification;
- record touched-flow accessibility evidence without claiming platform-wide AAA;
- retain unresolved security rotation and production migration verification as operational blockers until independently confirmed.

## Out Of Scope

- source lifecycle redesign;
- chat replacement or chat-thread synchronization;
- programs and portfolios;
- task dependency scheduling, lead/lag, critical path, float, or baselines;
- workload and capacity planning;
- email, WhatsApp, or telephony delivery;
- procurement, finance, field service, assets, or resource-rate management;
- generic custom objects, generic workflow builders, or a universal polymorphic registry;
- a platform-wide WCAG 2.2 AAA conformance claim.

## Prioritized Platform Roadmap After This Slice

The following sequence reconciles `summary.md` with the strategic breadth of `131.md`.

### P0: Release Trust

1. Verify credential rotation and revocation described by the security runbook; repository changes cannot prove external revocation.
2. Verify the linked Supabase migration history, create a restorable checkpoint, apply outstanding migrations in order, and prove frontend/backend revision parity.
3. Run authenticated owner, administrator, intern, and public-survey smoke tests without silent environment skips.
4. Reconcile and republish the quality audit matrix based on executable evidence.

### P1: Complete Existing Product Promises

1. Finish project collaboration UX through this design.
2. Resolve remaining survey gaps: secure embed policy, hidden-field configuration, coding workflow, true cross-tabs, QR generation, and reviewer assignment.
3. Implement or remove placeholder reports for PMF, recruitment, and workload.
4. Enforce recruitment lifecycle transitions server-side.
5. Complete bilingual copy and language metadata coverage.

### P2: Project Execution Expansion

Design dependencies and workload as separate approved slices:

- finish-to-start and related dependency types;
- explicit blocker/dependency distinction;
- team capacity, allocation, workload, and availability;
- role-adaptive personal and manager views;
- only then consider Gantt, baselines, critical path, and scenario planning.

### P3: Controlled Business OS Expansion

Select typed domains based on demonstrated operational need rather than implementing all 246 capabilities at once. Likely candidates are documents and executable SOPs, external communication delivery, commercial pipeline, procurement, and resource management. Each domain needs its own object model, authorization contract, lifecycle, audit history, accessibility acceptance, and release plan.

### P4: Platform Extensibility

Generic object, workflow, dashboard, portal, API, and low-code builders should follow repeated typed-domain evidence. They should not precede stable patterns for authorization, lifecycle transitions, evidence, history, retries, and accessible interaction.

## Success Criteria

This slice is complete when:

1. Project records display and mutate contextual collaboration without leaving the record.
2. Today uses the same collaboration behavior in a compact triage presentation.
3. Users never enter raw member IDs for mentions, handoffs, or project membership.
4. Follow and unfollow both work from authoritative state.
5. Comment revisions are visible and auditable.
6. Unauthorized recipients remain unavailable in the UI and rejected by the server.
7. Retry and uncertain-commit behavior preserves user work and prevents duplicates.
8. Collaboration never changes source lifecycle state.
9. Touched workflows pass automated tests and documented manual AAA checks.
10. Touched preview data is clearly synthetic.
11. Documentation separates repaired findings, residual risks, and production verification.
