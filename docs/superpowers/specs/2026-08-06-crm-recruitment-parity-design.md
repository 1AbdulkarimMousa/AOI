# CRM Recruitment Parity

## Goal

Make CRM Recruitment the primary participant recruitment workspace with every function of `Participant_Recruitment_Tracker.html`, including an always-visible `Add a prospect` action. Keep the standalone tracker available as a secondary view for existing bookmarks and focused work.

## User Experience

- Keep the CRM local tabs: `Contacts`, `Recruitment`, and `Outreach`.
- Show the Contact CRM introduction and its contact actions only on the Contacts tab.
- Give Recruitment its own compact heading with `Open full tracker` and a primary `+ Add prospect` button.
- Open the shared prospect drawer from the new button with the same fields, validation, save flow, conversion controls, and notices as the standalone tracker.
- Preserve summary metrics, search, stage filtering, prospect rows, CRM deep links, respondent conversion, loading states, errors, empty states, and the research-boundary notice.
- Keep responsive behavior from 320px upward and use the existing workspace design system.
- Make links from the standalone tracker return to `workspace.html?view=crm&tab=recruitment`.

## Architecture

- Continue using the single `participantTrackerPage` Alpine component for standalone and embedded presentations.
- Continue sharing `participantTrackerContentTemplate`; do not copy tracker state, forms, or persistence logic into CRM.
- Make the CRM introduction tab-aware instead of adding a second CRM shell.
- Keep `Participant_Recruitment_Tracker.html` and its Vite entry.
- Use the current date for a new prospect's default next-action due date instead of a fixed historical date.

## Data And Security

- No database migration is required.
- Continue using `rpc_aoi_participant_tracker_snapshot`, `rpc_aoi_upsert_participant_recruitment`, and `rpc_aoi_convert_recruitment_to_respondent` as the data boundary.
- Preserve existing authentication, role checks, RLS, assignment scoping, and admin-only respondent conversion.
- Do not expose credentials from `spb.md` in source, build output, logs, or user-facing responses.

## Error Handling

- Keep the existing retry state when the tracker snapshot fails.
- Keep inline save and conversion notices.
- Disable save and conversion actions while their requests are running.
- Preserve required participant ID and name validation.

## Testing And Delivery

- Assert the embedded Recruitment heading exposes `+ Add prospect` and calls the shared `openNew()` action.
- Assert the contact introduction is visible only on the Contacts tab.
- Assert standalone CRM links include `tab=recruitment`.
- Assert new prospect defaults use the current date rather than a hard-coded date.
- Run focused tests, lint, the full test suite, and the production build.
- Verify CRM Recruitment on desktop and mobile, including opening the prospect drawer.
- Verify the live Supabase-backed page after deployment.
- Commit intended files, push `main`, and confirm the GitHub Pages deployment succeeds.
