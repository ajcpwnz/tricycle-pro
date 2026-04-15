# Data Model: Fix /trc.specify worktree provisioning gap

**Feature**: TRI-26-worktree-provisioning
**Date**: 2026-04-15

This feature is a CLI/workflow fix — no runtime data model, no persistence, no entities in the traditional sense. The "data model" here is the shape of the config the script reads, the inputs the script accepts, and the post-condition it guarantees.

## 1. `ProvisioningConfig` (read from `tricycle.config.yml`)

Fields consumed by the new `parse_worktree_config` helper:

| Field | YAML Path | Type | Default (when unset) | Validation |
|---|---|---|---|---|
| `package_manager` | `project.package_manager` | string | `"npm"` | One of: `bun`, `npm`, `pnpm`, `yarn`. Unknown values still invoke `<value> install` but a warning is emitted. |
| `setup_script` | `worktree.setup_script` | string \| null | `null` (no-op) | If set, the path must resolve under the worktree root at execution time. Missing file = hard error. |
| `env_copy` | `worktree.env_copy` | string[] | `[]` (no-op) | Each entry is a path (relative to worktree root). Absolute paths are rejected. Globs are not expanded by the verifier (treated as literal). |
| `enabled` | `worktree.enabled` | bool | `false` | Only read to confirm block should run. Already handled by the existing block-enabled gate in commit `27ebf1f`. |

### Lifecycle

- Read **once** per `create-new-feature.sh --provision-worktree` invocation.
- Not cached across invocations.
- Not written back — the script never mutates `tricycle.config.yml`.

### State transitions

None. Config is read-only.

## 2. `ProvisioningInputs` (script arguments)

What `create-new-feature.sh --provision-worktree` needs, after the flag is parsed:

| Input | Source | Required | Notes |
|---|---|---|---|
| `WORKTREE_PATH` | Derived from `project.name` + `BRANCH_NAME` | yes | Absolute path; computed after the worktree is created. |
| `MAIN_TRC_SOURCE` | Absolute path to the `.trc/` dir in the main checkout | yes | Needed because `.trc/` is typically gitignored and must be copied into the worktree. |
| `ProvisioningConfig` | `parse_worktree_config` output | yes | Inlined above. |
| `BRANCH_NAME` | Output of the existing branch-creation logic | yes | Already computed earlier in the same script. |

## 3. `ProvisioningOutcome` (observable post-condition)

The successful execution of `--provision-worktree` guarantees the following state in the worktree directory:

1. **`.trc/` present**: directory exists at worktree root. Copy is idempotent — pre-existing `.trc/` is not overwritten.
2. **Dependencies installed**: `{package_manager} install` exited 0 inside `WORKTREE_PATH`. (We do not inspect `node_modules/` to confirm — we trust the install command's exit code.)
3. **Setup script ran (if configured)**: `$WORKTREE_PATH/$setup_script` was invoked with `cwd = WORKTREE_PATH` and exited 0. If `setup_script` is unset/null, this sub-step is a no-op.
4. **Every `env_copy` path exists**: for each `p` in `env_copy`, `[ -e "$WORKTREE_PATH/$p" ]` is true. If `env_copy` is empty/unset, this sub-step is a no-op.
5. **Spec scaffolding present**: `specs/<BRANCH_NAME>/spec.md` copied from template (existing responsibility, preserved).

### Failure modes (each produces a distinct error and non-zero exit)

| Exit code | Condition | Error message shape |
|---|---|---|
| 10 | `.trc/` copy failed (permission, disk full) | `Error: failed to copy .trc/ into worktree at $WORKTREE_PATH: <reason>` |
| 11 | Package-manager install exited non-zero | `Error: '$package_manager install' failed with exit $N in $WORKTREE_PATH` |
| 12 | `setup_script` path not found | `Error: worktree.setup_script '$path' does not exist in worktree root` |
| 13 | `setup_script` not executable | `Error: worktree.setup_script '$path' is not executable` |
| 14 | `setup_script` exited non-zero | `Error: worktree.setup_script '$path' exited $N` |
| 15 | One or more `env_copy` paths missing after setup | `Error: worktree.env_copy paths missing after setup:\n  - path1\n  - path2\n...` |

All errors are written to stderr. Exit codes are stable across versions (tests will assert against them).

## 4. Out of scope (explicit non-entities)

- **No cache** of parsed config. Each invocation re-reads.
- **No state file** tracking which worktrees have been provisioned. The file-system state is the source of truth.
- **No rollback** on partial failure. If install succeeds but setup_script fails, the worktree is left as-is; the error message names the failing step.
- **No cleanup hook.** Cleanup is the `implement:worktree-cleanup` block's responsibility, not this feature's.

## 5. Relationship to existing entities

- **Worktree** (git primitive): created by `git worktree add` earlier in the same script execution. This feature operates on the directory after creation.
- **`create-new-feature.sh` existing flags**: `--no-checkout`, `--json`, `--style`, `--issue`, `--prefix`, `--short-name`, `--number`. `--provision-worktree` coexists with all of them. It implies `--no-checkout` (see research.md Decision 4) but does not replace any existing flag.
- **`worktree-setup.md` optional block**: surfaces the three new config fields to `feature-setup.md`. The block itself does not run any commands — it documents the handoff. See [contracts/worktree-setup-handoff.md](./contracts/worktree-setup-handoff.md).
