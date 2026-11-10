# Spec Delta

## Purpose

Keeps every pull request small enough for the owner to read in full by measuring the diff size in CI and blocking the merge of oversized pull requests unless the owner explicitly overrides.

## ADDED Requirements

### Requirement: Diff is measured against the merge-base
The gate SHALL measure a pull request as the diff between the merge-base of the PR head and the target branch and the PR head commit, so that commits already on the target branch are not counted.

#### Scenario: Target branch moved ahead
- **GIVEN** a PR branch created from `main` and `main` has since received unrelated commits
- **WHEN** the gate runs
- **THEN** only the lines and files changed on the PR branch are counted

### Requirement: Line limit
The gate SHALL fail when the sum of added and deleted lines across counted files exceeds 500.

#### Scenario: At the limit
- **WHEN** a PR changes exactly 500 lines across counted files
- **THEN** the gate passes

#### Scenario: Over the limit
- **WHEN** a PR changes 501 or more lines across counted files
- **THEN** the gate fails and its output names the measured line count and the limit

### Requirement: File limit
The gate SHALL fail when the number of counted changed files exceeds 20, regardless of the line count.

#### Scenario: Many small edits
- **WHEN** a PR changes 21 files with one line each
- **THEN** the gate fails and its output names the measured file count and the limit

#### Scenario: Binary file
- **WHEN** a PR adds a binary file
- **THEN** the file counts as one changed file and contributes zero lines

### Requirement: Excluded paths
The gate SHALL exclude `Cargo.lock` and every path under `openspec/changes/archive/` from both the line count and the file count. All other paths, including documentation and OpenSpec artifacts, SHALL count.

#### Scenario: Lockfile churn
- **WHEN** a PR changes 10 lines of code and 2000 lines of `Cargo.lock`
- **THEN** the gate measures 10 lines and 1 file and passes

#### Scenario: Archiving a change
- **WHEN** a PR moves a completed change into `openspec/changes/archive/` and updates `openspec/specs/`
- **THEN** only the files under `openspec/specs/` and any other non-excluded paths are counted

### Requirement: Override label
The gate SHALL pass a PR that carries the `size/override` label even when a limit is exceeded, and SHALL still report the measured size and state that the override is in effect. Adding or removing the label SHALL re-run the gate.

#### Scenario: Owner overrides
- **GIVEN** a PR that exceeds a limit
- **WHEN** the owner adds the `size/override` label
- **THEN** the gate re-runs, passes, and its output shows the measured size with an override notice

#### Scenario: Override removed
- **GIVEN** a PR that exceeds a limit and carries the `size/override` label
- **WHEN** the label is removed
- **THEN** the gate re-runs and fails

### Requirement: Gate blocks merging
The gate SHALL be a required status check for pull requests targeting `main`, so that a PR with a failed or missing gate result cannot be merged by anyone, including the repository owner.

#### Scenario: Oversized PR without override
- **WHEN** a PR exceeds a limit and has no `size/override` label
- **THEN** GitHub reports the PR as not mergeable until the branch is reduced or the label is added

### Requirement: Agent conduct around the limit
Agents working in the repository MUST keep every PR within the limits, splitting a task group across several PRs when needed. Agents MUST NOT add the `size/override` label. An agent MAY ask the owner to add it only together with a written justification explaining why the PR cannot be split smaller.

#### Scenario: Task group too large for one PR
- **WHEN** an agent finds that a task group would exceed a limit
- **THEN** it splits the work into several PRs, each self-contained and buildable, and notes the split in each PR body

#### Scenario: Split is impossible
- **WHEN** an agent cannot bring a PR under the limit (for example, a generated file or a single atomic rename)
- **THEN** it stops before asking for review, explains in the PR body and to the owner why the PR cannot be made smaller, and waits for the owner to add the label or decline
