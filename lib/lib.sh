#!/bin/bash
# Shared utility functions for autoresearch hook scripts.
# Source this file at the top of any hook script:
#   source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/lib.sh"

# --- Hook Input Parsing ---

# Parse JSON hook input from stdin. Call once, store result in HOOK_INPUT.
# Sets: HOOK_INPUT, HOOK_CWD, HOOK_STOP_ACTIVE
read_hook_input() {
  HOOK_INPUT=$(cat)
  HOOK_CWD=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
  HOOK_STOP_ACTIVE=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('stop_hook_active', False)).lower())" 2>/dev/null || echo "false")
}

# Extract a string field from HOOK_INPUT by key name.
# Usage: VALUE=$(hook_field "last_assistant_message")
hook_field() {
  local key="$1"
  echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$key',''))" 2>/dev/null || echo ""
}

# --- State File Parsing ---

# Parse the autoresearch state file frontmatter.
# Sets: STATE_STOP_COUNT, STATE_MAX_ITERATIONS, STATE_ACTIVE
# Args: $1 = path to state file
parse_state_file() {
  local state_file="$1"
  STATE_STOP_COUNT=$(sed -n 's/^stop_count:[[:space:]]*\([0-9]*\)/\1/p' "$state_file" 2>/dev/null)
  # Fallback: support legacy "iteration" field name
  if [ -z "$STATE_STOP_COUNT" ]; then
    STATE_STOP_COUNT=$(sed -n 's/^iteration:[[:space:]]*\([0-9]*\)/\1/p' "$state_file" 2>/dev/null)
  fi
  STATE_STOP_COUNT="${STATE_STOP_COUNT:-0}"

  STATE_MAX_ITERATIONS=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$state_file" 2>/dev/null)
  STATE_MAX_ITERATIONS="${STATE_MAX_ITERATIONS:-50}"

  STATE_ACTIVE=$(sed -n 's/^active:[[:space:]]*\([a-z]*\)/\1/p' "$state_file" 2>/dev/null)
  STATE_ACTIVE="${STATE_ACTIVE:-false}"
}

# --- Worktree Detection ---

# Check if a directory is a git worktree (not the main checkout).
# In a worktree, .git is a FILE (containing "gitdir: ...").
# In the main checkout, .git is a DIRECTORY.
# Returns 0 if in a worktree, 1 if not.
# Usage: is_worktree "/path/to/dir" && echo "yes"
is_worktree() {
  [ -f "${1:-.}/.git" ]
}

# --- Path Helpers ---

# Resolve the state file path from a cwd.
# Usage: STATE_FILE=$(state_file_path "/path/to/project")
state_file_path() {
  echo "${1}/.claude/autoresearch-loop.local.md"
}
