#!/bin/bash
# Autoresearch statusline script.
# Shows live experiment loop progress in the Claude Code terminal.
#
# Reads the state file and JSONL to display:
#   autoresearch 5/50 | best: 42.3us (-85%) | last: keep | $1.23
#
# When no autoresearch session is active, outputs nothing.

set -euo pipefail

# Read statusline JSON from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('workspace', {}).get('current_dir', d.get('cwd', '')))
" 2>/dev/null || echo "")

if [ -z "$CWD" ]; then
  exit 0
fi

STATE_FILE="${CWD}/.claude/autoresearch-loop.local.md"
JSONL_FILE="${CWD}/autoresearch.jsonl"

# Only show when autoresearch is active
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Parse state file
ACTIVE=$(sed -n 's/^active:[[:space:]]*\([a-z]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

STOP_COUNT=$(sed -n 's/^stop_count:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
STOP_COUNT="${STOP_COUNT:-0}"
MAX_ITER=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$STATE_FILE" 2>/dev/null)
MAX_ITER="${MAX_ITER:-50}"

# Parse JSONL for experiment stats
if [ -f "$JSONL_FILE" ]; then
  STATS=$(python3 -c "
import json, sys
lines = open(sys.argv[1]).readlines()
config = None
results = []
for line in lines:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
    except: continue
    if d.get('type') == 'config':
        config = d
    else:
        results.append(d)

if not results:
    print('no_results')
    sys.exit(0)

total = len(results)
kept = sum(1 for r in results if r.get('status') == 'keep')
direction = (config or {}).get('bestDirection', 'lower')
unit = (config or {}).get('metricUnit', '')

# Find best and baseline
baseline = results[0].get('metric', 0) if results else 0
if direction == 'lower':
    best_r = min(results, key=lambda r: r.get('metric', float('inf')))
else:
    best_r = max(results, key=lambda r: r.get('metric', float('-inf')))
best = best_r.get('metric', 0)

# Delta from baseline
if baseline and baseline != 0:
    delta = ((best - baseline) / abs(baseline)) * 100
    delta_str = f'{delta:+.1f}%'
else:
    delta_str = ''

# Last result
last = results[-1]
last_status = last.get('status', '?')

# Format metric value
if best >= 1000:
    best_str = f'{best:,.0f}'
elif best >= 1:
    best_str = f'{best:.1f}'
else:
    best_str = f'{best:.2f}'

unit_str = unit if unit else ''
parts = [f'best: {best_str}{unit_str}']
if delta_str:
    parts[0] += f' ({delta_str})'
parts.append(f'last: {last_status}')
parts.append(f'{total} runs {kept} kept')

print(' | '.join(parts))
" "$JSONL_FILE" 2>/dev/null || echo "")
else
  STATS=""
fi

# Build output line
if [ -n "$STATS" ] && [ "$STATS" != "no_results" ]; then
  echo "autoresearch ${STOP_COUNT}/${MAX_ITER} | ${STATS}"
else
  echo "autoresearch ${STOP_COUNT}/${MAX_ITER} | starting..."
fi
