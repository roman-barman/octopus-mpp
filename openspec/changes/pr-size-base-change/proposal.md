# Proposal

## Why

Pull requests are sometimes stacked: an implementation PR is opened on top of a `spec/<change>` branch (or any other unmerged branch) and retargeted to `main` when its parent merges. The size gate handles such a PR correctly while it is stacked, because `.github/workflows/pr-size.yml` measures against the PR's base branch. Two things around it are wrong, both found in the review of PR #24:

- The gate does not re-run when the base branch of a PR changes. The workflow triggers on `opened`, `synchronize`, `reopened`, `labeled`, and `unlabeled`, not on `edited`, which is the event GitHub sends for a base change. After a retarget to `main` the required `pr-size` check still shows the verdict computed against the old base, although the diff against `main` may be larger (the parent's commits count until the branch is rebased).
- The README tells a contributor to check the size with `scripts/ci/pr-size.sh origin/main`. For a stacked PR that counts the parent's commits too, so the local number disagrees with CI.

The owner approved the fix on 2026-11-21.

## What Changes

- `.github/workflows/pr-size.yml` also triggers on `edited`, so a base change produces a fresh verdict against the new base. The job runs on every `edited` event (a title or body edit too); it takes a few seconds. A `concurrency` group per pull request cancels a run that a newer event has overtaken, so the last event decides the verdict.
- The `pr-size-gate` spec gets one requirement: a change of the base branch re-runs the gate against the new base.
- The "Pull request size" section of `README.md` and the usage comment of `scripts/ci/pr-size.sh` say the argument is the PR's base branch, `origin/main` unless the PR is stacked.

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `pr-size-gate`: adds a requirement that a base-branch change re-runs the gate. The existing requirements are unchanged; "Diff is measured against the merge-base" already speaks of the target branch, not of `main`.

## Impact

- Files: `.github/workflows/pr-size.yml` (one trigger type and its comment), `README.md` (one section), `scripts/ci/pr-size.sh` (usage comment only), the delta spec for `pr-size-gate`.
- The job name `pr-size` and the required check context do not change. `scripts/ci/pr-size.sh` measures exactly as before.
- `.github/workflows/ci.yml` is not changed, and that is a known gap, not an equivalence: its six gates build GitHub's merge of the head into the base, so after a retarget their verdicts also belong to the old base. They catch up at the rebase the agent rules require after a parent merges, which is a push. Whether `ci.yml` should also run on `edited` (six jobs on every body edit) is left to the owner as a separate decision.
- `CLAUDE.md` says, once PR #24 is merged, that no check re-runs on a base change. That sentence becomes inexact for `pr-size` and is corrected by a `docs/` PR outside this change (workflow follow-up).
