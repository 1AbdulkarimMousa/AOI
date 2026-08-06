# AOI Survey Suite Design

## Goal

Add a research-grade questionnaire and survey system to AOI with reusable templates, bilingual authoring, immutable approval, secure public and invited links, reviewed responses, PMF promotion, analysis, and portable exports.

## Product Boundaries

The suite has five bounded surfaces: Survey Library, Form Builder, Distribution, Response Review, and Analysis. Authenticated authoring remains in the AOI workspace. Respondents use a separate lightweight public runner that never loads protected workspace data.

## Roles And Workflow

Interns can create and edit assigned drafts, submit versions, manage assigned distributions, and recommend response decisions. Administrators approve or reject versions, publish immutable versions, make final response decisions, and promote mapped answers into PMF observations.

Survey lifecycle:

`draft -> awaiting_approval -> approved -> published -> paused/closed -> archived`

Response lifecycle:

`in_progress -> submitted -> in_review -> approved | revision_requested | rejected | excluded`

Only approved responses enter authoritative analysis or PMF promotion.

## Definition Model

Survey definitions are versioned bilingual JSON documents. They contain sections, stable question and option IDs, validation, declarative visibility rules, scoring, restricted calculations, deterministic randomization, quotas, theme settings, completion content, and PMF mappings. Published definitions are immutable and checksummed.

Supported question families include text, contact, numeric, date/time, choice, rating, NPS, Likert, matrix, ranking, upload, signature, consent, calculated, and hidden fields.

## Security

Anonymous users receive no table grants. Opaque link and resume tokens are stored only as SHA-256 hashes. The `survey-public` Edge Function validates origins, constrains request size and upload MIME types, and calls service-role-only public RPCs. Links resolve organization, project, and immutable version server-side.

Response contact identity is separated from analytical answers. Consent stores the exact version and locale shown. Files use a private bucket and short-lived signed upload grants. Corrections are append-only and administrative transitions are audited.

## Analysis And Portability

Operational analysis shows all review states. Authoritative analysis defaults to approved responses. Every summary exposes denominator and population. The system supports question distributions, completion, quality flags, cross-tab foundations, manual text coding records, score results, CSV response/codebook export, printable PDF views, and checksummed AOI JSON definition packages.

## Accessibility

The builder provides keyboard move controls in addition to pointer interaction. The runner uses fieldsets, legends, associated errors, focus recovery, an `aria-live` save status, reduced-motion support, and responsive layouts down to 320 pixels.

## Verification

Pure tests cover definition defaults, cloning reactive data, bilingual validation, branch cycles, visibility, piping, calculations, scoring, randomization, answer validation, package checksums, and safe exports. Schema tests cover all tables, RLS, grants, RPCs, null-safe authorization, and crypto resolution. UI contract tests cover workspace, runner, and Edge Function wiring. Production verification exercises load, start, autosave, submit, persistence, and cleanup through a disposable fixture.
