# Spec Delta

## Purpose

Catches violations of the repository's git and code rules on the developer's machine, at commit and push time, before CI or the owner sees them.

## ADDED Requirements

### Requirement: Hooks are versioned and installed by one command
The hooks SHALL live in the repository under `scripts/hooks/` and SHALL be activated by one documented command that points git's hooks path at that directory. The installer SHALL be idempotent.

#### Scenario: Fresh clone
- **WHEN** a developer runs the documented install command in a fresh clone
- **THEN** `git config core.hooksPath` resolves to the repository's hooks directory and every later commit and push runs the hooks

#### Scenario: Installed twice
- **WHEN** the install command runs in a clone where the hooks are already installed
- **THEN** it exits 0 and the configuration is unchanged

### Requirement: No commits on main
The `pre-commit` hook SHALL refuse a commit when the current branch is `main`.

#### Scenario: Commit on main
- **WHEN** a developer commits while `main` is checked out
- **THEN** the commit is refused and the message tells them to create a `<type>/<topic>` branch

### Requirement: Branch naming
The `pre-commit` hook SHALL refuse a commit when the current branch name is not `<type>/<topic>` with `type` one of `feat`, `fix`, `chore`, `docs`, `spec` and `topic` made of lowercase letters, digits, and hyphens.

#### Scenario: Wrong type
- **WHEN** a developer commits on a branch named `feature/codec`
- **THEN** the commit is refused and the message lists the allowed types

#### Scenario: Detached HEAD
- **WHEN** a developer commits in detached HEAD state (for example during a rebase)
- **THEN** the branch checks are skipped and the remaining pre-commit checks run

### Requirement: Formatting at commit time
The `pre-commit` hook SHALL check the formatting of the staged content (the tree the commit will contain), not the working tree, SHALL refuse the commit when any file is unformatted, and SHALL skip the check when neither a Rust file nor a file that governs formatting (`rustfmt.toml`, a `Cargo.toml`, `rust-toolchain.toml`) is staged.

#### Scenario: Unformatted staged file
- **WHEN** a staged `.rs` file is not formatted
- **THEN** the commit is refused and the output names the file

#### Scenario: Unformatted working copy, formatted index
- **WHEN** the staged `.rs` file is formatted but the working copy of the same file is not
- **THEN** the commit is accepted

#### Scenario: Docs-only commit
- **WHEN** the staged changes contain no `.rs` file and no formatting configuration
- **THEN** the formatting check is skipped and the hook exits 0

### Requirement: Message cleanup before checking
The `commit-msg` hook SHALL apply the cleanup git applies per `commit.cleanup` before any check: cut at the scissors line (built from `core.commentChar`), drop comment lines unless the mode keeps them (`whitespace`, `scissors`, `verbatim`), and trim blank padding, so that the subject is the first remaining line and the body is the rest. In the default mode, where git keeps comments for `-m`/`-F`, a leading comment line SHALL be refused unless the file looks like an editor template.

#### Scenario: Editor template
- **WHEN** the message file starts with a blank line followed by git's `#` comment block and the subject typed below it
- **THEN** the hook checks the typed subject, not the blank line or a comment

#### Scenario: Leading comment with -F in default mode
- **WHEN** a message file given with `-F` starts with a single `#` line
- **THEN** the commit is refused, because git would commit that line as the subject

### Requirement: Commit subject conventions
The `commit-msg` hook SHALL refuse a commit whose subject line is longer than 72 characters, does not start with an uppercase letter, ends with a period, or starts with a past-tense or gerund verb form (first word ending in `ed` or `ing`, except a documented list of imperative verbs with those endings), and SHALL skip these checks for `fixup!`, `squash!`, `amend!`, merge (in progress, or git's own merge subject forms), and git-generated revert subjects.

#### Scenario: Past tense subject
- **WHEN** the subject is `Added the codec crate`
- **THEN** the commit is refused and the message shows the imperative form rule

#### Scenario: Imperative verb on the exception list
- **WHEN** the subject is `Embed the codec options in the plan`
- **THEN** the hook accepts the subject

#### Scenario: Fixup commit
- **WHEN** the subject starts with `fixup! `
- **THEN** the hook exits 0 without checking the subject or the body

### Requirement: Subject is one paragraph of one line
The `commit-msg` hook SHALL refuse a message whose second line is not blank, because git makes the whole first paragraph the subject.

#### Scenario: Second line glued to the subject
- **WHEN** the message is `Add a note` followed directly by `quality-gates: 2.2` with no blank line
- **THEN** the commit is refused and the message asks for a blank line after the subject

### Requirement: Reference line format
The `commit-msg` hook SHALL treat as an OpenSpec reference every body line `<change>: <ids>` whose key is lowercase kebab-case and whose right-hand side is a comma-separated list of task ids (`N` or `N.M`), optionally followed by a parenthesized note, or the phrase `planning artifacts only`. Other lines are prose and are not checked.

#### Scenario: Trailers and prose are not references
- **WHEN** the body contains `Co-Authored-By: ...`, `Note: see D2`, and `octopus-codec: plan codecs and options` lines and one valid reference
- **THEN** the hook exits 0

### Requirement: References name an existing change
The `commit-msg` hook SHALL refuse the commit when any reference names a change that is neither `openspec/changes/<change>/` nor `openspec/changes/archive/<date>-<change>/` with an exact `YYYY-MM-DD-` prefix, even when another reference is valid.

#### Scenario: Unknown change name
- **WHEN** the body cites `v1-readonly-engine: 1.3` and no such change directory exists
- **THEN** the commit is refused and the message lists the existing change names

#### Scenario: Unknown reference next to a valid one
- **WHEN** the body cites both `quality-gates: 2.2` and `qualty-gates: 2.3`
- **THEN** the commit is refused and the message names `qualty-gates`

#### Scenario: Suffix of an archived name
- **WHEN** the body cites `limit: 1` and the archive contains `2026-11-10-ci-pr-size-limit`
- **THEN** the commit is refused

### Requirement: Body without a reference needs an explicit opt-out
The `commit-msg` hook SHALL refuse a commit whose body has no reference and no line `No OpenSpec change: <reason>`.

#### Scenario: Missing reference
- **WHEN** the body has neither an OpenSpec reference nor a `No OpenSpec change:` line
- **THEN** the commit is refused and the message shows both accepted forms

### Requirement: Push gate
The `pre-push` hook SHALL refuse a push that updates the remote `main` branch and SHALL accept every other push without running further checks; formatting, lints, tests, and the pull request size are verified by CI on the pull request.

#### Scenario: Push to main
- **WHEN** a developer pushes a branch to `refs/heads/main` on the remote
- **THEN** the push is refused with a message pointing to pull requests

#### Scenario: Branch deletion
- **WHEN** a developer runs `git push origin --delete feat/old`
- **THEN** the hook exits 0

#### Scenario: Feature branch with a clippy warning
- **WHEN** a developer pushes a feature branch whose code has a clippy warning
- **THEN** the push is accepted and the `clippy` CI check reports it on the pull request


### Requirement: Hooks are tested
The hooks SHALL have a test script that runs every scenario above in a throwaway repository without network access and exits non-zero when any scenario fails.

#### Scenario: Test run
- **WHEN** the hook test script runs
- **THEN** it reports each scenario as passed and exits 0
