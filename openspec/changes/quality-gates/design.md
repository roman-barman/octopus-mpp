# Design

## Context

See proposal.md for motivation. Current state:

- CI is one workflow, `pr-size.yml`, whose job `pr-size` is the only required status check in the `protect-main` ruleset (id 26716811). Its logic is a bash script with a test script in `scripts/ci/`; that pattern (script first, workflow only calls it) is the house style.
- `cargo fmt --check`, `clippy -D warnings`, and `cargo test` are run by hand before each PR (CLAUDE.md). The repository has no git hooks and no `[workspace.lints]`.
- The workspace is nine stub crates with empty `[dependencies]`; the toolchain is pinned to 1.98.1 in `rust-toolchain.toml`, which rustup on GitHub's Ubuntu runners honors automatically.
- Design D2 of `v1-read-only-engine` states the crate dependency graph; today it exists only in README prose.
- Tools checked on 2026-11-13: `cargo-deny` 0.20.2 (MSRV 1.88). `cargo-modules` 0.28.0 was evaluated for a module acyclicity check and dropped on 2026-11-15 (D8).

## Goals / Non-Goals

**Goals:**
- Every rule the gates enforce is readable bash or a declarative config file; no logic hidden in YAML or third-party actions.
- Local and CI verdicts agree: same toolchain, same tool versions, same commands.
- Gates land before task 1.3 pulls in the dependency tree.

**Non-Goals:**
- Code coverage thresholds, unused-dependency detection (`cargo udeps` needs nightly, `cargo machete` is heuristic), benchmark regression gates, and a `cargo xtask` crate: revisit when there is code worth measuring.
- Replacing `pr-size`; it stays a separate workflow and check.
- Enforcing anything on the owner's merge itself; merging stays a manual owner action.
- Module acyclicity inside a crate (owner decision 2026-11-15, D8): revisit when there is code to calibrate the rule on.

## Decisions

### D1. Hooks are plain bash in `scripts/hooks/`, activated with `core.hooksPath`
`scripts/hooks/install.sh` runs `git config core.hooksPath scripts/hooks`. The three hooks (`pre-commit`, `commit-msg`, `pre-push`) share nothing but a sourced `lib.sh` with the `refuse` helper that prints the rule, the offending value, and exits 1. No hook offers a skip flag: `git commit --no-verify` is the only bypass, and a `docs/` PR (workflow follow-up) adds the CLAUDE.md rule that agents never use it. Unlike the hooks a framework installs, these are reviewed in PRs like any other code.

*Alternatives:* `pre-commit` (Python runtime, YAML config, hooks fetched from the network) and `lefthook` (Go binary) were rejected: both add a runtime for what four scripts do, and the project already has the `pr-size.sh` pattern. `cargo-husky` was rejected because it installs hooks as a build side effect, which surprises readers.

### D2. Commit body rule: an OpenSpec reference or an explicit opt-out
`commit-msg` treats as a reference every body line `<key>: <ids>` where `<key>` matches `[a-z][a-z0-9-]*` and `<ids>` is a comma-separated list of task ids (`1`, `1.2`), optionally followed by a parenthesized note, or the phrase `planning artifacts only`. The right-hand side is what separates a reference from prose: `octopus-codec: plan codecs` is a sentence, `qualty-gates: 2.3` is a typo. The lowercase key additionally excludes git trailers (`Co-Authored-By:`). Each candidate's `<change>` must be a directory `openspec/changes/<change>/` or `openspec/changes/archive/YYYY-MM-DD-<change>/` (the date prefix is matched exactly, so `limit: 1` does not match `2026-11-10-ci-pr-size-limit`); one unknown candidate refuses the commit even when a valid one is present, because a typo next to a correct reference is still a typo. A body with no candidate must contain a line `No OpenSpec change: <reason>`. This mechanizes the CLAUDE.md rule and the owner's 2026-11-11 decision that CLAUDE.md edits bypass OpenSpec: those commits write `No OpenSpec change: agent conduct rules (CLAUDE.md)`. Merge, revert, `fixup!`, and `squash!` commits are exempt because git or the developer rewrites them before they reach a PR.

### D3. Imperative subject is checked by a word-ending heuristic
The first word of the subject may not end in `ed` or `ing`, and the subject must start uppercase and not end in a period. A verb list would be longer and still incomplete; the heuristic catches the actual mistakes (`Added`, `Fixing`). Its cost is real: imperative verbs such as `Embed`, `Feed`, `Ping`, `Thread`, `Proceed`, `Bring` end the same way, so the hook keeps an exception list seeded with the imperative verbs plausible in this project (`Bring Embed Exceed Feed Need Ping Proceed Ring Seed Shed Shred Speed Spread String Succeed Swing Thread`, extended by PR when a new one is hit) and the refusal message shows the rule and the list.

### D4. `pre-push` only guards `main`; `pre-commit` runs the fast checks
`pre-commit` runs branch checks and a formatting check of the index, not the working tree: it exports the staged tree with `git checkout-index -a --prefix=<tmpdir>/` and runs `cargo fmt --check` there (`cargo fmt` reads manifests only, no network), so the verdict is about the commit being created. Checking the working tree would pass an unformatted commit whenever the developer formatted after staging, and refuse a formatted one in the opposite case.

`pre-push` reads the ref updates from stdin, ignores branch deletions (local sha all zeros), and refuses if any update targets `refs/heads/main`; nothing else. **Owner decision, 2026-11-13:** the PR size, clippy, and tests are CI's job. A hook cannot know the pull request's base branch, can only check the working tree rather than the pushed commit, and would make every push wait for a compilation, while CI measures exactly the pushed commit against the real base and the agent reads the check results on the pull request. The refusal of pushes to `main` stays in the hook because it fires before any network round trip and with a message the GitHub ruleset does not give.

### D5. CI is one workflow, `ci.yml`, with six jobs that each call one command
Jobs: `fmt`, `clippy`, `test`, `doc`, `deny`, `deps`. Each job name is the status context the owner adds to the ruleset. Jobs run in parallel; `fmt` and `clippy` fail fast while `test` compiles. Only first-party actions are used (`actions/checkout`, `actions/cache`); the toolchain comes from `rust-toolchain.toml` through the runner's rustup. `cargo-deny` is installed with `cargo install --locked --version <pinned>`, guarded by `[ -x ~/.cargo/bin/cargo-deny ] || ...` because cargo decides "already installed" from `~/.cargo/.crates.toml`, which is not cached, and would otherwise rebuild on every run; only the resulting binary `~/.cargo/bin/cargo-deny` is cached, keyed on tool version and toolchain channel, so the install cost is paid once per bump and the runner's rustup proxies (`cargo`, `rustc`, `rustfmt`) are never overwritten by a cache from an older image. Build artifacts under `target/` are cached by `Cargo.lock` hash.

*Alternatives:* a single job running all checks (one red check does not tell which gate failed, and the ruleset could not require gates individually); `taiki-e/install-action` or `Swatinem/rust-cache` (faster, but third-party code in the merge path, which `pr-size` D1 already declined).

### D6. Lints live in `[workspace.lints]`, every crate inherits them
Root `Cargo.toml` gets `[workspace.lints.rust]` with `unsafe_code = "forbid"`, `missing_docs = "warn"`, `unreachable_pub = "warn"`, and `[workspace.lints.clippy]` with `all = "warn"`, `unwrap_used = "deny"`. Each crate adds `[lints] workspace = true`. Warnings become errors through `-D warnings` in CI and the `pre-push` hook, so local `cargo build` stays informative rather than blocking. A one-line `clippy.toml` at the workspace root sets `allow-unwrap-in-tests = true`, so `#[cfg(test)]` code may unwrap without a per-module `#[allow]` that nine crates would have to repeat; production code never unwraps. `expect_used` stays allowed (owner decision 2026-11-13): an `expect` with a message is an explicit invariant, an `unwrap` is not.

`clippy::allow_attributes_without_reason` (owner decision 2026-11-15) makes the "every suppression says why" rule mechanical: an `#[allow(...)]` or `#[expect(...)]` without `reason = "..."` is itself a lint, so the rule no longer depends on a reviewer noticing a bare `#[allow]`.

`allow-unwrap-in-tests` covers `#[test]` functions and `#[cfg(test)]` modules only (verified on 1.98.1: a helper function in `tests/x.rs` that unwraps fails `unwrap_used`, and the file fails `missing_docs` for the crate). The integration test package `tests/integration` of `v1-read-only-engine` D2 is therefore linted like production code: its helpers use `expect("...")`, its `pub` items carry doc comments, and its tests are one test binary (`tests/main.rs` with `mod` submodules) whose root carries the `//!` doc and, if needed, one `#![allow(clippy::unwrap_used, reason = "...")]`. Owner decision 2026-11-15; v1 task 3.6 follows it.

*Alternative:* `clippy::pedantic` (rejected: a stream of style opinions the owner would have to adjudicate one by one).

### D7. `deny.toml` bans duplicate versions outright
`[bans] multiple-versions = "deny"` with an initially empty `skip` list; `[licenses] allow` lists the permissive licenses the current tree needs (Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ISC, Unicode-3.0, Zlib, MPL-2.0, CDLA-Permissive-2.0, OpenSSL for `ring`), extended by PR when a dependency needs another one; `[advisories]` denies vulnerabilities and warns on unmaintained; `[sources]` allows crates.io and the two git repositories `v1-read-only-engine` D1 names for a pinned Ballista branch: `https://github.com/apache/datafusion-ballista` and the project's staging fork `https://github.com/roman-barman/datafusion-ballista` (D1: "a fork branch under our control only as a staging area for upstream PRs"). Task 1.3 of that change will add `skip` entries only for duplicates it cannot avoid, each with a comment naming the crates that cause it.

### D8. Dependency direction is a script over `cargo metadata`; module acyclicity is not checked
`scripts/ci/crate-deps.sh` reads `cargo metadata --no-deps --format-version 1` (declared dependencies only, no resolution, so it needs neither network nor a complete lock file), extracts the edges between workspace crates of kind normal and build with a short embedded Python snippet, ignoring `dev-dependencies` because they never link into a shipped binary (a test-only edge is a cost in compile time, not in architecture; the choice is stated in the script header) (the runners and the dev machine have `python3`; `jq` is not assumed, matching `pr-size.sh`), and compares them with the allowed edges from `v1-read-only-engine` D2, hard-coded in the script as the single source of truth. Every workspace member is a source and a target, whatever its name or directory; a member missing from the table may depend on no other member. It prints every forbidden edge and exits 1 if there is one. Cargo already forbids cycles between crates.

The design originally added `cargo modules dependencies --acyclic` (cargo-modules 0.28.0) per crate to catch module cycles. It was dropped on 2026-11-15 (owner decision) after the review of the implementing pull request showed, on scratch crates with both 0.28.0 and 0.21.1, that the flag reports a cycle for any struct with an inherent method (`Config` owns `Config::n`, `Config::n` uses `Config`), that the item filters are applied after the check and so cannot help, and that the tool does not see dependencies inside function bodies without a `use`. The 2026-11-13 verification missed this because its scratch crates had no methods. A prototype that parses the module-only graph and searches cycles among `uses` edges between non-ancestor modules works on scratch cases, but on real crates it flags 2 cycles in `serde_json`, 4 in `regex`, and 32 in `clap_builder`: a strictness no idiomatic crate meets. With no project code to calibrate the rule on, module acyclicity is a non-goal of this change; it is revisited when there is code, with that prototype as the starting point.

## Risks / Trade-offs

- [`multiple-versions = "deny"` fails task 1.3 if Ballista and delta-rs disagree on a transitive crate] → Expected and wanted: the `skip` list is where that disagreement is written down with a reason instead of hiding in `Cargo.lock`.
- [`missing_docs` and `unreachable_pub` produce a wave of warnings when real code lands] → The crates are empty today; the lints shape the code from the first line instead of being retrofitted.
- [Hooks are per-clone and a developer can forget `install.sh`] → CI enforces the same rules; the README and CLAUDE.md name the command as the first step after cloning.
- [`pre-push` makes a push take as long as `cargo test`] → Accepted; it replaces the manual pre-PR checklist agents run anyway.
- [Six new required checks mean six places where a renamed job blocks merging] → Same rule as `pr-size`: a job rename is a change that also updates the ruleset, stated in CLAUDE.md.
- [The `ed`/`ing` heuristic rejects valid subjects] → Rare; the message explains the rule and the developer rewrites the subject.

## Migration Plan

1. PR `spec/quality-gates`: these artifacts plus the one-line rewrite of v1 task 1.4.
2. PR `chore/git-hooks`: hooks, installer, hook tests, CLAUDE.md and README updates.
3. PR `chore/ci-gates`: `ci.yml` with `fmt`, `clippy`, `test`, `doc`, `deny`; `[workspace.lints]`; `[lints] workspace = true` in nine crates; `deny.toml`.
4. PR `chore/deps-gate`: `crate-deps.sh` with its test and the `deps` job.
5. Owner adds the six job names as required status checks after each has run once; then task 1.3 of `v1-read-only-engine` starts.

Rollback: remove a job from the ruleset's required checks; the workflow then only reports.
