#!/bin/bash
# Autoresearch PreCompact Hook
# Ensures autoresearch state is written to disk before compaction.
# The session-start-compact hook will re-inject it after compaction.

set -euo pipefail

HOOK_INPUT=$(cat)
CWD=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# Only act if autoresearch is active
STATE_FILE="${CWD}/.claude/autoresearch-loop.local.md"
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Remind the compaction to preserve autoresearch context
echo "IMPORTANT: An autoresearch experiment loop is active. Preserve all details about: the optimization goal, current best metric, what has been tried, what files are in scope, and the current approach being explored."
exit 0
