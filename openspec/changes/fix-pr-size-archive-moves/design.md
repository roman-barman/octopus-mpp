# Design

## Context

See proposal.md for motivation. `scripts/ci/pr-size.sh` currently runs `git diff --numstat <merge-base> HEAD -- . ':(exclude)Cargo.lock' ':(exclude)openspec/changes/archive'` and sums the columns. Pathspecs narrow the file set before git looks for renames, so a destination inside an excluded directory removes the "added" side of a move and leaves the source as a deletion. Observed on PR #6: five artifact files reported as deletions, 57 extra lines and 4 extra files.

## Goals / Non-Goals

**Goals:**
- Exclusions decided by the destination path of each entry, with rename detection on.
- Keep the script readable: one loop, one exclusion check, no new tools.

**Non-Goals:**
- Changing the limits, the exclusion list, the override, or the workflow.
- Tuning rename detection thresholds; git's default similarity (50%) is kept.

## Decisions

### D1. Read `git diff --numstat -z -M` with no pathspec, filter in the script
Without a pathspec, git detects renames across the whole tree. The `-z` form separates fields with NUL and prints a rename as `<added>\t<deleted>\t\0<source>\0<destination>\0`, with an empty path field marking the rename; a plain entry is `<added>\t<deleted>\t<path>\0`. The loop reads one record, and when the path is empty reads two more for source and destination. The exclusion check is a `case` on the destination path: `Cargo.lock` and `openspec/changes/archive/*`.

*Why:* `-z` is unambiguous and needs no parsing of the human-readable `prefix{old => new}suffix` form, which would break on paths containing braces or ` => `. Alternatives: `--no-renames` plus pathspecs (the current behavior, wrong for moves); `--name-status` as a second pass to learn which entries are renames (two git calls to join); counting via the GitHub API (no exclusions at all).

### D2. Content changes in a moved file count at the destination
A rename with edits reports the lines changed between source and destination. They count when the destination is not excluded, as for any other file. The delta spec to main spec move in an archive PR (`openspec/changes/<name>/specs/x/spec.md` to `openspec/specs/x/spec.md`) is therefore counted as one file with the header edits, which is what the owner has to read.

### D3. Test fixture gains a change directory on `main`
The test's base commit adds `openspec/changes/sample/` with a few files, so scenarios can `git mv` it into `openspec/changes/archive/` and move one file out again. Existing scenarios diff from `main` and are unaffected by extra files in the base.

## Risks / Trade-offs

- [Rename detection is heuristic: a moved file edited beyond 50% similarity becomes delete plus add, and the deletion is counted] → Acceptable; such a PR genuinely has that much to read. Documented in the script comment.
- [`git diff -z` parsing in bash is less familiar than the text form] → Six commented lines; the test covers both record shapes.
- [Archive PRs are now measured smaller than before] → Intended; it restores the behavior the spec always required.
