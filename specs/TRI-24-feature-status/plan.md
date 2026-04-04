# Implementation Plan: Tricycle Status Command

**Branch**: `TRI-24-feature-status` | **Date**: 2026-04-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-24-feature-status/spec.md`

## Summary

Add a `tricycle status` CLI subcommand that scans `specs/` directories and displays each feature's workflow progress as a formatted table with progress bars. Supports `--json` output and single-feature filtering. Pure Bash implementation using existing `json_builder.sh` and `helpers.sh` utilities.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default)
**Primary Dependencies**: None new — uses existing `json_builder.sh`, `helpers.sh`
**Storage**: Filesystem (read-only scan of `specs/` directories)
**Testing**: Shell integration tests (`run-tests.sh`) + Node.js unit tests (`node --test`)
**Target Platform**: macOS / Linux CLI
**Project Type**: CLI tool
**Performance Goals**: < 2 seconds for 20+ feature directories
**Constraints**: No external dependencies (no `jq`, no Python), Bash 3.2 compatible
**Scale/Scope**: Handles 0 to ~50 feature directories in `specs/`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is a placeholder — no gates to evaluate. Proceeding.

**Post-design re-check**: No violations. The feature is a read-only CLI subcommand with no new dependencies, no new abstractions beyond a single library file, and follows the existing patterns in `bin/lib/`.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-24-feature-status/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (created by /trc.tasks)
```

### Source Code (repository root)

```text
bin/
├── tricycle              # MODIFY: add status to dispatch + help
└── lib/
    ├── status.sh         # CREATE: scan, detect stage, format output
    ├── json_builder.sh   # EXISTING: reuse for --json
    └── helpers.sh        # EXISTING: reuse cfg_get for branching config

tests/
├── run-tests.sh          # MODIFY: add status integration tests
└── test-status.js        # CREATE: Node.js unit tests for stage detection
```

**Structure Decision**: Single new library file `bin/lib/status.sh` following the existing pattern of `bin/lib/*.sh` modules sourced by the main `bin/tricycle` entrypoint. No new directories needed.

## Phase 0: Research

See [research.md](research.md). All decisions resolved:
- Stage detection via file-existence checks (highest stage wins)
- Directory name parsing supports both `TRI-XX-slug` and `NNN-slug` conventions
- Progress bar: 12-char Unicode blocks, fixed width
- JSON output via existing `json_builder.sh` helpers

## Phase 1: Design & Contracts

### Data Model

See [data-model.md](data-model.md). Key entity: Feature (dir, id, name, stage, progress). Stage enum with fixed progress mapping per clarification.

### Interface Contract

**CLI interface**:

```
tricycle status [<filter>] [--json]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<filter>` | No | Feature ID (e.g., `TRI-24`) or directory name to filter to one feature |
| `--json` | No | Output JSON array instead of formatted table |

**Exit codes**:
- `0` — success (including empty specs/)
- `1` — error (e.g., not in a tricycle project)

**Table output format**:

```
  TRI-23  local-config-overrides  ████████████ done
  TRI-22  auto-worktree-cleanup   ████████████ done
  TRI-24  feature-status          ██████░░░░░░ tasks
```

**JSON output format**:

```json
[
  {"id": "TRI-24", "name": "feature-status", "dir": "TRI-24-feature-status", "stage": "specify", "progress": 25}
]
```

### Implementation Details

**`bin/lib/status.sh`** exports these functions:

- `status_detect_stage DIR_PATH` — returns stage string for a specs/ subdirectory
- `status_parse_dir_name DIR_NAME` — sets `STATUS_ID` and `STATUS_NAME` variables
- `status_progress_for_stage STAGE` — returns integer progress percentage
- `status_render_bar PROGRESS` — returns 12-char Unicode progress bar string
- `status_scan [FILTER]` — main entry, scans specs/, prints table or JSON

**`bin/tricycle`** changes:

- Add `status` case to the dispatch `case` statement
- Add `--json` flag parsing (only for status command)
- Add `status` line to `show_help()`
- Source `status.sh` in the library loading section

### Version

Current: `0.12.0`. This is a new feature → minor bump to `0.13.0` at implementation.

## Quickstart

See [quickstart.md](quickstart.md).
