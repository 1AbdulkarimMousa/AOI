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
- CSV, JSON, and tab-delimited import with preview and validation
- Formula-safe CSV and JSON export

Apply `supabase/migrations/202608040001_outreach_operations.sql` after the existing migrations to persist candidate, outreach, evidence, import, and audit records. The browser preview is usable without Supabase; authenticated writes use organization-scoped RPCs and RLS.

Email automation still requires selecting and configuring a provider adapter before production sending. Social platforms remain manual by design because unsupported automation and scraping create account and compliance risk.

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

The browser receives only the Supabase publishable key. RLS and organization membership checks protect workspace data. Keep real respondent contacts, oral images, and production research data out of this test build until AOI retention and compliance decisions are finalized.
