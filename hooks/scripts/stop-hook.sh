#!/bin/bash
# Autoresearch Stop Hook
# Keeps the experiment loop running by blocking Claude from stopping.
# Based on the Ralph Wiggum pattern from Anthropic's reference implementation.
#
# Gate: .claude/autoresearch-loop.local.md must exist and have active: true
# Guards: stop_hook_active check, max iterations, state file existence

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Guard 1: If already in a hook-triggered continuation, allow stop
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('stop_hook_active', False)).lower())" 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Guard 2: State file must exist
CWD=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
STATE_FILE="${CWD}/.claude/autoresearch-loop.local.md"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Parse state file frontmatter (macOS-compatible, no grep -P)
ITERATION=$(sed -n 's/^iteration:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"
ACTIVE=$(sed -n 's/^active:[[:space:]]*\([a-z]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
ACTIVE="${ACTIVE:-false}"

# Guard 3: Must be active
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# Guard 4: Check max iterations
if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  rm -f "$STATE_FILE"
  exit 0
fi

# Check for completion promise in last assistant message
LAST_MSG=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_assistant_message',''))" 2>/dev/null || echo "")
if echo "$LAST_MSG" | grep -q '<promise>AUTORESEARCH_COMPLETE</promise>' 2>/dev/null; then
  rm -f "$STATE_FILE"
  exit 0
fi

# Increment iteration in state file
NEW_ITERATION=$((ITERATION + 1))
TEMP_FILE=$(mktemp)
sed "s/^iteration:.*/iteration: ${NEW_ITERATION}/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Extract the prompt text (everything after the frontmatter closing ---)
PROMPT=$(awk '/^---$/{c++; next} c>=2' "$STATE_FILE" | sed '/^$/d')
if [ -z "$PROMPT" ]; then
  PROMPT="Continue the autoresearch experiment loop. Read autoresearch.md and autoresearch.jsonl for context."
fi

# Block the stop and feed the prompt back to Claude
SYSTEM_MSG="Autoresearch loop iteration ${NEW_ITERATION}/${MAX_ITERATIONS}"

cat << HOOKEOF
{"decision": "block", "reason": "${PROMPT}", "systemMessage": "${SYSTEM_MSG}"}
HOOKEOF

exit 0
