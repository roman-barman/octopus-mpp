# Proposal

## Why

The project rule that the owner must be able to understand every line only holds if pull requests stay small enough to be read in one sitting. Today nothing enforces that: the `protect-main` ruleset requires a PR but accepts one of any size, and the repository has no CI at all yet. Adding the gate before the first code lands means every implementation PR of `v1-read-only-engine` is shaped by it from the start.

## What Changes

- Add a GitHub Actions workflow that runs on every pull request targeting `main` and fails when the diff against the merge-base exceeds **500 changed lines** (additions + deletions) or **20 changed files**.
- The measurement excludes `Cargo.lock` and `openspec/changes/archive/**`; everything else, including docs and OpenSpec artifacts, counts.
- The only escape hatch is the `size/override` label on the PR. With the label present the check passes but still reports the measured size.
- Make the check a **required status check** in the `protect-main` ruleset so that an oversized PR cannot be merged, not even by the owner.
- Add the agent rules to `CLAUDE.md`: keep every PR under the limit, split work across PRs when a task group is too large, never add the `size/override` label, and request it from the owner only with a written justification why the PR cannot be made smaller.
- Put the size logic in a small shell script with its own test script, so the owner can run and read it locally, instead of hiding it inside workflow YAML or a third-party action.

## Capabilities

### New Capabilities
- `pr-size-gate`: the repository's pull request size limit — what is measured, the thresholds, the exclusions, the override, and how the result blocks merging.

### Modified Capabilities
- none (no existing specs in `openspec/specs/`)

## Impact

- New files: `.github/workflows/pr-size.yml`, `scripts/ci/pr-size.sh`, `scripts/ci/pr-size-test.sh`.
- `CLAUDE.md`: new bullets in the "Git and GitHub" section.
- GitHub repository settings (owner action): a new `size/override` label and a `required_status_checks` rule in the `protect-main` ruleset. Agents do not edit the ruleset; the owner runs or explicitly authorizes that step.
- Process: planning artifacts of a change (proposal, specs, design, tasks) count toward the limit, so they land in their own `spec/<change>` PR before implementation PRs. The limit then also keeps proposals reviewable.
- No Rust code, no dependencies, no interaction with `v1-read-only-engine` task 1.4 beyond sharing the `.github/workflows/` directory (that task adds a separate `ci.yml`).
