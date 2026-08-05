# CRM Outreach Consolidation

## Goal

Make CRM the single relationship workspace by consolidating the complete Outreach suite inside it without removing any current Outreach, Evidence, or Imports capability.

## Information Architecture

CRM exposes three primary tabs:

1. `Contacts`
2. `Recruitment`
3. `Outreach`

The Outreach tab contains compact secondary navigation for:

1. `Pipeline`
2. `Evidence`
3. `Imports`

Pipeline is the default Outreach section. The top-level sidebar entries for Outreach, Evidence, and Imports are removed. Existing CRM Contacts and Recruitment behavior remains unchanged.

## Feature Preservation

### Pipeline

Pipeline preserves the complete current Outreach workflow:

- Campaign summary and category metrics.
- Explainable recommendations and recovery actions.
- Candidate search and operational filters.
- Candidate creation and editing.
- Contact readiness, assignment, priority, PMF-candidate, source, next-step, and due-date fields.
- Outreach activity logging with channel, kind, status, summary, actor, and timestamp.
- Candidate-specific PMF evidence entry.
- Candidate drawer validation and inline notices.

### Evidence

Evidence preserves:

- The evidence and consent ledger.
- Supporting and contradictory evidence presentation.
- Consent status, evidence strength, authorship, and recorded dates.
- Existing control guidance and privacy boundaries.
- The action that returns users to the candidate pipeline.

### Imports

Imports preserves:

- CSV, JSON, and tab-delimited file parsing.
- Preview-before-commit behavior.
- Source-row validation errors.
- Administrator-only atomic import commit.
- Formula-safe CSV and JSON exports.
- Import quality guardrails and existing inline notices.

## Component Boundaries

Extract the existing Pipeline, Evidence, and Imports markup from `src/js/workspace-template.js` into a focused Outreach template module. The module renders the three sections within the CRM Outreach tab and depends on the existing workspace Alpine controller contract.

Keep the existing controller state and methods for candidates, outreach events, evidence records, imports, exports, recommendations, and notices. Keep the existing candidate drawer as the single editor. Do not duplicate state, API calls, persistence logic, or Supabase records.

The CRM template owns the primary CRM tabs. The Outreach template owns only its secondary section navigation and section markup.

## Routing

Canonical routes are:

- Contacts: `?view=crm`
- Recruitment: `?view=crm&tab=recruitment`
- Outreach Pipeline: `?view=crm&tab=outreach&section=pipeline`
- Outreach Evidence: `?view=crm&tab=outreach&section=evidence`
- Outreach Imports: `?view=crm&tab=outreach&section=imports`

The workspace parses only known CRM tabs and Outreach sections. Unknown CRM tabs fall back to Contacts. Unknown Outreach sections fall back to Pipeline.

Changing a CRM tab or Outreach section updates the URL with `history.replaceState` and does not reload the workspace. Selecting the Outreach tab without a section opens Pipeline.

Legacy routes remain compatible and are normalized to canonical routes:

- `?view=outreach` becomes CRM Outreach Pipeline.
- `?view=evidence` becomes CRM Outreach Evidence.
- `?view=imports` becomes CRM Outreach Imports.

This normalization preserves unrelated query parameters such as preview mode. Contact deep links continue to open CRM Contacts and its contact drawer. Starting a new candidate opens CRM Outreach Pipeline before opening the candidate drawer. Evidence actions that previously opened the top-level Outreach view now open CRM Outreach Pipeline.

## State And Data Flow

Add an Outreach section state value alongside the existing CRM tab state. Route parsing initializes both values before preview or authenticated data loads.

The consolidation does not alter dashboard snapshots, API methods, RPC names, role checks, database tables, RLS policies, import contracts, or evidence privacy. Existing live and preview data continue to populate the same workspace controller fields.

Switching tabs or sections does not reset candidate edits, import previews, filters, evidence forms, or inline notices. Closing a drawer or completing an existing action retains its current behavior.

## Access And Security

No Supabase migration or permission change is required. Existing authenticated RPCs and RLS remain authoritative.

- Interns retain their current assignment-scoped access.
- Administrators retain import commit and campaign steering capabilities.
- Browser code continues to use the existing public Supabase client only.
- PMF evidence privacy and consent controls are not broadened by the UI move.

## Error Handling

- Existing candidate, outreach, evidence, and import validation remains inline.
- Failed writes preserve entered values and the active CRM/Outreach section.
- Legacy-route normalization does not trigger data writes or page reloads.
- Unsupported route values degrade to Contacts or Pipeline rather than showing an empty workspace.
- Preview behavior remains explicitly labeled and keeps its current local-write restrictions.

## Responsive And Accessible Behavior

Use the existing CRM local-tab visual language for primary tabs. Use a compact secondary navigation within Outreach that remains readable on narrow screens and supports horizontal overflow without clipping actions.

All tab and section controls are real buttons with active-state text and appropriate navigation labels. Existing drawers, forms, status text, keyboard behavior, and mobile stacking remain intact.

## Verification

Add tests that assert:

- CRM exposes Contacts, Recruitment, and Outreach primary tabs.
- Outreach exposes Pipeline, Evidence, and Imports secondary sections.
- Outreach, Evidence, and Imports are absent from top-level navigation.
- Canonical route parameters initialize the correct tab and section.
- Legacy Outreach, Evidence, and Imports routes normalize to their canonical CRM destinations.
- Contact deep links still force the Contacts tab.
- New-candidate and evidence-to-pipeline actions target CRM Outreach Pipeline.
- Pipeline still includes recommendations, candidate filtering, candidate CRUD, outreach logging, and candidate evidence controls.
- Evidence still includes its ledger and consent controls.
- Imports still includes preview, validation, admin commit, and export controls.
- Existing API method and role-restriction contracts remain present.

Run `npm test` and `npm run lint`. The test script includes a production Vite build, so successful completion also verifies the consolidated templates compile into all workspace entry pages.

## Out Of Scope

- Database schema or RLS changes.
- New Outreach capabilities or provider integrations.
- Changes to candidate, CRM, evidence, or import data models.
- Removal of legacy route compatibility.
- Redesign of Contacts, Recruitment, or the candidate drawer beyond what is required to mount Outreach cleanly.
