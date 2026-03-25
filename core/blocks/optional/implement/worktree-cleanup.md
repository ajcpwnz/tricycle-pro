---
name: worktree-cleanup
step: implement
description: Suggest worktree cleanup after implementation is complete and PR is merged
required: false
default_enabled: false
order: 70
---

## Worktree Cleanup Reminder

After implementation is complete, lint/tests pass, and the user has approved the push:

**Do NOT clean up automatically.** Per the artifact cleanup rules, worktrees and spec artifacts MUST NOT be cleaned up until the PR is merged.

Instead, after the push is approved and PR is created, remind the user:

```
Worktree cleanup available after PR merge:

  # Remove the worktree
  git worktree remove ../[worktree-path]

  # Prune stale worktree references
  git worktree prune

  # Optionally delete the feature branch (after merge)
  git branch -d [branch-name]
```

Only display this reminder if the current working directory is a worktree (`.git` is a file, not a directory). If already in the main checkout, skip this block silently.
