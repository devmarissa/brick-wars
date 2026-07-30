#!/usr/bin/env bash
#
# Point git at tools/ for its hooks. Run once per clone.
#
# `core.hooksPath` rather than copying files into .git/hooks, so the hook is version
# controlled like everything else and updating it is a pull rather than a reminder.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

chmod +x tools/check.sh tools/pre-push
git config core.hooksPath tools

echo "hooks installed — tools/pre-push now runs tools/check.sh before every push"
echo "to undo: git config --unset core.hooksPath"
