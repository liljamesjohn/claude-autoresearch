# claude-autoresearch

Autonomous experiment loop plugin for Claude Code — try ideas, measure results, keep what works, discard what doesn't, repeat forever.

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) and [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch).

## What it does

You tell Claude what to optimize and how to measure it. Claude then runs an autonomous loop:

1. Edit code with an optimization idea
2. Run the benchmark
3. Run quality checks (tests, types, lint)
4. **If better** → git commit, keep the change
5. **If worse** → git revert, discard the change
6. Log the result
7. Repeat forever (until you stop it or max iterations hit)

Works for any optimization target: test speed, bundle size, algorithm performance, build times, API latency, Lighthouse scores.

## Install

```bash
# Add the marketplace (first time only)
/plugin marketplace add liljamesjohn/claude-autoresearch

# Install the plugin
/plugin install autoresearch
```

## Usage

### Start a new session

```
/autoresearch optimize FIFO lot matching speed
```

Claude will ask about the benchmark command, metric, files in scope, and quality gates — then start looping.

### Check progress

```
/autoresearch-status
```

### Resume after a restart

```
/autoresearch resume
```

### Stop the loop

```
/autoresearch off
```

Or just press `Ctrl+C` at any time.

### Full reset

```
/autoresearch clear
```

## How it works

### The loop

The experiment loop is prompt-driven, not code-driven. The skill prompt (`skills/autoresearch/SKILL.md`) teaches Claude the full protocol. Claude uses its built-in tools (Bash, Edit, Read, Write) to execute each iteration.

### Safety model

Everything happens on a **dedicated branch** (`autoresearch/<goal>-<date>`). Your main branch is never touched.

| Threat | Protection |
|--------|------------|
| Loop runs forever | Max iteration cap (default 50) + `Ctrl+C` |
| Bad experiment breaks code | Git revert on discard — last good commit restored |
| Context fills up | SessionStart hook re-injects `autoresearch.md` after compaction |
| Agent stops unexpectedly | Stop hook keeps the loop running |
| Session files lost on revert | Protected files are staged before git revert |

### Worktree support

For maximum safety, run in a git worktree:

```bash
# Terminal 1: keep working normally
claude

# Terminal 2: autoresearch runs in isolation
claude -w autoresearch-session
> /autoresearch optimize test speed
```

Two completely independent working directories, same repo. You can develop on main while autoresearch optimizes in the background.

### Files created in your project

| File | Purpose | Committed? |
|------|---------|------------|
| `autoresearch.md` | Living session document — objective, metrics, what's been tried | Yes |
| `autoresearch.sh` | Benchmark script | Yes |
| `autoresearch.checks.sh` | Optional quality gate script | Yes |
| `autoresearch.jsonl` | Append-only experiment log | Yes |
| `autoresearch.ideas.md` | Ideas backlog for deferred optimizations | Yes |
| `.claude/autoresearch-loop.local.md` | Stop hook state file (active/iteration/max) | No (local) |

## Plugin structure

```
claude-autoresearch/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace catalog
├── skills/
│   └── autoresearch/
│       └── SKILL.md             # /autoresearch skill — setup + loop prompt
├── commands/
│   └── autoresearch-status.md   # /autoresearch-status — results summary
├── lib/
│   └── lib.sh                   # Shared utilities (frontmatter parsing, hook input)
├── hooks/
│   ├── hooks.json               # Hook registrations (Stop, SessionStart, PreCompact)
│   └── scripts/
│       ├── stop-hook.sh         # Keeps the loop running (Ralph Wiggum pattern)
│       ├── session-start-compact.sh   # Re-injects context after compaction
│       ├── session-start-resume.sh    # Auto-resume on session start
│       ├── pre-compact.sh       # Preserves state before compaction
│       ├── revert-experiment.sh # Git revert with protected files
│       └── log-experiment.sh    # Structured JSONL experiment logger
├── tests/                       # Unit + E2E test suites
├── LICENSE
└── README.md
```

## Example domains

| Domain | Metric | Direction | Command |
|--------|--------|-----------|---------|
| Test speed | `test_ms` | lower | `bun run test` |
| Bundle size | `bundle_kb` | lower | `bun run build && du -sb dist` |
| Algorithm perf | `recalc_us` | lower | `bun run bench:fifo` |
| Build speed | `build_s` | lower | `bun run build` |
| Lighthouse | `perf_score` | higher | `lighthouse http://localhost:3000 --output=json` |
| API latency | `p95_ms` | lower | `wrk -t2 -c10 -d10s http://localhost:3000/api` |
| LLM training | `val_bpb` | lower | `uv run train.py` |

## Credits

- [Andrej Karpathy](https://github.com/karpathy/autoresearch) — the original autoresearch concept
- [davebcn87/pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) — the pi plugin that generalized it
- [Anthropic/ralph-wiggum](https://github.com/anthropics/claude-code) — the stop hook loop pattern

## License

MIT
