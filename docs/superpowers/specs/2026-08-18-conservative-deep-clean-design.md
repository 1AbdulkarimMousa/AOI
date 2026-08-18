# AOI Conservative Deep-Clean Design

## Goal

Reduce verified dead code and reproducible local disk usage without changing product behavior, deleting user-authored source material, weakening security coverage, or disturbing active worktrees.

## Scope

### Tracked Repository Cleanup

- Remove workspace template sections that are permanently rewritten to unreachable legacy views or hidden output.
- Remove state, methods, tests, and selectors used only by those deleted sections.
- Remove template rewrite calls whose source no longer exists or whose replacement is identical.
- Remove browser API wrappers and controller members with no repository consumers.
- Remove compatibility wrappers used only by tests after moving those tests to canonical functions.
- Remove generic starter assets with no references.
- Remove obsolete stack-specific ignore entries, deferring `.vinext` and `.wrangler` until their generated directories are deleted after the first deployment.
- Correct README wording that describes Administration as non-embedded.

Only selectors exclusively coupled to deleted markup are removed. Broad CSS-family purges, dependency upgrades, shared-controller refactors, seed-script consolidation, and uncertain feature removal are outside this cleanup.

### Generated Local Cleanup

After tracked changes pass verification and deploy successfully:

- Stop the orphan Vite preview on port `4199`.
- Remove `dist/`, `node_modules/`, `.vinext/`, `.wrangler/`, `test-results/`, and `tsconfig.tsbuildinfo`.
- Leave dependencies removed; restore them later with `npm ci`.
- Preserve `supabase/.temp/` because deleting it requires an explicit relink operation.
- Remove the `.vinext` and `.wrangler` ignore entries in a focused follow-up commit, then deploy that final tracked state.

### Git Cleanup

- Remove only `/tmp/opencode/aoi-release1-verify`; it is clean, detached, and fully reachable from `main`.
- Preserve `feature/survey-suite` locally and remotely.
- Preserve `internal-chat-profiles` and its recovery reference.
- Preserve dirty `outreach-rebuild` and `survey-rebuild` worktrees without modification.

## Protected Files

The cleanup must not delete, stage, commit, or modify these files; their existing ignore treatment remains unchanged:

- `.env.local`
- `spb.md` until its credentials are rotated or revoked
- `131.md`
- `summary.md`
- `raw_data/`
- `deno.lock`

The unexecuted Deno test and lockfile policy remains a separate follow-up because the test covers security-sensitive code and is not proven obsolete.

## Implementation Sequence

1. Remove one high-confidence dead-code group at a time.
2. Run its closest static or domain tests immediately.
3. Run the complete local verification suite.
4. Obtain an independent diff review and address findings.
5. Commit tracked cleanup to `main`, push, wait for the GitHub Pages workflow, and smoke-test production.
6. Stop the preview process and remove approved generated artifacts.
7. Remove the `.vinext` and `.wrangler` ignore entries, run the focused cleanup contract, commit, push, and verify the final deployment.
8. Remove the approved detached worktree and verify all protected worktrees remain intact.

## Verification

The tracked cleanup is complete only when all of the following pass:

- `npm test`
- `npm run lint`
- `npm run test:e2e`
- `git diff --check`
- independent diff review
- GitHub Pages workflow
- production smoke test

The local cleanup is complete only when the approved generated paths and detached worktree are absent, protected files still exist, dirty worktrees retain their original changes, and the main worktree contains only the preserved untracked files.

## Rollback

Tracked cleanup is reversible through its Git commit. Generated artifacts are recreated with `npm ci` and `npm run build`. The detached verification worktree is removable only because its commit remains reachable from `main`; no dirty or recovery-bearing worktree is eligible for deletion.
