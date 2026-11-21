# ci-quality-gates Specification

## Purpose
Blocks the merge of any pull request whose code is unformatted, has lint warnings, fails tests or documentation, violates the dependency policy, or breaks the crate dependency direction.

## Requirements

### Requirement: One required check per gate
The CI SHALL run on pull requests without any filter on the base branch, and on every push to `main`, with one job per gate, named `fmt`, `clippy`, `test`, `doc`, `deny`, and `deps`, so that each job name can be a required status check and a failure names the gate that failed. The repository ruleset SHALL require these six checks for pull requests targeting `main`.

#### Scenario: One gate fails
- **WHEN** a pull request targeting `main` fails only the `doc` gate
- **THEN** the `doc` check is reported as failed, the other five as passed, and the PR is not mergeable

#### Scenario: Stacked pull request
- **WHEN** a pull request that has no conflict with its base targets a branch other than `main`, such as a `spec/<change>` branch
- **THEN** all six gates run on it and report their verdicts

#### Scenario: Push to main
- **WHEN** a pull request is merged and its commits are pushed to `main`
- **THEN** all six gates run on `main`

### Requirement: Formatting, lints, and tests
The `fmt` job SHALL fail on any `cargo fmt --check` difference; the `clippy` job SHALL fail on any warning across the workspace and all targets; the `test` job SHALL fail on any failing test in the workspace. Tests that need an external service (the Compose stand, MinIO) SHALL be marked `#[ignore]` so that `cargo test --workspace` passes on a machine without them.

#### Scenario: Warning in a test
- **WHEN** a `#[cfg(test)]` module produces a clippy warning
- **THEN** the `clippy` job fails

#### Scenario: Integration test without the stand
- **WHEN** the workspace contains a test that connects to the Compose stand and the stand is not running
- **THEN** the `test` job passes because that test is ignored by default

### Requirement: Documentation builds without warnings
The `doc` job SHALL build the workspace documentation, including private items, with rustdoc warnings denied.

#### Scenario: Broken intra-doc link
- **WHEN** a doc comment links to an item that does not exist
- **THEN** the `doc` job fails and names the link

### Requirement: Workspace lints
Every crate SHALL inherit the workspace lint table, which SHALL forbid `unsafe_code`, deny `clippy::unwrap_used`, and warn on `missing_docs`, `unreachable_pub`, `clippy::all`, and `clippy::allow_attributes_without_reason`; CI SHALL treat the warnings as errors. A local `#[allow(...)]` or `#[expect(...)]` SHALL carry a `reason = "..."` stating why.

#### Scenario: unwrap in production code
- **WHEN** a crate calls `.unwrap()` outside a `#[cfg(test)]` module
- **THEN** `cargo clippy` reports an error and the `clippy` job fails

#### Scenario: unwrap in a test
- **WHEN** a `#[cfg(test)]` module calls `.unwrap()` without any `#[allow]`
- **THEN** the `clippy` job passes

#### Scenario: Undocumented public item
- **WHEN** a crate exports a `pub` item without a doc comment
- **THEN** the `clippy` job fails

#### Scenario: Suppression without a reason
- **WHEN** a crate contains `#[allow(clippy::too_many_arguments)]` without a `reason`
- **THEN** the `clippy` job fails and names the attribute

### Requirement: Dependency policy
The `deny` job SHALL fail when any dependency has a known vulnerability, a license outside the project's allowlist, a source other than crates.io or an explicitly allowed git repository, or when two versions of the same crate are present in the lock file.

#### Scenario: Two Arrow versions
- **WHEN** the lock file resolves `arrow` 59 and `arrow` 60
- **THEN** the `deny` job fails and names both versions and the crates that pull them

#### Scenario: Copyleft license
- **WHEN** a dependency is licensed only under GPL-3.0
- **THEN** the `deny` job fails and names the crate

### Requirement: Crate dependency direction
The `deps` job SHALL fail when a workspace crate depends on another workspace crate outside the allowed edges listed in the table of the "Edge table" scenario. A workspace crate missing from the table SHALL depend on no other workspace crate. Only normal and build dependencies are edges; `[dev-dependencies]` are not checked.

#### Scenario: Edge table
- **WHEN** every workspace crate listed in this table has normal and build dependencies only on the workspace crates its row names, and every workspace crate not listed has none on any workspace crate
- **THEN** the `deps` job passes

| Crate | May depend on |
|---|---|
| `octopus-config` | no workspace crate |
| `octopus-storage` | `octopus-config` |
| `octopus-codec` | `octopus-config`, `octopus-storage` |
| `octopus-catalog` | `octopus-config`, `octopus-storage` |
| `octopus-auth` | `octopus-config` |
| `octopus-session` | `octopus-config`, `octopus-storage`, `octopus-catalog`, `octopus-auth`, `octopus-codec` |
| `octopus-gateway` | `octopus-config`, `octopus-catalog`, `octopus-auth`, `octopus-session` |
| `octopus-executor` | `octopus-config`, `octopus-storage`, `octopus-codec` |
| `octopus-scheduler` | `octopus-config`, `octopus-storage`, `octopus-catalog`, `octopus-auth`, `octopus-codec`, `octopus-session`, `octopus-gateway` |

#### Scenario: Executor links the catalog
- **WHEN** `octopus-executor` adds `octopus-catalog` to its dependencies
- **THEN** the `deps` job fails and names the forbidden edge

#### Scenario: Allowed edge
- **WHEN** `octopus-session` depends on `octopus-codec`
- **THEN** the `deps` job passes

#### Scenario: Test-only dependency
- **WHEN** a crate lists another workspace crate only under `[dev-dependencies]`
- **THEN** the edge is not checked and the `deps` job passes

#### Scenario: Build dependency
- **WHEN** `octopus-executor` lists `octopus-catalog` only under `[build-dependencies]`
- **THEN** the `deps` job fails and names the forbidden edge

#### Scenario: Crate missing from the table
- **WHEN** a new workspace crate that the table does not list depends on `octopus-config`
- **THEN** the `deps` job fails and names the forbidden edge

### Requirement: Local reproducibility
Every gate SHALL be runnable locally with a documented command that produces the same verdict as CI, using the pinned toolchain and pinned tool versions.

#### Scenario: Developer runs a gate
- **WHEN** a developer runs the documented command for the `deny` gate
- **THEN** the result matches the `deny` job on the same commit
