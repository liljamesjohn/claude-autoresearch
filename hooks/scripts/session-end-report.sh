#!/bin/bash
# Autoresearch SessionEnd Hook
# Generates autoresearch-report.md when the session ends.

set -euo pipefail

# Source shared utilities
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/lib.sh"

read_hook_input

# Only generate report if autoresearch JSONL exists
JSONL_FILE="${HOOK_CWD}/autoresearch.jsonl"
if [ ! -f "$JSONL_FILE" ]; then
  exit 0
fi

REPORT_FILE="${HOOK_CWD}/autoresearch-report.md"

python3 -c "
import json, sys, os
from datetime import datetime

jsonl_path = sys.argv[1]
report_path = sys.argv[2]
cwd = sys.argv[3]

# Parse JSONL
config = None
results = []
for line in open(jsonl_path):
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
    sys.exit(0)

name = (config or {}).get('name', 'unknown')
metric_name = (config or {}).get('metricName', 'metric')
metric_unit = (config or {}).get('metricUnit', '')
direction = (config or {}).get('bestDirection', 'lower')

total = len(results)
kept = sum(1 for r in results if r.get('status') == 'keep')
discarded = sum(1 for r in results if r.get('status') == 'discard')
crashed = sum(1 for r in results if r.get('status') in ('crash', 'checks_failed'))

baseline = results[0].get('metric', 0)
if direction == 'lower':
    best_r = min(results, key=lambda r: r.get('metric', float('inf')) if r.get('status') == 'keep' else float('inf'))
else:
    best_r = max(results, key=lambda r: r.get('metric', float('-inf')) if r.get('status') == 'keep' else float('-inf'))
best = best_r.get('metric', 0)
best_desc = best_r.get('description', '')
best_run = best_r.get('run', '?')

if baseline and baseline != 0:
    improvement = ((best - baseline) / abs(baseline)) * 100
    improvement_str = f'{improvement:+.2f}%'
else:
    improvement_str = 'N/A'

# Build report
lines = []
lines.append(f'# Autoresearch Report: {name}')
lines.append(f'')
lines.append(f'Generated: {datetime.now().strftime(\"%Y-%m-%d %H:%M\")}')
lines.append(f'')
lines.append(f'## Summary')
lines.append(f'')
lines.append(f'| | |')
lines.append(f'|---|---|')
lines.append(f'| **Metric** | {metric_name} ({metric_unit}, {direction} is better) |')
lines.append(f'| **Total runs** | {total} |')
lines.append(f'| **Kept** | {kept} |')
lines.append(f'| **Discarded** | {discarded} |')
lines.append(f'| **Crashed** | {crashed} |')
lines.append(f'| **Baseline** | {baseline} (run #1) |')
lines.append(f'| **Best** | {best} (run #{best_run}, {improvement_str}) |')
lines.append(f'| **Best description** | {best_desc} |')
lines.append(f'')
lines.append(f'## Experiments')
lines.append(f'')
lines.append(f'| Run | Status | {metric_name} | Delta | Description |')
lines.append(f'|-----|--------|{\"---\" * 1}|-------|-------------|')

for r in results:
    run = r.get('run', '?')
    status = r.get('status', '?')
    metric = r.get('metric', 0)
    delta = r.get('delta_pct')
    desc = r.get('description', '')
    delta_str = f'{delta:+.1f}%' if delta is not None else '—'
    status_icon = {'keep': 'keep', 'discard': 'discard', 'crash': 'CRASH', 'checks_failed': 'FAIL'}.get(status, status)
    lines.append(f'| {run} | {status_icon} | {metric} | {delta_str} | {desc} |')

lines.append(f'')
lines.append(f'## Git History (kept experiments)')
lines.append(f'')
lines.append(f'```')
try:
    import subprocess
    git_log = subprocess.run(['git', '-C', cwd, 'log', '--oneline', '-20'], capture_output=True, text=True).stdout.strip()
    lines.append(git_log if git_log else '(no commits)')
except:
    lines.append('(git log unavailable)')
lines.append(f'```')

with open(report_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

# Print summary to terminal (best-effort — /dev/tty may not exist in headless mode)
summary = f'Autoresearch report written: {total} experiments, {kept} kept, best {metric_name}={best} ({improvement_str})'
try:
    with open('/dev/tty', 'w') as tty:
        tty.write(summary + '\\n')
except:
    print(summary, file=sys.stderr)
" "$JSONL_FILE" "$REPORT_FILE" "$HOOK_CWD" 2>/dev/null || true

exit 0
