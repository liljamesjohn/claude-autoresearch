#!/bin/bash
# Autoresearch SessionStart (startup/resume) Hook
# Detects an active autoresearch session and prompts Claude to resume the loop.
# Fires on new sessions and resumed sessions (not compaction — that's handled
# by session-start-compact.sh).

set -euo pipefail

HOOK_INPUT=$(cat)
CWD=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# Only inject if autoresearch is active
STATE_FILE="${CWD}/.claude/autoresearch-loop.local.md"
SESSION_FILE="${CWD}/autoresearch.md"

if [ ! -f "$STATE_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

# Check if active
ACTIVE=$(sed -n 's/^active:[[:space:]]*\([a-z]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
ACTIVE="${ACTIVE:-false}"
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

ITERATION=$(sed -n 's/^iteration:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"

echo "<AUTORESEARCH_SESSION_DETECTED>
An autoresearch experiment loop is active (iteration ${ITERATION}/${MAX_ITERATIONS}).
Session document: ${SESSION_FILE}
Experiment log: ${CWD}/autoresearch.jsonl

Read autoresearch.md and autoresearch.jsonl, then resume the experiment loop.
Do not stop. Do not ask for permission. Continue optimizing.
</AUTORESEARCH_SESSION_DETECTED>"

exit 0
