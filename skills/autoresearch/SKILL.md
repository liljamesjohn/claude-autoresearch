---
name: autoresearch
description: Set up and run an autonomous experiment loop for any optimization target. Use when asked to "run autoresearch", "optimize X in a loop", "set up autoresearch", "start experiments", or "benchmark and optimize".
argument-hint: <goal or "resume" or "off" or "clear" or "status">
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Autoresearch

Autonomous experiment loop: try ideas, keep what works, discard what doesn't, never stop.

## Commands

- `/autoresearch <goal>` — set up a new session and start looping
- `/autoresearch resume` — resume from existing `autoresearch.md`
- `/autoresearch status` — show experiment results summary
- `/autoresearch off` — deactivate the loop (stop hook stops blocking)
- `/autoresearch clear` — delete `autoresearch.jsonl` and reset all state

## Setup

When starting a new session:

1. **Gather info** — ask or infer from context:
   - **Goal**: what are we optimizing? (e.g., "FIFO lot matching speed")
   - **Command**: the benchmark command (e.g., `bun run bench:fifo`)
   - **Metric**: name, unit, and direction (e.g., `recalc_us`, microseconds, lower is better)
   - **Files in scope**: which files may be modified
   - **Quality gate** (optional): correctness checks command (e.g., `bun run test`)
   - **Constraints**: hard rules (no new deps, specific files off-limits, etc.)

2. **Create branch**: `git checkout -b autoresearch/<goal-slug>-<date>`

3. **Read source files deeply** before writing anything. Understand the workload.

4. **Write session files** and commit them:

### `autoresearch.md`

The heart of the session. A fresh agent with zero context should be able to read this file and run the loop effectively. Invest time making it excellent.

```markdown
# Autoresearch: <goal>

## Objective
Specific description of what we're optimizing and why.

## Metrics
- **Primary**: <name> (<unit>, <lower|higher> is better)
- **Secondary** (optional): additional metrics to track

## How to Run
./autoresearch.sh

## Files in Scope
List every file the agent may modify, with brief notes on what each does.

## Off Limits
What must NOT be touched and why.

## Constraints
Hard rules: tests must pass, no new dependencies, etc.

## Baseline
- Primary metric: <value>
- Date: <date>
- Commit: <hash>

## What's Been Tried
Updated as experiments accumulate. Format:
- Run N: <description> → <kept|discarded|crashed> (<metric value>, <delta%>)
```

### `autoresearch.sh`

Bash benchmark script. Must:
- Use `set -euo pipefail`
- Run fast (every second is multiplied by hundreds of runs)
- Output `METRIC <name>=<number>` lines on stdout
- Exit 0 on success, non-zero on failure

Example:
```bash
#!/bin/bash
set -euo pipefail
# Pre-check: fast syntax/compile verification
bun check

# Run benchmark
RESULT=$(bun run bench:fifo 2>&1)
echo "$RESULT"

# Extract and output metric
TIME=$(echo "$RESULT" | grep -oP 'recalc_us: \K[0-9.]+')
echo "METRIC recalc_us=$TIME"
```

### `autoresearch.checks.sh` (optional)

Only create when quality gates are needed. Runs after every passing benchmark.
- Uses `set -euo pipefail`
- Runs correctness checks (tests, types, lint)
- Exit 0 = checks pass, non-zero = checks fail
- Its execution time does NOT affect the primary metric
- Keep output minimal — only errors, suppress verbose success

Example:
```bash
#!/bin/bash
set -euo pipefail
bun run test --run 2>&1 | tail -20
```

5. **Make scripts executable**: `chmod +x autoresearch.sh autoresearch.checks.sh`

6. **Activate the loop**: write the state file that tells the stop hook to keep looping:

```bash
cat > .claude/autoresearch-loop.local.md << 'EOF'
---
iteration: 0
max_iterations: 50
active: true
---
Read autoresearch.md for full context. Continue the experiment loop.
EOF
```

7. **Initialize JSONL** using the log helper:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/log-experiment.sh . init "<goal>" "<metric_name>" "<metric_unit>" "<lower|higher>"
```

8. **Run baseline**: execute `./autoresearch.sh`, parse the metric, log the baseline:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/log-experiment.sh . result 1 <baseline_metric> keep "baseline"
```

9. **Start looping immediately**

## The Experiment Loop

Each iteration:

1. **Review context**: read `autoresearch.md` (especially "What's Been Tried"), check git log for recent experiments, check `autoresearch.ideas.md` if it exists
2. **Form a hypothesis**: decide what to try next. Prefer ideas that are structurally different from recent failures.
3. **Edit files**: make the code change
4. **Run benchmark**: `./autoresearch.sh`
5. **Parse metric**: extract the `METRIC name=value` line from output
6. **Run quality gate** (if `autoresearch.checks.sh` exists): `./autoresearch.checks.sh`
7. **Decide and act**:

### If improved (metric is better) AND checks pass:
```bash
git add -A
git commit -m "<description>

Autoresearch: {\"status\":\"keep\",\"metric\":<value>,\"delta\":\"<delta%>\"}"
```
Log the result using the helper (ensures consistent JSONL format):
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/log-experiment.sh . result <run_number> <metric_value> keep "<description>"
```

### If worse/equal OR checks fail:
Revert code changes (autoresearch files are automatically preserved):
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/revert-experiment.sh .
```
Log the result:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/log-experiment.sh . result <run_number> <metric_value> discard|crash|checks_failed "<description>"
```

8. **Update `autoresearch.md`**: append to "What's Been Tried"
9. **Repeat** — go to step 1

## Loop Rules

**LOOP FOREVER.** Never ask "should I continue?" Never stop to summarize. Never wait for permission.

- **Primary metric is king.** Improved → `keep`. Worse or equal → `discard`.
- **Simpler is better.** Removing code for equal performance = `keep`.
- **Don't thrash.** Repeatedly reverting the same idea? Try something structurally different.
- **Crashes**: fix if trivial (typo, missing import), otherwise log as `crash` and move on.
- **Think longer when stuck.** Re-read source files. Study profiling data. Try a completely different approach.
- **If out of ideas, think harder.** Read academic papers in your training data. Try counterintuitive approaches. Combine two previous ideas.

**NEVER STOP.** The user may be away for hours.

## Guardrails

- **Do not overfit to the benchmark.** The optimization must improve real-world performance, not just game the measurement script.
- **Do not cheat on the benchmark.** Never modify `autoresearch.sh`, `autoresearch.checks.sh`, or the test suite to make metrics look better.
- **Do not add benchmark-specific code paths.** No `if running_benchmark: ...` shortcuts. The optimized code must be production-quality.

## Ideas Backlog

When you discover promising but complex optimizations you won't pursue right now, append them as bullets to `autoresearch.ideas.md`. On resume, check and prune stale entries, experiment with the rest.

## Resuming

When `/autoresearch resume` is called or after context compaction:

1. Read `autoresearch.md` — this is the complete session state
2. Read `autoresearch.jsonl` — parse to find run count, best metric, recent results
3. Check `git log --oneline -10` — see recent commits
4. Check `autoresearch.ideas.md` if it exists — promising paths to explore
5. Continue looping from where you left off

## User Messages During Experiments

If the user sends a message while you're mid-experiment, finish the current run + log cycle first, then incorporate their feedback.

## Status Display

When `/autoresearch status` is called, parse `autoresearch.jsonl` and display:

```
Autoresearch: <name>
Metric: <metric_name> (<unit>, <direction> is better)
Runs: <total> | Kept: <kept> | Discarded: <discarded> | Crashed: <crashed>
Baseline: <baseline_value> (run #1)
Best: <best_value> (run #N, <delta%> improvement)

Recent experiments:
  #N: <description> → <status> (<value>, <delta%>)
  #N-1: ...
  ...
```

## Deactivating

When `/autoresearch off` is called:
- Delete `.claude/autoresearch-loop.local.md` (stops the stop hook)
- Print a summary of results
- Do NOT delete `autoresearch.jsonl` or `autoresearch.md`

When `/autoresearch clear` is called:
- Delete `.claude/autoresearch-loop.local.md`
- Delete `autoresearch.jsonl`
- Print confirmation
- Do NOT delete `autoresearch.md` (it's still useful as documentation)
