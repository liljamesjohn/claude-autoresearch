#!/bin/bash
# Autoresearch SessionStart (compact) Hook
# Re-injects autoresearch context after context compaction so the agent
# can seamlessly resume the experiment loop.

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

# Check active flag
parse_state_file "$STATE_FILE"
if [ "$STATE_ACTIVE" != "true" ]; then
  exit 0
fi

# Read the session document
SESSION_CONTENT=$(cat "$SESSION_FILE")

# Read recent results from JSONL (last 10 experiments)
RECENT=""
if [ -f "${HOOK_CWD}/autoresearch.jsonl" ]; then
  RECENT=$(tail -10 "${HOOK_CWD}/autoresearch.jsonl" 2>/dev/null || echo "")
fi

# Build context injection
CONTEXT="<AUTORESEARCH_CONTEXT_RESTORED>
You are in an active autoresearch experiment loop (continuation ${STATE_STOP_COUNT}/${STATE_MAX_ITERATIONS}).
Context was compacted. Here is the full session state:

${SESSION_CONTENT}

Recent experiment results (last 10 from autoresearch.jsonl):
${RECENT}

CONTINUE THE LOOP. Do not stop. Do not ask for permission. Read autoresearch.md and git log for full context, then run the next experiment.
</AUTORESEARCH_CONTEXT_RESTORED>"

# Output as additionalContext
echo "$CONTEXT"
exit 0
