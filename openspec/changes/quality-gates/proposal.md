# Proposal

## Why

The project's quality rules (formatted code, no clippy warnings, passing tests, small PRs, no commits on `main`, imperative commit subjects that cite an OpenSpec task, the dependency direction of design D2) are enforced today by one CI check, `pr-size`, and otherwise by agent discipline. Task 1.3 of `v1-read-only-engine` is about to pull several hundred crates into the workspace; license, advisory, and duplicate-version gates are cheap to switch on while the dependency tree is empty and every gate is green, and expensive to retrofit afterwards.

## What Changes

- Add versioned **git hooks** under `scripts/hooks/` (`pre-commit`, `commit-msg`, `pre-push`) with a one-command installer, enforcing: no commits or pushes to `main`, branch names of the form `<type>/<topic>`, `cargo fmt --check` on the staged tree, commit subject conventions, and an OpenSpec reference in the commit body. Clippy, tests, and the PR size are CI-only checks.
- Add a **`ci.yml` GitHub Actions workflow** with one job per gate: `fmt`, `clippy`, `test`, `doc` (rustdoc with warnings denied), `deny` (`cargo deny`: advisories, licenses, duplicate versions, allowed sources), and `deps` (crate dependency direction from design D2 and `cargo modules dependencies --acyclic` for every crate). Each job name is a status check context to be required by the `protect-main` ruleset.
- Add **workspace lints** (`[workspace.lints]`) inherited by every crate: `unsafe_code` forbidden, `unwrap_used` denied, `missing_docs`, `unreachable_pub`, and `clippy::all` as warnings that CI turns into errors.
- Add a **`deny.toml`** with the license allowlist, advisory policy, a ban on multiple versions of any crate, and crates.io as the only allowed source (git sources allowed per pinned Ballista branch when D1 of `v1-read-only-engine` needs one).
- Update **`README.md`** with the install command and the local command for every gate. The matching agent rules (install the hooks after cloning, never bypass them with `--no-verify`, never add `#[allow]` without a comment stating why, the CI job names are required checks) go into **`CLAUDE.md`** through separate `docs/` PRs, as the owner's 2026-11-11 rule requires for that file; they are listed as workflow follow-up, not as tasks.
- **Supersede task 1.4 of `v1-read-only-engine`** (fmt, clippy, tests in CI): this change delivers it. The v1 task text is updated to point here and is checked when `ci.yml` is merged.

## Capabilities

### New Capabilities
- `git-hooks`: the local gates that run on commit and push in a clone with the hooks installed, what each one checks, and how it reports a refusal.
- `ci-quality-gates`: the checks every pull request must pass in CI beyond `pr-size`: formatting, lints, tests, documentation, dependency policy, dependency direction, and acyclic modules.

### Modified Capabilities
- none. `pr-size-gate` is unchanged; the `pre-push` hook only runs its existing script.

## Impact

- New files: `scripts/hooks/{lib.sh,pre-commit,commit-msg,pre-push,install.sh,hooks-test.sh}`, `.github/workflows/ci.yml`, `deny.toml`, `clippy.toml`, `scripts/ci/crate-deps.sh` and its test.
- Modified: root `Cargo.toml` (`[workspace.lints]`), every `crates/*/Cargo.toml` (`[lints] workspace = true`), `README.md`, `openspec/changes/v1-read-only-engine/tasks.md` (task 1.4). `CLAUDE.md` changes follow in `docs/` PRs outside this change.
- New developer tools, pinned by version and installed by `cargo install` in CI and by the developer locally: `cargo-deny` 0.20.2, `cargo-modules` 0.28.0. They are not workspace dependencies and never link into the binaries.
- GitHub repository settings (owner action): the new job names become required status checks in `protect-main`, after each has produced its first result.
- Task 1.3 of `v1-read-only-engine` waits for this change: its "one DataFusion, one Arrow" check becomes a permanent gate (`deny` job) instead of a one-time `cargo tree` look.
