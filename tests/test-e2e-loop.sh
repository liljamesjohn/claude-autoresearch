#!/bin/bash
# End-to-end integration test for the autoresearch loop lifecycle.
# Simulates what Claude would do: setup → baseline → keep → discard → status → off → resume.
# Uses the toy-project fixture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR}/.."
STOP_HOOK="${PLUGIN_ROOT}/hooks/scripts/stop-hook.sh"
REVERT_SCRIPT="${PLUGIN_ROOT}/hooks/scripts/revert-experiment.sh"
LOG_SCRIPT="${PLUGIN_ROOT}/hooks/scripts/log-experiment.sh"
SESSION_HOOK="${PLUGIN_ROOT}/hooks/scripts/session-start-compact.sh"
RESUME_HOOK="${PLUGIN_ROOT}/hooks/scripts/session-start-resume.sh"
FIXTURE="${SCRIPT_DIR}/fixtures/toy-project"

PASS=0
FAIL=0
TESTS=0

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

# === SETUP: Create a main repo, then a worktree (simulating `claude -w`) ===
MAIN_REPO=$(mktemp -d)
cp -r "$FIXTURE"/* "$MAIN_REPO/"
cd "$MAIN_REPO"
git init -q
git checkout -b main 2>/dev/null || true
git add -A
git commit -q -m "initial commit"

# Create a worktree — this is what `claude -w autoresearch-sort` does
WORKTREE_DIR=$(mktemp -d)
rm -rf "$WORKTREE_DIR"  # git worktree add needs a non-existent path
git worktree add "$WORKTREE_DIR" -b autoresearch/sort-speed 2>/dev/null

# All work happens in the worktree
TEST_DIR="$WORKTREE_DIR"
cd "$TEST_DIR"

cleanup() {
  cd /
  git -C "$MAIN_REPO" worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
  rm -rf "$MAIN_REPO" "$WORKTREE_DIR"
}
trap cleanup EXIT

echo "============================================"
echo "E2E Test: Full Autoresearch Loop Lifecycle"
echo "Main repo: $MAIN_REPO"
echo "Worktree:  $TEST_DIR"
echo "============================================"
echo ""

# === Phase 1: Setup (what the skill would do) ===
echo "Phase 1: Setup"

# Verify we're in a worktree (.git is a file, not a directory)
TESTS=$((TESTS + 1))
if [ -f .git ]; then
  PASS=$((PASS + 1))
  echo "  PASS: running in a worktree (.git is a file)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: not in a worktree (.git should be a file)"
fi
assert_equals "autoresearch/sort-speed" "$(git branch --show-current)" "on worktree branch"

# Write session files
cat > autoresearch.md << 'EOF'
# Autoresearch: Optimize sort speed

## Objective
Speed up the sort_numbers function in sort.py.

## Metrics
- **Primary**: sort_us (microseconds, lower is better)

## How to Run
./autoresearch.sh

## Files in Scope
- sort.py — the sorting module to optimize

## Off Limits
- test_sort.py — tests must not be modified
- benchmark.sh — benchmark must not be modified

## Constraints
- All tests must pass
- No external dependencies

## Baseline
- TBD

## What's Been Tried
(none yet)
EOF

cp benchmark.sh autoresearch.sh
chmod +x autoresearch.sh

cat > autoresearch.checks.sh << 'CHECKS'
#!/bin/bash
set -euo pipefail
python3 test_sort.py 2>&1 | tail -5
CHECKS
chmod +x autoresearch.checks.sh

git add autoresearch.md autoresearch.sh autoresearch.checks.sh
git commit -q -m "autoresearch: session setup"

assert_file_exists "autoresearch.md" "session doc created"
assert_file_exists "autoresearch.sh" "benchmark script created"
assert_file_exists "autoresearch.checks.sh" "checks script created"

# Write state file for stop hook
mkdir -p .claude
cat > .claude/autoresearch-loop.local.md << 'STATE'
---
stop_count: 0
max_iterations: 50
active: true
---
Read autoresearch.md for full context. Continue the experiment loop.
STATE

assert_file_exists ".claude/autoresearch-loop.local.md" "state file created"

# Initialize JSONL with config header using helper
bash "$LOG_SCRIPT" "$TEST_DIR" init "sort-speed" "sort_us" "us" "lower" > /dev/null 2>&1

echo ""

# === Phase 2: Baseline measurement ===
echo "Phase 2: Baseline"

BENCH_OUTPUT=$(bash autoresearch.sh 2>&1)
BASELINE_METRIC=$(echo "$BENCH_OUTPUT" | sed -n 's/METRIC sort_us=\([0-9.]*\)/\1/p')
assert_contains "METRIC sort_us=" "$BENCH_OUTPUT" "benchmark outputs metric"

# Log baseline using helper
bash "$LOG_SCRIPT" "$TEST_DIR" result 1 "$BASELINE_METRIC" "keep" "baseline (bubble sort)" > /dev/null 2>&1

JSONL_LINES=$(wc -l < autoresearch.jsonl | tr -d ' ')
assert_equals "2" "$JSONL_LINES" "JSONL has config + baseline"
echo "  Baseline metric: ${BASELINE_METRIC} us"

echo ""

# === Phase 3: Simulate a KEEP experiment ===
echo "Phase 3: Keep experiment (replace bubble sort with Python sorted())"

# Make the optimization
cat > sort.py << 'PYEOF'
"""Optimized sorting module."""


def sort_numbers(numbers: list[int]) -> list[int]:
    """Sort a list of integers using Python's built-in Timsort."""
    return sorted(numbers)


def find_median(numbers: list[int]) -> float:
    """Find the median of a list of integers."""
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    if n % 2 == 0:
        return (sorted_nums[n // 2 - 1] + sorted_nums[n // 2]) / 2
    return sorted_nums[n // 2]


def find_percentile(numbers: list[int], p: float) -> float:
    """Find the p-th percentile (0-100) of a list of integers."""
    if not 0 <= p <= 100:
        raise ValueError("Percentile must be between 0 and 100")
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    k = (p / 100) * (n - 1)
    f = int(k)
    c = f + 1
    if c >= n:
        return sorted_nums[f]
    return sorted_nums[f] + (k - f) * (sorted_nums[c] - sorted_nums[f])
PYEOF

# Run benchmark
BENCH_OUTPUT=$(bash autoresearch.sh 2>&1)
NEW_METRIC=$(echo "$BENCH_OUTPUT" | sed -n 's/METRIC sort_us=\([0-9.]*\)/\1/p')
echo "  New metric: ${NEW_METRIC} us"

# Run checks
CHECKS_OUTPUT=$(bash autoresearch.checks.sh 2>&1)
CHECKS_EXIT=$?
assert_equals "0" "$CHECKS_EXIT" "checks pass after optimization"

# Simulate KEEP: commit
git add -A
git commit -q -m "Use Python built-in sorted() instead of bubble sort

Autoresearch: {\"status\":\"keep\",\"metric\":${NEW_METRIC},\"delta\":\"-99%\"}"
KEEP_COMMIT=$(git rev-parse --short HEAD)

bash "$LOG_SCRIPT" "$TEST_DIR" result 2 "$NEW_METRIC" "keep" "Replace bubble sort with built-in sorted()" "$KEEP_COMMIT" > /dev/null 2>&1

JSONL_LINES=$(wc -l < autoresearch.jsonl | tr -d ' ')
assert_equals "3" "$JSONL_LINES" "JSONL has 3 lines after keep"

# Verify the optimization stuck
CURRENT_CONTENT=$(head -5 sort.py)
assert_contains "Timsort" "$CURRENT_CONTENT" "optimized code is in place"

echo ""

# === Phase 4: Simulate a DISCARD experiment ===
echo "Phase 4: Discard experiment (bad change that breaks tests)"

# Make a bad change
cat > sort.py << 'PYEOF'
"""Broken sorting module — returns reversed list."""


def sort_numbers(numbers: list[int]) -> list[int]:
    """Intentionally broken."""
    return list(reversed(numbers))


def find_median(numbers: list[int]) -> float:
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    if n % 2 == 0:
        return (sorted_nums[n // 2 - 1] + sorted_nums[n // 2]) / 2
    return sorted_nums[n // 2]


def find_percentile(numbers: list[int], p: float) -> float:
    if not 0 <= p <= 100:
        raise ValueError("Percentile must be between 0 and 100")
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    k = (p / 100) * (n - 1)
    f = int(k)
    c = f + 1
    if c >= n:
        return sorted_nums[f]
    return sorted_nums[f] + (k - f) * (sorted_nums[c] - sorted_nums[f])
PYEOF

# Run checks — should fail
CHECKS_OUTPUT=$(bash autoresearch.checks.sh 2>&1 || true)
CHECKS_EXIT=$?
# Note: set -e in the checks script means it exits non-zero on test failure
# But we're running it with || true, so we check the content
assert_contains "failed" "$CHECKS_OUTPUT" "checks detect broken code"

# Simulate DISCARD: log then revert
bash "$LOG_SCRIPT" "$TEST_DIR" result 3 "0" "checks_failed" "Return reversed list (broken)" > /dev/null 2>&1
bash "$REVERT_SCRIPT" "$TEST_DIR" > /dev/null 2>&1

# Verify code was reverted to the good version
REVERTED_CONTENT=$(head -5 sort.py)
assert_contains "Timsort" "$REVERTED_CONTENT" "code reverted to last good commit"

# Verify JSONL survived the revert
JSONL_LINES=$(wc -l < autoresearch.jsonl | tr -d ' ')
assert_equals "4" "$JSONL_LINES" "JSONL has 4 lines after discard (preserved)"

# Verify tests pass again
CHECKS_OUTPUT=$(bash autoresearch.checks.sh 2>&1)
assert_contains "passed" "$CHECKS_OUTPUT" "tests pass after revert"

echo ""

# === Phase 5: Stop hook behavior ===
echo "Phase 5: Stop hook keeps loop running"

OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"I optimized the sort."}' | bash "$STOP_HOOK" 2>/dev/null)
assert_contains '"decision": "block"' "$OUTPUT" "stop hook blocks"
assert_contains "1/50" "$OUTPUT" "stop count incremented to 1"

# Check stop_count was updated in state file
COUNT=$(sed -n 's/^stop_count:[[:space:]]*\([0-9]*\)/\1/p' .claude/autoresearch-loop.local.md)
assert_equals "1" "$COUNT" "state file shows stop_count 1"

echo ""

# === Phase 6: Autoresearch OFF ===
echo "Phase 6: Turn off autoresearch"

rm -f .claude/autoresearch-loop.local.md
assert_file_not_exists ".claude/autoresearch-loop.local.md" "state file deleted"

# Stop hook should now allow stop
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false,"last_assistant_message":"Done."}' | bash "$STOP_HOOK" 2>/dev/null)
TESTS=$((TESTS + 1))
if [ -z "$OUTPUT" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: stop hook allows stop after OFF"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: stop hook should produce no output (got: $OUTPUT)"
fi

echo ""

# === Phase 7: Resume (re-activate) ===
echo "Phase 7: Resume"

cat > .claude/autoresearch-loop.local.md << 'STATE'
---
stop_count: 1
max_iterations: 50
active: true
---
Read autoresearch.md for full context. Continue the experiment loop.
STATE

# Simulate context compaction — session start hook should re-inject context
COMPACT_OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","hook_event_name":"SessionStart","source":"compact"}' | bash "$SESSION_HOOK" 2>/dev/null)
assert_contains "AUTORESEARCH_CONTEXT_RESTORED" "$COMPACT_OUTPUT" "context restored after compaction"
assert_contains "Optimize sort speed" "$COMPACT_OUTPUT" "session doc content injected"
assert_contains "Replace bubble sort" "$COMPACT_OUTPUT" "JSONL results injected"

echo ""

# === Phase 8: JSONL integrity check ===
echo "Phase 8: JSONL format validation"

# Every line should be valid JSON
INVALID_LINES=0
while IFS= read -r line; do
  if ! echo "$line" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    INVALID_LINES=$((INVALID_LINES + 1))
    echo "  Invalid JSON: $line"
  fi
done < autoresearch.jsonl

TESTS=$((TESTS + 1))
if [ "$INVALID_LINES" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo "  PASS: all JSONL lines are valid JSON"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: $INVALID_LINES invalid JSON lines"
fi

# Check config line
CONFIG_LINE=$(head -1 autoresearch.jsonl)
assert_contains '"type":"config"' "$CONFIG_LINE" "first line is config"
assert_contains '"bestDirection":"lower"' "$CONFIG_LINE" "config has direction"

# Check we have the right number of entries
TOTAL_LINES=$(wc -l < autoresearch.jsonl | tr -d ' ')
assert_equals "4" "$TOTAL_LINES" "JSONL has 4 total lines (1 config + 3 experiments)"

# Check statuses
KEEP_COUNT=$(grep -c '"status":"keep"' autoresearch.jsonl)
DISCARD_COUNT=$(grep -c '"status":"checks_failed"' autoresearch.jsonl)
assert_equals "2" "$KEEP_COUNT" "2 keep entries (baseline + optimization)"
assert_equals "1" "$DISCARD_COUNT" "1 checks_failed entry"

echo ""

# === Phase 9: Git history integrity ===
echo "Phase 9: Git history"

COMMIT_COUNT=$(git log --oneline | wc -l | tr -d ' ')
assert_equals "3" "$COMMIT_COUNT" "3 commits (initial + setup + kept optimization)"

LAST_COMMIT_MSG=$(git log -1 --format=%s)
assert_contains "sorted()" "$LAST_COMMIT_MSG" "last commit is the kept optimization"

# The discarded experiment should NOT be in the git history
DISCARD_IN_HISTORY=$(git log --oneline --all | grep -c "reversed" || true)
assert_equals "0" "$DISCARD_IN_HISTORY" "discarded experiment not in git history"

echo ""

# === Phase 10: Worktree isolation verification ===
echo "Phase 10: Main repo untouched"

# The main repo should have exactly 1 commit (the initial one)
MAIN_COMMITS=$(git -C "$MAIN_REPO" log --oneline main | wc -l | tr -d ' ')
assert_equals "1" "$MAIN_COMMITS" "main repo has only initial commit"

# Main repo should not have autoresearch files
TESTS=$((TESTS + 1))
if [ ! -f "${MAIN_REPO}/autoresearch.md" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: main repo has no autoresearch.md"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: autoresearch.md leaked to main repo"
fi

TESTS=$((TESTS + 1))
if [ ! -f "${MAIN_REPO}/autoresearch.jsonl" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: main repo has no autoresearch.jsonl"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: autoresearch.jsonl leaked to main repo"
fi

echo ""

# === Summary ===
echo "============================================"
echo "E2E Tests: $TESTS total, $PASS passed, $FAIL failed"
echo "============================================"
exit $FAIL
