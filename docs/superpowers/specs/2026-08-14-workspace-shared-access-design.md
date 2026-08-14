# Workspace Shared Access and AAA Repair

## Goal

Make `workspace.html` the unified authenticated operating surface for AOI. Help Center and Administration must be reachable in the same workspace page for every authenticated user, while privileged administration actions remain guarded. Repair the surrounding navigation, routing, accessibility, responsive behavior, and runtime failure handling to AAA quality without rewriting the existing feature modules.

## Scope

### In scope

- Add Help Center and Administration as first-class workspace destinations.
- Reuse the existing Help Center and Administration state, templates, data loaders, and mutation guards.
- Support direct workspace routes for both destinations and browser back/forward navigation.
- Keep preview mode functional for both destinations.
- Preserve bilingual labels and existing AOI visual language.
- Repair keyboard, focus, dialog, tab, Escape, reduced-motion, responsive, zoom, loading, empty, and error states.
- Add focused Playwright coverage and run the existing audit suite.

### Out of scope

- Building every future module described in `131.md`.
- Replacing the existing Help Center or Administration implementations with new backend systems.
- Removing standalone `helpcenter.html` or `administration.html`; they may remain compatibility entry points.
- Changing authorization policy for privileged mutations.

## Architecture

The workspace shell remains the single mounted Alpine application. `workspacePage` owns top-level route state and navigation. Help Center and Administration are mounted as workspace views using their existing templates and feature factories. Their existing data and action APIs remain authoritative.

The route vocabulary is:

- `today`
- `relationships`
- `research`
- `projects`
- `end-of-day`
- `chat`
- `help-center`
- `administration`

Aliases are normalized centrally rather than handled by scattered template string replacements. Direct route loading, route changes, and browser history must produce the same selected navigation state.

## Navigation and Access

- Both destinations appear in desktop and mobile workspace navigation for all authenticated users.
- Both destinations appear in command search and have visible active and focus states.
- Administration actions continue to use the existing owner/admin checks. Users without mutation access see a readable permission state rather than broken controls or silent failures.
- The workspace route must not bypass session validation.
- Existing standalone page links remain valid as compatibility entry points.

## UX and Accessibility

- Use existing AOI tokens and component vocabulary from `DESIGN.md`.
- Every interactive control has a discernible accessible name, visible focus state, hover state, disabled state, loading state, and error state where applicable.
- Tabs expose correct `role`, `aria-selected`, keyboard movement, and panel relationships.
- Drawers and dialogs trap focus while open, close on Escape, restore focus to the opener, and do not leave hidden controls tabbable.
- Mobile navigation uses inert/hidden semantics when closed and keeps touch targets at least 44px.
- Layouts must remain usable at 320px width and 200% browser zoom without page-level horizontal overflow.
- `prefers-reduced-motion` disables non-essential transitions.
- Status uses text or symbols in addition to color.
- English and Simplified Chinese labels remain supported.

## Error and Loading Behavior

- Workspace initialization failures identify the unavailable capability and provide retry or return-to-login actions.
- Help Center and Administration load independently where possible so one failed data source does not blank the entire shell.
- Empty states explain what is absent and what action is valid next.
- Preview mode is explicit and prevents live mutations.
- Async refreshes must not overwrite newer route or data state.

## Verification

Add or update Playwright tests covering:

- Shared navigation reaches Help Center and Administration without leaving `workspace.html`.
- Direct routes and legacy aliases normalize correctly.
- Back/forward navigation restores the correct destination.
- Preview mode renders both destinations without authentication redirects.
- Keyboard navigation and accessible selected states work.
- Mobile navigation and 320px containment work.
- Dialog/drawer focus containment, Escape, and focus restoration work where applicable.
- Administration permission states remain safe for non-privileged users.
- No page errors or failed document/script/style/fetch responses occur during the covered flows.

Run the project build, focused tests, and existing AAA audit tests before completion.

## Implementation Constraints

- Make the smallest coherent changes; do not duplicate backend logic.
- Use the established Alpine and route patterns already present in the project.
- Do not introduce a new design system or unrelated refactor.
- Do not modify user-authored unrelated worktree files.
