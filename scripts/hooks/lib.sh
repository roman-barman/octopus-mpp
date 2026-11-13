#!/usr/bin/env bash
# Shared helpers for the git hooks in this directory. Sourced, not run.
# See openspec/specs/git-hooks/spec.md (or the quality-gates change until it
# is archived) for the rules the hooks enforce.

# refuse <rule> [detail ...]: explain why the hook refuses and exit 1.
# The first argument is the rule in one line; the rest are printed indented,
# one per line, so the developer sees the offending value and what to do.
refuse() {
  local rule="$1"
  shift
  echo "hook: refused: $rule" >&2
  local detail
  for detail in "$@"; do
    echo "  $detail" >&2
  done
  exit 1
}

# Every hook runs from the repository root so relative paths are stable.
cd "$(git rev-parse --show-toplevel)" || exit 1
