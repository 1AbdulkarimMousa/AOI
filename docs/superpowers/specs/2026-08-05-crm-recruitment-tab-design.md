# CRM Recruitment Tab

## Goal

Make participant recruitment available as a first-class tab inside the existing CRM while keeping `Participant_Recruitment_Tracker.html` available for direct access and existing bookmarks.

## User Experience

- The CRM page exposes two local tabs: `Contacts` and `Recruitment`.
- `Contacts` preserves the current directory, filters, contact drawer, and CRM actions.
- `Recruitment` embeds the existing participant tracker workflow: summary counts, search, stage filter, prospect rows, edit drawer, CRM deep links, and the research-boundary notice.
- The embedded view includes a link to the standalone tracker for a larger workspace.
- `workspace.html?view=crm&tab=recruitment` opens the Recruitment tab directly.
- Existing `workspace.html?view=crm` links continue to open Contacts.

## Architecture

- The existing participant snapshot and upsert RPCs remain the only persistence interface.
- Extract tracker state/actions into a reusable Alpine component implementation that supports `standalone` and `embedded` presentation modes.
- Keep the existing standalone page shell and tracker CSS behavior.
- Add an embedded tracker template that omits standalone top navigation and uses the CRM content frame.
- Register the participant component wherever the workspace app is loaded; do not create a second data model or duplicate save logic.
- Keep CRM contact deep links pointed at the existing contact drawer and preserve the existing `contact` query parameter behavior.

## State & Routing

- Add `crmTab` to the workspace state, defaulting to `contacts`.
- Parse `tab=recruitment` only when `view=crm` is selected.
- Update the URL when the CRM tab changes without changing the existing view routing contract.
- The embedded tracker owns its editor state and refreshes its own snapshot; it does not mutate CRM contact state directly.

## Access & Data Boundaries

- No database migration is needed.
- Existing RLS policies and authenticated RPCs continue to control visibility and writes.
- Recruitment records remain unscreened prospects until eligibility and consent are verified.
- No respondent, session, quote, or evidence records are created by this UI change.

## Testing

- Assert the CRM template contains both local tabs and the embedded tracker entry point.
- Assert workspace routing recognizes `tab=recruitment` without changing the default Contacts route.
- Assert the standalone tracker entry remains in the Vite build.
- Run `npm test`, `npm run lint`, and the production build.
