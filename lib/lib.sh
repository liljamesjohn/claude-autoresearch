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

  STATE_MAX_CONSECUTIVE_DISCARDS=$(sed -n 's/^max_consecutive_discards:[[:space:]]*\([0-9]*\)/\1/p' "$state_file" 2>/dev/null)
  STATE_MAX_CONSECUTIVE_DISCARDS="${STATE_MAX_CONSECUTIVE_DISCARDS:-8}"

  STATE_MAX_COST=$(sed -n 's/^max_cost_usd:[[:space:]]*\([0-9.]*\)/\1/p' "$state_file" 2>/dev/null)
  STATE_MAX_COST="${STATE_MAX_COST:-0}"
}

# --- Convergence Detection ---

# Count consecutive non-keep results from the tail of the JSONL.
# Reads the file in reverse, counts until a "keep" is found.
# Returns the count via stdout.
consecutive_discards() {
  local jsonl_file="$1"
  python3 -c "
import json, sys
count = 0
for line in reversed(open(sys.argv[1]).readlines()):
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
    except: continue
    if d.get('type') == 'config': continue
    if d.get('status') == 'keep':
        break
    count += 1
print(count)
" "$jsonl_file" 2>/dev/null || echo "0"
}

# --- Cost Estimation ---

# Estimate session cost from the Claude Code transcript JSONL.
# Sums token usage from assistant turns and applies approximate pricing.
# Returns cost in USD via stdout (e.g., "1.2345").
estimate_session_cost() {
  local transcript="$1"
  python3 -c "
import json, sys
total = 0.0
# Approximate pricing per 1M tokens (Sonnet 4.6 rates as default)
INPUT_RATE = 3.0 / 1_000_000
OUTPUT_RATE = 15.0 / 1_000_000
CACHE_READ_RATE = 0.30 / 1_000_000
CACHE_WRITE_RATE = 3.75 / 1_000_000
for line in open(sys.argv[1]):
    try:
        d = json.loads(line.strip())
        u = d.get('message', {}).get('usage', {})
        if not u: continue
        total += u.get('input_tokens', 0) * INPUT_RATE
        total += u.get('output_tokens', 0) * OUTPUT_RATE
        total += u.get('cache_read_input_tokens', 0) * CACHE_READ_RATE
        total += u.get('cache_creation_input_tokens', 0) * CACHE_WRITE_RATE
    except: continue
print(f'{total:.4f}')
" "$transcript" 2>/dev/null || echo "0.0000"
}

# --- Adaptive Search Strategy ---

# Compute the current search strategy from experiment history.
# Returns a JSON string: {"mode":"explore","reason":"..."}
# Args: $1 = path to autoresearch.jsonl
compute_strategy() {
  local jsonl_file="$1"
  python3 -c "
import json, sys

results = []
best_metric = None
best_direction = 'lower'

for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
    except: continue
    if d.get('type') == 'config':
        best_direction = d.get('bestDirection', 'lower')
        continue
    results.append(d)

if len(results) < 5:
    print(json.dumps({'mode': 'explore', 'reason': 'fewer than 5 experiments, still exploring'}))
    sys.exit(0)

# Find best metric
for r in results:
    m = r.get('metric', 0)
    if r.get('status') != 'keep': continue
    if best_metric is None:
        best_metric = m
    elif best_direction == 'lower' and m < best_metric:
        best_metric = m
    elif best_direction == 'higher' and m > best_metric:
        best_metric = m

if best_metric is None:
    best_metric = results[0].get('metric', 0)

# Compute stats over last 10
recent = results[-10:]
keeps = sum(1 for r in recent if r.get('status') == 'keep')
crashes = sum(1 for r in recent if r.get('status') == 'crash')
total = len(recent)
keep_rate = keeps / total if total else 0
crash_rate = crashes / total if total else 0

# Count consecutive discards from tail
consec = 0
for r in reversed(results):
    if r.get('status') == 'keep': break
    consec += 1

# Count near-misses (discards within 5% of best)
near_misses = 0
for r in results:
    if r.get('status') == 'keep': continue
    m = r.get('metric', 0)
    if best_metric and best_metric != 0:
        pct = abs(m - best_metric) / abs(best_metric) * 100
        if pct <= 5:
            near_misses += 1

# Transition rules
if crash_rate > 0.5:
    mode, reason = 'exploit', f'high crash rate ({crash_rate:.0%}), switching to conservative tweaks'
elif consec >= 5 and near_misses >= 2:
    mode, reason = 'combine', f'{consec} consecutive discards, {near_misses} near-misses — try combining best ideas'
elif consec >= 5 and near_misses < 2:
    mode, reason = 'ablation', f'{consec} consecutive discards, no near-misses — try removing components'
elif keep_rate > 0.3:
    mode, reason = 'exploit', f'high keep rate ({keep_rate:.0%}), refining current approach'
else:
    mode, reason = 'explore', f'default exploration (keep rate {keep_rate:.0%})'

print(json.dumps({'mode': mode, 'reason': reason, 'keep_rate': round(keep_rate, 2), 'crash_rate': round(crash_rate, 2), 'near_misses': near_misses}))
" "$jsonl_file" 2>/dev/null || echo '{"mode":"explore","reason":"fallback"}'
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
