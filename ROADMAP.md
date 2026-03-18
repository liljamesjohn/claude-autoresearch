# Roadmap

Feature roadmap based on codebase review, ecosystem analysis (20+ repos), web research, and QMD community patterns.

---

## Tier 1 — High Impact, Low Effort

### 1. Convergence Detection
Auto-stop when improvements plateau (e.g., 5 consecutive discards or <1% improvement across last N runs). Prevents burning tokens on exhausted search spaces.

**Prior art:** n-autoresearch (explore/exploit/combine modes), ContinueGate (budget slope + rework ratio)
**Effort:** ~50 lines of logic in the skill prompt + state file field

### 2. Cost/Token Budget Ceiling
Stop the loop when cumulative cost exceeds a threshold. The #1 user concern with autonomous loops — no budget control means nobody trusts it unattended.

**Prior art:** Ralph (partial), CCUsage, ContinueGate
**Approach:** Read `cost.total_cost_usd` from statusline JSON in the stop hook
**Effort:** Low

### 3. Status Line Integration
Live progress display in the terminal. Currently the loop is completely silent — users have no idea what's happening without running `/autoresearch-status`.

**Prior art:** claude-hud plugin, pi-autoresearch widget, Ralph display module
**Approach:** A `statusline.sh` script that reads the state file + JSONL tail
**Effort:** Low

### 4. Fix Completion Signal Gap
The stop hook supports `<promise>AUTORESEARCH_COMPLETE</promise>` but SKILL.md never tells Claude to emit it. Dead code. The skill should instruct Claude to emit it when max iterations hit or all ideas are exhausted.

**Prior art:** Ralph Wiggum (canonical pattern)
**Effort:** 3 lines added to SKILL.md

### 5. Guard Rails as Explicit Config
Separate "must not regress" metrics from the optimization target. Currently quality gates are a single pass/fail script. Users want to say "optimize speed but memory must stay under 512MB."

**Prior art:** uditgoenka (`Guard` block), pi-autoresearch (secondary metrics)
**Approach:** Add a `## Guards` section to autoresearch.md parsed by the skill
**Effort:** Low

---

## Tier 2 — High Impact, Medium Effort

### 6. Adaptive Search Strategy
Switch between explore/exploit/combine/ablation modes based on experiment history. The difference between 100 random experiments and 100 progressively smarter ones.

- Crash rate >50% → exploit (conservative, known-good territory)
- Plateau detected + near-misses → combine (merge top-N ideas)
- Plateau detected + no near-misses → ablation (determine what's driving gains)
- Keep rate >30% → back to exploit

**Prior art:** n-autoresearch (4-mode state machine)
**Effort:** ~100 lines of prompt engineering in SKILL.md + state tracking

### 7. Session End Report
Generate a markdown summary when the loop completes. Users want a "what happened while I was away" artifact: experiment count, best/worst, improvement trajectory, recommendations.

**Prior art:** Session summary hook (Florian Bruniaux), Agent Farm HTML reports, Karpathy's analysis.ipynb
**Approach:** A `SessionEnd` hook + report template
**Effort:** Medium

### 8. Profiling-Informed Optimization
Run a profiler after baseline, inject hotspot data into the agent's context. Without profiling data, the agent guesses where to optimize. With it, the agent targets the actual bottleneck.

**Prior art:** Performance profiling specialist agent, Rust perf agent
**Approach:** A `profile.sh` step in setup that runs once, output saved to `autoresearch.md`
**Effort:** Medium

### 9. Secondary Metrics Tracking
Log additional metrics beyond the primary one. SKILL.md mentions it, JSONL schema doesn't support it. Users want to track memory alongside speed, or correctness alongside performance.

**Prior art:** pi-autoresearch (full multi-metric)
**Approach:** Extend `log-experiment.sh` to accept key=value pairs
**Effort:** Medium

### 10. Delta Calculation in Log Helper
Compute and store improvement % vs baseline automatically. Currently Claude computes deltas freehand, leading to inconsistent formatting.

**Prior art:** Every competitor stores deltas.
**Approach:** Add baseline tracking to `log-experiment.sh`
**Effort:** Low-medium

---

## Tier 3 — Medium Impact, Medium-High Effort

### 11. Crash Recovery Ladder
Typed error handling: syntax → retry immediately, runtime → retry 3x, timeout → revert, resource exhaustion → scale down. Current crash handling is "fix if trivial, otherwise move on."

**Prior art:** uditgoenka (4-tier ladder)
**Effort:** Prompt engineering in SKILL.md

### 12. Interactive Setup Wizard
`/autoresearch:plan` with dry-run benchmark verification before the loop starts. Catches misconfigured benchmarks before wasting 50 iterations. Verifies the metric parses correctly.

**Prior art:** uditgoenka (`/plan`), liviaellen (auto-verified baseline with 3 retries)
**Approach:** A new command that runs the benchmark once and validates output format
**Effort:** Medium

### 13. Parallel Worktree Experiments
Spawn N worktrees, each trying a different approach, compare results. Multiplies throughput. The `isolation: worktree` agent pattern is built into Claude Code.

**Prior art:** anything-autoresearch (`launch_agents.sh` + `compare_agents.sh`), Agent Farm
**Approach:** New agent definition + orchestration prompt
**Effort:** Medium-high

### 14. Cross-Session Experiment Sharing
Shared JSONL that survives across branches/sessions. Currently each session is isolated. Users want to know "across all my autoresearch sessions, what's worked?"

**Prior art:** Hyperspace (P2P gossip), Agent Farm (`completed_work_log.json`)
**Approach:** A shared log file in `.git/autoresearch/` (survives worktrees)
**Effort:** Medium

---

## Tier 4 — Nice to Have

### 15. Desktop Notifications
Notify the user on completion, stall, or circuit breaker trigger. Users walk away and want to know when to check back.

**Prior art:** Ralph (open request), Notification hook
**Approach:** `osascript` or `terminal-notifier` in a Stop hook
**Effort:** Trivial

### 16. Adversarial Review of Winners
Challenge each kept experiment with a critic persona before committing. "Find three ways this result could be misleading or fragile."

**Prior art:** ARIS (cross-model adversarial review, improved scores from 5.0 to 7.5/10)
**Effort:** Medium — second prompt per keep

### 17. Domain Templates
Pre-built configs for common optimization targets (test speed, bundle size, API latency, build time, Lighthouse scores).

**Prior art:** astro-sdn, auto-x, automl-research
**Approach:** Markdown templates in `skills/autoresearch/references/`
**Effort:** Low

### 18. Statistical Significance Testing
"Is this 2% improvement real or noise?" Run the benchmark multiple times per experiment and apply basic statistics.

**Prior art:** Experiment Tracker agent (95% CI, p-values)
**Effort:** Medium — requires multiple benchmark runs per experiment

---

## Known Bugs

| Issue | Severity | File |
|-------|----------|------|
| `git clean -fd` in revert can destroy user's untracked files (`.env.local`) | **High** | `hooks/scripts/revert-experiment.sh` |
| `session-start-compact.sh` doesn't check `active` flag — could re-inject context for a stopped session | Low | `hooks/scripts/session-start-compact.sh` |
| `pre-compact.sh` doesn't check `active` flag | Low | `hooks/scripts/pre-compact.sh` |
| Frontmatter parsing duplicated across 3 scripts (DRY violation) | Low | stop-hook.sh, session-start-compact.sh, session-start-resume.sh |
| `log-experiment.sh` silently coerces bad metrics to 0.0 | Medium | `hooks/scripts/log-experiment.sh` |
| README plugin structure missing `log-experiment.sh` and `session-start-resume.sh` | Low | `README.md` |
| Empty `skills/autoresearch/references/` directory | Trivial | — |
| Status command overlap: `/autoresearch status` (SKILL.md) vs `/autoresearch-status` (command) have inconsistent format specs | Low | SKILL.md, commands/autoresearch-status.md |
| Stop hook iteration counter starts at 0, increments before experiment runs — "iteration 1" = end of setup, not first experiment | Low | `hooks/scripts/stop-hook.sh` |

---

## Ecosystem References

| Project | URL | Key Feature to Study |
|---------|-----|---------------------|
| karpathy/autoresearch | https://github.com/karpathy/autoresearch | Original pattern, `program.md` as "research org code" |
| davebcn87/pi-autoresearch | https://github.com/davebcn87/pi-autoresearch | Multi-metric dashboard, backpressure checks, auto-resume |
| uditgoenka/autoresearch | https://github.com/uditgoenka/autoresearch | 8-command suite, Guard blocks, crash recovery ladder |
| drivelineresearch/autoresearch-claude-code | https://github.com/drivelineresearch/autoresearch-claude-code | Claude Code port, mid-loop steering, real-world results |
| iii-hq/n-autoresearch | https://github.com/iii-hq/n-autoresearch | Adaptive search strategy, multi-GPU, structured state |
| liviaellen/autoresearch-gen | https://github.com/liviaellen/autoresearch-gen | Streamlit dashboard, auto-verified baseline, scaffold generator |
| jialinyi94/anything-autoresearch | https://github.com/jialinyi94/anything-autoresearch | Multi-agent worktrees, 3-layer data isolation |
| chrisworsey55/atlas-gic | https://github.com/chrisworsey55/atlas-gic | AI trading agent optimization, Darwinian weights |
| jarrodwatts/claude-hud | https://github.com/jarrodwatts/claude-hud | Status line plugin reference implementation |
| frankbria/ralph-claude-code | https://github.com/frankbria/ralph-claude-code | Mature loop plugin with circuit breaker, rate limiting |
| wanshuiyin/ARIS | https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep | Cross-model adversarial review |
| hyperspaceai/agi | https://github.com/hyperspaceai/agi | Distributed P2P experiment sharing |
