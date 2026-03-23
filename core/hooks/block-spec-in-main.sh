#!/bin/bash
# PreToolUse hook: blocks Write/Edit to specs/*/spec.md in the main checkout
# Forces all spec work to happen in a git worktree

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Write and Edit
if [ "$TOOL" != "Write" ] && [ "$TOOL" != "Edit" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only care about spec.md files inside specs/
if ! echo "$FILE_PATH" | grep -qE '/specs/[^/]+/'; then
  exit 0
fi

# Derive the repo root from the file's directory, not from cwd
FILE_DIR=$(dirname "$FILE_PATH")
REPO_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# In a worktree, .git is a file pointing to the main repo's .git/worktrees/<name>
# In the main checkout, .git is a directory
if [ -d "$REPO_ROOT/.git" ]; then
  # .git is a directory = main checkout, BLOCK
  cat <<EOJSON
{"decision":"block","reason":"BLOCKED: You are writing spec files in the main checkout. You MUST create a git worktree first (see CLAUDE.md 'Feature Worktree Workflow'). Run: git worktree add -b <branch> ../polst-<branch> and cd into it before writing specs."}
EOJSON
  exit 0
fi

# .git is a file = we're in a worktree, allow
exit 0
