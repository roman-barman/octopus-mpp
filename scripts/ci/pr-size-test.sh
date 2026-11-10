#!/usr/bin/env bash
# Tests for scripts/ci/pr-size.sh.
#
# Builds a throwaway git repository, creates one branch per scenario from
# the pr-size-gate spec, runs the gate against it and checks the exit code
# and the key output lines. No network, no GitHub, runs in a few seconds.
#
# Usage: scripts/ci/pr-size-test.sh
set -euo pipefail

gate="$(cd "$(dirname "$0")" && pwd)/pr-size.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME="pr-size-test" GIT_AUTHOR_EMAIL="pr-size-test@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

failures=0

# write_lines <file> <count>: writes <count> numbered lines to <file>.
write_lines() {
  mkdir -p "$(dirname "$1")"
  seq 1 "$2" | sed 's/^/line /' > "$1"
}

# check <scenario> <expected-exit> <expected-substring> [env=value ...]
# Runs the gate on the current branch against main and reports one line.
check() {
  local name="$1" want_exit="$2" want_text="$3"
  shift 3
  local output got_exit=0
  output="$(env "$@" "$gate" main 2>&1)" || got_exit=$?
  if [ "$got_exit" -eq "$want_exit" ] && [[ "$output" == *"$want_text"* ]]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name: exit $got_exit (want $want_exit), missing text '$want_text'"
    printf '      %s\n' "${output//$'\n'/$'\n      '}"
    failures=$((failures + 1))
  fi
}

# branch <name>: starts a scenario branch from main.
branch() {
  git checkout -q main
  git checkout -q -b "$1"
}

# commit <message>: stages everything and commits.
commit() {
  git add -A
  git commit -q -m "$1"
}

cd "$work"
git init -q
git symbolic-ref HEAD refs/heads/main
write_lines base.txt 3
commit "base"

branch at-limit
write_lines a.txt 500
commit "500 lines"
check "exactly 500 lines passes" 0 "RESULT: within limits"

branch over-lines
write_lines a.txt 501
commit "501 lines"
check "501 lines fails" 1 "lines 501 exceed the limit of 500"

branch over-files
for i in $(seq 1 21); do write_lines "f$i.txt" 1; done
commit "21 files"
check "21 one-line files fails" 1 "files 21 exceed the limit of 20"

branch lockfile
write_lines code.rs 10
write_lines Cargo.lock 2000
commit "lockfile churn"
check "Cargo.lock is excluded (lines)" 0 "changed lines: 10 "
check "Cargo.lock is excluded (files)" 0 "changed files: 1 "

branch archive
write_lines openspec/changes/archive/old/design.md 600
write_lines openspec/specs/thing/spec.md 5
commit "archive a change"
check "archive is excluded (lines)" 0 "changed lines: 5 "
check "archive is excluded (files)" 0 "changed files: 1 "

branch binary
printf 'PNG\0\1\2\3\0binary' > image.png
commit "binary file"
check "binary counts as one file" 0 "changed files: 1 "
check "binary counts zero lines" 0 "changed lines: 0 "

branch override
write_lines a.txt 501
commit "501 lines with override"
check "override passes with notice" 0 "size/override label is set" PR_SIZE_OVERRIDE=true

branch base-moved
write_lines a.txt 10
commit "small change"
git checkout -q main
write_lines unrelated.txt 600
commit "unrelated work on main"
git checkout -q base-moved
check "commits on main are not counted" 0 "changed lines: 10 "

branch custom-limits
write_lines a.txt 50
commit "50 lines"
check "limits come from the environment" 1 "lines 50 exceed the limit of 40" PR_SIZE_MAX_LINES=40

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) failed"
  exit 1
fi
echo "all scenarios passed"
