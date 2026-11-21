# Tasks

This change is small: the planning artifacts land in one `spec/fix-ci-quality-gates-spec` pull request, and the tasks below plus the archive land in a second one.

## 1. Bring the references and the test in line with the new text

- [ ] 1.1 Compare the table of the "Crate dependency direction" requirement with the `ALLOWED` table in `scripts/ci/crate-deps.sh`, crate by crate; verify the eight `ALLOWED` entries equal their eight rows and that `octopus-config`, the ninth row, has no entry and is therefore allowed no workspace dependency, and record the comparison in the PR body
- [ ] 1.2 In `scripts/ci/crate-deps.sh` reword the header comment, the comment above `ALLOWED`, and the failure message, in `.github/workflows/ci.yml` the name of the `deps` step, and in `README.md` the `deps` row of the "Quality gates" table, so that each names the "Crate dependency direction" requirement of `openspec/specs/ci-quality-gates/spec.md` as the statement of the allowed edges (design D2 of `v1-read-only-engine` may stay as the rationale) and the script no longer calls its table "the single source of truth"; verify `shellcheck scripts/ci/crate-deps.sh` passes, `scripts/ci/crate-deps-test.sh` passes, and `grep -rn "D2" scripts/ci .github README.md` shows no line that presents D2 as the definition of the edges
- [ ] 1.3 In `scripts/ci/crate-deps-test.sh` add a scenario that adds a new workspace member absent from `ALLOWED` and from the spec table, makes it depend on `octopus-config`, and expects exit 1 with the edge named; rename the existing `octopus-config -> octopus-storage` scenario after the `octopus-config` row it tests; verify `shellcheck` passes and every scenario, old and new, passes
- [ ] 1.4 Compare the "One required check per gate" requirement with the `on:` block of `.github/workflows/ci.yml` and with `gh api repos/roman-barman/octopus-mpp/rulesets/26716811`; verify the workflow triggers on `pull_request` without a branch filter and on `push` to `main`, and that the ruleset condition is the default branch and its required checks include the six gate contexts (`pr-size`, the seventh, belongs to the `pr-size-gate` capability)
- [ ] 1.5 Record in the PR body two observed runs that back the added scenarios: a `ci` run on a pull request whose base is not `main` with all six gates reporting, and a `ci` run triggered by a push to `main`; verify both links open runs with the six jobs

## Workflow follow-up

- Archive the change in the same pull request as tasks 1.1 to 1.5, so that the two requirements of `openspec/specs/ci-quality-gates/spec.md` are replaced by the delta.
