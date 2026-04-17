# Data Model: One-way drift check

**Feature**: TRI-34
**Date**: 2026-04-17

Stateless. No files on disk, no config keys, no durable state. Only a transient walk over `core/<src>` + per-file primitive comparison.

## Entities

### Source file

Every regular file under `core/<src>` for each mapping pair in `TRICYCLE_MANAGED_PATHS` (hardcoded in the test per R3). For each source file `<src-dir>/<rel-path>`, the expected destination is `<dst-dir>/<rel-path>`.

**Attributes (per file)**:

- `src-absolute-path` — `$REPO_ROOT/<src-dir>/<rel-path>`.
- `dst-absolute-path` — `$REPO_ROOT/<dst-dir>/<rel-path>`.
- `state` — one of:
  - **match** — `dst-absolute-path` exists and `cmp -s` reports identity with `src-absolute-path`.
  - **missing** — `dst-absolute-path` does not exist.
  - **differ** — `dst-absolute-path` exists but `cmp -s` reports a byte difference.

### Mapping pair (inherited from v0.20.1)

Same five pairs as `TRICYCLE_MANAGED_PATHS`:

```text
core/commands       → .claude/commands
core/templates      → .trc/templates
core/scripts/bash   → .trc/scripts/bash
core/hooks          → .claude/hooks
core/blocks         → .trc/blocks
```

Hardcoded in `tests/test-dogfood-drift.sh` for scope containment (R3).

### Failure output (transient)

Collected during the walk, printed only if non-empty.

**Fields**:

- `drifted-paths` — list of destination paths in state `missing` or `differ`.
- `details` — a concatenation of `--- diff <src> vs <dst> ---` header + `diff` output per drifted file, preserving v0.20.1's actionable shape (R6).

## State transitions

None durable. One invocation runs once, produces exit 0 or 1.

- **no `core/`** → skip → exit 0.
- **every source file matches** → exit 0, print `dogfood-drift: OK`.
- **any source file missing or differs** → exit 1, print drifted paths + details.

## Extras in destination (out of scope)

Files under `<dst>` that have no `core/<src>/<rel-path>` counterpart are **not walked, not flagged, not cleaned**. This is the core behavior change from v0.20.1. The rationale lives in `spec.md` (runtime-generated files are legitimate; orphan cleanup is a separate concern).
