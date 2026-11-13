#!/usr/bin/env bash
# Install the repository's git hooks into this clone.
#
# Points git's hooks path at scripts/hooks, so the versioned pre-commit,
# commit-msg, and pre-push hooks run. Safe to run again: the setting is
# simply written once more. Usage: scripts/hooks/install.sh
set -euo pipefail
# shellcheck source=scripts/hooks/lib.sh
. "$(dirname "$0")/lib.sh"
for hook in pre-commit commit-msg pre-push; do
  [ -x "scripts/hooks/$hook" ] || refuse "scripts/hooks/$hook is not executable" "run: chmod +x scripts/hooks/$hook"
done
previous="$(git config --get core.hooksPath || true)"
if [ -n "$previous" ] && [ "$previous" != "scripts/hooks" ]; then
  echo "note: replacing core.hooksPath = $previous in this clone (a global value still applies elsewhere)"
fi
git config core.hooksPath scripts/hooks
echo "core.hooksPath = $(git config core.hooksPath)"
