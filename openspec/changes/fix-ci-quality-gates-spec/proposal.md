# Proposal

## Why

The review of the `quality-gates` archive (PR #22) found two places where the published `ci-quality-gates` spec does not state what CI does:

- The "Crate dependency direction" requirement defines the allowed edges as "design D2 of `v1-read-only-engine`" and spells out only the executor and codec edges. D2 is a design decision of a change that is still in progress: once that change is archived or D2 is revised, the edges of the other six crates are specified nowhere in `openspec/specs/`.
- The "One required check per gate" requirement says CI runs "on every pull request targeting `main`". `.github/workflows/ci.yml` deliberately runs on every pull request whatever its base, so that an implementation PR stacked on a `spec/<change>` branch gets its verdict, and on every push to `main`, so that later pull requests start from a warm cache. A reader who trusts the spec could narrow the trigger and leave stacked PRs without a verdict.

Both are wording gaps, not defects in the gates. The owner asked for the fix on 2026-11-21.

## What Changes

- The "Crate dependency direction" requirement lists the allowed workspace dependencies of every crate itself, as a table equal to the one `scripts/ci/crate-deps.sh` enforces, and states that a crate missing from the table may depend on no workspace crate.
- The "One required check per gate" requirement says the gates run on every pull request whatever its base branch and on every push to `main`, and states that the ruleset makes them required only for pull requests targeting `main`. Two scenarios are added: a stacked pull request, and a push to `main`.
- No workflow, script, or lint changes: CI already behaves as the new text says.

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `ci-quality-gates`: two requirements are reworded to match the existing behavior. The other five requirements are unchanged.

## Impact

- Files: the delta spec for `ci-quality-gates`, and `openspec/specs/ci-quality-gates/spec.md` when the change is archived.
- No change to `.github/workflows/ci.yml`, `scripts/ci/crate-deps.sh`, the ruleset, `README.md`, or `CLAUDE.md`. The script and the README keep citing design D2 of `v1-read-only-engine` as the reason for the edges; the spec becomes the statement of what is enforced.
- When a later change revises the allowed edges, it now has a requirement to modify, next to the table in `crate-deps.sh`.
- No `design.md`: there is no technical decision to record, only two sentences brought in line with the implementation.
