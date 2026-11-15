#!/usr/bin/env bash
# Acyclic modules gate.
#
# Runs `cargo modules dependencies --acyclic` once per library crate and once
# per binary of the workspace, so that a module cycle in any crate fails the
# `deps` job. Cargo already forbids cycles between crates; this checks the
# module tree inside each one. See design D8 of the quality-gates change for
# what the tool does and does not catch.
#
# Needs cargo-modules at the version ci.yml pins (CARGO_MODULES_VERSION);
# the README has the install command.
#
# Usage: scripts/ci/acyclic-modules.sh
# Exit code: 0 when every crate is acyclic, 1 on the first cycle found.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# One line per target: "<package> lib" or "<package> bin <name>", from the
# workspace metadata (declared targets only, no resolution).
targets=$(cargo metadata --no-deps --format-version 1 | python3 -I -c '
import json, sys
for package in json.load(sys.stdin)["packages"]:
    for target in package["targets"]:
        if "lib" in target["kind"]:
            print(package["name"], "lib")
        elif "bin" in target["kind"]:
            print(package["name"], "bin", target["name"])
')

while read -r package kind name; do
  if [ "$kind" = lib ]; then
    echo "checking $package (lib)"
    cargo modules dependencies --acyclic -p "$package" --lib > /dev/null
  else
    echo "checking $package (bin $name)"
    cargo modules dependencies --acyclic -p "$package" --bin "$name" > /dev/null
  fi
done <<< "$targets"
echo "module trees are acyclic"
