#!/bin/bash
# Autoresearch SessionStart (startup/resume) Hook
# Detects an active autoresearch session and prompts Claude to resume the loop.
# Fires on new sessions and resumed sessions (not compaction — that's handled
# by session-start-compact.sh).

set -euo pipefail

# Source shared utilities
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/lib.sh"

read_hook_input

# Only inject if autoresearch is active
STATE_FILE=$(state_file_path "$HOOK_CWD")
SESSION_FILE="${HOOK_CWD}/autoresearch.md"

if [ ! -f "$STATE_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

# Check if active
parse_state_file "$STATE_FILE"
if [ "$STATE_ACTIVE" != "true" ]; then
  exit 0
fi

echo "<AUTORESEARCH_SESSION_DETECTED>
An autoresearch experiment loop is active (continuation ${STATE_STOP_COUNT}/${STATE_MAX_ITERATIONS}).
Session document: ${SESSION_FILE}
Experiment log: ${HOOK_CWD}/autoresearch.jsonl

Read autoresearch.md and autoresearch.jsonl, then resume the experiment loop.
Do not stop. Do not ask for permission. Continue optimizing.
</AUTORESEARCH_SESSION_DETECTED>"

exit 0
