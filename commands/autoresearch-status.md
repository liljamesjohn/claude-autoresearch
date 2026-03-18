---
description: Show autoresearch experiment results summary
allowed-tools: Bash, Read
---

Parse `autoresearch.jsonl` in the current directory and display a summary of experiment results.

Show:
- Session name and metric info (from the config line)
- Total runs, kept, discarded, crashed counts
- Baseline metric value and run number
- Best metric value, run number, and improvement percentage vs baseline
- Table of the last 15 experiments with: run number, status, metric value, delta vs baseline %, and description

If `autoresearch.jsonl` does not exist, say "No autoresearch session found in this directory."

If `autoresearch.md` exists, also show the current objective from it.

Format the output as a clean markdown table.
