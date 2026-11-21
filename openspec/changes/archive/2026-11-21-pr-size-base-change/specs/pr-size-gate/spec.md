# Spec Delta

## ADDED Requirements

### Requirement: Base branch change re-runs the gate
The gate SHALL re-run when the base branch of a pull request changes, and SHALL then measure against the new base branch, so that a mergeable pull request does not keep a verdict computed for a base it no longer has. GitHub may start no run for a pull request that conflicts with its new base; the gate then runs again at the next push to the pull request.

#### Scenario: Stacked pull request retargeted to main
- **GIVEN** a pull request stacked on a branch that is ahead of `main`, with a passing gate result
- **WHEN** its base branch is changed to `main` without a new push
- **THEN** the gate re-runs and measures the diff from the merge-base with `main`, which includes every commit of the former base branch that is not an ancestor of `main`, even when `main` already holds the same changes under new commit ids after a rebase merge, until the pull request is rebased on `main`

#### Scenario: Title or body edited
- **WHEN** only the title or the body of a pull request is edited
- **THEN** the gate re-runs and measures against the current tip of the base branch

#### Scenario: Retarget produces a conflict
- **GIVEN** a pull request whose base branch is changed to a branch it conflicts with
- **WHEN** the conflict is resolved by rebasing and pushing the branch
- **THEN** the gate runs on the push and measures against the new base branch

### Requirement: Every run uses the current base branch and labels
The gate SHALL measure against the base branch the pull request has at the time the job runs, and SHALL honor the `size/override` label only if the pull request carries it at that time, whatever the event that started or restarted the run said.

#### Scenario: Old run re-run after a retarget
- **GIVEN** a pull request whose gate passed against a former base branch and whose base branch has since been changed to `main`
- **WHEN** the old passing run is re-run
- **THEN** it measures the diff from the merge-base with `main`

#### Scenario: Old run re-run after the label was removed
- **GIVEN** an oversized pull request whose gate passed while it carried the `size/override` label, and the label has since been removed
- **WHEN** the old passing run is re-run
- **THEN** it fails
