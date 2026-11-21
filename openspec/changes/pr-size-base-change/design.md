# Design

## Context

`pr-size.yml` passes `origin/${{ github.base_ref }}` to `scripts/ci/pr-size.sh`, so the measurement already follows the base branch. What is missing is a run at the moment the base changes. GitHub reports a base change as the `pull_request` activity type `edited`, the same type it uses for title and body edits; the payload of a base change carries `changes.base`.

## Goals / Non-Goals

- Goal: after a base change, the `pr-size` check shows a verdict for the new base without anyone pushing.
- Goal: the documented local command gives the number CI gives, for a stacked pull request too.
- Non-goal: changing how the size is measured, the limits, the exclusions, or the override label.
- Non-goal: making the six `ci.yml` gates re-run on a base change. They do depend on the base (the default checkout of a `pull_request` run is the merge of head into base), so this is a gap left open on purpose: six jobs on every body edit is a cost the owner should weigh separately, and the rebase after a parent merges re-runs them anyway.

## Decisions

### D1. Run on every `edited` event, without filtering for base changes

The workflow adds `edited` to its `types` and runs the same job. It does not skip title and body edits.

Alternative considered: a job-level `if: github.event.action != 'edited' || github.event.changes.base`, so that only base changes re-run the gate. Rejected: a skipped job still reports a `pr-size` check for the head commit, with the conclusion "skipped", which GitHub accepts for a required check. An oversized pull request with a failed gate would turn mergeable the moment someone edited its body. Running the real measurement on every `edited` event cannot produce a wrong verdict, and the job takes a few seconds; agents edit PR bodies after each review round, so the cost is a handful of extra runs per pull request.

Alternative considered: filter at the step level (the job runs, the measuring step is skipped). Rejected for the same reason: the job would succeed without measuring.

### D2. A pull request that conflicts with its new base gets no run

GitHub starts no `pull_request` workflow for a pull request with merge conflicts, so a retarget that produces a conflict leaves the old verdict in place. This needs no handling: a conflicting pull request cannot be merged, and the rebase that resolves the conflict is a push, which triggers `synchronize` and a fresh measurement.

### D3. One run per pull request at a time

The workflow gets `concurrency: { group: pr-size-${{ github.event.pull_request.number }}, cancel-in-progress: true }`. Without it a push followed at once by a retarget starts two overlapping runs, one per base, and which of them the required check ends up showing depends on which finishes last. With it the run of the older event is cancelled, so the newest event, which carries the current base and the current labels, decides. A cancelled run leaves the check unsatisfied only until its successor finishes, a few seconds later.

## Risks / Trade-offs

- [GitHub retargets a stacked pull request automatically when its parent is merged and the parent's branch deleted; whether that sends `edited` is not documented clearly] → It cannot be probed with throwaway pull requests, because it needs a real merge (deleting an unmerged base branch closes the pull request instead). Task 1.4 observes it on this change itself: the implementation pull request is opened stacked on the `spec/pr-size-base-change` branch, and the owner's merge of the spec pull request is the retarget. If no run starts, the requirement is narrowed to manual base changes before the change is archived; the rebase the agent rules require after a parent merges re-runs the gate either way.
- [Extra runs on body edits] → A few seconds each; accepted in D1.
