# AOI Survey Suite Implementation Plan

## Phase 1: Domain And Persistence

- Define the versioned bilingual schema and pure rule engine.
- Add immutable survey assets, drafts, versions, links, invitations, submissions, answers, review, coding, promotion, aggregate, and transfer records.
- Enforce organization/project scope, RLS, explicit Data API grants, optimistic revisions, and audited transitions.

## Phase 2: Authoring And Governance

- Add the Survey Library and three-region Form Builder.
- Support all question families, validation, branching, piping, scoring, calculations, randomization, PMF mapping, autosave, and version approval.
- Keep complex feature logic in focused survey modules rather than the workspace monolith.

## Phase 3: Collection And Distribution

- Add the public bilingual runner as its own Vite entry.
- Implement public/invited/embed link modes, identity modes, schedules, response limits, resumable autosave, private uploads, review-before-submit, and idempotent submission.
- Deploy the `survey-public` Edge Function with service-role-only RPC access.

## Phase 4: Review, Analysis, And Portability

- Add assigned response review and administrator final decisions.
- Promote explicitly mapped approved answers into PMF observations with provenance.
- Add approved/operational population analysis, quality flags, response drill-down foundations, CSV/codebook exports, AOI JSON round trips, and print/PDF views.

## Phase 5: Verification And Rollout

- Run build, lint, unit, schema, UI contract, browser, mobile, and production Edge Function verification.
- Apply migrations transactionally and deploy the Edge Function.
- Push `main` to trigger GitHub Pages and verify the deployment workflow.
