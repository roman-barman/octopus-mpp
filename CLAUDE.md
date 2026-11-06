# octopus-mpp — rules for AI agents

Read this before doing anything in the repository. These rules take precedence over default agent behavior.

## Language

- Talk to the project owner in **Russian**.
- Everything that lands in the repository is in **English**: code, comments, docs, OpenSpec artifacts, commit messages, PR titles and bodies, issue text.

## Workflow: OpenSpec first

- All work goes through [OpenSpec](https://github.com/Fission-AI/OpenSpec). Do not write or change project code without an active change under `openspec/changes/<name>/` whose `tasks.md` covers the work.
- Use the `/opsx:propose`, `/opsx:apply`, `/opsx:archive` commands (skills in `.claude/skills/openspec-*`). Run `openspec validate <change> --strict` after editing artifacts.
- While applying, mark a task `- [x]` only when its behavior is fully implemented and its stated verification passed. If the work turns out larger than the task, stop and surface it; never silently narrow a spec.
- When a change is complete, archive it so the delta specs merge into `openspec/specs/`, the living specification.

## Git and GitHub

- **Never commit to `main`.** `main` is protected by a repository ruleset: changes land only through pull requests; force-pushes and deletion are blocked. Do not try to bypass or edit the ruleset.
- Work on a branch named `<type>/<short-topic>`, where `type` is `feat`, `fix`, `chore`, `docs`, or `spec`. One branch and one PR per OpenSpec task group (or per change when it is small).
- Commit small, coherent commits with imperative subjects (`Add SQLite catalog store`). Reference the OpenSpec change and task ids in the body (`v1-read-only-engine: 4.1, 4.2`).
- Open the PR with `gh pr create`. The body states: what changed, which tasks it completes, how it was verified (commands and results), and anything the reviewer should look at first.
- **Only the project owner merges**, as repository maintainer. Agents never merge PRs, never approve them, and never enable auto-merge. The ruleset enforces this: updates to `main` are allowed only through a pull request merged by a repository admin.
- The only merge method is **rebase**: commits land on `main` linearly, one by one, so keep every commit in a PR self-contained and buildable. Squash and merge commits are disabled. Branches are deleted automatically after merge.
- Before asking for review, rebase the branch on the current `main` (`git fetch origin && git rebase origin/main`) and force-push **your own feature branch only** (`git push --force-with-lease`).
- Never force-push a branch you did not create, never delete remote branches you did not create, never rewrite history on `main`.

## Upstream (Apache DataFusion, Ballista, delta-rs)

- Ballista is a dependency, not a fork. Anything that must change inside Ballista or DataFusion is an **upstream item**.
- Before any upstream work: research whether the maintainers want it (issues, discussions, roadmap), then present to the owner: the gap, evidence of demand, proposed approach, and the alternative of a local patch. **The owner decides.**
- Only after approval: align on the upstream issue, implement on our pinned branch, have the owner review the diff, then open the PR. Never open an upstream PR or issue on your own initiative.
- Items upstream does not want stay as documented local patches (`docs/upstream-patches.md`), rebased on each Ballista release.

## Code

- The owner must be able to understand every line. Prefer small crates with one responsibility, explicit code over macros (derive macros from `serde`, `clap`, `thiserror`, `utoipa` only), and doc comments that explain intent.
- Every Ballista or DataFusion extension point we implement is documented in `docs/architecture.md` with the trait name and the reason.
- Architectural decisions are ADRs in `docs/adr/`; change a decision by adding a new ADR, not by editing an old one.
- Do not add a dependency for something a few lines of code can do. Pin Ballista, DataFusion, Arrow, and delta-rs versions in the workspace; upgrade them together in a dedicated change.
- Before opening a PR run `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`. Integration tests run against the Docker Compose stand in `deploy/compose`.

## Reporting

- Report outcomes faithfully: failing tests are reported with their output, skipped steps are named as skipped. When handing over work, explain how the new code works and how it plugs into Ballista and DataFusion.
