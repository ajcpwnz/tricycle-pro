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
- `project.package_manager` — passed through to `create-new-feature.sh --provision-worktree` (defaults to `npm` when unset)
- `worktree.setup_script` — passed through to `create-new-feature.sh --provision-worktree` (no-op when unset)
- `worktree.env_copy` — passed through to `create-new-feature.sh --provision-worktree` (no-op when empty)
- Default worktree path: `../{project}-{branch}` (where `{project}` is the project name and `{branch}` is the branch name from the script output)

The three pass-through fields above are **read by `create-new-feature.sh` directly**, not by this block. Listing them here documents the contract: when the feature-setup block calls the script with `--provision-worktree`, every one of those fields flows into a single atomic provisioning step (dependency install → setup script → env-copy verification). The block MUST NOT re-parse these fields or re-run any of those steps inline.

Keep `project.name` available for the feature-setup block.

### Notes

- This block only detects and configures. It does NOT create branches or worktrees.
- The feature-setup block (next) will use `WORKTREE_MODE` to decide whether to pass `--provision-worktree` to `create-new-feature.sh`. That single flag owns branch creation, worktree creation, `.trc/` copy, dependency install, setup-script execution, env-copy verification, and spec directory/template creation.
- The worktree isolates feature work from the main checkout, preventing accidental changes to main.
- If worktree creation or any provisioning sub-step fails, the script exits with a reserved non-zero code (10–15). Surface the error verbatim and let the user resolve it manually — do NOT retry or paper over the failure.
