---
name: worktree-setup
step: specify
description: Create a git worktree before spec work to isolate feature development
required: false
default_enabled: false
order: 5
companions: implement:worktree-cleanup
---

## Worktree Setup (Detection)

Before creating the feature branch, determine whether you need to work in a git worktree.

### Detection

Check the current working directory:
- If `.git` is a **file** (not a directory), you are already in a worktree. Set `WORKTREE_MODE=already` and proceed to the next block.
- If `.git` is a **directory**, you are in the main checkout. Set `WORKTREE_MODE=needed` — the feature-setup block will handle worktree creation after branch creation.

### Configuration

Read `tricycle.config.yml` for worktree settings:
- `project.name` — for substitution into the path pattern
- Default worktree path: `../{project}-{branch}` (where `{project}` is the project name and `{branch}` is the branch name from the script output)

Keep these values available for the feature-setup block.

### Notes

- This block only detects and configures. It does NOT create branches or worktrees.
- The feature-setup block (next) will use `WORKTREE_MODE` to decide whether to pass `--no-checkout` to `create-new-feature.sh` and whether to create the worktree after branch creation.
- The worktree isolates feature work from the main checkout, preventing accidental changes to main.
- If worktree creation fails later (e.g., branch already checked out elsewhere), report the error and suggest the user resolve the conflict manually.
