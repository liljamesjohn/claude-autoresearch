#!/bin/bash
# Autoresearch Revert Script
# Reverts code changes from a failed/discarded experiment while preserving
# autoresearch session files (JSONL log, session doc, scripts, ideas).
#
# Usage: revert-experiment.sh [working_dir]

set -euo pipefail

WORKDIR="${1:-.}"
cd "$WORKDIR"

# Files that must survive the revert
PROTECTED_FILES=(
  "autoresearch.jsonl"
  "autoresearch.md"
  "autoresearch.ideas.md"
  "autoresearch.sh"
  "autoresearch.checks.sh"
)

# Stage protected files so they survive the revert
for f in "${PROTECTED_FILES[@]}"; do
  if [ -f "$f" ]; then
    git add "$f" 2>/dev/null || true
  fi
done

# Stash the staged protected files
if git diff --cached --quiet 2>/dev/null; then
  # Nothing staged — just revert directly
  git checkout -- . 2>/dev/null || true
  git clean -fd 2>/dev/null || true
else
  # Stash protected files, revert everything, restore protected files
  git stash push --staged -m "autoresearch-protected" 2>/dev/null || true
  git checkout -- . 2>/dev/null || true
  git clean -fd 2>/dev/null || true
  git stash pop 2>/dev/null || true
fi

echo "Reverted to last good commit. Autoresearch files preserved."
