# Contract: `worktree-setup` block → `feature-setup` block handoff

**Feature**: TRI-26-worktree-provisioning
**Artifact type**: Inter-block configuration handoff
**Stability**: These variable names and semantics are the interface between the two blocks. They must not change silently.

## Purpose

Today, `.trc/blocks/optional/specify/worktree-setup.md` surfaces two fields to the downstream `feature-setup.md` block:

- `WORKTREE_MODE` (`needed` | `already`)
- `project.name` (implicitly, via the default path pattern)

TRI-26 extends the handoff with three additional fields so that `feature-setup.md` has a single handoff point and does not re-parse `tricycle.config.yml` itself.

## New handoff surface

After TRI-26, the `worktree-setup` block's "Configuration" section declares the following variables as handed off to `feature-setup.md`:

| Variable | Source (YAML path) | Type | Default | Used by |
|---|---|---|---|---|
| `WORKTREE_MODE` | (detection of `.git` file vs directory) | `needed` \| `already` | — | `feature-setup.md` Step 2b gate |
| `PROJECT_NAME` | `project.name` | string | — | Worktree path construction |
| `PACKAGE_MANAGER` | `project.package_manager` | string | `"npm"` | `--provision-worktree` input |
| `WORKTREE_SETUP_SCRIPT` | `worktree.setup_script` | string \| null | `null` | `--provision-worktree` input |
| `WORKTREE_ENV_COPY` | `worktree.env_copy` | string[] | `[]` | `--provision-worktree` input |

**Important**: The block **narrates** these variables; the **actual parsing** is performed by `create-new-feature.sh --provision-worktree` when it reads `tricycle.config.yml` directly. This contract ensures the block and the script agree on names and semantics — not that the block parses anything itself.

## Why this indirection

Putting the parse in the script (not the block) solves two problems at once:

1. **No duplicate parse logic.** If we parsed YAML in the block's shell snippets, any later YAML-shape change would require updating both sites.
2. **No agent-skip risk on parsing.** The block is interpreted by an agent; a script is not. The agent can skip reading a YAML line; the script cannot.

## Updated block behavior

After TRI-26, `worktree-setup.md`'s Configuration section reads:

> Read `tricycle.config.yml` for:
> - `project.name` — for substitution into the worktree path
> - `project.package_manager` — passed to `--provision-worktree`
> - `worktree.setup_script` — passed to `--provision-worktree` (null if unset)
> - `worktree.env_copy` — passed to `--provision-worktree` (empty if unset)
>
> These fields are read by `create-new-feature.sh --provision-worktree` directly; the block lists them here for documentation and to guarantee the contract.

## Updated `feature-setup.md` Step 2b

The multi-step recipe collapses to a single invocation:

```bash
.trc/scripts/bash/create-new-feature.sh "$ARGUMENTS" \
    --json \
    --style <configured-style> \
    --short-name <slug> \
    [--issue <id> --prefix <prefix>] \
    --provision-worktree
```

After this call, the script has:
- Created the branch
- Created the worktree
- Copied `.trc/` into the worktree
- Installed dependencies
- Run `setup_script` (if set)
- Verified `env_copy` paths
- Created `specs/<BRANCH_NAME>/spec.md` from the template inside the worktree

The block then parses the JSON output (which now includes `WORKTREE_PATH`) and changes its working directory to `WORKTREE_PATH` for the remainder of the `/trc.specify` execution.

## What the block MUST NOT do after TRI-26

- Must NOT `cd` into the worktree and run `{package_manager} install` itself (the script does it).
- Must NOT re-parse `worktree.setup_script` or run it inline (the script does it).
- Must NOT verify `env_copy` paths (the script does it).
- Must NOT `mkdir -p specs/<BRANCH_NAME>` or copy the spec template inline (the script does it when `--provision-worktree` is set).

All of these steps are now **script-owned** to guarantee FR-012 (single invocation, not a multi-step recipe the agent can skip).

## Backward-compat guarantee

Projects that have `worktree.enabled: false` or that do not enable the `worktree-setup` optional block continue to hit the existing code path: the script runs without `--provision-worktree`, and `feature-setup.md` Step 2b's worktree-creation branch is skipped entirely. **No behavior change for those projects.**
