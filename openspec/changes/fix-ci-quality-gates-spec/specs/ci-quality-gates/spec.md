# Spec Delta

## MODIFIED Requirements

### Requirement: One required check per gate
The CI SHALL run on every pull request, whatever its base branch, and on every push to `main`, with one job per gate, named `fmt`, `clippy`, `test`, `doc`, `deny`, and `deps`, so that each job name can be a required status check and a failure names the gate that failed. The repository ruleset SHALL require all six checks for pull requests targeting `main`.

#### Scenario: One gate fails
- **WHEN** a pull request targeting `main` fails only the `doc` gate
- **THEN** the `doc` check is reported as failed, the other five as passed, and the PR is not mergeable

#### Scenario: Stacked pull request
- **WHEN** a pull request targets a branch other than `main`, such as a `spec/<change>` branch
- **THEN** all six gates run on it and report their verdicts

#### Scenario: Push to main
- **WHEN** a pull request is merged and its commits are pushed to `main`
- **THEN** all six gates run on `main`

### Requirement: Crate dependency direction
The `deps` job SHALL fail when a workspace crate depends on another workspace crate outside the allowed edges below. A workspace crate missing from the table SHALL depend on no other workspace crate. Only normal and build dependencies are edges; `[dev-dependencies]` are not checked.

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

#### Scenario: Crate missing from the table
- **WHEN** a new workspace crate that the table does not list depends on `octopus-config`
- **THEN** the `deps` job fails and names the forbidden edge
