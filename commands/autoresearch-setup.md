---
description: Install the autoresearch statusline for live progress display
allowed-tools: Bash, Read, Write, Edit
---

Set up the autoresearch statusline to show live experiment progress in the Claude Code terminal.

The statusline shows: `autoresearch 5/50 | best: 42.3us (-85%) | last: keep | 12 runs 8 kept`

Steps:
1. Read `~/.claude/settings.json` to check if a `statusLine` is already configured
2. If one exists, warn the user: "You have an existing statusline configured. Installing the autoresearch statusline will replace it. The previous command was: `<their command>`. Proceed?"
3. If the user agrees (or no existing statusline), update `~/.claude/settings.json` to add:
   ```json
   "statusLine": {
     "type": "command",
     "command": "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"
   }
   ```
4. Tell the user: "Statusline installed. It will show autoresearch progress when a session is active, and be blank otherwise. Run `/autoresearch-setup` again to reinstall after plugin updates."

Important: Use `${CLAUDE_PLUGIN_ROOT}` in the command path — do NOT hardcode an absolute path. Claude Code resolves this variable at runtime.
