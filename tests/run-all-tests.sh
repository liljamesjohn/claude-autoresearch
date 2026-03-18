#!/bin/bash
# Run all test suites and report aggregate results.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
SUITES=0
FAILED_SUITES=""

run_suite() {
  local name=$1
  local script=$2
  SUITES=$((SUITES + 1))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  set +e
  OUTPUT=$(bash "$script" 2>&1)
  EXIT_CODE=$?
  set -e

  echo "$OUTPUT"

  # Extract pass/fail counts from the summary line
  PASSED=$(echo "$OUTPUT" | grep -o '[0-9]* passed' | grep -o '[0-9]*' || echo "0")
  FAILED=$(echo "$OUTPUT" | grep -o '[0-9]* failed' | grep -o '[0-9]*' || echo "0")

  TOTAL_PASS=$((TOTAL_PASS + PASSED))
  TOTAL_FAIL=$((TOTAL_FAIL + FAILED))

  if [ "$EXIT_CODE" -ne 0 ]; then
    FAILED_SUITES="${FAILED_SUITES} ${name}"
  fi
}

run_suite "Stop Hook" "${SCRIPT_DIR}/test-stop-hook.sh"
run_suite "Revert Script" "${SCRIPT_DIR}/test-revert-experiment.sh"
run_suite "Session Hooks" "${SCRIPT_DIR}/test-session-hooks.sh"
run_suite "Log Experiment" "${SCRIPT_DIR}/test-log-experiment.sh"
run_suite "E2E Integration" "${SCRIPT_DIR}/test-e2e-loop.sh"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ALL TESTS: $((TOTAL_PASS + TOTAL_FAIL)) total, ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo "  Suites: ${SUITES} run"
if [ -n "$FAILED_SUITES" ]; then
  echo "  Failed:${FAILED_SUITES}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $TOTAL_FAIL
