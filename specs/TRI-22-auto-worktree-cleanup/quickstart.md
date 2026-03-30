# Quickstart: Auto Worktree Cleanup

**Branch**: `TRI-22-auto-worktree-cleanup` | **Date**: 2026-03-31

## Enable Auto Cleanup

Add `worktree-cleanup` to your implement block enables:

```yaml
workflow:
  blocks:
    implement:
      enable:
        - worktree-cleanup
```

Then reassemble:

```bash
tricycle assemble
```

## What Happens

After `/trc.implement` merges the PR (via push-deploy block), the worktree-cleanup block automatically:

1. Switches working context to the main checkout
2. Runs `git worktree remove ../project-branch`
3. Runs `git worktree prune`
4. Runs `git branch -d branch-name`

If any step fails, it prints manual cleanup instructions as a fallback.

## No Action Needed

If you're not in a worktree (`.git` is a directory), the block skips silently.
