#!/bin/bash
# Autoresearch Revert Script
# Reverts code changes from a failed/discarded experiment while preserving
# autoresearch session files and user's local config files.
#
# Safety:
#   - Worktree-safe: uses temp dir instead of git stash (stash is shared across worktrees)
#   - User-file-safe: git clean excludes .env*, *.local, IDE configs
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

# Step 1: Revert all tracked file modifications
git restore . 2>/dev/null || git checkout -- . 2>/dev/null || true

# Step 2: Remove untracked files created by the experiment, but protect
# user's local config files, IDE settings, and OS artifacts
git clean -fd \
  -e ".env*" \
  -e "*.local" \
  -e ".idea" \
  -e ".vscode" \
  -e ".fleet" \
  -e "*.sublime-*" \
  -e ".DS_Store" \
  2>/dev/null || true

# Restore protected files from backup
for f in "${PROTECTED_FILES[@]}"; do
  if [ -f "${BACKUP_DIR}/$f" ]; then
    cp "${BACKUP_DIR}/$f" "$f"
  fi
done

# Clean up
rm -rf "$BACKUP_DIR"

echo "Reverted to last good commit. ${SAVED} autoresearch files preserved."
