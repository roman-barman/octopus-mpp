# Proposal

## Why

The review of the `quality-gates` archive (PR #22) found two places where the published `ci-quality-gates` spec does not state what CI does:

- The "Crate dependency direction" requirement defines the allowed edges as "design D2 of `v1-read-only-engine`" and spells out only the executor and codec edges. D2 is a design decision of a change that is still in progress: once that change is archived or D2 is revised, the edges of the other seven crates are specified nowhere in `openspec/specs/`.
- The "One required check per gate" requirement says CI runs "on every pull request targeting `main`". `.github/workflows/ci.yml` deliberately runs on every pull request whatever its base, so that an implementation PR stacked on a `spec/<change>` branch gets its verdict, and on every push to `main`, so that later pull requests start from a warm cache. A reader who trusts the spec could narrow the trigger and leave stacked PRs without a verdict.

Both are wording gaps, not defects in the gates. The owner asked for the fix on 2026-11-21.

## What Changes

- The "Crate dependency direction" requirement lists the allowed workspace dependencies of every crate itself, as a table that agrees with what `scripts/ci/crate-deps.sh` enforces (its eight `ALLOWED` entries, plus `octopus-config`, which the script covers by its default), and states that a crate missing from the table may depend on no workspace crate.
- The "One required check per gate" requirement says the gates run on pull requests without a base-branch filter and on every push to `main`, and states that the ruleset makes them required for pull requests targeting `main`. Two scenarios are added: a stacked pull request, and a push to `main`. The dependency requirement also gains scenarios for a build dependency and for a crate missing from the table, both already enforced.
- `scripts/ci/crate-deps.sh` (header comment, table comment, failure message), the `deps` step name in `.github/workflows/ci.yml`, and the `deps` row of the README table name the `ci-quality-gates` requirement as the statement of the allowed edges and no longer mention design D2 of `v1-read-only-engine`. The script no longer calls its table "the single source of truth".
- `scripts/ci/crate-deps-test.sh` gains a scenario for a workspace crate that the table does not list, and its existing `octopus-config` scenario is renamed after the row it now tests.
- No behavior change: the gates, the triggers, the `ALLOWED` table, and the ruleset stay as they are.

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `ci-quality-gates`: two requirements are reworded to match the existing behavior. The other five requirements are unchanged.

## Impact

- Files: the delta spec for `ci-quality-gates` (and `openspec/specs/ci-quality-gates/spec.md` when the change is archived), `scripts/ci/crate-deps.sh` (comments and one message), `scripts/ci/crate-deps-test.sh`, one step name in `.github/workflows/ci.yml`, one row of `README.md`.
- No change to job names, triggers, the ruleset, or `CLAUDE.md`.
- When a later change revises the allowed edges, it now has a requirement to modify, next to the table in `crate-deps.sh`.
