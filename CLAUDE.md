# octopus-mpp — rules for AI agents

Read this before doing anything in the repository. These rules take precedence over default agent behavior.

## Language

- Talk to the project owner in **Russian**.
- Everything that lands in the repository is in **English**: code, comments, docs, OpenSpec artifacts, commit messages, PR titles and bodies, issue text.

## Workflow: OpenSpec first

- All work goes through [OpenSpec](https://github.com/Fission-AI/OpenSpec). Do not write or change project code without an active change under `openspec/changes/<name>/` whose `tasks.md` covers the work. This file is the exception, by the owner's decision (2026-11-11): it governs how agents work, not how the system behaves, so its rules are edited directly through an ordinary `docs/` PR, not through an OpenSpec change.
- Use the `/opsx:propose`, `/opsx:apply`, `/opsx:archive` commands (skills in `.claude/skills/openspec-*`). Run `openspec validate <change> --strict` after editing artifacts.
- While applying, mark a task `- [x]` only when its behavior is fully implemented and its stated verification passed. If the work turns out larger than the task, stop and surface it; never silently narrow a spec.
- When a change is complete, archive it so the delta specs merge into `openspec/specs/`, the living specification.

## Git and GitHub

- **Never commit to `main`.** `main` is protected by a repository ruleset: changes land only through pull requests; force-pushes and deletion are blocked. Do not try to bypass or edit the ruleset.
- Work on a branch named `<type>/<short-topic>`, where `type` is `feat`, `fix`, `chore`, `docs`, or `spec`. One branch and one PR per OpenSpec task group (or per change when it is small).
- Commit small, coherent commits with imperative subjects (`Add SQLite catalog store`). Reference the OpenSpec change and task ids in the body (`v1-read-only-engine: 4.1, 4.2`).
- Open the PR with `gh pr create`. The body states: what changed, which tasks it completes, how it was verified (commands and results), anything the reviewer should look at first, and a "Review history" section that starts as "pending" and is filled in with `gh pr edit --body` after each agent review round (next rule).
- **Every PR gets an agent review before the owner review.** The order is: pre-PR checks, `gh pr create`, agent review loop, rebase and force-push, report to the owner. Right after `gh pr create`, run `/code-review medium <PR number>` as a subagent, without `--comment` or `--fix` (nothing is posted to GitHub as a review, nothing is applied unverified), and wait for its findings. Sort each finding into one of three outcomes: **fixed** (you verified it and changed the branch), **rejected** (you verified it is wrong or not worth it), or **escalated** (it would change the scope of a task or a spec, so the owner decides). Every finding and its outcome goes into "Review history", rejections with their reason, so the owner can audit them; escalated findings are also named in chat when you report. After fixing, re-run the pre-PR checks and `scripts/ci/pr-size.sh <base-ref>` before pushing. Run a second round only when the diff the PR shows against its base branch has changed (a pure rebase does not count); there is no third round. Fixes made after the last round are recorded as "fixed, not re-reviewed". An oversized PR (next section) stops before the agent review, not after it.
- **Only the project owner merges**, as repository maintainer. Agents never merge PRs, never approve them, and never enable auto-merge. This is a project rule, not a platform check: agents act under the owner's credentials, so the ruleset cannot tell them apart.
- The only merge method is **rebase**: commits land on `main` linearly, one by one, so keep every commit in a PR self-contained and buildable. Squash and merge commits are disabled. Branches are deleted automatically after merge.
- Before asking the owner for review, rebase the branch on the current `main` (`git fetch origin && git rebase origin/main`) and force-push **your own feature branch only** (`git push --force-with-lease`).
- Never force-push a branch you did not create, never delete remote branches you did not create, never rewrite history on `main`.
- **Pull request size limit.** CI (`.github/workflows/pr-size.yml`, job `pr-size`) fails a PR that changes more than **500 lines** (additions + deletions) or **20 files**, measured from the merge-base with `main`. Only `Cargo.lock` and `openspec/changes/archive/**` are excluded; docs and OpenSpec artifacts count. The check is required by the ruleset, so an oversized PR cannot be merged. Check locally before pushing: `scripts/ci/pr-size.sh origin/main`.
- Plan work to fit the limit: a change's planning artifacts (proposal, specs, design, tasks) land in their own `spec/<change>` PR; implementation task groups that would exceed the limit are split into several self-contained PRs, with the split noted in each PR body.
- **Agents never add the `size/override` label.** It is the owner's escape hatch. If a PR cannot be brought under the limit, stop before the agent review and explain to the owner, in the PR body and in chat, why it cannot be split smaller (for example, a single atomic rename or a generated file). The owner decides whether to add the label.
- The job name `pr-size` is the required status check context. Do not rename the job or the workflow without the owner updating the ruleset first.

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
