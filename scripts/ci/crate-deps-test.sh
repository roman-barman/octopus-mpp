#!/usr/bin/env bash
# Tests for scripts/ci/crate-deps.sh.
#
# Copies the workspace manifests into a temporary directory with an empty
# source file per target (enough for `cargo metadata --no-deps`), changes
# the copy once per scenario of the "Crate dependency direction" requirement
# of the ci-quality-gates spec (one edited manifest, or one new member
# written from scratch), and checks the gate's exit code and output. The
# copied members and their source files come from the real workspace's
# metadata, so a member outside `crates/` is copied too. No network, no
# build, a few seconds.
#
# Usage: scripts/ci/crate-deps-test.sh
set -euo pipefail

gate="$(cd "$(dirname "$0")" && pwd)/crate-deps.sh"
source_root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

# One line per workspace member: "<name> <manifest> <source file>...", all
# paths relative to the workspace root, read once from the real workspace.
members=$(cd "$source_root" && cargo metadata --no-deps --format-version 1 | python3 -I -c '
import json, os, sys
metadata = json.load(sys.stdin)
root = metadata["workspace_root"]
for package in metadata["packages"]:
    paths = [package["manifest_path"]] + [t["src_path"] for t in package["targets"]]
    print(package["name"], *(os.path.relpath(p, root) for p in paths))
')

# fresh_workspace: resets $work/ws to a copy of the real manifests with
# empty sources, so each scenario starts from the current workspace.
fresh_workspace() {
  rm -rf "$work/ws"
  mkdir -p "$work/ws"
  cp "$source_root/Cargo.toml" "$source_root/rust-toolchain.toml" "$work/ws/"
  local name manifest sources source
  while read -r name manifest sources; do
    mkdir -p "$work/ws/$(dirname "$manifest")"
    cp "$source_root/$manifest" "$work/ws/$manifest"
    for source in $sources; do
      mkdir -p "$work/ws/$(dirname "$source")"
      : > "$work/ws/$source"
    done
  done <<< "$members"
}

# manifest_of <crate>: the scratch manifest path of a workspace member.
manifest_of() {
  local name manifest rest
  while read -r name manifest rest; do
    if [ "$name" = "$1" ]; then
      echo "$work/ws/$manifest"
      return
    fi
  done <<< "$members"
  echo "no workspace member named $1" >&2
  exit 2
}

# add_dependency <crate> <table> <dependency>: adds a path dependency on
# <dependency> to the <table> ("dependencies", "build-dependencies", or
# "dev-dependencies") of
# <crate>'s manifest in the scratch workspace, replacing an existing entry
# for the same dependency so the manifest stays valid TOML. The path is
# computed from the two manifest directories, wherever the crates live.
add_dependency() {
  local manifest target path line
  manifest="$(manifest_of "$1")"
  target="$(manifest_of "$3")"
  path="$(python3 -I -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
    "$(dirname "$target")" "$(dirname "$manifest")")"
  line="$3 = { path = \"$path\" }"
  sed -i "/^$3[[:space:]]*=/d" "$manifest"
  # A table header may carry a trailing comment.
  if grep -q "^\[$2\][[:space:]]*\(#.*\)\?$" "$manifest"; then
    sed -i "/^\[$2\][[:space:]]*\(#.*\)\?$/a $line" "$manifest"
  else
    printf '\n[%s]\n%s\n' "$2" "$line" >> "$manifest"
  fi
}

# add_member <crate> <dependency>: creates a new workspace member under
# `crates/` in the scratch workspace (the root manifest's `crates/*` glob
# picks it up) with one normal path dependency on the existing member
# <dependency>. The real workspace has no such crate, so `manifest_of`
# cannot be asked for it. The helper relies on that glob; if the root
# manifest ever lists its members one by one, it stops with exit 2 and says
# so, so that the scenario does not look like a regression of the gate.
add_member() {
  local dir="$work/ws/crates/$1" target path
  target="$(manifest_of "$2")"
  mkdir -p "$dir/src"
  : > "$dir/src/lib.rs"
  path="$(python3 -I -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
    "$(dirname "$target")" "$dir")"
  printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2024"\n\n[dependencies]\n%s = { path = "%s" }\n' \
    "$1" "$2" "$path" > "$dir/Cargo.toml"
  # Two separate failures with two messages: cargo rejecting the scratch
  # workspace, and the new crate not being a member of it.
  local metadata
  if ! metadata="$(cd "$work/ws" && cargo metadata --no-deps --format-version 1 2>&1)"; then
    echo "add_member: cargo metadata failed on the scratch workspace with crates/$1 added:" >&2
    echo "$metadata" >&2
    exit 2
  fi
  if ! python3 -I -c 'import json, sys
names = {package["name"] for package in json.load(sys.stdin)["packages"]}
sys.exit(0 if sys.argv[1] in names else 1)' "$1" <<< "$metadata"; then
    echo "add_member: crates/$1 did not become a workspace member; does the root manifest still use members = [\"crates/*\"]?" >&2
    exit 2
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
check "session linking the codec is allowed" 0 "crate dependency direction ok"

fresh_workspace
add_dependency octopus-config dependencies octopus-storage
check "octopus-config may depend on no workspace crate" 1 "octopus-config -> octopus-storage"
check "octopus-config gets the hint for a crate without an entry" 1 "octopus-config has no allowed workspace dependencies"

fresh_workspace
add_member octopus-probe octopus-config
check "a crate missing from the table may depend on no workspace crate" 1 "octopus-probe -> octopus-config"
check "a crate missing from the table gets the hint" 1 "octopus-probe has no allowed workspace dependencies"

fresh_workspace
add_dependency octopus-executor build-dependencies octopus-catalog
check "build dependencies are checked like normal ones" 1 "octopus-executor -> octopus-catalog"

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) failed"
  exit 1
fi
echo "all scenarios passed"
