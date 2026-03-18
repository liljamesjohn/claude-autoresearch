#!/bin/bash
# Unit tests for log-experiment.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/scripts/log-experiment.sh"
PASS=0
FAIL=0
TESTS=0

setup() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  git init -q
  echo "test" > file.txt
  git add -A && git commit -q -m "init"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

assert_equals() {
  local expected=$1 actual=$2 name=$3
  TESTS=$((TESTS + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local needle=$1 haystack=$2 name=$3
  TESTS=$((TESTS + 1))
  if echo "$haystack" | grep -q "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (did not contain '$needle')"
  fi
}

assert_valid_json() {
  local line=$1 name=$2
  TESTS=$((TESTS + 1))
  if echo "$line" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (not valid JSON: $line)"
  fi
}

# --- Test 1: Init creates config line ---
echo "Test 1: Init creates config line"
setup
bash "$HOOK" "$TEST_DIR" init "sort-speed" "sort_us" "us" "lower" > /dev/null 2>&1
LINE=$(cat "$TEST_DIR/autoresearch.jsonl")
assert_valid_json "$LINE" "config line is valid JSON"
assert_contains '"type":"config"' "$LINE" "has type config"
assert_contains '"name":"sort-speed"' "$LINE" "has name"
assert_contains '"metricName":"sort_us"' "$LINE" "has metric name"
assert_contains '"bestDirection":"lower"' "$LINE" "has direction"
teardown

# --- Test 2: Result appends correctly ---
echo "Test 2: Result appends to JSONL"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 1 "42.5" "keep" "baseline" > /dev/null 2>&1
LINES=$(wc -l < "$TEST_DIR/autoresearch.jsonl" | tr -d ' ')
assert_equals "2" "$LINES" "JSONL has 2 lines"
RESULT_LINE=$(tail -1 "$TEST_DIR/autoresearch.jsonl")
assert_valid_json "$RESULT_LINE" "result line is valid JSON"
assert_contains '"run":1' "$RESULT_LINE" "has run number"
assert_contains '"metric":42.5' "$RESULT_LINE" "has metric value"
assert_contains '"status":"keep"' "$RESULT_LINE" "has status"
assert_contains '"description":"baseline"' "$RESULT_LINE" "has description"
assert_contains '"timestamp":' "$RESULT_LINE" "has timestamp"
teardown

# --- Test 3: Multiple results accumulate ---
echo "Test 3: Multiple results"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 1 "100" "keep" "baseline" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 2 "80" "keep" "optimization A" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 3 "120" "discard" "bad idea" > /dev/null 2>&1
LINES=$(wc -l < "$TEST_DIR/autoresearch.jsonl" | tr -d ' ')
assert_equals "4" "$LINES" "JSONL has 4 lines (1 config + 3 results)"
teardown

# --- Test 4: Description with special characters ---
echo "Test 4: Special characters in description"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 1 "50" "keep" 'Replace "bubble sort" with sorted() — 50% faster' > /dev/null 2>&1
RESULT_LINE=$(tail -1 "$TEST_DIR/autoresearch.jsonl")
assert_valid_json "$RESULT_LINE" "JSON valid with quotes and special chars"
assert_contains "bubble sort" "$RESULT_LINE" "description preserved"
teardown

# --- Test 5: Crash with zero metric ---
echo "Test 5: Crash status with zero metric"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
bash "$HOOK" "$TEST_DIR" result 1 "0" "crash" "segfault in optimizer" > /dev/null 2>&1
RESULT_LINE=$(tail -1 "$TEST_DIR/autoresearch.jsonl")
assert_valid_json "$RESULT_LINE" "crash line is valid JSON"
assert_contains '"status":"crash"' "$RESULT_LINE" "has crash status"
assert_contains '"metric":0.0' "$RESULT_LINE" "metric is 0"
teardown

# --- Test 6: Missing required args ---
echo "Test 6: Missing required args"
setup
OUTPUT=$(bash "$HOOK" "$TEST_DIR" init 2>&1 || true)
TESTS=$((TESTS + 1))
if echo "$OUTPUT" | grep -qi "error"; then
  PASS=$((PASS + 1))
  echo "  PASS: init with missing args shows error"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: should show error for missing args"
fi
teardown

# --- Test 7: Non-numeric metric is rejected ---
echo "Test 7: Non-numeric metric rejected"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
OUTPUT=$(bash "$HOOK" "$TEST_DIR" result 1 "N/A" "keep" "bad metric" 2>&1 || true)
TESTS=$((TESTS + 1))
if echo "$OUTPUT" | grep -qi "error"; then
  PASS=$((PASS + 1))
  echo "  PASS: non-numeric metric rejected with error"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: should reject non-numeric metric"
fi
# JSONL should NOT have a result line (only the config line)
LINES=$(wc -l < "$TEST_DIR/autoresearch.jsonl" | tr -d ' ')
assert_equals "1" "$LINES" "no result logged for bad metric"
teardown

# --- Test 8: Invalid status is rejected ---
echo "Test 8: Invalid status rejected"
setup
bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "lower" > /dev/null 2>&1
OUTPUT=$(bash "$HOOK" "$TEST_DIR" result 1 "50" "invalid_status" "test" 2>&1 || true)
TESTS=$((TESTS + 1))
if echo "$OUTPUT" | grep -qi "error"; then
  PASS=$((PASS + 1))
  echo "  PASS: invalid status rejected with error"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: should reject invalid status"
fi
teardown

# --- Test 9: Invalid direction is rejected ---
echo "Test 9: Invalid direction rejected"
setup
OUTPUT=$(bash "$HOOK" "$TEST_DIR" init "test" "ms" "ms" "better" 2>&1 || true)
TESTS=$((TESTS + 1))
if echo "$OUTPUT" | grep -qi "error"; then
  PASS=$((PASS + 1))
  echo "  PASS: invalid direction rejected with error"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: should reject invalid direction"
fi
teardown

# --- Summary ---
echo ""
echo "=============================="
echo "Log Experiment Tests: $TESTS total, $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
