# Outreach Operations Suite Design

## Goal

Give administrators and interns one reliable place to research contacts, prepare and log outreach, manage follow-ups, and understand campaign progress. CRM and Outreach remain distinct workflows while editing one canonical contact identity and one activity history.

## Delivery Strategy

Deliver the suite through four independently reviewed and deployed releases:

1. Trustworthy data foundation: normalize contact and workflow data, link every candidate to CRM, repair evidence privacy, unify activity history, and expose transactional RPCs.
2. Dedicated page and data portability: add `outreach.html`, role-neutral routing, focused browser modules, complete record editing, import preview/commit, exports, and contextual guidance.
3. Complete operations workflow: add configurable stages and transitions, follow-ups, meetings, offers, communication preferences, duplicate resolution, and administrator bulk actions.
4. Analytics and hardening: add event-derived metrics, transparent definitions, Markdown reports, accessibility review, responsive polish, and complete operational procedures.

Each release must pass database role tests, browser tests, build, lint, review, migration verification, and live deployment checks before the next release begins.

## Page Architecture

Add a genuine role-neutral `outreach.html` entrypoint. Authentication sends any active administrator or intern to the same Outreach application while retaining their permissions. General workspace navigation links to the page instead of mounting Outreach and Imports as Alpine views.

Use focused modules rather than loading the full workspace controller:

- `src/js/outreach.js` owns page state and actions.
- `src/js/outreach-template.js` owns the shell, pipeline, editor, timeline, tools, and guidance markup.
- `src/js/outreach-data.js` owns pure normalization, filtering, metrics, and import/export projections.
- `src/js/outreach-guidance.js` owns role-aware checklists and searchable procedures.
- `src/js/outreach-demo-data.js` owns explicit preview-only records.
- `src/css/outreach.css` extends the existing visual language without duplicating global tokens.

The desktop layout uses a compact navigation rail, pipeline/list workspace, and record drawer. Mobile stacks these regions with persistent primary actions and tap targets of at least 44 pixels. Status is always communicated with text, not color alone.

## Canonical Contact Model

`crm_contacts` remains the canonical identity and relationship record. Both CRM and Outreach edit canonical fields through the same transactional RPC and optimistic `updated_at` check.

Every Outreach candidate has exactly one CRM contact. The candidate stores Outreach-specific qualification, campaign, research, assignment, and stage state. It does not duplicate canonical names, organizations, contact methods, preferences, or relationship ownership.

Normalize supporting data into these concepts:

- Contact methods: email, phone, form, website, and social handles with verification and primary status.
- Communication preferences: channel consent, allowed state, source, evidence, and effective time.
- Campaign memberships: one contact in one campaign with assignment and stage state.
- Outreach research: shared, operational research notes separate from PMF evidence.
- Activities: one append-only timeline for CRM and Outreach actions.
- Tasks: follow-up ownership, due date, status, and completion metadata.
- Meetings: planned and completed meetings with outcome and next action.
- Offers: proposed value exchange with status and non-sensitive fulfillment notes.
- Audit history: RPC-only trusted events for privileged mutations and exports.

## Visibility And Security

An active organization member can read CRM contacts linked to an Outreach candidate in that organization. Unrelated CRM contacts remain owner-scoped unless the caller is an administrator.

Active members can read shared Outreach records and create operational activities assigned to them. Administrators configure stages, resolve duplicates, commit imports, perform bulk mutations, and access organization-wide controls.

PMF evidence keeps assignment-or-approved visibility. Shared Outreach research uses its own table and must never broaden access to PMF drafts, respondent data, consent records, or private attachments.

All browser writes use RPCs. RPCs derive organization, project, actor, and role from authenticated membership; use optimistic concurrency; validate cross-table scope; use safe `search_path`; revoke default execution; and grant only required entrypoints to `authenticated`. Direct audit writes are not trusted for analytics.

## Pipeline

Administrators configure ordered stage definitions. Every stage maps to a stable semantic family so reporting remains comparable when labels change:

- `research`
- `ready`
- `contacted`
- `engaged`
- `qualified`
- `committed`
- `closed`

Definitions include display label, position, active state, SLA days, and transition requirements. Campaign membership stores the selected stage. Stage changes are transactional events and may require contact readiness, an outcome, a next action, or a reason depending on the destination.

The default stages preserve the current operational meaning: Research Needed, Ready to Send, Sent, Follow-up Due, Responded, Interested, Confirmed, Declined, and Unreachable.

## Record Editor

The editor groups information by decision instead of database table:

1. Identity: name, organization, role, category, geography, and canonical owner.
2. Contactability: normalized methods, verification, preferred channel, and consent state.
3. Outreach fit: campaign, tier, reach, priority, PMF-candidate flag, and research notes.
4. Workflow: stage, assignee, next action, due date, and transition requirements.
5. Timeline: activities, meetings, offers, tasks, and audited changes in chronological order.

CRM and Outreach use one mutation contract. A stale `updated_at` rejects the save and presents the latest record without silently discarding local text.

## Communication Workflow

Release communication as manual-first tooling:

- Select a template and render a draft from canonical contact/campaign fields.
- Copy the draft or open the relevant external channel.
- Log drafted, sent, delivered-known, replied, bounced, or failed outcomes manually.
- Require an outcome and next action where the stage transition calls for them.
- Never claim an email, direct message, or form was delivered unless a user records verified evidence.

Provider sending, inbound webhooks, social APIs, calendar synchronization, e-signature, shipping, enrichment vendors, and automated sequences are out of scope.

## Import And Duplicate Handling

Accept CSV, TSV, JSON, XLSX, and Markdown tables through one normalized field contract. Detect format, map headers, normalize values, and present a preview before any write.

Missing headers preserve existing values. Blank cells preserve values by default; explicit clearing requires a clear directive. Identity conflicts never merge silently. Administrators resolve conflicts by choosing an existing contact, creating a new contact, or skipping the row.

Import commit is administrator-only and atomic. The result reports created, updated, linked, skipped, and conflicted rows with stable row references.

## Export And Reporting

Both roles may export records they can read. Administrators can export broader organization views. Every export is audited.

Supported outputs:

- Formula-safe CSV.
- Round-trip JSON.
- Round-trip Markdown table.
- Human-readable Markdown campaign report.

Shared exports omit internal UUIDs, private PMF data, respondent details, consent evidence, private attachment paths, and restricted audit metadata. Export definitions state exactly which filters and metric formulas were used.

## Guidance

Contextual guidance appears beside the current task rather than in a separate manual only. It includes:

- Intern checklists for research quality, contact verification, outreach logging, and follow-up completion.
- Administrator checklists for import review, duplicate resolution, stage configuration, workload assignment, and campaign health.
- Searchable procedures for common errors and workflow decisions.
- Empty states that explain the next safe action.

Guidance is bilingual-ready and uses concise operational language.

## Analytics

Derive analytics from trusted activities, transitions, tasks, and meetings rather than browser-authored counters. Show metric definitions and denominators in the interface.

Core measures include contact readiness, time in stage, follow-up SLA, response rate, positive-response rate, meeting conversion, commitment conversion, workload by assignee, data completeness, and unresolved duplicate/import counts. Avoid opaque predictive or AI scores.

## Error Handling

- Preserve entered values on validation errors.
- Reject stale writes and scope changes explicitly.
- Keep import preview errors tied to source rows.
- Isolate timeline, guidance, analytics, and export failures so one panel cannot take down the page.
- Provide scoped retry actions.
- Label preview data and keep preview writes local.

## Verification

- Pure tests cover normalization, semantic stages, transitions, filtering, metrics, duplicate detection, and round-trip formats.
- Migration tests execute fresh and populated upgrade paths.
- Role tests cover anonymous denial, intern/admin reads, linked versus unrelated CRM visibility, direct-write denial, RPC authorization, stale writes, and trusted audit events.
- Browser tests cover routing, editor behavior, import preview, exports, guidance, keyboard focus, mobile layout, and reduced motion.
- Live verification checks migration history, row counts, representative role RPCs, Pages deployment, and absence of browser secrets.
