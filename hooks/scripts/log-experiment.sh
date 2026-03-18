#!/bin/bash
# Autoresearch Experiment Logger
# Writes a properly formatted JSONL line to autoresearch.jsonl.
# Ensures consistent schema across all experiments.
#
# Usage:
#   log-experiment.sh <working_dir> init <name> <metric_name> <metric_unit> <direction>
#   log-experiment.sh <working_dir> result <run> <metric> <status> <description> [commit] [key=value ...]
#
# Status: keep, discard, crash, checks_failed
# Direction: lower, higher
# Secondary metrics: trailing key=value pairs (e.g., memory_mb=128.4 throughput=9800)

set -euo pipefail

WORKDIR="${1:-.}"
ACTION="${2:-}"
JSONL_FILE="${WORKDIR}/autoresearch.jsonl"

case "$ACTION" in
  init)
    NAME="${3:-}"
    METRIC_NAME="${4:-}"
    METRIC_UNIT="${5:-}"
    DIRECTION="${6:-lower}"

    if [ -z "$NAME" ] || [ -z "$METRIC_NAME" ]; then
      echo "Error: init requires <name> <metric_name> <metric_unit> <direction>" >&2
      exit 1
    fi

    if [ "$DIRECTION" != "lower" ] && [ "$DIRECTION" != "higher" ]; then
      echo "Error: direction must be 'lower' or 'higher', got '$DIRECTION'" >&2
      exit 1
    fi

    python3 -c "
import json, sys
print(json.dumps({
    'type': 'config',
    'name': sys.argv[1],
    'metricName': sys.argv[2],
    'metricUnit': sys.argv[3],
    'bestDirection': sys.argv[4]
}, separators=(',', ':')))
" "$NAME" "$METRIC_NAME" "$METRIC_UNIT" "$DIRECTION" >> "$JSONL_FILE"

    echo "Initialized autoresearch session: $NAME ($METRIC_NAME, $DIRECTION is better)"
    ;;

  result)
    RUN="${3:-}"
    METRIC="${4:-}"
    STATUS="${5:-}"
    DESCRIPTION="${6:-}"
    COMMIT="${7:-$(git -C "$WORKDIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")}"

    if [ -z "$RUN" ] || [ -z "$STATUS" ]; then
      echo "Error: result requires <run> <metric> <status> <description> [commit]" >&2
      exit 1
    fi

    # Validate status
    case "$STATUS" in
      keep|discard|crash|checks_failed) ;;
      *)
        echo "Error: status must be keep, discard, crash, or checks_failed — got '$STATUS'" >&2
        exit 1
        ;;
    esac

    # Collect secondary metrics from trailing key=value args (args 8+)
    SECONDARY_ARGS=""
    shift 7 2>/dev/null || true
    for arg in "$@"; do
      SECONDARY_ARGS="${SECONDARY_ARGS}${SECONDARY_ARGS:+ }${arg}"
    done

    python3 -c "
import json, sys, time

run = int(sys.argv[1])
metric_str = sys.argv[2]
try:
    metric = float(metric_str)
except ValueError:
    print(f'Error: metric must be a number, got \"{metric_str}\"', file=sys.stderr)
    sys.exit(1)

status = sys.argv[3]
commit = sys.argv[4]
description = sys.argv[5]
jsonl_path = sys.argv[6]
secondary_str = sys.argv[7] if len(sys.argv) > 7 else ''

# Parse secondary metrics from space-separated key=value pairs
secondary = {}
for pair in secondary_str.split():
    if '=' in pair:
        k, v = pair.split('=', 1)
        try:
            secondary[k] = float(v)
        except ValueError:
            secondary[k] = v

# Auto-compute delta from baseline (first result in JSONL)
delta_pct = None
try:
    for line in open(jsonl_path):
        d = json.loads(line.strip())
        if d.get('type') == 'config': continue
        baseline = d.get('metric', 0)
        if baseline and baseline != 0:
            delta_pct = round((metric - baseline) / abs(baseline) * 100, 2)
        break
except: pass

record = {
    'run': run,
    'commit': commit,
    'metric': metric,
    'delta_pct': delta_pct,
    'status': status,
    'description': description,
    'timestamp': int(time.time() * 1000)
}
if secondary:
    record['secondary_metrics'] = secondary

print(json.dumps(record, separators=(',', ':')))
" "$RUN" "$METRIC" "$STATUS" "$COMMIT" "$DESCRIPTION" "$JSONL_FILE" "$SECONDARY_ARGS" >> "$JSONL_FILE"

    echo "Logged run #${RUN}: ${STATUS} (${METRIC})"
    ;;

  *)
    echo "Usage: log-experiment.sh <dir> init|result ..." >&2
    exit 1
    ;;
esac
