#!/bin/bash
# Autoresearch PreCompact Hook
# Ensures autoresearch state is written to disk before compaction.
# The session-start-compact hook will re-inject it after compaction.

set -euo pipefail

# Source shared utilities
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/lib.sh"

read_hook_input

# Only act if autoresearch is active
STATE_FILE=$(state_file_path "$HOOK_CWD")
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Check active flag
parse_state_file "$STATE_FILE"
if [ "$STATE_ACTIVE" != "true" ]; then
  exit 0
fi

# Remind the compaction to preserve autoresearch context
echo "IMPORTANT: An autoresearch experiment loop is active. Preserve all details about: the optimization goal, current best metric, what has been tried, what files are in scope, and the current approach being explored."
exit 0
