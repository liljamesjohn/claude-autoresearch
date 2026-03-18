#!/bin/bash
# Autoresearch SessionStart (compact) Hook
# Re-injects autoresearch context after context compaction so the agent
# can seamlessly resume the experiment loop.

set -euo pipefail

HOOK_INPUT=$(cat)
CWD=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# Only inject if autoresearch is active
STATE_FILE="${CWD}/.claude/autoresearch-loop.local.md"
SESSION_FILE="${CWD}/autoresearch.md"

if [ ! -f "$STATE_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

# Read the session document
SESSION_CONTENT=$(cat "$SESSION_FILE")

# Read recent results from JSONL (last 10 experiments)
RECENT=""
if [ -f "${CWD}/autoresearch.jsonl" ]; then
  RECENT=$(tail -10 "${CWD}/autoresearch.jsonl" 2>/dev/null || echo "")
fi

# Read current iteration from state (macOS-compatible, no grep -P)
ITERATION=$(sed -n 's/^iteration:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"

# Build context injection
CONTEXT="<AUTORESEARCH_CONTEXT_RESTORED>
You are in an active autoresearch experiment loop (iteration ${ITERATION}/${MAX_ITERATIONS}).
Context was compacted. Here is the full session state:

${SESSION_CONTENT}

Recent experiment results (last 10 from autoresearch.jsonl):
${RECENT}

CONTINUE THE LOOP. Do not stop. Do not ask for permission. Read autoresearch.md and git log for full context, then run the next experiment.
</AUTORESEARCH_CONTEXT_RESTORED>"

# Output as additionalContext
echo "$CONTEXT"
exit 0
