# Today Briefing Full-Stack Repair Design

**Date:** 2026-08-13
**Status:** Approved for implementation planning
**Surface:** `/AOI/workspace.html?view=today&tab=briefing`

## Purpose

Repair Today Briefing into a trustworthy, action-first workday surface. The current page combines an authoritative work inbox with a legacy dashboard whose hard-coded narrative, all-or-nothing loading, disconnected seed counters, and incomplete states can contradict live work.

The repaired Briefing must help administrators act and decide. It must give interns a private, assignment-focused view without exposing organization-wide governance or performance data. It must preserve the existing Vite, Alpine, Supabase, shared shell, and AOI design-system architecture.

## Product Outcome

When an authorized user opens Briefing, they can:

- see the work requiring attention now, ordered by urgency;
- distinguish pending reviews, blocked execution, and overdue deadlines;
- open the authoritative source record and take the next valid action;
- understand factual project evidence movement without unsupported confidence claims;
- inspect configured sample targets and honestly derived actuals;
- continue using successful sections when a supporting data source fails;
- understand loading, empty, stale, partial-failure, offline, and preview states;
- complete the workflow with keyboard, screen reader, zoom, forced colors, light/dark themes, and a 320 CSS pixel viewport.

## Guiding Decisions

1. Briefing is action-first rather than a general dashboard.
2. Administrators receive a team and governance view; interns receive an assignment-scoped view.
3. Shared PMF evidence may appear to interns only as clearly labeled project context, never personal performance.
4. Live Briefing data is derived from maintained source records, not seed-only summary tables.
5. Unsupported analytics remain unavailable instead of being estimated.
6. Core Briefing availability is independent from unrelated CRM, Collect, gamification, or other supporting snapshots.
7. Partial live data remains usable and labels only the section that failed.
8. Synthetic preview data is explicit and never appears behind an authenticated loading or error state.
9. Personal mission, XP, levels, and streaks belong in Momentum, not the operational Briefing.
10. This work targets strict WCAG 2.2 AAA acceptance for the touched surface without claiming platform-wide conformance.

## Current Defects

The current Briefing has several systemic failures:

- the hero greeting and decision count are hard-coded and can contradict current state;
- authenticated loading and failure can expose fallback fixtures as if they were live;
- one failure among six parallel dashboard RPCs rejects the whole dashboard;
- `project_metrics`, `research_signals`, `team_progress`, `sample_plan_items.actual`, and PMF confidence fields are seeded and have no maintained reconciliation path;
- the intern preview identity does not match fixture ownership and can produce an empty personal Briefing;
- metrics, focus work, sample progress, PMF, activity, and signals lack complete loading and empty states;
- the sample donut is not connected to its displayed value and progress widths are not clamped;
- arrays are unbounded or non-deterministically ordered;
- research-signal actions do not guarantee navigation to Analyze;
- task and inbox details lack complete authoritative loading presentation;
- stale deep-link parameters can open records outside the visible owning workflow;
- the legacy hero and mission cards compete with the actionable inbox for priority.

## Experience Architecture

### Role-Aware Brief Header

The page opens with a compact heading generated from authoritative counts and role scope. It does not use a time-of-day greeting or a fixed claim.

Administrator copy summarizes project-level pending reviews, blockers, and deadlines. Intern copy summarizes only assigned work and support needs. Generated time, project identity, live/preview state, and partial-data status remain visible without dominating the page.

### Needs Attention

The primary reading lane contains the actionable queue. It distinguishes:

- pending reviews;
- blocked tasks, milestones, and active blocker records;
- overdue task and operational deadlines;
- authorized mentions, handoffs, and followed work supplied by the contextual inbox.

Items are ordered by explicit severity, due state, and age. The interface must not call a review urgent unless source priority, blocker impact, or a defined quality flag supports that label.

Selecting an item opens authoritative detail in context. The detail shows a skeleton while loading, prevents premature actions, preserves focus, and provides an exact source-workflow action. Mobile replaces the list with detail and offers a clear Back action.

### Project Pulse

A restrained summary region supports the action queue. It shows factual, explainable values such as:

- pending review count;
- blocked execution count;
- overdue task count;
- approved consent-eligible evidence count.

Each value has a stable definition, deterministic position, source destination, and generated timestamp. There are no decorative deltas without a declared comparison window.

### Sample Progress

Configured targets remain in `sample_plan_items`. Actuals are derived from maintained records according to an explicit source mapping.

Existing labels can support these definitions:

- Dental professionals: distinct approved, active, consent-granted professional respondents.
- Consumer interviews: distinct consent-granted consumers with approved research sessions.
- Product test users: distinct consent-granted respondents with approved product events.

Concept-test responses cannot be inferred from survey titles or all survey submissions. The durable repair adds a stable source declaration, including an optional survey asset reference where required. Until a row has a supported mapping, its actual is `null` and the UI says that the source mapping is required.

Text always shows raw actual and target values. Visual progress clamps to 0 through 100 percent so over-target work does not break layout.

### PMF Evidence Chain

The legacy confidence percentages are removed from live Briefing because no approved confidence formula, weighting model, minimum sample contract, or threshold mapping exists.

Each H1 through H5 layer instead shows factual counts:

- supporting approved evidence;
- contradicting approved evidence;
- approved observations;
- independent consent-eligible respondents where available.

The chain keeps supporting and contradictory evidence equally visible. A layer action opens Research / Analyze with the layer selected explicitly.

### Evidence Movement

Research themes derive from approved, consent-eligible evidence with a non-empty topic. Rows group by topic and stance and show evidence count and average recorded strength. Unsupported change percentages are omitted.

Recent recorded activity combines bounded, append-only task, research review, project record, survey review, CRM, and outreach histories. It is labeled Recorded activity because the platform has no universal event stream and some draft edits only update timestamps.

Both lists are deterministically ordered and capped. View-all actions route to the exact owning destination.

## Data Contract

Add a narrow selected-project RPC for Briefing. It returns one authoritative projection:

```json
{
  "scope": "team | personal",
  "project": {},
  "summary": {},
  "attention": [],
  "deadlines": [],
  "samplePlan": [],
  "pmfChain": [],
  "evidenceSummary": {},
  "signals": [],
  "activity": [],
  "generatedAt": "ISO-8601 timestamp",
  "timezone": "IANA timezone"
}
```

The RPC resolves the selected project through the existing authoritative project-context helper. Organization-local dates govern overdue logic.

### Role Scope

Administrator scope includes authorized project records. Intern scope filters action rows through each source's assignment or ownership column:

- tasks and six research record types: `assigned_to`;
- survey responses: `assigned_to`;
- milestones, risks, decisions, CRM contacts, and recruitment: `owner_id`;
- blockers: `resolution_owner_id`.

Project evidence readouts remain project-scoped and are labeled accordingly.

### Pending Reviews

Pending reviews derive from current lifecycle states in tasks, submitted research records, submitted survey versions or responses, submitted milestones, submitted or resubmitted decisions, and escalated unresolved blockers. Counts and rows must respect source authorization and role scope.

### Blocked Work

Blocked work includes:

- tasks with `status = 'blocked'`;
- milestones with `status = 'blocked'`;
- blocker records with `status IN ('open', 'acknowledged', 'resolving')`.

Risks are not blockers. Typed rows remain separate even when they may refer to related work.

### Overdue Work

Overdue tasks have a due date before the organization-local current date and are not completed or cancelled. Operational deadlines include overdue milestone finish or next-action dates, blocker resolution dates, risk review dates, CRM next actions, and recruitment next actions, excluding their terminal states.

Task overdue and operational deadline overdue remain separate values so the labels stay meaningful.

### Evidence Eligibility

Evidence and PMF observations count only approved records. Respondent-linked records also require current granted consent in the same organization and project. Stances remain separate. Evidence count must not imply independent sample size; distinct respondent counts are returned separately.

### Removed Live Sources

The new contract must not read these disconnected values:

- `project_metrics`;
- `research_signals`;
- `team_progress`;
- `sample_plan_items.actual`;
- `pmf_layers.confidence` and its seeded evidence counters.

Existing tables may remain for migration compatibility until a separately approved cleanup proves they have no consumers.

## Loading And Failure Model

The browser maintains section state for the core Briefing and optional supporting snapshots. Each section has `idle`, `loading`, `ready`, `empty`, `stale`, or `error` presentation.

- Initial authenticated state renders skeletons, not fallback data.
- A successful section replaces only its own skeleton.
- A failed section keeps successful sections visible and offers section-level retry.
- A refresh preserves the last confirmed live projection with an explicit Updating or Stale label rather than blanking the page.
- A complete core failure shows a focused retry state and an optional, clearly labeled preview action.
- Preview never calls live mutations.
- Request sequencing prevents stale responses from replacing a newer project or retry result.
- Detail failures preserve the selected summary but disable authoritative actions until retry succeeds.

## Navigation And Interaction

- Every action specifies its canonical owning view and tab.
- Research themes and PMF layers always open Research / Analyze.
- Sample progress opens the appropriate research or survey destination only when a supported source mapping exists.
- Attention items open their source record and clear unrelated deep-link parameters.
- URL writes remove stale `task`, `type`, `id`, contact, and project-record parameters unless the active workflow owns them.
- Bell navigation performs one canonical route update rather than adding duplicate history entries.
- List and detail focus return follows the existing accessible drawer and pane contract.

## Visual System

The surface preserves AOI's warm paper-like light theme and complete dark theme. Users are conducting daytime research operations on sustained-work desktop displays and may continue in lower-light conditions, so the base remains calm and light while dark mode receives equal semantic treatment.

Desktop uses a 12-column composition. Needs Attention occupies the primary lane; compact deadline and project-pulse summaries form the secondary rail. Evidence movement spans the lower page. Tablet and mobile collapse to one reading column in task order.

Hierarchy comes from typography, spacing, and semantic state markers. The repair removes the legacy decorative hero and mission cards, avoids nested cards, and reserves orange for primary action and current selection. Rose marks risk, teal verified progress, and blue information. State never relies on color alone.

At 320 CSS pixels:

- the page remains a strict single column;
- tabs scroll within their own region;
- queue rows wrap without page overflow;
- list/detail transitions keep all actions reachable;
- controls keep at least 44 by 44 CSS pixel targets;
- labels and bilingual text can wrap without clipping.

Motion is limited to 150 through 250 millisecond state feedback using transform or opacity and is removed when reduced motion is requested.

## Accessibility Acceptance

The touched Briefing targets WCAG 2.2 AAA where applicable:

- ordinary text targets 7:1 contrast; large text targets 4.5:1;
- non-text controls, focus indicators, and meaningful graphics meet at least 3:1;
- all workflows are keyboard complete with logical focus order;
- headings, landmarks, tabs, lists, progress, statuses, and detail regions use correct semantics;
- loading, partial failure, refresh, and mutation outcomes are announced without unnecessary focus movement;
- 200 percent zoom and WCAG text-spacing overrides do not hide content or actions;
- forced-colors mode retains selection, risk, state, and focus meaning;
- light and dark themes preserve semantic contrast;
- reduced-motion preferences are honored;
- English and Simplified Chinese layouts do not truncate controls;
- hidden details and navigation are not focusable or exposed as active content.

Automated tests support but do not replace manual keyboard, screen-reader, contrast, forced-colors, zoom, and text-spacing verification. Release evidence must state which manual checks were completed.

## Testing Strategy

Implementation follows red-green-refactor.

### Unit And Contract Tests

- normalize the new Briefing payload and unsupported values;
- clamp display percentages without changing raw counts;
- derive role-aware headings and summary labels from live values;
- map every source type to its exact destination;
- remove stale deep-link parameters;
- preserve successful section data across partial failures and refreshes;
- prevent fixture data from appearing in authenticated loading or failure states;
- keep admin/team and intern/personal behavior distinct;
- verify preview fixtures have matching synthetic identities and ownership.

### PostgreSQL Execution Tests

- derive pending reviews, blockers, and overdue work from maintained lifecycle rows;
- use organization-local dates;
- enforce selected-project and organization scope;
- enforce personal assignment scope for interns;
- derive consent-safe evidence and distinct respondent counts;
- derive supported sample actuals and return `null` for unsupported mappings;
- never read seed-only summary values;
- order and bound attention, signals, and activity deterministically;
- reject unauthorized cross-project reads through existing access rules.

### Browser Tests

- render administrator and intern Briefings with correct role scope;
- exercise loading, empty, partial failure, stale, complete failure, and preview states;
- open attention items and exact source destinations;
- verify authoritative detail loading and disabled actions;
- verify desktop, 390px, and 320px layout without page overflow;
- verify keyboard-only tab, queue, detail, retry, and source-navigation paths;
- verify dark mode, reduced motion, forced colors, text spacing, and 200 percent zoom;
- verify no uncaught console or page errors;
- verify raw values and clamped visual progress when a target is exceeded.

### Release Commands

Run at minimum:

```bash
npm run lint
npm test
npm run test:e2e
```

If a linked Supabase environment is available, apply the migration only after a verified checkpoint and run authenticated administrator and intern smoke tests against matching frontend and backend revisions.

## Out Of Scope

- inventing a PMF confidence formula;
- inferring concept-test surveys from titles or free-form tags;
- individual employee ranking or surveillance-style productivity scoring;
- replacing Chat, Projects, Research, or Momentum;
- creating a universal event stream;
- deleting legacy summary tables before consumer analysis;
- platform-wide WCAG 2.2 AAA conformance claims;
- unrelated collaboration, survey, project, or security work already present in the working tree.

## Success Criteria

This slice is complete when:

1. Briefing leads with authoritative action and decision work.
2. Administrators receive project governance scope and interns receive assignment scope.
3. Authenticated loading and failure never expose fallback fixtures as live data.
4. One supporting-module failure cannot take down successful Briefing sections.
5. No live Briefing value depends on disconnected seed counters.
6. Unsupported sample and confidence values remain explicit rather than estimated.
7. Every action routes to the exact owning workflow and authoritative detail.
8. Every section has complete loading, empty, stale, error, and retry behavior.
9. Touched workflows pass unit, PostgreSQL, browser, responsive, accessibility, theme, and console checks.
10. The page has no P0 or P1 audit findings at release.
11. Documentation distinguishes repository-tested behavior from deployed-environment verification.
