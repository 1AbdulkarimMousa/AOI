# AOI Conservative Deep-Clean Plan

## Batch 1: Lock The Cleanup Contract

- Add `tests/deep-clean.test.mjs` with source-level assertions that the approved dead identifiers, unreachable template markers, obsolete starter assets, and retired ignore rules are absent.
- Run the new test and confirm it fails against the current repository for the expected cleanup candidates.

## Batch 2: Remove Unreachable Workspace Surfaces

- Remove permanently hidden or renamed legacy Research, PMF, and EOD template sections from `src/js/workspace-template.js`.
- Remove ineffective template rewrites.
- Remove `selectedLayer`, `openPmfLayer`, `samplePercent`, and `overallSample` from `src/js/workspace.js`.
- Remove only CSS selectors dedicated to the deleted EOD entry and stale tests that require the removed UI.
- Run `tests/deep-clean.test.mjs`, `tests/workspace-repair.test.mjs`, `tests/workspace-consolidation.test.mjs`, and `tests/ui-foundations.test.mjs`.

## Batch 3: Narrow Unused Browser Surfaces

- Remove uncalled wrappers from `src/js/api.js` and stale wrapper assertions.
- Remove declaration-only controller state and methods from workspace, administration, participant tracker, and survey controllers.
- Remove unused CRM constants/helpers.
- Remove test-only compatibility wrappers after tests use canonical functions directly.
- Remove unnecessary `export` modifiers from module-private helpers.
- Run the closest domain and static contract tests.

## Batch 4: Remove Obsolete Repository Material

- Delete unreferenced starter SVGs and superseded `public/og.png`.
- Remove retired Next, Yarn/PnP, and Vercel ignore entries while retaining active environment, build, test, and security ignores. Keep `.vinext` and `.wrangler` ignored until their generated directories are deleted after deployment.
- Correct Administration wording in `README.md`.
- Run the cleanup contract and rendered/static application tests.

## Batch 5: Verify, Review, Commit, And Deploy

- Run `npm test`, `npm run lint`, `npm run test:e2e`, and `git diff --check`.
- Obtain an independent diff review and address findings.
- Commit the tracked cleanup to `main`, push to `origin`, wait for the Pages workflow, and smoke-test production.

## Batch 6: Local And Worktree Cleanup

- Stop the Vite preview on port `4199`.
- Remove approved generated artifacts and leave `node_modules/` absent.
- Remove the `.vinext` and `.wrangler` ignore entries, update and run the focused cleanup contract, commit, push, and verify the final deployment.
- Remove `/tmp/opencode/aoi-release1-verify`.
- Verify all protected files and preserved worktrees remain intact.
