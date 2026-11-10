#!/usr/bin/env bash
# Pull request size gate.
#
# Measures the diff between the merge-base of HEAD and the given base ref
# and HEAD itself, then fails when the pull request is too large to review
# in one sitting. See openspec/specs/pr-size-gate/spec.md for the contract.
#
# Usage:
#   scripts/ci/pr-size.sh <base-ref>          e.g. scripts/ci/pr-size.sh origin/main
#
# Environment (all optional):
#   PR_SIZE_MAX_LINES   maximum added + deleted lines, default 500
#   PR_SIZE_MAX_FILES   maximum changed files, default 20
#   PR_SIZE_OVERRIDE    "true" when the PR carries the size/override label;
#                       the measurement is still printed but the exit code is 0
#
# Exit code: 0 within limits or overridden, 1 over a limit, 2 usage error
# (including a base ref that cannot be resolved).
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <base-ref>" >&2
  exit 2
fi
base="$1"

# Pathspecs are relative to the current directory, so always measure from
# the repository root; the documented command then works from anywhere.
cd "$(git rev-parse --show-toplevel)"

# Resolve the merge-base up front. A failure inside the process substitution
# below would not stop the script and would report an empty diff as a pass.
if ! merge_base="$(git merge-base "$base" HEAD 2>/dev/null)"; then
  echo "error: cannot find the merge-base of '${base}' and HEAD; is the base ref fetched?" >&2
  exit 2
fi
max_lines="${PR_SIZE_MAX_LINES:-500}"
max_files="${PR_SIZE_MAX_FILES:-20}"
override="${PR_SIZE_OVERRIDE:-false}"

# Paths that never count. Git pathspecs without magic match by prefix, so
# "openspec/changes/archive" covers everything under that directory.
excluded=(
  ':(exclude)Cargo.lock'
  ':(exclude)openspec/changes/archive'
)

lines=0
files=0
# --numstat prints "<added>\t<deleted>\t<path>" per file. Binary files print
# "-" in both numeric columns: they count as one file and zero lines.
while IFS=$'\t' read -r added deleted _path; do
  files=$((files + 1))
  if [ "$added" != "-" ]; then
    lines=$((lines + added + deleted))
  fi
done < <(git diff --numstat "$merge_base" HEAD -- . "${excluded[@]}")

echo "PR size against merge-base with ${base}:"
echo "  changed lines: ${lines} (limit ${max_lines})"
echo "  changed files: ${files} (limit ${max_files})"
echo "  excluded: Cargo.lock, openspec/changes/archive/**"
if [ "$override" = "true" ]; then
  echo "  override: size/override label is set"
fi

over=""
if [ "$lines" -gt "$max_lines" ]; then
  over="${over}  lines ${lines} exceed the limit of ${max_lines}"$'\n'
fi
if [ "$files" -gt "$max_files" ]; then
  over="${over}  files ${files} exceed the limit of ${max_files}"$'\n'
fi

if [ -z "$over" ]; then
  echo "RESULT: within limits"
  exit 0
fi

printf '%s' "$over"
if [ "$override" = "true" ]; then
  echo "RESULT: over the limit, but the size/override label is set; passing"
  exit 0
fi
echo "RESULT: over the limit. Split the pull request, or ask the owner for the size/override label with a justification."
exit 1
