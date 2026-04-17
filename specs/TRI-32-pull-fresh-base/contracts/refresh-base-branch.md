# Contract: `refresh_base_branch` function (in `create-new-feature.sh`)

**Status**: New function inside `core/scripts/bash/create-new-feature.sh`. Invoked from the script's main flow, once per `create-new-feature.sh` call, before branch creation.

## Signature

```bash
refresh_base_branch <repo_root> <base_branch_name>
```

- `<repo_root>` — absolute path to the main checkout (already set as `REPO_ROOT` by the time this runs).
- `<base_branch_name>` — the configured base branch. Derived from `tricycle.config.yml`'s `push.pr_target`, default `main`.

## Behavior

1. **Opt-out check**: if `TRC_SKIP_BASE_REFRESH=1` is set OR the `--no-base-refresh` flag was passed to the outer script (surfaced as `SKIP_BASE_REFRESH=true`), return 0 silently.

2. **Git presence check**: if `HAS_GIT` is not `true`, return 0 silently.

3. **Remote reachability probe**: attempt `git fetch --dry-run origin <base>` with a short timeout (5–10 s). On failure whose stderr matches any of: `Could not resolve host`, `Connection refused`, `Operation timed out`, `unable to access`, `Authentication failed`, `Network is unreachable`:
   - Print a one-line warning on stderr: `[specify] Warning: origin unreachable; skipping base-branch refresh. New branch will be cut from local <base>.`
   - Return 0.

4. **Branch the dispatch on current HEAD**:

   - If `git rev-parse --abbrev-ref HEAD` equals `<base_branch_name>`:
     - **Dirty-tree guard**: run `git diff-index --quiet HEAD --` AND `git diff-files --quiet`. Either non-zero → halt (exit 20) with:
       ```
       Error: Working tree on <base> has uncommitted changes. Commit, stash, or discard them and retry.
       Dirty paths:
         <path 1>
         <path 2>
         ...
       ```
     - Run `git pull --ff-only origin <base>`. On non-zero exit → halt (exit 21) with the captured stderr prefixed by:
       ```
       Error: local <base> cannot fast-forward from origin/<base> (diverged or non-FF). Resolve manually and retry.
       ```
   - Else (current HEAD ≠ `<base>`):
     - Run `git fetch origin <base>:<base>`. On non-zero exit → halt (exit 21) with the same diverged/non-FF error.

5. **Success output**: if the refresh advanced local `<base>` (i.e. its tip SHA changed), print one line on stderr: `[specify] Base branch <base> fast-forwarded to <new-short-sha>`. Otherwise silent.

## Exit codes

- `0` — refreshed, already up to date, or skipped (any reason).
- `20` — halt: dirty working tree on base branch.
- `21` — halt: divergent history or non-fast-forward.

Both halt paths cause `create-new-feature.sh` to exit with the same code (error propagation), so callers can distinguish the two conditions.

## Side effects

- One `git fetch --dry-run origin <base>` (reachability probe).
- Either one `git pull --ff-only origin <base>` (if on base) or one `git fetch origin <base>:<base>` (otherwise).
- No `git switch`, no `git stash`, no `git reset`, no `git push`.
- No file-system writes outside of what git itself does to update refs.

---

# Contract change: `create-new-feature.sh` CLI surface

**Status**: Additive — existing flags and JSON shape unchanged.

## New flag

- `--no-base-refresh` — when passed, skip the base-branch refresh step entirely. Equivalent to setting `TRC_SKIP_BASE_REFRESH=1` in the environment. Documented in `--help` output.

## Backwards compatibility

- Default behavior adds the refresh step. Existing callers that do NOT pass `--no-base-refresh` and have a reachable origin will see local `<base>` fast-forwarded as part of any kickoff. This is a deliberate, documented behavior change. Opt-out is available per FR-011.
- Existing flags (`--json`, `--short-name`, `--number`, `--style`, `--issue`, `--prefix`, `--no-checkout`, `--provision-worktree`) behave identically.
- Exit codes 20 and 21 are new. Existing exit codes (0, 1, 2, 10–15) retain their meanings.

## `push.pr_target` lookup

- Minimal awk parse consistent with `read_project_name` already in the file. If `tricycle.config.yml` is absent, or `push.pr_target` is unset, default to `main`.
