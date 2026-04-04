# Data Model: TRI-24 Feature Status Command

**Date**: 2026-04-04

## Entities

### Feature (in-memory, derived from filesystem)

| Field    | Type   | Source                                        |
|----------|--------|-----------------------------------------------|
| dir      | string | Directory name under `specs/`                 |
| id       | string | Parsed issue ID (e.g., `TRI-24`) or dir name  |
| name     | string | Slug after ID prefix (e.g., `feature-status`) |
| stage    | enum   | Derived from artifact detection               |
| progress | int    | Fixed mapping from stage (0-100)              |

### Workflow Stage (enum)

| Value     | Condition                                    | Progress |
|-----------|----------------------------------------------|----------|
| empty     | No recognized artifacts in directory         | 0        |
| specify   | `spec.md` exists                             | 25       |
| plan      | `plan.md` exists                             | 50       |
| tasks     | `tasks.md` exists, no checked items          | 75       |
| implement | `tasks.md` has some `- [x]` but not all     | 80       |
| done      | All `- [ ]` in `tasks.md` are `- [x]`       | 100      |

### Detection priority

Stage detection checks artifacts from highest to lowest stage. The highest detected stage wins:

1. Check `tasks.md` → count `- [x]` and `- [ ]`
   - All checked → `done`
   - Some checked → `implement`
   - None checked → `tasks`
2. Check `plan.md` exists → `plan`
3. Check `spec.md` exists → `specify`
4. None found → `empty`

## State Transitions

Features progress linearly through the workflow chain. The status command is read-only — it never modifies state.

```
empty → specify → plan → tasks → implement → done
```

## No persistence

This feature reads filesystem state on every invocation. No database, cache, or state file.
