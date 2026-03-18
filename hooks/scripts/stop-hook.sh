#!/bin/bash
# Autoresearch Stop Hook
# Keeps the experiment loop running by blocking Claude from stopping.
# Based on the Ralph Wiggum pattern from Anthropic's reference implementation.
#
# Gate: .claude/autoresearch-loop.local.md must exist and have active: true
# Guards: stop_hook_active check, max iterations, state file existence

set -euo pipefail

# Source shared utilities
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/lib.sh"

# Read hook input from stdin
read_hook_input

# Guard 1: If already in a hook-triggered continuation, allow stop
if [ "$HOOK_STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# Guard 2: State file must exist
STATE_FILE=$(state_file_path "$HOOK_CWD")
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Parse state file frontmatter
parse_state_file "$STATE_FILE"

# Guard 3: Must be active
if [ "$STATE_ACTIVE" != "true" ]; then
  exit 0
fi

# Guard 4: Check max iterations
if [ "$STATE_STOP_COUNT" -ge "$STATE_MAX_ITERATIONS" ]; then
  rm -f "$STATE_FILE"
  exit 0
fi

# Guard 5: Convergence detection — too many consecutive non-keep results
JSONL_FILE="${HOOK_CWD}/autoresearch.jsonl"
if [ -f "$JSONL_FILE" ]; then
  CONSEC=$(consecutive_discards "$JSONL_FILE")
  if [ "$CONSEC" -ge "$STATE_MAX_CONSECUTIVE_DISCARDS" ]; then
    rm -f "$STATE_FILE"
    exit 0
  fi
fi

# Guard 6: Cost budget ceiling
TRANSCRIPT=$(hook_field "transcript_path")
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ "$STATE_MAX_COST" != "0" ]; then
  COST=$(estimate_session_cost "$TRANSCRIPT")
  if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$COST" "$STATE_MAX_COST" 2>/dev/null; then
    rm -f "$STATE_FILE"
    exit 0
  fi
fi

# Check for completion promise in last assistant message
LAST_MSG=$(hook_field "last_assistant_message")
if echo "$LAST_MSG" | grep -q '<promise>AUTORESEARCH_COMPLETE</promise>' 2>/dev/null; then
  rm -f "$STATE_FILE"
  exit 0
fi

# Increment stop count in state file
NEW_COUNT=$((STATE_STOP_COUNT + 1))
TEMP_FILE=$(mktemp)
# Update stop_count (or legacy iteration field)
sed -e "s/^stop_count:.*/stop_count: ${NEW_COUNT}/" \
    -e "s/^iteration:.*/stop_count: ${NEW_COUNT}/" \
    "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Extract the prompt text (everything after the frontmatter closing ---)
PROMPT=$(awk '/^---$/{c++; next} c>=2' "$STATE_FILE" | sed '/^$/d')
if [ -z "$PROMPT" ]; then
  PROMPT="Continue the autoresearch experiment loop. Read autoresearch.md and autoresearch.jsonl for context."
fi

# Compute adaptive search strategy from experiment history
STRATEGY_MODE="explore"
STRATEGY_REASON=""
if [ -f "$JSONL_FILE" ]; then
  STRATEGY_JSON=$(compute_strategy "$JSONL_FILE")
  STRATEGY_MODE=$(echo "$STRATEGY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode','explore'))" 2>/dev/null || echo "explore")
  STRATEGY_REASON=$(echo "$STRATEGY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null || echo "")
fi

# Block the stop and feed the prompt back to Claude
SYSTEM_MSG="Loop continuation ${NEW_COUNT}/${STATE_MAX_ITERATIONS} | Strategy: ${STRATEGY_MODE}"
if [ -n "$STRATEGY_REASON" ]; then
  SYSTEM_MSG="${SYSTEM_MSG} (${STRATEGY_REASON})"
fi

# Use python3 to properly JSON-encode the output (handles quotes, newlines, etc.)
python3 -c "
import json, sys
print(json.dumps({
    'decision': 'block',
    'reason': sys.argv[1],
    'systemMessage': sys.argv[2]
}))
" "$PROMPT" "$SYSTEM_MSG"

exit 0
