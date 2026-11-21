# Tasks

This change is small: the planning artifacts land in one `spec/fix-ci-quality-gates-spec` pull request, and the verification below plus the archive land in a second one.

## 1. Verify the new text against the implementation

- [ ] 1.1 Compare the table of the "Crate dependency direction" requirement with the `ALLOWED` table in `scripts/ci/crate-deps.sh`, crate by crate; verify they list the same nine crates and the same edges, and that `scripts/ci/crate-deps-test.sh` has a passing scenario for a crate missing from the table (add the scenario if it has none)
- [ ] 1.2 Compare the "One required check per gate" requirement with the `on:` block of `.github/workflows/ci.yml` and with `gh api repos/roman-barman/octopus-mpp/rulesets/26716811`; verify the workflow triggers on `pull_request` without a branch filter and on `push` to `main`, and that the ruleset condition is the default branch with the six contexts required
- [ ] 1.3 Verify on this change's own pull requests that all six gates report a verdict, and record the run link in the PR body

## Workflow follow-up

- Archive the change in the same pull request as tasks 1.1 to 1.3, so that the two requirements of `openspec/specs/ci-quality-gates/spec.md` are replaced by the delta.
