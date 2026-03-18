#!/bin/bash
# Unit tests for stop-hook.sh
# Each test sets up state, pipes JSON to the hook, and checks exit code + output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/scripts/stop-hook.sh"
PASS=0
FAIL=0
TESTS=0

# Create a temp directory for each test
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
    echo "  Output was: $haystack"
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
    echo "  FAIL: $name (expected empty output, got: $output)"
  fi
}

assert_file_not_exists() {
  local path=$1 name=$2
  TESTS=$((TESTS + 1))
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (file still exists: $path)"
  fi
}

# --- Test 1: No state file → allows stop (exit 0, no output) ---
echo "Test 1: No state file"
setup
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 2: stop_hook_active=true → allows stop ---
echo "Test 2: stop_hook_active=true"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 3
max_iterations: 50
active: true
---
Continue the loop.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":true,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 3: Active state file → blocks stop ---
echo "Test 3: Active state file blocks stop"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 3
max_iterations: 50
active: true
---
Continue the autoresearch experiment loop.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"I finished."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_contains '"decision": "block"' "$OUTPUT" "outputs block decision"
assert_output_contains '"reason": "Continue the autoresearch experiment loop."' "$OUTPUT" "outputs reason with prompt"
assert_output_contains "4/50" "$OUTPUT" "outputs iteration 4/50"
teardown

# --- Test 4: Iteration increments in state file ---
echo "Test 4: Iteration increments"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 7
max_iterations: 50
active: true
---
Keep going.
EOF
echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" > /dev/null 2>&1
UPDATED_COUNT=$(sed -n 's/^stop_count:[[:space:]]*\([0-9]*\)/\1/p' "${TEST_DIR}/.claude/autoresearch-loop.local.md")
TESTS=$((TESTS + 1))
if [ "$UPDATED_COUNT" = "8" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: stop_count incremented from 7 to 8"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: expected stop_count 8, got $UPDATED_COUNT"
fi
teardown

# --- Test 5: Max iterations reached → deletes state file, allows stop ---
echo "Test 5: Max iterations reached"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 50
max_iterations: 50
active: true
---
Continue.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
assert_file_not_exists "${TEST_DIR}/.claude/autoresearch-loop.local.md" "state file deleted"
teardown

# --- Test 6: active: false → allows stop ---
echo "Test 6: active: false"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 3
max_iterations: 50
active: false
---
Continue.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
teardown

# --- Test 7: Completion promise in last_assistant_message → stops loop ---
echo "Test 7: Completion promise detected"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 10
max_iterations: 50
active: true
---
Continue.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"All done. <promise>AUTORESEARCH_COMPLETE</promise>"}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_empty "$OUTPUT" "no output"
assert_file_not_exists "${TEST_DIR}/.claude/autoresearch-loop.local.md" "state file deleted"
teardown

# --- Test 8: Empty prompt in state file → uses default prompt ---
echo "Test 8: Empty prompt uses default"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 0
max_iterations: 50
active: true
---
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
assert_output_contains "Continue the autoresearch experiment loop" "$OUTPUT" "uses default prompt"
teardown

# --- Test 9: JSON escaping — prompt with quotes and newlines ---
echo "Test 9: JSON escaping with special characters"
setup
cat > "${TEST_DIR}/.claude/autoresearch-loop.local.md" << 'EOF'
---
stop_count: 0
max_iterations: 50
active: true
---
Continue the loop. Try "sorted()" or use a backslash \ path.
Also check the "What's Been Tried" section.
EOF
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$HOOK" 2>/dev/null)
EXIT_CODE=$?
assert_exit 0 $EXIT_CODE "exits 0"
# Validate the output is valid JSON
TESTS=$((TESTS + 1))
if echo "$OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  PASS=$((PASS + 1))
  echo "  PASS: output is valid JSON despite quotes and backslashes"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: output is not valid JSON"
  echo "  Output was: $OUTPUT"
fi
# Verify the prompt content survived encoding
assert_output_contains "sorted()" "$OUTPUT" "prompt with quotes preserved"
teardown

# --- Summary ---
echo ""
echo "=============================="
echo "Stop Hook Tests: $TESTS total, $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
