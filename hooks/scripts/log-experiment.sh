#!/bin/bash
# Autoresearch Experiment Logger
# Writes a properly formatted JSONL line to autoresearch.jsonl.
# Ensures consistent schema across all experiments.
#
# Usage:
#   log-experiment.sh <working_dir> init <name> <metric_name> <metric_unit> <direction>
#   log-experiment.sh <working_dir> result <run> <metric> <status> <description> [commit]
#
# Status: keep, discard, crash, checks_failed
# Direction: lower, higher

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

    python3 -c "
import json, sys, time
run = int(sys.argv[1])
try:
    metric = float(sys.argv[2])
except (ValueError, IndexError):
    metric = 0.0
print(json.dumps({
    'run': run,
    'commit': sys.argv[4],
    'metric': metric,
    'status': sys.argv[3],
    'description': sys.argv[5],
    'timestamp': int(time.time() * 1000)
}, separators=(',', ':')))
" "$RUN" "$METRIC" "$STATUS" "$COMMIT" "$DESCRIPTION" >> "$JSONL_FILE"

    echo "Logged run #${RUN}: ${STATUS} (${METRIC})"
    ;;

  *)
    echo "Usage: log-experiment.sh <dir> init|result ..." >&2
    exit 1
    ;;
esac
