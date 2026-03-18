#!/bin/bash
# Autoresearch Revert Script
# Reverts code changes from a failed/discarded experiment while preserving
# autoresearch session files (JSONL log, session doc, scripts, ideas).
#
# Worktree-safe: uses a temp directory instead of git stash (stash is shared
# across worktrees and would cause conflicts).
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

# Save protected files to a temp directory
BACKUP_DIR=$(mktemp -d)
SAVED=0
for f in "${PROTECTED_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp "$f" "${BACKUP_DIR}/$f"
    SAVED=$((SAVED + 1))
  fi
done

# Revert all changes
git checkout -- . 2>/dev/null || true
git clean -fd 2>/dev/null || true

# Restore protected files from backup
for f in "${PROTECTED_FILES[@]}"; do
  if [ -f "${BACKUP_DIR}/$f" ]; then
    cp "${BACKUP_DIR}/$f" "$f"
  fi
done

# Clean up
rm -rf "$BACKUP_DIR"

echo "Reverted to last good commit. ${SAVED} autoresearch files preserved."
