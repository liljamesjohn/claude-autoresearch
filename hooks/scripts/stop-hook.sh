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

# Block the stop and feed the prompt back to Claude
SYSTEM_MSG="Loop continuation ${NEW_COUNT}/${STATE_MAX_ITERATIONS}"

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
