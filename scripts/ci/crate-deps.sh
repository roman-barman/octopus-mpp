#!/usr/bin/env bash
# Crate dependency direction gate.
#
# Reads the declared dependencies of every workspace crate from
# `cargo metadata --no-deps` (no resolution, so no network and no complete
# lock file needed) and compares the `octopus-*` to `octopus-*` edges with
# the allowed edges of design D2 of `v1-read-only-engine`, hard-coded below
# as the single source of truth. Every forbidden edge is printed.
#
# Only normal and build dependencies are edges: a `[dev-dependencies]` entry
# never links into a shipped binary, so a test-only edge is a cost in compile
# time, not in architecture, and is not checked.
#
# Usage:
#   scripts/ci/crate-deps.sh [<workspace-dir>]   default: the repository root
#
# Exit code: 0 when every edge is allowed, 1 when at least one is forbidden,
# 2 on a usage error.
set -euo pipefail

if [ $# -gt 1 ]; then
  echo "usage: $0 [<workspace-dir>]" >&2
  exit 2
fi
workspace="${1:-$(git rev-parse --show-toplevel)}"

# The comparison is a few lines of Python (the runners and the dev machine
# have python3; jq is not assumed, as in pr-size.sh). The program is read
# into a variable so that the metadata can arrive on stdin.
program=$(cat <<'PY'
import json
import sys

# Design D2 of v1-read-only-engine: which workspace crates each crate may
# depend on. A crate missing here may depend on no workspace crate.
ALLOWED = {
    "octopus-storage": {"octopus-config"},
    "octopus-codec": {"octopus-config", "octopus-storage"},
    "octopus-catalog": {"octopus-config", "octopus-storage"},
    "octopus-auth": {"octopus-config"},
    "octopus-session": {"octopus-config", "octopus-storage", "octopus-catalog",
                        "octopus-auth", "octopus-codec"},
    "octopus-gateway": {"octopus-config", "octopus-catalog", "octopus-auth",
                        "octopus-session"},
    "octopus-executor": {"octopus-config", "octopus-storage", "octopus-codec"},
    # The scheduler binary wires every library together.
    "octopus-scheduler": {"octopus-config", "octopus-storage", "octopus-catalog",
                          "octopus-auth", "octopus-codec", "octopus-session",
                          "octopus-gateway"},
}

metadata = json.load(sys.stdin)
forbidden = []
checked = 0
for package in metadata["packages"]:
    source = package["name"]
    if not source.startswith("octopus-"):
        continue
    for dependency in package["dependencies"]:
        target = dependency["name"]
        # `kind` is null for a normal dependency, "build" or "dev" otherwise.
        if not target.startswith("octopus-") or dependency["kind"] == "dev":
            continue
        checked += 1
        if target not in ALLOWED.get(source, set()):
            forbidden.append(f"{source} -> {target}")

if forbidden:
    print("forbidden crate dependencies (design D2 of v1-read-only-engine):")
    for edge in forbidden:
        print(f"  {edge}")
    sys.exit(1)
print(f"crate dependency direction ok: {checked} workspace edges checked")
PY
)

cargo metadata --no-deps --format-version 1 --manifest-path "$workspace/Cargo.toml" |
  python3 -I -c "$program"
