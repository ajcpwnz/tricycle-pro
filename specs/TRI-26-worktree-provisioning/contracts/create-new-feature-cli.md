# Contract: `create-new-feature.sh --provision-worktree`

**Feature**: TRI-26-worktree-provisioning
**Artifact type**: CLI flag contract
**Stability**: This is the user-facing surface added by this feature. Exit codes and error-message prefixes are stable after merge.

## Synopsis

```text
create-new-feature.sh <feature description> \
    [--json] \
    --style (feature-name|issue-number|ordered) \
    [--short-name <slug>] \
    [--issue <id>] \
    [--prefix <prefix>] \
    [--number <n>] \
    [--no-checkout] \
    [--provision-worktree]
```

`--provision-worktree` is the new flag introduced by TRI-26.

## Semantics

When `--provision-worktree` is passed:

1. The script creates the branch (existing behavior).
2. The script implies `--no-checkout` automatically. Passing `--no-checkout` explicitly is redundant but not an error.
3. The script creates the worktree at `../{project.name}-{BRANCH_NAME}` (existing behavior via the block — with this flag, the *script* performs the `git worktree add` itself so the whole chain is script-owned).
4. The script copies `.trc/` from the main checkout into the worktree (idempotent: if the target `.trc/` already exists, this is a no-op).
5. The script parses `tricycle.config.yml` for:
   - `project.package_manager` (default `npm`)
   - `worktree.setup_script` (default unset → no-op)
   - `worktree.env_copy` (default empty → no-op)
6. The script runs `{package_manager} install` with `cwd = <worktree>`. Exit non-zero aborts with exit code **11**.
7. If `setup_script` is set, the script invokes it with `cwd = <worktree>`. Preflight checks (exists, executable) run before invocation.
8. The script verifies every `env_copy[i]` exists under the worktree root. Collects every miss; exits **15** if any are missing.
9. The script creates `specs/<BRANCH_NAME>/` inside the worktree and copies `spec-template.md` (this replaces the responsibility previously handled by `feature-setup.md` Step 2b).
10. On success, the script prints the existing JSON payload (`BRANCH_NAME`, `SPEC_FILE`, `FEATURE_NUM`) plus a new key `WORKTREE_PATH` when `--json` is set.

## Preconditions

- `git` is available (existing precondition).
- The main checkout is NOT currently on the branch about to be created (existing precondition).
- `tricycle.config.yml` exists at the repo root. (If absent, the script falls back to defaults and issues a warning — does not hard-fail.)
- The package manager binary named by `project.package_manager` is on `PATH`. Missing binary → exit **11** with the reason clearly stated.

## JSON Output (when `--json` is set)

**Before this feature**:
```json
{"BRANCH_NAME":"TRI-26-foo","SPEC_FILE":"/.../spec.md","FEATURE_NUM":"TRI-26"}
```

**After this feature, when `--provision-worktree` is used**:
```json
{"BRANCH_NAME":"TRI-26-foo","SPEC_FILE":"/.../spec.md","FEATURE_NUM":"TRI-26","WORKTREE_PATH":"/abs/path/to/worktree"}
```

The `SPEC_FILE` path is **absolute** and resolves to the worktree when `--provision-worktree` is active (previously it resolved to the main checkout).

Backwards compatibility: existing callers that parse only `BRANCH_NAME` / `SPEC_FILE` / `FEATURE_NUM` continue to work — the new `WORKTREE_PATH` key is additive.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic error (existing — bad args, branch already exists, etc.) |
| 2 | Missing required flag value (existing) |
| 10 | `.trc/` copy into worktree failed |
| 11 | `{package_manager} install` exited non-zero |
| 12 | `setup_script` path does not exist |
| 13 | `setup_script` is not executable |
| 14 | `setup_script` exited non-zero |
| 15 | One or more `env_copy` paths missing after setup |

Codes 10–15 are **new** and reserved for the provisioning pipeline. They must not overlap with existing exits.

## Error Message Format

All provisioning errors are written to stderr with the prefix `Error: ` and end with a newline. When listing multiple missing `env_copy` paths, each path appears on its own indented line:

```text
Error: worktree.env_copy paths missing after setup:
  - .env.local
  - apps/backend/.env
```

This format is asserted by `tests/test-worktree-provisioning.js`.

## Interaction with Existing Flags

| Combination | Behavior |
|---|---|
| `--provision-worktree` alone | Implies `--no-checkout`; full provisioning pipeline runs. |
| `--provision-worktree --no-checkout` | Equivalent to `--provision-worktree`; no error. |
| `--provision-worktree --style feature-name` | Works; branch name is the slug. |
| `--provision-worktree --style issue-number --issue TRI-26` | Works; branch name is `TRI-26-<slug>`. |
| `--provision-worktree --style ordered` | Works; branch name is `NNN-<slug>`. |
| No `--provision-worktree` | Unchanged from current behavior. Regression test `test-create-new-feature-unchanged` guards this. |

## Test Hooks

`tests/test-worktree-provisioning.js` must cover:

1. Happy path: all four sub-steps succeed, exit 0, JSON contains `WORKTREE_PATH`.
2. `package_manager` unset → defaults to `npm`.
3. `setup_script` unset → sub-step is a no-op; no error.
4. `env_copy` empty → verification sub-step is a no-op.
5. Install fails → exit 11.
6. `setup_script` path missing → exit 12.
7. `setup_script` not executable → exit 13.
8. `setup_script` exits non-zero → exit 14.
9. Exactly one `env_copy` path missing → exit 15, error message lists the one path.
10. Multiple `env_copy` paths missing → exit 15, error message lists all of them.
11. Backward-compat: `create-new-feature.sh` without `--provision-worktree` behaves exactly as before (snapshot test against existing fixtures).
