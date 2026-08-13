# Relationships Quality Closure

## Goal

Bring the canonical Relationships workspace to release quality across:

- `workspace.html?view=relationships&tab=contacts`
- `workspace.html?view=relationships&tab=recruitment`
- `workspace.html?view=relationships&tab=outreach&section=pipeline`

This pass repairs data integrity and runtime defects, completes the workflows already advertised by these surfaces, and raises accessibility and responsive quality to WCAG 2.2 AA with AAA-level polish where practical. It does not activate the entire historical Outreach roadmap.

## Product Boundary

Relationships remains one workspace with three primary tabs:

1. Contacts
2. Recruitment
3. Outreach

Outreach retains Pipeline, Evidence, and Imports as secondary sections. Contacts remains the canonical relationship identity. Recruitment remains a pre-research prospect workflow. Outreach candidates remain an explicit subset of contacts rather than an automatic side effect of creating any CRM contact.

The following historical roadmap items are out of scope for this closure unless required to make a current workflow truthful: configurable stage administration, meetings, offers, communication-template sending, duplicate-resolution workbenches, bulk actions, and campaign report generation.

## Data Integrity

### Selected Project

Every Relationships snapshot and mutation must resolve the same selected project through the canonical project resolver. Creating or editing a contact, candidate, recruitment prospect, outreach event, or candidate evidence record while project B is selected must never read from or write to project A.

Compatibility RPC names may remain for the current browser API, but their effective implementations must use the selected-project foundation rather than independently selecting the first active project.

### Optimistic Concurrency

Contact and candidate snapshots must include the revision value required by their save contracts. Existing records send that revision on save. A stale revision is rejected without losing local edits and returns an actionable reload path. New records do not require a prior revision.

### Truthful Projections

Operations snapshots must return campaign configuration, summary counts, category coverage, candidates, outreach events, and evidence required by the current interface. Displayed metrics are derived from source records and must not silently fall back to zeros when records exist.

The Contacts activity trail uses the unified relationship activity source so contact and Outreach actions appear in one chronology.

### Contact And Candidate Boundary

Saving a CRM contact does not automatically create an Outreach candidate. The contact editor presents an explicit candidate-creation choice for eligible new contacts. Existing candidate links remain visible and stable.

Candidate snapshots include stable owner identifiers as well as owner labels. Reassignment uses identifiers and is limited by the existing role rules.

### Recruitment Integrity

General recruitment upserts cannot set or replace managed `crm_contact_id` or `respondent_id` links. Those links are created only by the audited respondent-conversion workflow.

Recruitment stage changes follow an explicit transition graph. Terminal records cannot silently reopen, and impossible jumps are rejected with an actionable error. Owner reassignment respects administrator and intern boundaries.

When a converted prospect withdraws consent, the effective respondent consent state and recontact eligibility are updated transactionally with audit provenance. Withdrawal must not delete historical research identity or evidence.

## Shared Navigation

The primary Relationships tab list and Outreach secondary tab list implement complete tab semantics:

- Stable tab and panel IDs
- `aria-controls` and `aria-labelledby`
- One active tab in the keyboard tab order
- Arrow Left and Arrow Right navigation
- Home and End navigation
- Selected state that does not rely on color
- URL and browser-history synchronization

Unknown tab or section values normalize to Contacts or Pipeline. Legacy CRM and Outreach aliases continue to normalize to canonical Relationships routes. Contact deep links continue to force the Contacts tab and restore correctly with browser Back and Forward.

## Contacts Workflow

The oversized introduction becomes a compact task header that preserves the existing warm, rigorous visual language while returning vertical space to the directory.

The directory provides:

- A programmatically labeled search field
- An accessible filter group with pressed state
- Accurate All, Mine, Needs action, and Qualified views
- Direct overdue and due-today text
- Keyboard-operable contact rows
- Helpful loading, empty, and retry states

The contact drawer provides:

- Verified identity and contact fields
- Lifecycle and next-action fields
- Owner selection backed by an owner ID
- An explicit create-Outreach-candidate option where applicable
- Profile completeness guidance
- Unified recent activity and outcome logging
- Scoped saving, success, validation, permission, stale-write, and network states
- Focus containment and restoration

## Recruitment Workflow

The embedded tracker inherits the parent workspace context. In preview mode it uses preview records and local mutations, does not request live authentication, and never redirects to Login. The standalone tracker retains its protected authentication behavior.

Recruitment provides:

- Skeleton or progress feedback during initial loading
- Scoped retry after load failure
- Search and stage filtering
- Keyboard-operable prospect rows
- Responsive record rows at narrow widths
- Administrator owner assignment
- Only valid next-stage choices for existing records
- Preserved local values on failed saves
- Explicit respondent-conversion readiness reasons
- Audited administrator conversion with stable CRM and respondent links
- Clear empty and no-filter-result guidance

The UI continues to state that prospects are not respondents or research evidence until governed conversion succeeds.

## Outreach Pipeline Workflow

The Pipeline presents a compact campaign pulse, explainable recovery recommendations, category coverage, operational filters, and the candidate list without generic dashboard decoration.

The candidate editor completes the fields and actions already supported by the current workflow:

- Identity and category
- Contact route and readiness
- Source and source URL
- Tier and priority
- PMF-candidate rationale
- Owner assignment
- Outreach stage and next action
- Outreach activity kind, channel, status, summary, actor, and timestamp
- Candidate evidence type, title, stance, strength, consent, and notes
- Candidate-specific activity and evidence chronology

Terminal-looking Outreach states must be backed by the corresponding recorded activity or governed evidence rather than direct unsupported status editing.

## Imports And Exports

Candidate import accepts the formats already advertised by the product. It must:

- Reject unterminated quoted fields and structurally malformed rows
- Preserve fields whose headers are omitted
- Distinguish an omitted value from an explicit clear instruction
- Keep errors tied to source row numbers
- Validate safe HTTP and HTTPS source URLs
- Preview changes before writes
- Expose commit controls only to administrators
- Commit atomically through the existing governed RPC boundary

CSV exports remain formula-safe. JSON and CSV exports use the documented portable candidate field set and exclude hydrated internal IDs, private evidence metadata, and unrelated workflow state.

## Failure Handling

Contacts, Recruitment, Pipeline, Evidence, and Imports each own their loading, empty, error, and retry states. A failure in one section must not blank another section or the workspace shell.

Mutations disable only the relevant form or action. Validation and service failures preserve entered values. Notices use `role="status"` or `role="alert"` as appropriate and distinguish:

- Validation failure
- Permission failure
- Stale revision
- Invalid lifecycle transition
- Network or service failure

Preview mode performs no live writes and labels local-only behavior.

## Visual And Responsive Quality

The existing product register remains authoritative: warm paper-like surfaces, restrained orange actions, semantic teal/blue/rose states, Geist Sans with Noto Sans SC, and calm information density.

The interface must:

- Use existing color, spacing, type, button, form, status, panel, and drawer tokens
- Avoid nested decorative cards, glass effects, gradient text, and hero-metric patterns
- Keep every interactive target at least 44 by 44 CSS pixels
- Retain visible focus in light and dark themes
- Meet WCAG 2.2 AA contrast and target 7:1 text contrast where compatible with semantic hierarchy
- Communicate state with text or symbols in addition to color
- Respect reduced motion
- Remain usable under WCAG text-spacing overrides and browser zoom
- Avoid page-level horizontal overflow at 320px and wider

Contacts and Recruitment reflow into structured record rows on narrow screens. Outreach uses local horizontal scrolling only where comparison density requires it. Drawers become full-screen sheets on narrow screens with safe-area padding and reachable sticky actions.

## Component Boundaries

- `crm.js` owns pure route, contact, queue, and relationship-tab behavior.
- `crm-template.js` owns the Relationships shell, Contacts view, and explicit composition of Recruitment and Outreach.
- `participant-tracker.js` and its template own standalone and embedded Recruitment modes without duplicating persistence logic.
- `outreach-template.js` owns Outreach section navigation and section markup.
- `operations.js` owns pure candidate import, export, filtering, and recommendation projections.
- `workspace.js` remains the orchestration layer for the existing workspace controller and shared drawers.
- `api.js` remains the browser persistence boundary.
- One focused Supabase migration repairs effective RPC and projection contracts.

Exact string replacement must not be the only mechanism establishing tab panels, labels, or critical workflow mounting. Changes should be focused to these boundaries rather than refactoring unrelated workspace views.

## Verification

### Database And Contract Tests

Executable tests cover:

- Selected-project isolation for contact, candidate, recruitment, outreach, and evidence writes
- Existing-record saves with valid revisions
- Rejection and recovery of stale revisions
- Managed recruitment-link injection denial
- Recruitment transition rules
- Owner-role boundaries
- Consent withdrawal propagation
- Truthful campaign summaries and category coverage
- Unified relationship activity projection

### Domain Tests

Unit tests cover:

- Needs-action filtering for complete overdue contacts
- Valid Recruitment next-stage helpers
- Legacy and canonical route normalization
- Partial imports preserving omitted fields
- Explicit clear semantics
- Malformed CSV rejection
- Formula-safe CSV exports
- Portable JSON field allowlisting

Every new behavior is introduced with a failing test before its implementation.

### Browser Tests

Playwright covers all three requested routes on desktop, 390px, and 320px viewports:

- Clean console and network behavior
- Preview Recruitment remains embedded and never redirects
- Primary and secondary tab keyboard navigation
- URL normalization and Back/Forward behavior
- Search and filter behavior
- Drawer focus containment and restoration
- Contact, prospect, and candidate create/edit affordances
- Candidate activity and evidence controls
- Empty, loading, validation, error, and retry states
- No page-level horizontal overflow
- Local containment of intentionally wide content
- 44px computed touch targets
- Dark mode, reduced motion, browser zoom, and text-spacing resilience

Final verification runs `npm test`, `npm run lint`, and `npm run test:e2e`, followed by a focused diff review and visual comparison.

## Delivery Constraints

- Preserve unrelated user and agent changes already present in the worktree.
- Do not deploy, commit, or alter production data as part of implementation unless separately requested.
- Do not broaden research evidence visibility, respondent access, or role permissions.
- Do not claim completion if database execution tests or browser checks are unavailable; report the unverified boundary explicitly.
