# Design

## Context

`pr-size.yml` passes `origin/${{ github.base_ref }}` to `scripts/ci/pr-size.sh`, so the measurement already follows the base branch. What is missing is a run at the moment the base changes. GitHub reports a base change as the `pull_request` activity type `edited`, the same type it uses for title and body edits; the payload of a base change carries `changes.base`.

## Goals / Non-Goals

- Goal: after a base change, the `pr-size` check shows a verdict for the new base without anyone pushing.
- Goal: the documented local command gives the number CI gives, for a stacked pull request too.
- Non-goal: changing how the size is measured, the limits, the exclusions, or the override label.
- Non-goal: making the six `ci.yml` gates re-run on a base change. They do depend on the base (the default checkout of a `pull_request` run is the merge of head into base), so this is a gap left open on purpose, by the owner's decision of 2026-11-21: six jobs on every body edit cost more than the gap, and the rebase after a parent merges re-runs them anyway.

## Decisions

### D1. Run on every `edited` event, without filtering for base changes

The workflow adds `edited` to its `types` and runs the same job. It does not skip title and body edits.

Alternative considered: a job-level `if: github.event.action != 'edited' || github.event.changes.base`, so that only base changes re-run the gate. Rejected: a skipped job still reports a `pr-size` check for the head commit, with the conclusion "skipped", which GitHub accepts for a required check. An oversized pull request with a failed gate would turn mergeable the moment someone edited its body. Running the real measurement on every `edited` event cannot produce a wrong verdict, and the job takes a few seconds; agents edit PR bodies after each review round, so the cost is a handful of extra runs per pull request.

Alternative considered: filter at the step level (the job runs, the measuring step is skipped). Rejected for the same reason: the job would succeed without measuring.

### D2. A pull request that conflicts with its new base gets no run

GitHub starts no `pull_request` workflow for a pull request with merge conflicts, so a retarget that produces a conflict leaves the old verdict in place. In the usual case this needs no handling: a conflicting pull request cannot be merged, and the rebase that resolves the conflict is a push, which triggers `synchronize` and a fresh measurement. One gap remains and is accepted: if the conflict disappears because the base branch changed, not the pull request, GitHub sends no event, and the pull request becomes mergeable with the verdict of its old base. The agent rules close it in practice (a retargeted pull request is rebased before review), and closing it in CI would need a scheduled re-check of open pull requests.

### D4. A red verdict right after a parent's rebase merge is expected

The repository merges by rebase, so the parent's commits land on `main` with new ids. A stacked pull request retargeted to `main` still contains the parent's original commits, the merge-base stays where it was, and the gate counts the parent's lines until the branch is rebased. A gate that turns red at that moment is correct: it tells the author to rebase, after which only the pull request's own lines remain.

### D3. One run per pull request at a time

The workflow gets `concurrency: { group: pr-size-${{ github.event.pull_request.number }}, cancel-in-progress: true }`. Without it a push followed at once by a retarget starts two overlapping runs, one per base, and which of them the required check ends up showing depends on which finishes last. With it the run that entered the group earlier is cancelled, so the run queued last decides; that is normally the newest event, which carries the current base and the current labels. GitHub does not promise to queue two events of the same second in order, so this narrows the race, it does not remove it. A cancelled run leaves the check unsatisfied only until its successor finishes, a few seconds later.

### D5. The job reads the base branch and the labels from GitHub when it runs

The measuring step calls `gh pr view <number> --json baseRefName,labels` and uses the answer, instead of `github.base_ref` and `github.event.pull_request.labels` from the event payload. The workflow gets the permission `pull-requests: read` for that call; `gh` is preinstalled on the runner and authenticates with the job's token.

Two defects found in the review of the implementation go away together. First, "Re-run" on an old run replays its old payload on the same head commit: a run that passed against a former base, or while `size/override` was set, would pass again and become the newest `pr-size` check. Reading the current state makes a re-run measure the pull request as it is. The label half of this defect is older than this change. Second, `${{ github.base_ref }}` was interpolated into the text of the shell command, so a branch named `x$(...)` would have run that substitution on the runner; the name now arrives as command output in a shell variable and is only ever expanded inside quotes. The pull request number, an integer, is passed through `env`.

Alternative considered: keep the payload and document that old runs must not be re-run. Rejected: a required check that a single click on the wrong run can turn green is not a check.

The head commit is still taken from the payload (`github.event.pull_request.head.sha`). A re-run of an old run therefore measures an old commit, and its result is attached to that commit, not to the current head, so it cannot satisfy the required check of a newer push.

## Risks / Trade-offs

- [GitHub retargets a stacked pull request automatically when its parent is merged and the parent's branch deleted; whether that sends `edited` is not documented clearly] → It cannot be probed with throwaway pull requests, because it needs a real merge (deleting an unmerged base branch closes the pull request instead). Task 1.4 observes it on this change itself: the implementation pull request is opened stacked on the `spec/pr-size-base-change` branch, and the owner's merge of the spec pull request is the retarget. If no run starts, the requirement is narrowed to manual base changes before the change is archived; the rebase the agent rules require after a parent merges re-runs the gate either way.
- [The label scenario of D5 cannot be probed by an agent: agents never add `size/override`] → Task 1.6 probes the base half by re-running a real old run; the label half goes through the same `gh pr view` call and the same variable, and the owner can toggle the label on a throwaway pull request to see it.
- [Extra runs on body edits] → A few seconds each; accepted in D1.
