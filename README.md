# AOI: Ambiloop PMF Operations

Static bilingual research-operations workspace for accountable work, traceable evidence, and confident PMF decisions.

## Stack

- Vite multi-page static build
- Alpine.js for page state and interactions
- Tailwind CSS v4 compiled through Vite
- Supabase Auth, RPCs, RLS, and Edge Functions
- GitHub Pages deployment from `main`

## Pages

- `index.html`: public landing page
- `login.html`: Supabase Auth sign-in
- `workspace.html`: administrator workspace
- `interns.html`: role-specific intern workspace
- `administration.html`: owner/admin people, access, CRM handoff, archive, and data-transfer workspace
- `survey.html`: standalone public and invited survey runner
- `helpcenter.html`: bilingual operational guidance library
- `Participant_Recruitment_Tracker.html`: focused recruitment tracking surface

Protected pages require an active AOI membership. For local UI review only, append `?preview=1` to `workspace.html`, `interns.html`, or `administration.html`; preview data is synthetic and explicitly labeled.

## Projects And Collaboration

Projects provide explicit organization/project context plus typed milestones, blockers, risks, and evidence-backed decisions. Each project record carries ownership, next action, due or review dates, legal lifecycle transitions, and append-only history. Approved decisions preserve immutable evidence snapshots rather than depending on later mutable source rows.

Contextual collaboration stays beside the authoritative record: named comments and mentions, follow/unfollow, auditable comment revisions, and reasoned handoffs. Today presents a compact role-adaptive work inbox derived from those source records. Collaboration and inbox actions never approve, complete, resolve, or otherwise transition the source workflow.

Apply all files in `supabase/migrations/` in timestamp order before deploying a frontend revision that uses Projects or contextual collaboration. Static Pages deployment does not apply database migrations.

## Outreach Operations

The workspace includes a role-aware KOL outreach command center for the August workbook:

- Candidate intake and enrichment for admins and interns
- Explainable pipeline, deadline, and category recommendations
- Outreach timeline logging for email and manual social activity
- PMF evidence and consent ledger with supporting and contradictory findings
- CSV, TSV, JSON, and XLSX import with preview and validation
- Formula-safe CSV and JSON export

Apply `supabase/migrations/202608040001_outreach_operations.sql` after the existing migrations to persist candidate, outreach, evidence, import, and audit records. The browser preview is usable without Supabase; authenticated writes use organization-scoped RPCs and RLS.

## PMF Workspace

The PMF workspace adds guided respondent, session, evidence, product-event, value-exchange, and structured metric collection. Submitted records require administrator review before they enter the five segment-comparison matrices. Recommendations are deterministic rules based on review backlog, sample gaps, contradictory evidence, and consent restrictions. Administrators can preserve an auditable Gate snapshot with a decision and rationale.

Consent documents, research sources, recordings, and oral images use four private Storage buckets. Recordings and oral images require the latest granted consent version. A later withdrawal restricts existing sensitive attachments. Retention is intentionally manual: use `retention_review_at`, legal hold, and attachment status to review, restrict, anonymize, or purge records rather than deleting them automatically.

## Questionnaire And Survey Suite

The Surveys workspace provides reusable bilingual templates, a schema-driven form builder, immutable version approval, secure public and invited distribution, response review, approved-only analysis, PMF mapping, and portable exports. Questionnaires support conditional logic, answer piping, validation, scoring, restricted calculations, deterministic randomization, matrices, rankings, consent, signatures, and private uploads.

Respondents use the standalone `survey.html` runner. Public links contain opaque tokens in the URL fragment, while the database stores only token hashes. Anonymous users have no direct survey-table access; the `survey-public` Edge Function owns load, start, autosave, signed upload, and idempotent submit operations. Apply all survey migrations and deploy the function before enabling live links:

```bash
supabase db push --linked
supabase functions deploy survey-public --no-verify-jwt
```

Operational analysis may include pending and flagged responses. Authoritative analysis and PMF promotion use approved responses only. AOI JSON preserves complete survey definitions with a checksum; CSV exports include formula-safe response data and a bilingual codebook.

Email automation still requires selecting and configuring a provider adapter before production sending. Social platforms remain manual by design because unsupported automation and scraping create account and compliance risk.

## Internal CRM

The workspace includes a connected CRM layer for administrators and interns:

- Today queue prioritized by due date, enrichment completeness, and contact value
- Shared contact directory with quick create/edit forms and lifecycle state
- CRM contacts connected to AOI KOL candidates and existing outreach activity
- Append-only activity trail for enrichment, outreach, qualification, and follow-up
- Personal XP, streaks, and badges without individual rankings

Contacts and their complete activity trails are visible only to the assigned owner and administrators. Rewards are derived and deduplicated in the database, so browser-supplied points cannot change the ledger. Linking a CRM contact to an outreach candidate requires matching project scope and ownership.

Apply all files in `supabase/migrations/` in order. The CRM uses assignment-scoped RLS, authenticated RPCs, and the final access-hardening migration.

## Daily EOD Briefs

Every active administrator and intern has a required end-of-day brief Monday through Friday, due at 5:00 PM in the organization timezone. The brief captures outcomes, evidence, deliverables, insights, blockers, executive support, three next-day priorities, project status, and labeled evidence links.

Authors can save drafts and submit late when necessary. All administrators can review organization submissions, make reasoned audited edits, and mark submitted records complete. Intern report searches remain limited to their own history; administrators can search all briefs by person, role, date, status, and completion state. In-app reminders show due and overdue work without blocking the rest of the workspace.

The persistence contract is in `supabase/migrations/20260804164524_daily_eod_briefs.sql`. Apply all migrations in order before deploying the static client.

## Administration

Administration is an embedded Administration workspace destination with a standalone direct-access page for compatibility. It provides invitation and temporary-password onboarding, operational staff profiles, task and CRM ownership, archived-user handoff, append-only audit history, and preview-first CSV, JSON, and structured Markdown portability. An archived person loses access while completed work, evidence, EOD briefs, CRM activity, and authorship remain intact.

The organization owner manages administrator-role changes and full restores. Administrators manage intern onboarding and offboarding. The migration `supabase/migrations/20260804190000_administration_foundation.sql` adds the lifecycle, ownership, profile, onboarding, transfer, CRM synchronization, and permission contracts.

## Local Setup

```bash
npm install
cp .env.example .env.local
npm run dev
```

Set these public browser variables in `.env.local`:

```text
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Never put a Supabase service-role or secret key in `.env.local` variables beginning with `VITE_`.

## Verification

```bash
npm run build
npm run lint
npm test
npm run test:e2e
```

The repository exercises fresh timestamp-ordered migrations in disposable PostgreSQL instances. Release verification still requires confirming the linked Supabase migration history, a restorable pre-deploy backup, matching frontend/backend revisions, and authenticated owner/admin/intern smoke tests.

## Wen Intern Seed

The repeatable Wen seed imports her supplied planning work and EOD briefs without creating synthetic respondents or interview evidence. It also enables the requested organization-wide bootstrap-password reset, so run it only after confirming that `123456` is approved for every active AOI member:

```bash
AOI_RESET_ALL_PASSWORDS=1 npm run seed:wen
```

The script reads `SUPABASE_SERVICE_ROLE_KEY` from `.env.local`, never prints it, and marks active users for an in-app password-change reminder. Do not use a Supabase access token as the service-role key.

### Wen Consumer Survey

Wen's 44-question Consumer Oral Health Survey is maintained as an English-only canonical definition and seeded as a draft assigned to Wen:

```bash
npm run seed:wen-survey
```

This standalone seed never creates users or changes passwords. It is repeatable when the canonical draft is unchanged and refuses to overwrite edits, submitted versions, or collected responses. Apply all survey migrations before approving or publishing the survey so direct identifiers are stored separately from analytical answers.

## Supabase

Apply `supabase/migrations/` in order. Deploy the privileged user workflow with the Supabase CLI:

The Today Briefing depends on `20260813090909_today_briefing_repair.sql`, which adds the selected-project `rpc_aoi_today_briefing` projection and explicit sample-source mappings. Apply it before treating Briefing values as live; preview data remains visibly labeled and never substitutes for an authenticated failure.

```bash
supabase functions deploy admin-create-user --no-verify-jwt
supabase secrets set ALLOWED_ORIGINS=https://1abdulkarimmousa.github.io
```

The Edge Function validates the caller JWT and active administrator membership. It creates invitation or temporary-password accounts, enforces owner-only administrator creation, suspends Auth access during archival, restores approved accounts, and rolls back Auth creation if application records fail. The service-role key remains a Supabase secret.

## GitHub Pages

The workflow at `.github/workflows/pages.yml` builds and deploys `dist/` under `/AOI/`. Configure these GitHub repository variables before enabling the workflow:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

The repository must use GitHub Pages with the Actions source. The generated site is designed for `https://1AbdulkarimMousa.github.io/AOI/`.

## Data Safety

The browser receives only the Supabase publishable key. Assignment-aware RLS and active organization membership checks protect workspace data. Contacts and consent stay restricted to assignees and administrators; only approved analytical records become project-visible. This is an internal research system, not a clinical record system or medical advice product.
