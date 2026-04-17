# Data Model: Pull fresh base branch on kickoff

**Feature**: TRI-32
**Date**: 2026-04-17

Stateless. No files on disk, no database, no new config keys beyond reading existing `push.pr_target`.

## Entities

### Kickoff invocation

The call to `create-new-feature.sh` that triggers a refresh attempt. Not stored.

**Inputs read during refresh**:

- `push.pr_target` (string) — parsed from `tricycle.config.yml`. Default `main` when absent.
- `$TRC_SKIP_BASE_REFRESH` (env var) — `1` means skip the refresh silently.
- `--no-base-refresh` (flag) — same effect as the env var.
- Local git state: current `HEAD` branch, working-tree cleanliness.
- Remote state: whether `origin` is reachable, whether `origin/<base>` exists, whether a fast-forward is possible.

### Refresh outcome (transient, logged)

One of:

- **`refreshed`** — local `<base>` was fast-forwarded; printing a single info line `[specify] Base branch <base> fast-forwarded to <new-sha>` on stderr.
- **`already-up-to-date`** — local `<base>` tip already equals `origin/<base>`. No output (silent no-op).
- **`skipped-opt-out`** — `TRC_SKIP_BASE_REFRESH` or `--no-base-refresh` was set. No output.
- **`skipped-not-git`** — `HAS_GIT=false`. No output.
- **`skipped-offline`** — fetch failed with a network-class signature; warn on stderr, proceed from local state.
- **`halt-dirty`** — base is the current branch and working tree is dirty. Halt with error listing offending paths.
- **`halt-divergent`** — local `<base>` has commits not on `origin/<base>` or cannot fast-forward. Halt with error.

## State transitions

None durable. The refresh is idempotent: running it twice back-to-back against an up-to-date base produces `already-up-to-date` both times.

## Config coupling

- Reads `push.pr_target` from `tricycle.config.yml` (already read by other script blocks in this repo). No new keys.
- The `push.pr_target` lookup is minimal and single-purpose (awk-based parse), consistent with the existing `read_project_name` pattern in `create-new-feature.sh`.
