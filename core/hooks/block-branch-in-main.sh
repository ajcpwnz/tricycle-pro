#!/bin/bash
# PreToolUse hook: blocks creating new branches in the main checkout
# Forces all new feature work to use git worktrees instead

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Bash commands
if [ "$TOOL" != "Bash" ]; then
  exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Check if command creates a new branch (checkout -b, switch -c, branch <name>)
if ! echo "$CMD" | grep -qE 'git (checkout -b|switch -c|branch )'; then
  exit 0
fi

# Allow if it's a worktree add command (git worktree add -b ...)
if echo "$CMD" | grep -q 'worktree'; then
  exit 0
fi

# Check if we're in the main checkout (.git is a directory)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

if [ -d "$REPO_ROOT/.git" ]; then
  # Main checkout — block branch creation
  cat <<EOJSON
{"decision":"block","reason":"BLOCKED: Do not create feature branches in the main checkout. You MUST use a git worktree instead (CLAUDE.md 'Feature Worktree Workflow' — NONNEGOTIABLE). Run: git worktree add -b <branch-name> ../polst-<branch-name> origin/staging — then cd into it and run bun install + worktree-db-setup.sh. Only skip if the user explicitly said to work on the current branch."}
EOJSON
  exit 0
fi

# In a worktree — allow
exit 0
