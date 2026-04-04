# Research: TRI-24 Feature Status Command

**Date**: 2026-04-04
**Feature**: `tricycle status` CLI command

## Research Tasks

### 1. Stage detection from directory contents

**Decision**: Detect stage by checking artifact file existence in priority order (highest stage wins):
- `tasks.md` exists with all `- [x]` → `done`
- `tasks.md` exists with some `- [x]` → `implement`
- `tasks.md` exists (no checked items) → `tasks`
- `plan.md` exists → `plan`
- `spec.md` exists → `specify`
- No artifacts → `empty`

**Rationale**: File-existence checks are fast, reliable, and require no parsing beyond simple grep for task checkboxes. Matches the workflow chain order naturally.

**Alternatives considered**:
- Git branch status checking — rejected: branches may be deleted/merged while specs persist
- Reading metadata from a status file — rejected: adds write requirement to existing workflow steps

### 2. Directory name parsing for mixed naming conventions

**Decision**: Support both naming conventions found in `specs/`:
- `TRI-XX-slug` (issue-number style) → extract ID + name
- `NNN-slug` (ordered style) → use full dir name as display name, no separate ID
- Anything else → use full dir name

Parse by checking if directory name matches `^[A-Z]+-[0-9]+-` first, then `^[0-9]{3}-`.

**Rationale**: The existing `specs/` directory already contains both `001-headless-mode` and `TRI-19-session-context-hook` style names. Must handle both.

**Alternatives considered**:
- Reading `tricycle.config.yml` branching.style to determine parsing — rejected: would miss legacy dirs using old style

### 3. Progress bar rendering in Bash 3.2

**Decision**: Use Unicode block characters `█` and `░` for the progress bar. Fixed width of 12 characters. No terminal width detection needed — the bar is short enough to fit any reasonable terminal.

**Rationale**: 12 chars maps cleanly to the 5 stages (0%, 25%, 50%, 75%, 80%, 100%) — 3/6/9/10/12 filled blocks respectively. Bash 3.2 handles UTF-8 output fine via `printf`.

**Alternatives considered**:
- ASCII-only (`#` and `-`) — rejected: less visually appealing for demo
- Terminal-width-aware dynamic bars — rejected: over-engineering for a fixed set of stages

### 4. JSON output structure

**Decision**: Use the existing `json_builder.sh` helpers (`json_kv`, `json_kv_raw`, `json_escape`) to build JSON. Output structure:

```json
[
  {"id": "TRI-24", "name": "feature-status", "dir": "TRI-24-feature-status", "stage": "specify", "progress": 25},
  ...
]
```

**Rationale**: Reuses existing project utilities. Fields match the table columns plus `dir` for unambiguous identification.

**Alternatives considered**:
- Using `jq` — rejected: not guaranteed to be installed, adds external dependency
