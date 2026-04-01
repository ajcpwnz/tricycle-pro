# Implementation Plan: Local Config Overrides

**Branch**: `TRI-23-local-config-overrides` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-23-local-config-overrides/spec.md`

**Version**: 0.11.1 → 0.12.0 (minor bump — new feature)

## Summary

Add an optional `tricycle.config.local.yml` file that deep-merges over the base config at runtime, giving developers per-worktree configuration overrides without modifying shared repository config. Assembly uses a two-pass strategy — base config for committed commands, merged config for a local overlay directory — ensuring identical committed output across developers regardless of local overrides.

## Technical Context

**Language/Version**: Bash (3.2+ compatible, macOS default) + Node.js (for tests)
**Primary Dependencies**: None new — uses existing `parse_yaml()`, `cfg_*()`, assembly script
**Storage**: Filesystem — YAML config files, flat key-value in memory
**Testing**: `bash tests/run-tests.sh` (bash harness) + `node --test tests/test-*.js` (Node.js)
**Target Platform**: macOS / Linux CLI
**Project Type**: CLI toolkit
**Constraints**: No new dependencies, bash 3.2 compatible, no `yq`/`jq` requirement

## Constitution Check

*Constitution is a placeholder — no gates defined. Pass by default.*

## Project Structure

### Documentation (this feature)

```text
specs/TRI-23-local-config-overrides/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/trc.tasks)
```

### Source Code (repository root)

```text
bin/
├── tricycle                # CLI — cmd_generate_gitignore() updated for override exclusion
└── lib/
    ├── helpers.sh          # load_config() + new merge logic, validation
    ├── yaml_parser.sh      # No changes (reused as-is for override parsing)
    └── assemble.sh         # cmd_assemble() updated for two-pass

core/
├── scripts/bash/
│   └── assemble-commands.sh  # No changes (already accepts --config flag)
└── hooks/
    └── session-context.sh    # Updated to detect and report active local overrides

tests/
├── test-local-config.js      # NEW — override loading, merge, validation, assembly
└── run-tests.sh              # Updated to include new test file
```

**Structure Decision**: Single-app CLI — all changes in existing `bin/lib/` modules with one new test file. No new directories except `.trc/local/commands/` (generated at runtime, gitignored).

## Design Decisions

### 1. Config Merge at Flat Key-Value Level

The existing config pipeline: YAML → `parse_yaml()` → flat KEY=VALUE lines → `CONFIG_DATA` → `cfg_get()`. Merging happens AFTER parsing both files into flat lines:

```bash
# Pseudocode for merge logic
base_data=$(parse_yaml "$base_config")
override_data=$(parse_yaml "$override_config")
# For each key in override_data, replace or add to base_data
# For arrays: strip all base entries matching prefix, use override entries
CONFIG_DATA=$(merge_config_data "$base_data" "$override_data")
```

This requires no YAML library and no changes to `parse_yaml()` or any `cfg_*()` accessor.

### 2. Two-Pass Assembly

`cmd_assemble()` in `bin/lib/assemble.sh` runs the assembly script. With overrides:

1. **Pass 1**: `--config=tricycle.config.yml --output-dir=.claude/commands` (always)
2. **Pass 2**: `--config=<temp-merged-file> --output-dir=.trc/local/commands` (only when override exists)

The assembly script already accepts `--config=FILE`, so pass 2 receives a temporary merged config file. To produce a valid YAML for the assembly script, a new `flat_to_yaml()` helper reconstructs YAML from merged flat key-value data.

### 3. Session Hook Integration

`core/hooks/session-context.sh` dynamically detects `tricycle.config.local.yml` at session start. When present, it appends a context note listing active overrides and the local commands directory path, so Claude knows to prefer local command variants.

### 4. Overridable Field Whitelist

Defined as a bash array in `helpers.sh`:

```bash
OVERRIDABLE_PREFIXES=(
  "push."
  "qa."
  "worktree."
  "workflow.blocks."
  "stealth."
)
```

Validation iterates override keys and warns on any key not matching a whitelisted prefix.

## Files Changed

| File | Change Type | Description |
|------|------------|-------------|
| `bin/lib/helpers.sh` | MODIFY | Add `merge_config_data()`, `validate_override()`, `load_config_with_override()`, overridable whitelist |
| `bin/lib/assemble.sh` | MODIFY | Add two-pass assembly: detect override → generate local overlay |
| `bin/tricycle` | MODIFY | Update `cmd_generate_gitignore()` to exclude override file and `.trc/local/` |
| `core/hooks/session-context.sh` | MODIFY | Detect active overrides → inject context note about local commands |
| `tests/test-local-config.js` | CREATE | Tests for merge, validation, assembly two-pass, VCS exclusion |
| `tests/run-tests.sh` | MODIFY | Add `test-local-config.js` to test suite |

## Complexity Tracking

No constitution violations to justify.
