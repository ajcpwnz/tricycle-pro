# Research: Auto Worktree Cleanup

**Branch**: `TRI-22-auto-worktree-cleanup` | **Date**: 2026-03-31

## Decision 1: Rewrite block vs. call existing script

**Decision**: Rewrite the block instructions inline. Do not call `modules/worktree/scripts/cleanup-worktree.sh`.

**Rationale**: The block is prompt text that instructs the AI agent what to do — it's not executed as a shell script. The existing `cleanup-worktree.sh` handles database isolation and other module-specific concerns that aren't relevant here. The block just needs to tell the agent to run 3 git commands.

**Alternatives considered**:
- Call `cleanup-worktree.sh` from the block — blocks are prompt text, not shell scripts. The agent executes commands, not the block itself.

## Decision 2: Cleanup order

**Decision**: After confirmed merge: (1) determine main checkout path, (2) change working context to main, (3) remove worktree, (4) prune, (5) delete branch.

**Rationale**: You can't remove the worktree while you're inside it. Must change context to main checkout first.

## Decision 3: Detecting main checkout path

**Decision**: Parse the `.git` file in the worktree. It contains `gitdir: /path/to/main/.git/worktrees/<name>`. Walk up from there to find the main checkout root.

**Rationale**: More reliable than `git worktree list` parsing. The `.git` file always points back to the main repo.

**Alternative**: `git worktree list --porcelain` and find the entry without `worktree` in the path. Works but more complex parsing.
