# AOI Static Alpine Refactor Plan

## 1. Static Build Foundation

- Add failing tests for the four HTML entries, static dependencies, and Vite multi-page output.
- Replace the Vinext/Cloudflare configuration with a Vite multi-page build.
- Add Alpine.js, Supabase JS, Lucide, and compiled Tailwind dependencies.
- Move the existing AOI CSS into the static source tree and preserve its tokens and responsive rules.

## 2. Shared Browser Runtime

- Add tested helpers for repository-relative URLs, role routing, CSV safety, date formatting, and error normalization.
- Add the Supabase client and API wrappers for authentication, dashboard, administrator users, and task creation.
- Add Alpine stores for authentication, locale, theme, and notifications.
- Keep authorization failures distinct from explicit preview data.

## 3. Multi-Page User Interface

- Port the bilingual landing page to `index.html`.
- Port login and session restoration to `login.html`.
- Build the protected administrator shell in `workspace.html`.
- Build the protected role-specific intern shell in `interns.html`.
- Preserve dashboard, work, research, PMF, reports, team, admin, command palette, task drawer, theme, locale, mobile navigation, and CSV behavior.

## 4. Privileged Supabase Workflow

- Add tests for Edge Function request validation and authorization boundaries.
- Implement `supabase/functions/admin-create-user/index.ts` using per-request JWT validation and a server-only service-role client.
- Preserve administrator verification, user/profile/membership creation, rollback, CORS, and sanitized errors.

## 5. Deployment And Cleanup

- Add a GitHub Pages workflow that publishes `dist/` from `main`.
- Update environment and project documentation.
- Remove obsolete React, Next, Vinext, Cloudflare, and Drizzle runtime files and dependencies.
- Run build, tests, lint, secret scanning, and browser checks at desktop and mobile widths.
- Create the GitHub `AOI` repository, push `main`, enable Pages, and verify the remote branch.
