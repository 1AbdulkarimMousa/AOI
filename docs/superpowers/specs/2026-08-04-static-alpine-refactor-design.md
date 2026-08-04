# AOI Static Alpine Refactor Design

## Goal

Refactor AOI from its React, Next, Vinext, and Cloudflare runtime into a static multi-page application that runs on GitHub Pages. Preserve the current product capabilities, Supabase security model, bilingual interface, visual language, and responsive behavior.

The deployed site will run at `https://1AbdulkarimMousa.github.io/AOI/`. GitHub Pages will serve only static assets. Supabase will provide authentication, database access, row-level security, RPCs, and the one privileged server-side workflow.

## Scope

The refactor preserves:

- Public bilingual landing page.
- Secure email/password login and session restoration.
- Administrator and intern role separation.
- Administrator overview, research, PMF, reports, team, and administration workflows.
- Intern task queue, task details, evidence requirements, progress updates, feedback, XP, streaks, and missions.
- Administrator user and task creation.
- Existing Supabase schema, migrations, RPCs, and RLS policies.
- English and Simplified Chinese content.
- Light and dark themes.
- CSV exports, command navigation, notifications, and responsive navigation.
- The current warm neutral, orange, teal, blue, rose, gold, and purple AOI visual system.

The refactor removes React, Next, Vinext, server-rendered routes, and the Cloudflare application runtime after feature parity is verified.

## Architecture

Use Vite as a multi-page static builder with npm-managed Alpine.js, Supabase JavaScript, and compiled Tailwind CSS.

### HTML entries

- `index.html`: public AOI landing page.
- `login.html`: authentication, session recovery, and role-aware redirect.
- `workspace.html`: protected administrator workspace.
- `interns.html`: protected intern workspace.

Each page is a real build entry. Vite emits the pages and their hashed assets into `dist/`. The Vite base path is `/AOI/` in production and `/` in local development.

### JavaScript boundaries

Shared modules have one clear responsibility:

- Supabase client initialization from public Vite environment variables.
- Authentication store, session restoration, role context, and sign-out.
- Locale store and English/Simplified Chinese translation lookup.
- Theme store and persisted light/dark preference.
- Navigation helpers that prepend the active Vite base path.
- Dashboard API wrappers for existing RPCs and protected tables.
- Reusable formatting, CSV, notification, and error helpers.

Page modules register focused Alpine components:

- Landing navigation and locale switching.
- Login form and authentication status.
- Administrator shell, dashboard views, admin console, task drawer, command palette, and exports.
- Intern shell, assigned work queue, evidence checklist, progress workflow, feedback, and reward state.

Shared state belongs in Alpine stores. Temporary UI state remains in the page component that owns it. Components communicate through store methods and browser events rather than mutable globals.

### Styling

Tailwind compiles at build time. Existing visual tokens move into CSS custom properties and Tailwind-compatible utility layers. Page-specific component styles remain organized by surface rather than embedded in HTML.

The refactor preserves the current design instead of introducing a redesign. It maintains responsive layouts from 320px upward, visible keyboard focus, reduced-motion handling, readable line lengths, and color contrast.

## Authentication And Role Routing

Protected pages start in a non-rendering authorization state to prevent protected-content flashes.

1. Initialize the Supabase browser client.
2. Restore the current Supabase Auth session.
3. If no session exists, redirect to `login.html`.
4. Call the existing current-user context RPC.
5. If the user is an administrator, allow `workspace.html` and redirect away from `interns.html`.
6. If the user is an intern, allow `interns.html` and redirect away from `workspace.html`.
7. If membership is missing or inactive, sign out and display a safe access error on `login.html`.

The login page redirects an already-authenticated user to the correct role-specific page. Sign-out clears the Supabase session and returns to `login.html`.

## Supabase Data Flow

The browser receives only:

- `VITE_SUPABASE_URL`.
- `VITE_SUPABASE_PUBLISHABLE_KEY`.

Authenticated reads and writes use the current user JWT. Existing RLS policies and organization membership checks remain the authorization source of truth. UI checks improve navigation but never replace database enforcement.

The existing secure dashboard RPC remains the primary workspace payload. Task creation continues through `rpc_admin_create_task`. Any direct table access must use authenticated calls against RLS-protected tables.

Synthetic fallback data may appear only when explicitly labeled as preview data. Authorization failures must never fall back to data that resembles a successful authenticated workspace.

## Privileged Administrator Workflow

Administrator user creation cannot run on GitHub Pages because it requires the Supabase service-role key. Move this workflow from the Next API route to a Supabase Edge Function.

The function will:

1. Require an `Authorization: Bearer <user-jwt>` header.
2. Resolve the calling user from the JWT.
3. Verify active administrator membership for the requested organization.
4. Validate email, display name, role, organization, and temporary password.
5. Use a service-role Supabase client created only inside the function.
6. Create the Auth user and associated application membership using the existing database workflow.
7. Return a minimal success or sanitized error response.

The service-role key is stored only as a Supabase function secret. It is never added to GitHub Actions, Vite variables, static assets, browser storage, or repository files.

## Error Handling

All pages use consistent states:

- Initializing: content remains hidden while session and role checks run.
- Loading: the active section shows a restrained loading state.
- Empty: explain why no records exist and provide the next allowed action.
- Offline or RPC failure: show retry controls and identify preview data when used.
- Unauthorized: clear the session and return to login without rendering protected data.
- Validation error: keep entered values and identify the invalid field.
- Privileged action error: show a safe, actionable message without exposing service details.

Unexpected errors are logged to the browser console in development. Production UI receives sanitized messages.

## GitHub Pages Deployment

A GitHub Actions workflow builds and deploys the site from `main`:

1. Check out the repository.
2. Install the pinned Node version and dependencies with `npm ci`.
3. Build with the repository base path and public Supabase variables supplied through GitHub Actions variables or secrets.
4. Upload only `dist/` as the Pages artifact.
5. Deploy through the official GitHub Pages action.

All links, redirects, images, imports, and runtime navigation use the configured base path. No clean-route fallback or custom `404.html` routing hack is required because each application surface has a real `.html` entry.

## Migration Strategy

The migration proceeds in parity-first slices:

1. Establish the Vite multi-page build, shared CSS, base-path navigation, and static entry pages.
2. Port the landing and login experiences.
3. Port shared Supabase authentication, locale, theme, and dashboard API modules.
4. Port the administrator workspace and all current views.
5. Build the dedicated intern workspace in `interns.html` from the existing role-specific task behavior.
6. Move administrator user creation to the Supabase Edge Function.
7. Add GitHub Pages deployment and environment documentation.
8. Verify parity and security.
9. Remove obsolete React, Next, Vinext, and Cloudflare runtime files and dependencies.

The existing Supabase migrations remain intact. New database changes are added only if the Edge Function requires an explicit secure RPC or if a verified parity gap cannot be served by the current schema.

## Testing And Acceptance

The refactor is complete when:

- `npm run build` emits all four HTML entry pages and their assets.
- Built pages load correctly under `/AOI/`, with no root-relative path failures.
- Landing and login content renders in English and Simplified Chinese.
- Login, session restoration, sign-out, and role-aware redirects work.
- Administrators cannot enter the intern workspace and interns cannot enter the administrator workspace.
- Unauthorized users cannot retrieve workspace data.
- Administrator user creation succeeds only through the authorized Edge Function.
- Existing dashboard, research, PMF, reports, team, task, CSV, notification, theme, and locale behavior remains available.
- Interns can inspect assigned work, evidence requirements, progress, feedback, and rewards from `interns.html`.
- Keyboard navigation, focus indicators, reduced motion, and mobile layouts remain usable.
- Automated tests verify rendered entry pages, base paths, protected redirects, data wrappers, and Edge Function authorization.
- GitHub Actions builds and publishes `dist/` successfully.

## Non-Goals

- Redesigning AOI or changing its brand identity.
- Replacing Supabase or weakening the existing RLS model.
- Exposing a service-role key in the static frontend.
- Introducing a client-side router or clean-route fallback workaround.
- Changing research-domain data structures unless required by a verified parity gap.
