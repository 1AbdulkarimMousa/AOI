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

Protected pages require an active AOI membership. For local UI review only, append `?preview=1` to `workspace.html` or `interns.html`; preview data is synthetic and explicitly labeled.

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

Email automation still requires selecting and configuring a provider adapter before production sending. Social platforms remain manual by design because unsupported automation and scraping create account and compliance risk.

## Internal CRM

The workspace includes a connected CRM layer for administrators and interns:

- Today queue prioritized by due date, enrichment completeness, and contact value
- Shared contact directory with quick create/edit forms and lifecycle state
- CRM contacts connected to AOI KOL candidates and existing outreach activity
- Append-only activity trail for enrichment, outreach, qualification, and follow-up
- Personal XP, streaks, and badges without individual rankings

Apply `supabase/migrations/20260804122136_crm_workspace.sql` and `supabase/migrations/20260804123948_crm_function_repairs.sql` after the existing migrations. The CRM uses organization-scoped RLS and authenticated RPCs.

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
```

## Supabase

Apply `supabase/migrations/` in order. Deploy the privileged user workflow with the Supabase CLI:

```bash
supabase functions deploy admin-create-user --no-verify-jwt
supabase secrets set ALLOWED_ORIGINS=https://1abdulkarimmousa.github.io
```

The Edge Function validates the caller JWT, requires active administrator membership, creates the Auth user and AOI membership with the service-role client, and rolls back Auth creation if application records fail. The service-role key remains a Supabase secret.

## GitHub Pages

The workflow at `.github/workflows/pages.yml` builds and deploys `dist/` under `/AOI/`. Configure these GitHub repository variables before enabling the workflow:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

The repository must use GitHub Pages with the Actions source. The generated site is designed for `https://1AbdulkarimMousa.github.io/AOI/`.

## Data Safety

The browser receives only the Supabase publishable key. Assignment-aware RLS and active organization membership checks protect workspace data. Contacts and consent stay restricted to assignees and administrators; only approved analytical records become project-visible. This is an internal research system, not a clinical record system or medical advice product.
