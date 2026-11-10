# Design

## Context

See proposal.md for motivation. Relevant current state:

- The repository is public, so GitHub Actions is free and available; there is no `.github/` directory yet.
- The `protect-main` ruleset (id 26716811) has three rules: `deletion`, `non_fast_forward`, and `pull_request` (rebase only, 0 approvals, thread resolution required). It has no `required_status_checks` rule.
- GitHub rulesets have no native "maximum diff size" rule. The only way to block merging on size is a required status check produced by CI.
- Agents operate under the owner's GitHub credentials. The platform cannot tell agent and owner apart, so the override policy is a procedural rule in `CLAUDE.md`, like the existing merge rule.
- `v1-read-only-engine` task 1.4 will later add `ci.yml` (fmt, clippy, tests) to the same directory. This change does not depend on it.

## Goals / Non-Goals

**Goals:**
- A size check whose logic the owner can read and run locally in under a minute.
- No third-party actions beyond `actions/checkout`; no new runtime dependencies.
- The check re-evaluates when the override label is added or removed.

**Non-Goals:**
- Per-commit size limits (rebase-only merging already asks for self-contained commits; revisit if PRs stay small but commits do not).
- Labelling PRs by size bucket (`size/xs` ... `size/xl`).
- Measuring anything other than the final PR diff (no complexity metrics, no review-time estimates).

## Decisions

### D1. Logic lives in `scripts/ci/pr-size.sh`, the workflow only calls it
A standalone POSIX-ish bash script takes the base ref as an argument, reads thresholds and the override flag from environment variables with defaults (`PR_SIZE_MAX_LINES=500`, `PR_SIZE_MAX_FILES=20`, `PR_SIZE_OVERRIDE=false`), prints a short summary table, and exits non-zero on failure. The workflow is ~30 lines of YAML that checks out the PR head, fetches the base branch, and runs the script.

*Why:* the owner can run `scripts/ci/pr-size.sh origin/main` on any branch before pushing, and the script can be tested without GitHub. Alternatives: inline bash in the workflow (not runnable locally, not testable), a marketplace action such as `pr-size-labeler` (external code in the merge path, exclusions harder to express), or `gh pr view --json additions,deletions` (counts everything, cannot exclude `Cargo.lock`).

### D2. Measurement is `git diff --numstat <base>...HEAD` with pathspec exclusions
The three-dot form diffs from the merge-base, so unrelated commits on `main` are not counted. Exclusions are git pathspecs: `':(exclude)Cargo.lock'` and `':(exclude)openspec/changes/archive/**'`. Binary files appear as `-\t-\tpath` in numstat and are counted as one file with zero lines. Renames count as one file with the reported line changes.

*Why:* git already does the work; the script only sums columns. The alternative of counting via the GitHub API cannot apply exclusions.

### D3. Checkout the PR head, not the merge ref
The workflow checks out `github.event.pull_request.head.sha` with `fetch-depth: 0` and fetches `origin/<base_ref>`. The default `pull_request` checkout is a synthetic merge commit, whose diff against the base would include the merge itself and can hide conflicts.

### D4. Override is a label, evaluated by the workflow and passed to the script
The workflow triggers on `pull_request` types `opened, synchronize, reopened, labeled, unlabeled` and sets `PR_SIZE_OVERRIDE` from `contains(github.event.pull_request.labels.*.name, 'size/override')`. The script, when the override is set and a limit is exceeded, prints the measurements with an explicit override notice and exits 0.

*Why:* `labeled`/`unlabeled` triggers make the check re-run when the owner adds or removes the label, satisfying the spec without manual re-runs. A comment-based override (`/override`) would need a bot token and more code.

### D5. The required status check is added by the owner, after the first run
The job is named `pr-size`; that name is the status context. The owner adds a `required_status_checks` rule with context `pr-size` and `strict_required_status_checks_policy: false` to ruleset 26716811 (via the UI or `gh api -X PUT`). The rule is added after the PR introducing the workflow has produced its first `pr-size` result, so the check exists when it becomes required.

*Why:* `CLAUDE.md` forbids agents from editing the ruleset, and this change does not relax that. `strict` is left off because the project already requires rebasing before review; enabling it would block merges on every unrelated push to `main`.

### D6. Planning artifacts are part of the limit and land in a `spec/` PR
OpenSpec proposals, specs, designs and tasks count. Because a change's planning artifacts alone can approach the limit, each change lands them in a dedicated `spec/<change>` PR before implementation PRs. `CLAUDE.md` says so explicitly.

*Why:* excluding `openspec/changes/**` would exempt exactly the documents the owner most needs to read. The cost is one extra PR per change, which also gives the owner a clean approval point for the plan.

### D7. A test script exercises the size script in a throwaway repository
`scripts/ci/pr-size-test.sh` creates a temporary git repository, builds branches for each scenario in the spec (under limit, over lines, over files, excluded paths, binary file, override, base moved ahead) and asserts the exit code and key output lines. It runs locally and as a step in the same workflow on every PR.

*Why:* the gate is itself code the owner must trust; a few dozen lines of test keep it honest without introducing a test framework.

## Risks / Trade-offs

- [The first PR of a large change may hit the limit on its planning artifacts alone] → Split the change, or the owner adds `size/override` with the agent's justification. This is the intended pressure.
- [`labeled`/`unlabeled` events run the workflow even for unrelated labels] → Each run is a few seconds on a public repository; acceptable.
- [A required check named `pr-size` blocks merging if the workflow is ever renamed or removed] → Renaming the job is a change that also updates the ruleset; documented in `CLAUDE.md` next to the merge rule.
- [Forks: `pull_request` from a fork still runs with read-only token] → The script needs no token, so fork PRs are measured correctly.
- [Agents could add the label since they act as the owner] → Procedural rule in `CLAUDE.md`, same enforcement model as "agents never merge". The owner sees every label change in the PR timeline.

## Migration Plan

1. PR 1 (`spec/ci-pr-size-limit`): the OpenSpec artifacts. Merged by the owner.
2. PR 2 (`chore/pr-size-gate`): workflow, script, test script, `CLAUDE.md` update. The `pr-size` check runs on this PR for the first time.
3. Owner: create the `size/override` label and add the `required_status_checks` rule to `protect-main`.
4. Merge PR 2. From now on every PR to `main` is gated.

Rollback: remove the `required_status_checks` rule from the ruleset; the workflow then only reports.
