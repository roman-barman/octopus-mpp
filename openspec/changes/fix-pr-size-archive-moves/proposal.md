# Proposal

## Why

Archiving `ci-pr-size-limit` (PR #6) measured 138 changed lines instead of the expected 81: `scripts/ci/pr-size.sh` passes its exclusions to `git diff` as pathspecs, and git applies pathspecs before rename detection, so a move into `openspec/changes/archive/` appears as plain deletions of the old `openspec/changes/<name>/` files and is counted. The `pr-size-gate` spec already says an archive PR counts only the non-excluded paths. For `ci-pr-size-limit` the error was harmless; archiving `v1-read-only-engine` would delete thousands of artifact lines and be blocked by the gate it was meant to pass.

## What Changes

- `scripts/ci/pr-size.sh` reads the full numstat with rename detection and applies the exclusions itself, by each entry's destination path. A file moved into an excluded location is not counted; a file moved out of one is.
- `scripts/ci/pr-size-test.sh` gains scenarios that move a change directory into the archive and move a file out of the archive.
- The `pr-size-gate` spec gets one requirement stating that moved and renamed files are measured by their destination path. The spec was silent on renames; the fix defines the behavior, so it is written down.

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `pr-size-gate`: adds a requirement on how moved and renamed files are measured. The existing "Excluded paths" requirement and its "Archiving a change" scenario are unchanged; the fix makes the implementation satisfy them.

## Impact

- Files: `scripts/ci/pr-size.sh`, `scripts/ci/pr-size-test.sh`, delta spec for `pr-size-gate`.
- No workflow change, no CLAUDE.md change, no new dependency. The `pr-size` check context stays the same.
