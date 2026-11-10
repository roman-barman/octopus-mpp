# Tasks

## 1. Size script

- [x] 1.1 Write `scripts/ci/pr-size.sh`: takes the base ref as `$1`, reads `PR_SIZE_MAX_LINES` (default 500), `PR_SIZE_MAX_FILES` (default 20) and `PR_SIZE_OVERRIDE` (default `false`), runs `git diff --numstat <base>...HEAD` excluding `Cargo.lock` and `openspec/changes/archive/**`, counts binary entries as one file with zero lines, prints lines/files/limits, and exits 1 when a limit is exceeded unless the override is set (then prints an override notice and exits 0). Verify: `shellcheck scripts/ci/pr-size.sh` passes and `scripts/ci/pr-size.sh origin/main` on the current branch prints the summary and exits 0.
- [x] 1.2 Write `scripts/ci/pr-size-test.sh`: builds a temporary git repository and asserts exit codes and key output for the spec scenarios: exactly 500 lines passes, 501 fails, 21 one-line files fails, `Cargo.lock` and `openspec/changes/archive/**` are ignored, a binary file counts as one file and zero lines, override passes with a notice, and commits added to the base after branching are not counted. Verify: `scripts/ci/pr-size-test.sh` exits 0 and reports every scenario as passed; flipping one expected value makes it fail.

## 2. Workflow

- [x] 2.1 Add `.github/workflows/pr-size.yml`: trigger `pull_request` with types `opened, synchronize, reopened, labeled, unlabeled`; one job named `pr-size` that checks out `github.event.pull_request.head.sha` with `fetch-depth: 0`, fetches `origin/${{ github.base_ref }}`, runs `scripts/ci/pr-size-test.sh`, then runs `scripts/ci/pr-size.sh origin/${{ github.base_ref }}` with `PR_SIZE_OVERRIDE` set from `contains(github.event.pull_request.labels.*.name, 'size/override')`. Verify: the check appears as `pr-size` on the PR that introduces it and passes; the step log shows the measured size.
- [x] 2.2 Verify the override path end to end on the same PR: the owner temporarily adds `size/override`, the workflow re-runs on the `labeled` event and the log shows the override notice; the owner removes the label and the workflow re-runs on `unlabeled`. Record both run links in the PR body.

## 3. Rules for agents

- [x] 3.1 Update the "Git and GitHub" section of `CLAUDE.md`: state the limits (500 changed lines, 20 files, exclusions), that planning artifacts count and land in their own `spec/<change>` PR, that agents split task groups across PRs to stay under the limit, that agents never add `size/override`, that an agent may only ask the owner for it with a written justification why the PR cannot be made smaller, and that the `pr-size` job name is a required check and must not be renamed without updating the ruleset. Verify: the text is in English, fits in the existing bullet style, and the PR containing it stays under the limit.
- [x] 3.2 Add a `## Pull request size` note to `README.md` pointing contributors to the limit, the script for local checks, and the override label. Verify: the documented local command runs as written.

## 4. Repository settings (owner)

- [x] 4.1 Owner creates the label `size/override` (description: "Owner-approved exception to the PR size limit"). Verify: `gh label list` shows it.
- [x] 4.2 Owner adds a `required_status_checks` rule with context `pr-size` and `strict_required_status_checks_policy: false` to ruleset `protect-main` (id 26716811), after the workflow has produced its first result. Verify: `gh api repos/roman-barman/octopus-mpp/rulesets/26716811` lists the rule, and a PR with a failed `pr-size` check shows as not mergeable.

## Workflow follow-up

- Archive the change after task 4.2 is confirmed, so `pr-size-gate` becomes part of `openspec/specs/`.
