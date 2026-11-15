#!/usr/bin/env bash
# Tests for scripts/ci/crate-deps.sh.
#
# Copies the workspace manifests into a temporary directory with an empty
# source file per crate (enough for `cargo metadata --no-deps`), edits one
# manifest per scenario of the "Crate dependency direction" requirement of
# the ci-quality-gates spec, and checks the gate's exit code and output.
# No network, no build, a few seconds.
#
# Usage: scripts/ci/crate-deps-test.sh
set -euo pipefail

gate="$(cd "$(dirname "$0")" && pwd)/crate-deps.sh"
source_root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

# fresh_workspace: resets $work/ws to a copy of the real manifests with
# empty crate sources, so each scenario starts from the current workspace.
fresh_workspace() {
  rm -rf "$work/ws"
  mkdir -p "$work/ws"
  cp "$source_root/Cargo.toml" "$source_root/rust-toolchain.toml" "$work/ws/"
  local crate name
  for crate in "$source_root"/crates/*/; do
    name="$(basename "$crate")"
    mkdir -p "$work/ws/crates/$name/src"
    cp "$crate/Cargo.toml" "$work/ws/crates/$name/"
    if [ -f "$crate/src/main.rs" ]; then
      : > "$work/ws/crates/$name/src/main.rs"
    else
      : > "$work/ws/crates/$name/src/lib.rs"
    fi
  done
}

# add_dependency <crate> <table> <dependency>: adds a path dependency on
# <dependency> to the <table> ("dependencies" or "dev-dependencies") of
# <crate>'s manifest in the scratch workspace.
add_dependency() {
  local manifest="$work/ws/crates/$1/Cargo.toml"
  local line="$3 = { path = \"../$3\" }"
  if grep -q "^\[$2\]$" "$manifest"; then
    sed -i "/^\[$2\]$/a $line" "$manifest"
  else
    printf '\n[%s]\n%s\n' "$2" "$line" >> "$manifest"
  fi
}

# check <scenario> <expected-exit> <expected-substring>
# Runs the gate on the scratch workspace and reports one line.
check() {
  local name="$1" want_exit="$2" want_text="$3"
  local output got_exit=0 problems=""
  output="$("$gate" "$work/ws" 2>&1)" || got_exit=$?
  if [ "$got_exit" -ne "$want_exit" ]; then
    problems="exit $got_exit (want $want_exit)"
  fi
  if [[ "$output" != *"$want_text"* ]]; then
    problems="${problems:+$problems, }missing text '$want_text'"
  fi
  if [ -z "$problems" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name: $problems"
    printf '      %s\n' "${output//$'\n'/$'\n      '}"
    failures=$((failures + 1))
  fi
}

fresh_workspace
check "current workspace passes" 0 "crate dependency direction ok"

fresh_workspace
add_dependency octopus-executor dependencies octopus-catalog
check "executor linking the catalog is forbidden" 1 "octopus-executor -> octopus-catalog"

fresh_workspace
add_dependency octopus-executor dev-dependencies octopus-catalog
check "test-only dependency is not checked" 0 "crate dependency direction ok"

fresh_workspace
add_dependency octopus-session dependencies octopus-codec
check "session linking the codec is allowed" 0 "1 workspace edges checked"

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) failed"
  exit 1
fi
echo "all scenarios passed"
