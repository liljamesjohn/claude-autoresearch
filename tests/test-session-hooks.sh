#!/bin/bash
# Unit tests for session-start-compact.sh and pre-compact.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_HOOK="${SCRIPT_DIR}/../hooks/scripts/session-start-compact.sh"
PRECOMPACT_HOOK="${SCRIPT_DIR}/../hooks/scripts/pre-compact.sh"
PASS=0
FAIL=0
TESTS=0

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "${TEST_DIR}/.claude"
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_exit() {
  local expected=$1 actual=$2 name=$3
  TESTS=$((TESTS + 1))
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name (exit $actual)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected exit $expected, got $actual)"
  fi
}

assert_output_contains() {
  local needle=$1 haystack=$2 name=$3
  TESTS=$((TESTS + 1))
  if echo "$haystack" | grep -q "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (output did not contain '$needle')"
  fi
}

assert_output_empty() {
  local output=$1 name=$2
  TESTS=$((TESTS + 1))
  if [ -z "$output" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected empty, got: $output)"
  fi
}

# ============================================
# SESSION START COMPACT HOOK
# ============================================
echo "=== Session Start Compact Hook ==="

# --- Test 1: No state file → no output ---
echo "Test 1: No state file"
setup
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"SessionStart","source":"compact"}' | bash "$SESSION_HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 2: No session doc → no output ---
echo "Test 2: State file but no autoresearch.md"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
iteration: 5
max_iterations: 50
active: true
---
Continue.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"SessionStart","source":"compact"}' | bash "$SESSION_HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 3: Both files present → outputs context ---
echo "Test 3: Full context injection"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
iteration: 12
max_iterations: 50
active: true
---
Continue.
EOF
cat > "${TEST_DIR}/autoresearch.md" << 'EOF'
# Autoresearch: Optimize FIFO
## Objective
Speed up FIFO lot matching
EOF
echo '{"run":1,"metric":100,"status":"keep","description":"baseline"}' > "${TEST_DIR}/autoresearch.jsonl"
echo '{"run":2,"metric":95,"status":"keep","description":"pre-sort"}' >> "${TEST_DIR}/autoresearch.jsonl"

OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"SessionStart","source":"compact"}' | bash "$SESSION_HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_contains "AUTORESEARCH_CONTEXT_RESTORED" "$OUTPUT" "contains context tag"
assert_output_contains "iteration 12/50" "$OUTPUT" "contains iteration count"
assert_output_contains "Optimize FIFO" "$OUTPUT" "contains session doc content"
assert_output_contains "pre-sort" "$OUTPUT" "contains JSONL results"
assert_output_contains "CONTINUE THE LOOP" "$OUTPUT" "contains loop instruction"
teardown

# ============================================
# PRE-COMPACT HOOK
# ============================================
echo ""
echo "=== Pre-Compact Hook ==="

# --- Test 4: No state file → no output ---
echo "Test 4: No state file"
setup
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"PreCompact","trigger":"auto"}' | bash "$PRECOMPACT_HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 5: Active autoresearch → outputs preservation reminder ---
echo "Test 5: Active session outputs reminder"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
iteration: 5
max_iterations: 50
active: true
---
Continue.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"PreCompact","trigger":"auto"}' | bash "$PRECOMPACT_HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_contains "IMPORTANT" "$OUTPUT" "contains IMPORTANT marker"
assert_output_contains "optimization goal" "$OUTPUT" "mentions optimization goal"
teardown

# --- Summary ---
echo ""
echo "=============================="
echo "Session Hook Tests: $TESTS total, $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
