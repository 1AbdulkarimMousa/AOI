# Intern EOD Restore And Workspace Repair

## Goal

Restore the missing historical work for Kayla Tillmon and Wen Tang in the live AOI workspace, and make `workspace.html?view=eod` reliably expose that history to administrators without weakening evidence integrity.

## Scope

- Reuse the existing idempotent Kayla seed path.
- Add an idempotent Wen intern seed path for canonical planning work and historical EOD briefs already represented in repository source data.
- Preserve historical source boundaries. Planning notes, OneDrive references without URLs, mock interviews, and recruitment activity must not become approved respondent evidence.
- Ensure the EOD archive loads both interns through the live RPC and preview mode, including search, author filters, report drawers, status labels, and responsive behavior.
- Add focused tests for stable upserts, both authors, historical date coverage, and missing-source-link messaging.

## Data Flow

The restore script resolves the AOI organization, `AOI-PMF-01`, and each intern by normalized login identifier. It temporarily activates memberships so assignment-integrity checks permit historical writes, upserts stable tasks and EOD rows, then restores terminal account state. EOD rows use the existing `(project_id, author_id, brief_date)` uniqueness rule. Wen's consumer survey seed remains separate and must not overwrite edited survey assets.

Historical EOD rows with no supplied URL keep `evidence_links` empty only when inserted by the trusted import path. The UI labels these records as historical imports and does not present them as validated evidence.

## UI Repair

The EOD archive remains the primary review surface. It will:

- show Kayla and Wen from live report RPC results;
- keep preview fixtures representative of both interns;
- avoid filtering historical rows out because they lack evidence links;
- distinguish imported source notes from verified links;
- preserve keyboard focus, named drawers, readable status text, dark theme contrast, and 320px reflow.

No modal-first workflow or decorative dashboard rewrite is needed.

## Error Handling

- Missing organization, project, profile, or membership fails before destructive data writes.
- Existing edited records are not overwritten outside the seed's stable ownership markers.
- Duplicate historical rows are resolved by the database uniqueness key.
- Live RPC errors remain visible with a retry action and do not silently replace live data with preview data.
- Source links are never fabricated to satisfy normal EOD validation.

## Verification

- Unit/script checks validate both account constants, stable IDs, EOD dates, and evidence boundaries.
- Existing EOD Playwright checks continue to cover validation, drawers, responsive containment, and dark theme.
- Add an archive assertion that both intern names are visible in preview mode.
- Run the focused test suite and inspect the final diff for accidental changes to unrelated seed data.

## Non-Goals

- Do not invent respondents, consent, sessions, evidence, observations, gate decisions, or URLs.
- Do not change authentication credentials or commit temporary passwords.
- Do not alter unrelated administrator or merchant workflows.
