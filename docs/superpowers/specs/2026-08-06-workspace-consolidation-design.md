# AOI Workspace Consolidation Design

## Goal

Reduce eleven parallel workspace destinations to five coherent operational destinations without rewriting the Alpine, Vite, or Supabase architecture and without collapsing records that have different consent, audit, or authorization semantics.

## Information Architecture

The authenticated primary navigation contains:

1. Today
2. Relationships
3. Research
4. End-of-Day Brief
5. Chat

Administration and Help Center remain separate utilities.

### Today

Today is the role-aware command center. It contains four tabs:

- Briefing: current Overview project health, blockers, evidence balance, and next decisions.
- Tasks: current My Work queue and checkpoint workflow.
- Relationships: due and incomplete CRM follow-ups.
- Momentum: cooperative goals and personal verified progress.

Canonical route: `?view=today&tab=briefing|tasks|relationships|momentum`.

Legacy `overview`, `work`, and `team` routes normalize to their matching Today tab. Existing intern defaults continue opening Today, while administrator defaults open Today Briefing.

### Relationships

Relationships contains existing Contacts, Recruitment, and Outreach tabs. Today relationship actions deep-link into the same canonical contact records and append-only activity.

Canonical route: `?view=relationships&tab=contacts|recruitment|outreach`. Outreach keeps `section=pipeline|evidence|imports` until candidate evidence moves to the shared research editor in a later data migration.

Legacy `crm`, `outreach`, `evidence`, and `imports` routes normalize to Relationships. `Participant_Recruitment_Tracker.html` remains a compatibility entry but points users back to Relationships Recruitment.

Domain records remain separate: `crm_contacts`, `candidates`, `participant_recruitment`, and `respondents` preserve different lifecycle and consent boundaries.

### Research

Research contains Collect, Surveys, Analyze, and Reports tabs.

Canonical route: `?view=research&tab=collect|surveys|analyze|reports`.

Legacy `collect`, `surveys`, `analyze`, `reports`, and `pmf` routes normalize to Research. Existing collection, survey versioning, review, Gate, and export behavior remains unchanged.

Reports becomes a research readout tab. EOD archive stays with End-of-Day Brief. Survey respondent runtime stays in standalone `survey.html`.

## Routing Contract

One route resolver returns canonical `view`, Today tab, Relationships tab, Outreach section, and Research tab. It rejects invalid tab/section combinations and marks aliases for `history.replaceState` normalization.

Browser back/forward restores all canonical tabs. Deep links to CRM contacts, survey assets, and legacy routes remain functional. Command palette lists only five primary destinations.

## Security And Data

No database migration or credential change is required. Existing RLS, RPCs, immutable survey versions, consent records, review states, and Gate snapshots remain authoritative.

Secrets from `spb.md` are local deployment inputs only. They must not enter source, build output, logs, commits, or browser code.

## Testing

- Route unit tests cover every legacy alias, canonical tab, invalid combination, and normalization result.
- Static template tests prove primary navigation contains only five operational destinations and each consolidated workspace exposes expected tabs.
- Existing CRM, recruitment, collection, survey, analysis, EOD, chat, accessibility, and production-build tests remain green.
- Browser verification covers administrator and intern preview routes at desktop and mobile widths, plus browser history.

## Deployment

Run lint, full unit suite, production build, and targeted Playwright checks. Commit only intended source, tests, and design files; leave `raw_data/` untouched. Push `main`, wait for GitHub Pages workflow, then verify deployed canonical and legacy routes against live Supabase authentication.
