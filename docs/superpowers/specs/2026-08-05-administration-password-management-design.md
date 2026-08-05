# Administration Password Management Design

## Goal

Allow active AOI administrators to change their own password and reset passwords for other active administrators or interns from `administration.html`. Preserve the existing Supabase Auth boundary, require safe reauthentication for self-service changes, and never store passwords in database records, logs, exports, or audit metadata.

## Permissions

- Only active administrators whose profile is active and whose current account does not require a password change may open Administration or use its password actions.
- Every active administrator may reset another active administrator or intern.
- Every active administrator may change their own password.
- Disabled or archived accounts cannot be reset. They must be restored before password management is available.
- Preview mode displays the interface but performs no password operation.

## Self Password Change

When an administrator opens their own person drawer, the Profile tab includes a `Password & access` section with:

- Current password
- New password
- Confirm new password
- `Change my password` action

The current password is required even though the administrator already has an authenticated session. The Edge Function reauthenticates the caller with an isolated, non-persistent Supabase client before changing the password. The new password must:

- Contain at least 12 characters
- Differ from the current password
- Match the confirmation value in the browser

A successful self-change leaves the administrator active, clears any stale password-change flags, records an audit event, clears the form, and shows a success notice. Password values never enter the audit event.

## Resetting Another User

When an administrator opens another active person, the same section offers `Reset password` with two modes:

1. `Generate secure password`, selected by default
2. `Use custom temporary password`

Generated passwords are created server-side with cryptographically secure randomness and contain at least 16 characters from multiple character classes. Custom temporary passwords must contain at least 12 characters. Every reset requires a short reason.

After the Supabase Auth password is replaced:

- `profiles.must_change_password` becomes `true`
- The profile status becomes `password_change_required`
- The organization membership status becomes `password_change_required`
- Password reminder timestamps are initialized for the existing forced-change workflow
- An audit event records actor, target, action, reason, and timestamp, but never the password

The temporary password is returned once and shown in the open drawer with explicit copy stating that it will not be shown again. Refreshing or closing the drawer removes it from browser state.

## Interface

Password management stays inside the existing person drawer rather than creating another page or nested modal.

The security section appears below operational profile fields and uses the existing form, notice, button, and status vocabulary. It includes:

- A concise explanation of the current action
- Standard password inputs with autocomplete attributes
- A show/hide control for password fields
- A generated/custom mode selector for other-user resets
- A required reset reason for other-user resets
- A single primary action with a loading label
- Inline success or error feedback with `role="status"` or `role="alert"`

The action is unavailable for invited, disabled, or archived users. The section explains the valid next action rather than silently hiding the control.

On mobile, fields stack at the existing drawer breakpoint and retain full-width, reachable actions. Keyboard focus remains inside the drawer through the current focus trap.

## Server Flow

The existing `admin-create-user` Edge Function gains two explicit actions:

- `change_own_password`
- `reset_user_password`

Both actions use the existing origin, JWT, profile, membership, and administrator checks. They execute before unrelated create/archive/import branches and reject unexpected target states.

### Change Own Password

1. Validate current and new password inputs.
2. Load the caller's normalized Auth email server-side.
3. Reauthenticate current credentials with a non-persistent client.
4. Update the caller through `auth.admin.updateUserById`.
5. Clear stale password-change state through a controlled database function.
6. Append a redacted audit event.

### Reset Another User

1. Validate the target UUID, target organization membership, active target state, mode, custom password, and reason.
2. Generate a secure temporary password when requested.
3. Save the target's prior profile and membership states for compensation.
4. Mark the target as requiring a password change.
5. Update Supabase Auth with the temporary password.
6. If the Auth update fails, restore the prior database state and report a safe error.
7. Append a redacted audit event.
8. Return the temporary password exactly once.

No secret or service-role credential is exposed to the browser.

## Database Contract

A migration adds controlled password-state functions in the private schema or an equivalently unexposed privileged boundary:

- Mark a target member as `password_change_required`
- Restore the prior password state when Auth update fails
- Clear stale forced-change state after an administrator changes their own password

Functions validate organization scope and target state. Execution is restricted to `service_role`; browser roles receive no direct execution grant. Existing RLS remains enabled on exposed tables.

Audit rows use the existing `audit_events` table. Metadata may include target user ID, reason, reset mode, and previous status. It must not include current, new, generated, or custom passwords.

## Failure Handling

- Invalid current password: no state changes; return a neutral credential error.
- Weak or mismatched new password: reject before network mutation where possible and revalidate server-side.
- Target not active: no mutation; instruct the administrator to restore the account first.
- Database preparation failure: do not change Auth.
- Auth reset failure: attempt database compensation and report whether administrator attention is required.
- Audit insert failure after a successful password operation: return success with an audit-warning indicator rather than claiming the password change failed.
- Repeated submission: disable the action while a request is active.

## Testing

Automated tests cover:

- Administration UI contains self-change and other-user reset controls
- Self-change requires current password and a 12-character new password
- Confirmation mismatch is blocked in the client
- Current-password reauthentication occurs server-side
- Any active administrator may reset another active administrator or intern
- Disabled, archived, and invited targets are rejected
- Generated and custom temporary-password modes are supported
- Generated passwords are strong and use cryptographic randomness
- Reset targets enter `password_change_required` state
- Failed Auth updates trigger state compensation
- Audit metadata excludes password fields and password values
- API helpers invoke the correct Edge Function actions
- Preview mode performs no live action
- Mobile and keyboard behavior use the existing responsive drawer and focus trap

End-to-end verification applies the migration and deploys the Edge Function, then uses controlled test accounts to prove self-change, other-user reset, forced next-login replacement, audit redaction, and invalid-current-password rejection.

## Scope

This feature does not expose existing passwords, add password fields to exports, reset disabled accounts, implement email recovery links, or redesign the broader Administration workspace.
