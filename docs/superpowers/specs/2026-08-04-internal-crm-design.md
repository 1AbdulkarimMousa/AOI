# Internal CRM Design

## Goal

Give AOI administrators and interns one shared contact workspace for finding, enriching, advancing, and following up with external relationships. CRM contacts remain connected to the existing KOL outreach pipeline and PMF evidence without turning the research workspace into a spreadsheet.

## Users And Permissions

- Admins and interns can create and edit CRM contacts.
- Admins and interns can advance lifecycle state and log outreach, notes, qualification, and follow-up activity.
- Intern views are assignment-scoped through the existing organization membership model.
- Admin-only actions remain user management, bulk import commit, assignment rules, and exports.
- Progress is personal: XP, streaks, and badges are visible to the individual without ranking team members.

## Information Architecture

- Today: a due-date-first queue showing one clear next action per contact.
- CRM: searchable directory with lifecycle, owner, next action, outreach state, and profile completeness.
- Contact drawer: short enrichment form, completeness indicator, and activity logging.
- Outreach: existing KOL-specific campaign view, connected through the CRM contact relationship.
- Team momentum: existing shared work view remains available for PMF tasks and research collaboration.

## Data Model

- `crm_contacts` stores canonical person or organization identity and operational fields.
- `candidates.crm_contact_id` connects AOI-specific KOL and PMF fields to a CRM contact.
- `crm_activity` stores the append-only handoff trail.
- `crm_reward_events` stores personal verified-progress points.
- `rpc_aoi_crm_snapshot` provides the role-scoped CRM payload.
- `rpc_aoi_upsert_crm_contact` persists contact changes and preserves the outreach link.
- `rpc_aoi_log_crm_activity` persists outcomes, next actions, lifecycle changes, and rewards.

## Interaction Rules

- Required data entry stays short: name, type, preferred channel, source, next action, and due date form the completeness score.
- Overdue contacts sort first, then due-today contacts, then incomplete records, then later work.
- Every saved enrichment or logged action gives a bounded personal XP reward.
- Empty or invalid saves remain in the drawer with an inline message; no destructive navigation occurs.
- Preview mode uses synthetic records and clearly labels writes as local-only.

## Verification

- Pure CRM queue, completeness, draft, and reward behavior is covered by `tests/crm.test.mjs`.
- CRM schema and browser contracts are covered by `tests/crm-schema.test.mjs` and `tests/static-app.test.mjs`.
- Build, lint, and the full Node test suite must pass before delivery.
- Supabase linked lint and a remote table/RPC smoke query verify the deployed migration.
