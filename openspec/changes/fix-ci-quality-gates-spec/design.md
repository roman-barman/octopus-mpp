# Design

## Context

`openspec/specs/ci-quality-gates/spec.md` was published by archiving `quality-gates`. Two of its requirements describe the gates less precisely than `.github/workflows/ci.yml` and `scripts/ci/crate-deps.sh` implement them (see the proposal). The implementation is right in both cases, so only the spec text moves.

## Goals / Non-Goals

- Goal: the living spec alone tells a reader which crate edges are allowed and when the gates run.
- Non-goal: changing what any gate accepts or rejects, any trigger, or the ruleset. The script edits are comments, one message, and one test scenario.
- Non-goal: changing design D2 of `v1-read-only-engine`; it stays the place that explains why the edges are what they are.

## Decisions

### D1. The edge table lives in two places, on purpose

The requirement carries the full table, and `scripts/ci/crate-deps.sh` keeps its hard-coded `ALLOWED` table. Generating one from the other would need a parser for a Markdown table or a data file both read, which is more machinery than nine rows deserve. The cost is that a change to the edges must touch both; that change is an OpenSpec change with a MODIFIED requirement anyway, and its review compares the two tables (task 1.1 does it once now). So that an editor of either table learns about the other, the script's comments and its failure message name the requirement, and stop calling the script's table "the single source of truth" (task 1.2). The failure message matters most: it is what a developer sees when the gate is red, and a pointer to design D2 would dangle once `v1-read-only-engine` is archived.

`octopus-config` has a row in the spec table ("no workspace crate") and no key in `ALLOWED`: the script gives every crate without a key an empty allowance. The row is there so that the table names all nine crates; the script is not changed to match.

Alternative considered: keep the pointer to D2 and wait until `v1-read-only-engine` is archived. Rejected: the pointer would dangle at exactly the moment the largest change of the project is archived, and until then the spec is not self-contained.

### D2. The trigger is stated as behavior, the ruleset as scope

The requirement says the gates run on every pull request and on pushes to `main`, and separately that the ruleset requires them for pull requests targeting `main`. These are two facts with different owners (the workflow file, the repository ruleset), and merging them into one sentence is what made the published text wrong.

## Risks / Trade-offs

- [The two edge tables drift apart] → Any edit to either is a reviewed change; the `deps` gate enforces the script's table, so a drift shows as a spec that is wrong, not as a gate that is silent.
