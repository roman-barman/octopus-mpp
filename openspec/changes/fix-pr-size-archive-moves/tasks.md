# Tasks

## 1. Rename-aware measurement

- [x] 1.1 Rewrite the diff loop in `scripts/ci/pr-size.sh` to read `git diff --numstat -z -M "$merge_base" HEAD` without pathspecs, resolve rename records to their destination path, and skip `Cargo.lock` and `openspec/changes/archive/*` by destination; keep the summary output unchanged. Verify: `shellcheck scripts/ci/pr-size.sh` passes and, on branch `chore/archive-ci-pr-size-limit`, `scripts/ci/pr-size.sh origin/main` reports 81 lines and 2 files (README plus the new main spec).
- [x] 1.2 Extend `scripts/ci/pr-size-test.sh`: add `openspec/changes/sample/` with several files to the base commit; add a scenario that `git mv`s it into `openspec/changes/archive/` and adds a 5-line `openspec/specs/` file (expect 5 lines, 1 file); add a scenario that moves an archived file to `openspec/specs/` with a 2-line edit (expect 1 file, 2 lines). Verify: `shellcheck` passes and the test reports every scenario, including all pre-existing ones, as passed.

## 2. Integration

- [ ] 2.1 Open the PR; verify the `pr-size` check passes on it and its log shows the test scenarios passing, then record the run link in the PR body.

## Workflow follow-up

- Archive the change after the PR is merged; the archive PR itself is the first real exercise of the fix.
