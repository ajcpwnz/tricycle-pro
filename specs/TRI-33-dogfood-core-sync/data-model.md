# Data Model: Dogfood drift sync

**Feature**: TRI-33
**Date**: 2026-04-17

No durable state beyond what's already in `.tricycle.lock`. The feature is a transformation: read `core/<src>/...`, write `<dst>/...`, update lock entries.

## Entities

### Mapping pair

The unit of mirroring. A 2-tuple of source-path-under-repo-root and destination-path-under-repo-root. Declared once in `bin/tricycle` as the shared array `TRICYCLE_MANAGED_PATHS`. Consumed by both `cmd_update` (existing) and `cmd_dogfood` (new).

**Canonical value**:

```text
core/commands       → .claude/commands
core/templates      → .trc/templates
core/scripts/bash   → .trc/scripts/bash
core/hooks          → .claude/hooks
core/blocks         → .trc/blocks
```

Skills trees (`.claude/skills/`) are intentionally NOT mirrored (FR-007) — they have their own upstream-fetch discipline.

### Meta-repo detection

A repo is a "meta-repo" for this feature's purposes when `core/` exists as a directory at `$CWD` (the repo root from which `tricycle` is invoked). `cmd_dogfood` is a no-op in any repo where the check fails.

### Lock adoption

Each successful mirror of `<dst>` writes an entry into `.tricycle.lock` via `lock_set "<dst>" "<checksum>" "false"`. The `false` marks the file as not-locally-customized, so a subsequent `tricycle update` against the same `core/` does not SKIP the path.

## State transitions

None durable. One transient state transition per invocation:

- **dry-run (default)**: read → diff → print. No writes. Exit 0.
- **write (`--yes`)**: read → diff → print → overwrite → lock_set. Save lock. Exit 0.
- **skip (no `core/`)**: detect → print one-line skip reason → exit 0.
- **no drift**: read → diff (empty) → print "nothing to do" → exit 0.

## Config coupling

No new config keys. `tricycle.config.yml` is not read by `cmd_dogfood` — the feature operates on the filesystem mapping, not on configuration. Consumer repos remain entirely unaffected.
