# Tasks

This change is small: the planning artifacts land in one `spec/pr-size-base-change` pull request, and the tasks below plus the archive land in a second one.

## 1. Re-run on a base change and document the base argument

- [ ] 1.1 Add `edited` to the `types` of the `pull_request` trigger in `.github/workflows/pr-size.yml` and extend the comment above it: `edited` is there for base-branch changes, and the job deliberately runs on title and body edits too (design D1); verify the workflow file parses by the `pr-size` check running on the implementation PR
- [ ] 1.2 Rewrite the "Pull request size" section of `README.md` to say the size is measured from the merge-base with the PR's base branch and to give the command as `scripts/ci/pr-size.sh origin/<base-branch>` with `origin/main` as the usual value, and make the usage comment of `scripts/ci/pr-size.sh` say the same; verify `shellcheck scripts/ci/pr-size.sh` passes, `scripts/ci/pr-size-test.sh` passes, and `scripts/ci/pr-size.sh origin/main` runs as written
- [ ] 1.3 Probe both scenarios of the new requirement on the implementation branch: open a throwaway draft PR `A` to `main` from a branch with one added file, and a throwaway draft PR `B` stacked on `A`'s branch with one more added file, both branches cut from the implementation branch so that they carry the new workflow; verify with `gh run list --workflow pr-size.yml --branch <B's branch> --json event,databaseId,conclusion` and the run logs that (a) `gh pr edit B --base main` starts a new `pr-size` run whose log shows both added files counted, and (b) `gh pr edit B --body ...` starts another run with the same result; close both PRs without merging, delete both branches, and record the run links in the implementation PR body

## Workflow follow-up

- A `docs/` PR for `CLAUDE.md`, outside OpenSpec: the size-limit bullet says no check re-runs on a base change; after this change `pr-size` does, the six `ci.yml` gates still do not.
- Archive the change in the same pull request as tasks 1.1 to 1.3.
