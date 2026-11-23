---
name: worktree-cleanup
step: implement
description: Automatically clean up worktree, prune references, and delete feature branch after a checked PR merge
required: false
default_enabled: false
order: 70
---

## Worktree Cleanup

After the push-deploy block checks that the PR is merged, automatically clean up the worktree.

**Prerequisites**: The PR MUST be merged, and checked, before this block executes. If the merge has not happened, skip this block entirely.

### Detection

Check if `.git` is a **file** (not a directory). If `.git` is a directory, you are in the main checkout — skip this block silently.

### Safety Check

Before cleanup, run `git status --porcelain` in the worktree. If there is any output (uncommitted changes), do NOT proceed with cleanup. Instead, warn the user:

```
Warning: Uncommitted changes detected in worktree. Skipping automatic cleanup.
```

Then fall back to printing the manual cleanup commands (see Fallback section below).

### Automatic Cleanup

Execute these steps in order. If any step fails, report the error and fall back to the manual reminder for remaining steps.

1. **Capture context before leaving the worktree**:
   - Worktree path: the current working directory
   - Branch name: `git rev-parse --abbrev-ref HEAD`
   - Main checkout path: run `git worktree list --porcelain`, take the first `worktree` line (this is always the main checkout)

2. **Switch working context** to the main checkout directory. All subsequent commands run from there. A worktree cannot delete itself.

   **Project cleanup script**: the project can have a worktree cleanup script, for example in `scripts/` or named in `qa/ai-agent-instructions.md`. If it has one, do step 3. Then run the script from the main checkout with the branch name, in place of steps 4 to 6. Such a script also deletes the resources of the worktree, for example its database and containers. Then go to step 7.

   **Worktree resources**: if there is no script and the worktree has its own resources (a database, containers), delete them before step 4.

3. **Fetch latest** to ensure the main branch is up to date:
   ```
   git fetch origin
   git pull origin <base-branch>
   ```
   Where `<base-branch>` is `push.pr_target` from `tricycle.config.yml` (default: `main`).

4. **Delete the worktree**:
   ```
   git worktree remove <worktree-path>
   ```

5. **Prune stale worktree references**:
   ```
   git worktree prune
   ```

6. **Delete the feature branch locally**:
   ```
   git branch -d <branch-name>
   ```

7. **Report success**:
   ```
   Worktree cleanup complete:
     ✓ Removed worktree: <worktree-path>
     ✓ Pruned stale references
     ✓ Deleted branch: <branch-name>
     ✓ Now on <base-branch> in <main-checkout-path>
   ```

### Fallback

If any cleanup step fails, print the error and then display manual instructions for any remaining steps:

```
Automatic cleanup encountered an error: <error message>

Manual cleanup commands:

  # Switch to main checkout
  cd <main-checkout-path>

  # Remove the worktree
  git worktree remove <worktree-path>

  # Prune stale worktree references
  git worktree prune

  # Delete the feature branch
  git branch -d <branch-name>
```

Do NOT halt the overall workflow on cleanup failure — cleanup is best-effort. The implementation is already complete and merged.
