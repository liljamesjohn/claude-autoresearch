#!/bin/bash
# Unit tests for revert-experiment.sh
# Sets up a test git repo, makes changes, runs the revert, checks results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/scripts/revert-experiment.sh"
PASS=0
FAIL=0
TESTS=0

setup_repo() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  git init -q
  git checkout -b main 2>/dev/null || true

  # Create initial committed files
  echo "original content" > source.txt
  echo '{"run":1}' > autoresearch.jsonl
  echo "# Session" > autoresearch.md
  cat > autoresearch.sh << 'BENCH'
#!/bin/bash
echo "METRIC test_ms=100"
BENCH
  chmod +x autoresearch.sh
  git add -A
  git commit -q -m "initial commit"
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

assert_file_exists() {
  local path=$1 name=$2
  TESTS=$((TESTS + 1))
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (file missing: $path)"
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

# --- Test 1: Modified source file is reverted, protected files preserved ---
echo "Test 1: Basic revert with protected files"
setup_repo

# Simulate a failed experiment: modify source and update JSONL
echo "modified content" > source.txt
echo '{"run":2,"status":"discard"}' >> autoresearch.jsonl

bash "$HOOK" "$TEST_DIR" > /dev/null 2>&1

assert_equals "original content" "$(cat source.txt)" "source.txt reverted"
assert_file_exists "autoresearch.jsonl" "JSONL preserved"
# The JSONL should have the new line (it was protected)
LINES=$(wc -l < autoresearch.jsonl | tr -d ' ')
assert_equals "2" "$LINES" "JSONL has both lines"
assert_file_exists "autoresearch.md" "session doc preserved"
assert_file_exists "autoresearch.sh" "benchmark script preserved"
teardown

# --- Test 2: New untracked files are cleaned up ---
echo "Test 2: Untracked files cleaned"
setup_repo

echo "new file" > new-experiment-file.txt
echo "another" > temp-output.log

bash "$HOOK" "$TEST_DIR" > /dev/null 2>&1

assert_file_not_exists "new-experiment-file.txt" "untracked file removed"
assert_file_not_exists "temp-output.log" "untracked log removed"
assert_file_exists "source.txt" "committed file still exists"
teardown

# --- Test 3: Revert with no changes (clean state) ---
echo "Test 3: Clean state (no changes to revert)"
setup_repo

OUTPUT=$(bash "$HOOK" "$TEST_DIR" 2>&1)
EXIT_CODE=$?

TESTS=$((TESTS + 1))
if [ "$EXIT_CODE" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo "  PASS: exits 0 on clean state"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: expected exit 0, got $EXIT_CODE"
fi
assert_equals "original content" "$(cat source.txt)" "source unchanged"
teardown

# --- Test 4: autoresearch.ideas.md is preserved ---
echo "Test 4: Ideas file preserved"
setup_repo

echo "- Try SIMD approach" > autoresearch.ideas.md
echo "modified" > source.txt

bash "$HOOK" "$TEST_DIR" > /dev/null 2>&1

assert_file_exists "autoresearch.ideas.md" "ideas file preserved"
assert_equals "- Try SIMD approach" "$(cat autoresearch.ideas.md)" "ideas content intact"
assert_equals "original content" "$(cat source.txt)" "source reverted"
teardown

# --- Test 5: autoresearch.checks.sh is preserved ---
echo "Test 5: Checks script preserved"
setup_repo

cat > autoresearch.checks.sh << 'CHECKS'
#!/bin/bash
bun run test
CHECKS
echo "modified" > source.txt

bash "$HOOK" "$TEST_DIR" > /dev/null 2>&1

assert_file_exists "autoresearch.checks.sh" "checks script preserved"
assert_equals "original content" "$(cat source.txt)" "source reverted"
teardown

# --- Test 6: .env files are NOT destroyed (Bug 1 fix) ---
echo "Test 6: User .env files preserved"
setup_repo

echo "SECRET_KEY=abc123" > .env.local
echo "DB_URL=postgres://localhost" > .env
echo "new experiment file" > new-code.py
echo "modified" > source.txt

bash "$HOOK" "$TEST_DIR" > /dev/null 2>&1

assert_file_exists ".env.local" ".env.local preserved"
assert_file_exists ".env" ".env preserved"
assert_equals "SECRET_KEY=abc123" "$(cat .env.local)" ".env.local content intact"
assert_equals "original content" "$(cat source.txt)" "source reverted"
assert_file_not_exists "new-code.py" "experiment file removed"
teardown

# --- Summary ---
echo ""
echo "=============================="
echo "Revert Tests: $TESTS total, $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
