# Spec Delta

## ADDED Requirements

### Requirement: Base branch change re-runs the gate
The gate SHALL re-run when the base branch of a pull request changes, and SHALL then measure against the new base branch, so that the reported verdict always belongs to the base the pull request currently has.

#### Scenario: Stacked pull request retargeted to main
- **GIVEN** a pull request stacked on a branch that is ahead of `main`, with a passing gate result
- **WHEN** its base branch is changed to `main` without a new push
- **THEN** the gate re-runs and measures the diff from the merge-base with `main`, which includes the commits of the former base branch that `main` does not have

#### Scenario: Title or body edited
- **WHEN** only the title or the body of a pull request is edited
- **THEN** the gate re-runs and reports the same verdict as before
