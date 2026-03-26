---
name: worktree-setup
step: specify
description: Create a git worktree before spec work to isolate feature development
required: false
default_enabled: false
order: 5
companions: implement:worktree-cleanup
---

## Worktree Setup

Before creating the feature branch or writing any spec files, ensure you are working in a git worktree — not the main checkout.

### Detection

Check if the current working directory is already a worktree:
- If `.git` is a **file** (not a directory), you are in a worktree — proceed to the next block.
- If `.git` is a **directory**, you are in the main checkout — you MUST create a worktree first.

### Creating the Worktree

1. Read `tricycle.config.yml` for the worktree path pattern (default: `../{project}-{branch}`).

2. You do NOT have the branch name yet (that comes from `feature-setup`). Instead:
   - Generate the short branch name first (same logic as feature-setup: 2-4 word name from the feature description).
   - Run `create-new-feature.sh` to get the branch name and number.
   - Then create the worktree:
     ```bash
     git checkout main  # ensure main is checked out in primary
     git worktree add ../{project}-{branch} {branch}
     ```

3. After creating the worktree, **all subsequent work must happen in the worktree directory**. Use absolute paths to the worktree for all file operations.

4. If `.trc/` does not exist in the worktree (it's gitignored), copy it from the main checkout:
   ```bash
   cp -r /path/to/main/.specify /path/to/worktree/.specify
   ```

### Notes

- The worktree isolates feature work from the main checkout, preventing accidental changes to main.
- This block replaces the `block-spec-in-main.sh` and `block-branch-in-main.sh` enforcement hooks with proactive worktree creation.
- If worktree creation fails (e.g., branch already checked out), report the error and suggest the user resolve the conflict manually.
