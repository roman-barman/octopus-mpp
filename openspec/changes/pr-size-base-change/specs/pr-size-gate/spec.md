# Spec Delta

## ADDED Requirements

### Requirement: Base branch change re-runs the gate
The gate SHALL re-run when the base branch of a pull request changes, and SHALL then measure against the new base branch, so that a mergeable pull request does not keep a verdict computed for a base it no longer has. A pull request that conflicts with its new base gets no run; the gate runs again at the next push to the pull request.

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
