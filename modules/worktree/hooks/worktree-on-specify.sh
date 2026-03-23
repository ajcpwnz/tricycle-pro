#!/bin/bash
# PreToolUse hook: blocks trc.specify until Claude is inside a worktree.
# Creates the worktree if needed and tells Claude to cd into it before re-invoking.

INPUT=$(cat)

# Only act on trc.specify
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
if [ "$SKILL" != "trc.specify" ]; then
  exit 0
fi

# Check if we're already in a worktree (.git is a file, not a directory)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.git" ]; then
  # Already in a worktree — allow the skill to proceed
  exit 0
fi

ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // empty')
if [ -z "$ARGS" ]; then
  # No args — allow through (specify will prompt for feature description)
  exit 0
fi

# Slugify args for branch/dir name
SLUG=$(echo "$ARGS" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g' | sed 's/^-//;s/-$//' | cut -c1-50)
WORKTREE_PATH="../polst-${SLUG}"
BRANCH="${SLUG}"

# If worktree already exists, block and tell Claude to cd into it
if [ -d "$WORKTREE_PATH" ]; then
  cat <<EOJSON
{"decision":"block","reason":"BLOCKED: You are not in a worktree. A worktree already exists at ${WORKTREE_PATH} on branch ${BRANCH}. You MUST:\n1. cd into ${WORKTREE_PATH}\n2. Run: bun install (if not already done)\n3. Run: cd apps/backend && ./scripts/worktree-db-setup.sh (if not already done)\n4. Then re-invoke trc.specify from inside the worktree."}
EOJSON
  exit 0
fi

# Create the worktree
OUTPUT=$(git worktree add -b "$BRANCH" "$WORKTREE_PATH" origin/staging 2>&1)

if [ $? -eq 0 ]; then
  cat <<EOJSON
{"decision":"block","reason":"BLOCKED: Worktree created at ${WORKTREE_PATH} on branch ${BRANCH}. You MUST complete setup before running trc.specify:\n1. cd into ${WORKTREE_PATH}\n2. Run: bun install\n3. Run: cd apps/backend && ./scripts/worktree-db-setup.sh\n4. Then re-invoke trc.specify from inside the worktree."}
EOJSON
else
  cat <<EOJSON
{"decision":"block","reason":"BLOCKED: Git worktree creation failed: ${OUTPUT}. Fix the issue, create the worktree manually, cd into it, and then re-invoke trc.specify."}
EOJSON
fi
