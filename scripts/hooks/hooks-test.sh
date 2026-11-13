#!/usr/bin/env bash
# Tests for the hooks in scripts/hooks.
#
# Builds a throwaway repository with a bare "origin", installs the hooks the
# way a developer does, puts a stub cargo on PATH, and runs one scenario per
# requirement of the git-hooks spec. No network, no real cargo, a few seconds.
#
# Usage: scripts/hooks/hooks-test.sh
set -euo pipefail

source_root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME="hooks-test" GIT_AUTHOR_EMAIL="hooks-test@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
# Hide the developer's own git configuration and hooks.
export HOME="$work" XDG_CONFIG_HOME="$work/.config" GIT_CONFIG_NOSYSTEM=1

# Stub cargo: logs every call; fmt --check fails on a file containing "unformatted".
export CARGO_STUB_LOG="$work/cargo.log"
mkdir -p "$work/bin"
cat > "$work/bin/cargo" <<'STUB'
#!/usr/bin/env bash
echo "cargo $*" >> "$CARGO_STUB_LOG"
case "$1" in
  fmt) grep -rl --include='*.rs' unformatted "$PWD" && { echo "Diff in the files above"; exit 1; } || exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$work/bin/cargo"
export PATH="$work/bin:$PATH"

failures=0
# check <scenario> <expected-exit> <expected-substring> <command...>
check() {
  local name="$1" want_exit="$2" want_text="$3"
  shift 3
  local output got_exit=0 problems=""
  output="$("$@" 2>&1)" || got_exit=$?
  [ "$got_exit" -eq "$want_exit" ] || problems="exit $got_exit (want $want_exit)"
  [[ "$output" == *"$want_text"* ]] || problems="${problems:+$problems, }missing text '$want_text'"
  if [ -z "$problems" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name: $problems"
    printf '      %s\n' "${output//$'\n'/$'\n      '}"
    failures=$((failures + 1))
  fi
}
# cargo_calls: how many times the stub cargo ran since the log was cleared.
cargo_calls() { echo "cargo calls: $(if [ -f "$CARGO_STUB_LOG" ]; then wc -l < "$CARGO_STUB_LOG"; else echo 0; fi)"; }
clear_log() { rm -f "$CARGO_STUB_LOG"; }
# ok_msg <subject>: a message whose body satisfies the reference rule.
ok_msg() { printf '%s\n\nsample: 1.1\n' "$1"; }
# commit_with <message>: stage everything and commit with the given message.
commit_with() { git add -A && git commit -q -F - <<< "$1"; }
# on_branch <name>: fresh branch from main.
on_branch() { git checkout -q main && git checkout -q -B "$1"; }

# The repository: scripts/ from this checkout, one active and one archived change.
git init -q --bare "$work/origin.git"
git -C "$work/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$work/origin.git" "$work/repo" 2>/dev/null
cd "$work/repo"
git symbolic-ref HEAD refs/heads/main
cp -r "$source_root/scripts" scripts
mkdir -p openspec/changes/sample openspec/changes/archive/2026-11-10-ci-pr-size-limit
echo sample > openspec/changes/sample/proposal.md
echo old > openspec/changes/archive/2026-11-10-ci-pr-size-limit/proposal.md
echo 'pub fn a() {}' > lib.rs
git add -A && git commit -q -m "base" && git push -q origin main

echo "# install"
check "fresh clone installs the hooks" 0 "core.hooksPath = scripts/hooks" scripts/hooks/install.sh
check "installing twice is a no-op" 0 "core.hooksPath = scripts/hooks" scripts/hooks/install.sh

echo "# pre-commit"
echo x > note.md
check "commit on main is refused" 1 "<type>/<topic>" commit_with "$(ok_msg "Add a note")"
git checkout -q -b feature/codec
check "wrong branch type is refused" 1 "allowed types: feat fix chore docs spec" commit_with "$(ok_msg "Add a note")"
on_branch docs/notes
check "docs-only commit passes" 0 "" commit_with "$(ok_msg "Add a note")"
check "docs-only commit skips cargo" 0 "cargo calls: 0" cargo_calls
git checkout -q --detach && echo y > note.md
check "detached HEAD skips the branch checks" 0 "" commit_with "$(ok_msg "Tweak a note")"
on_branch feat/fmt
echo 'pub fn b() { unformatted }' > lib.rs
check "unformatted staged file is refused" 1 "cargo fmt --check failed" commit_with "$(ok_msg "Add b")"
check "refusal names the file without the temp prefix" 1 $'lib.rs\nDiff in' commit_with "$(ok_msg "Add b")"
echo 'pub fn b() {}' > lib.rs && git add lib.rs && echo 'pub fn b() { unformatted }' > lib.rs
check "formatted index with unformatted working copy passes" 0 "" git commit -q -F - <<< "$(ok_msg "Add b")"
git checkout -q lib.rs
clear_log
echo 'max_width = 80' > rustfmt.toml
check "rustfmt.toml change runs the format check" 0 "" commit_with "$(ok_msg "Narrow the lines")"
check "rustfmt.toml change called cargo fmt" 0 "cargo calls: 1" cargo_calls

echo "# commit-msg"
on_branch feat/msg
m() { echo "m $RANDOM" >> note.md; commit_with "$1"; }
check "past tense subject is refused" 1 "imperative verb" m "$(ok_msg "Added the codec crate")"
check "imperative subject passes" 0 "" m "$(ok_msg "Add the codec crate")"
check "exception-list verb passes" 0 "" m "$(ok_msg "Embed the codec options in the plan")"
check "long subject is refused" 1 "longer than 72" m "$(ok_msg "Add a subject line that keeps going well past the seventy-two character limit")"
check "lowercase subject is refused" 1 "uppercase" m "$(ok_msg "add a note")"
check "trailing period is refused" 1 "period" m "$(ok_msg "Add a note.")"
check "fixup commit is exempt" 0 "" m "fixup! whatever. no body"
check "squash commit is exempt" 0 "" m "squash! whatever. no body"
check "amend commit is exempt" 0 "" m "amend! whatever. no body"
check "punctuated past tense is refused" 1 "imperative verb" m "$(ok_msg "Fixed: the codec crate panics")"
check "second line glued to the subject is refused" 1 "blank line" m $'Add a note\nsample: 1.1'
check "leading comment line via -F is refused" 1 "comment character" m $'# not a comment\n\nAdd d\n\nsample: 1.1'
git config core.commentChar auto
check "commentChar auto cuts the scissors" 0 "" m $'Add a note\n\nsample: 1.1\n# ------------------------ >8 ------------------------\ndiff --git a b\n+bogus-change: 9.9\nbogus-change: 9.9'
git config --unset core.commentChar
git config commit.cleanup whitespace
check "cleanup=whitespace keeps a comment subject" 1 "uppercase" m $'# not a comment\n\nsample: 1.1'
git config commit.cleanup strip
check "cleanup=strip drops a leading comment" 0 "" m $'# a comment\nAdd a note\n\nsample: 1.1'
git config --unset commit.cleanup
check "fixup with a glued second line is exempt" 0 "" m $'fixup! Add codec\nsee review'
check "amended merge subject is exempt" 0 "" m "Merge branch 'feat/a' into feat/b"
check "huge body does not break the hook" 0 "" m "Add a note"$'\n\n'"$(seq 1 60000 | sed 's/^/log line /')"$'\n\nsample: 1.1'
check "missing reference is refused" 1 "No OpenSpec change" m "Add a note"
check "explicit opt-out passes" 0 "" m $'Add a note\n\nNo OpenSpec change: agent conduct rules'
check "unknown change is refused" 1 "existing changes: ci-pr-size-limit sample" m $'Add a note\n\nv1-readonly-engine: 1.3'
check "unknown next to valid is refused" 1 "qualty-gates" m $'Add a note\n\nsample: 2.2\nqualty-gates: 2.3'
check "suffix of an archived name is refused" 1 "unknown OpenSpec change 'limit'" m $'Add a note\n\nlimit: 1'
check "archive directory is not a change" 1 "unknown OpenSpec change 'archive'" m $'Add a note\n\narchive: 1'
check "imperative Merge is not a merge commit" 1 "cite the OpenSpec change" m "Merge the two codec crates into one"
check "git-generated revert is exempt" 0 "" m $'Revert "Add a note"\n\nThis reverts commit 0000000.'
git config core.commentChar ";"
check "scissors line honours core.commentChar" 0 "" m $'Add a note\n\nsample: 1.1\n; ------------------------ >8 ------------------------\ndiff --git a b\n+bogus-change: 9.9'
git config --unset core.commentChar
check "archived change by full name passes" 0 "" m $'Add a note\n\nci-pr-size-limit: 2.1 (part 1 of 2)'
check "trailers and prose are not references" 0 "" m $'Add a note\n\nsample: 1.1\nNote: see D2\noctopus-codec: plan codecs and options\nCo-Authored-By: X <x@example.invalid>'
check "editor template is cleaned before checking" 0 "" m $'\n# Please enter the commit message for your changes. Lines starting\n# with \'#\' will be ignored, and an empty message aborts the commit.\n#\n# On branch feat/msg\nAdd a note\n\nsample: 1.1\n# ------------------------ >8 ------------------------\ndiff --git a b'

git checkout -q -b feat/merge-side && echo side > side.md && commit_with "$(ok_msg "Add side")"
on_branch feat/merge-main && echo main > main.md && commit_with "$(ok_msg "Add main side")"
check "merge commit is exempt" 0 "" git merge -q --no-ff -m "Merge branch 'feat/merge-side' into feat/merge-main. no body" feat/merge-side

echo "# pre-push"
on_branch feat/push
echo z > note.md && commit_with "$(ok_msg "Add z")"
check "push to main is refused" 1 "no pushes to main" git push -q origin HEAD:main
echo 'pub fn c() { todo!() }' > lib.rs && commit_with "$(ok_msg "Add c")"
clear_log
check "feature branch with a clippy warning is accepted" 0 "" git push -q origin feat/push
check "feature branch push runs no cargo" 0 "cargo calls: 0" cargo_calls
check "branch deletion is ignored" 0 "" git push -q origin --delete feat/push
git tag v0-test
check "tag push is ignored" 0 "" git push -q origin v0-test

echo
if [ "$failures" -eq 0 ]; then echo "all scenarios passed"; else echo "$failures scenario(s) failed"; exit 1; fi
