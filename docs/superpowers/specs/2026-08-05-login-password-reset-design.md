# Login Password Reset Design

## Goal

Allow AOI users to recover access through either an administrator-issued temporary password or a Supabase recovery email, without trapping the user on the password setup screen.

## Design

- Temporary-password accounts are stored as `password_change_required` with `must_change_password = true`.
- Password completion accepts both legacy active temporary accounts and the canonical password-change-required state, then activates the profile and membership in one database operation.
- The login page requests recovery emails through Supabase Auth and uses the recovery callback URL to render the new-password form instead of redirecting to a workspace.
- Both password paths update Auth, mark the profile password as changed, reload workspace access, and route by role.
- Existing organization membership, RLS, and role routing remain unchanged.

## Verification

- Unit tests cover recovery callback detection and the required Auth/RPC integration points.
- Build, lint, and the complete Node test suite must pass.
- The deployed Supabase migration and `admin-create-user` Edge Function are verified against the AOI project from `spb.md`.
