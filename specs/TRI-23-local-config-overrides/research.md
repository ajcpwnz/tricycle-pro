# Research: Local Config Overrides

**Branch**: `TRI-23-local-config-overrides` | **Date**: 2026-03-31

## R1: Deep Merge Strategy for Flat Key-Value Config

**Decision**: Merge at the flat key-value level after `parse_yaml()`, not at the YAML AST level.

**Rationale**: The existing config system parses YAML into flat `KEY=VALUE` lines via `parse_yaml()` (in `bin/lib/yaml_parser.sh`). All config access goes through `cfg_get()` / `cfg_has()` / `cfg_count()` which grep against this flat format. Merging two flat key-value sets is trivial and doesn't require a new YAML library.

**Merge semantics**:
- Parse base config → flat lines
- Parse override config → flat lines
- For scalar keys: override value wins (last-writer-wins)
- For array keys (detected by numeric index pattern `prefix.N.` or `prefix.N=`): strip all base entries matching the prefix, replace with override entries
- Result: merged flat key-value string fed into `CONFIG_DATA`

**Alternatives considered**:
- YAML-level merge with `yq`: Would require `yq` as a dependency — rejected (no new dependencies for a bash CLI)
- Node.js deep merge: Would require a JS layer for config — rejected (config is loaded by bash scripts)
- Patch-based override (only support leaf scalars): Simpler but doesn't satisfy FR-010's array replacement requirement

## R2: Override File Name and Location

**Decision**: `tricycle.config.local.yml`, colocated with `tricycle.config.yml` in project root.

**Rationale**: Follows the established convention of `.local` suffix for local overrides (e.g., `.env.local`, `docker-compose.override.yml`). Same YAML format means zero learning curve (FR-002). Colocating makes the relationship to the base config obvious.

**Alternatives considered**:
- `tricycle.override.yml`: Less conventional naming
- `.tricycle.local.yml`: Hidden file — harder to discover
- `~/.tricycle/overrides.yml`: Global, not per-worktree — violates assumption that overrides are per-working-copy

## R3: Assembly Clash Prevention Strategy

**Decision**: Two-pass assembly with local overlay directory.

**Rationale**: The spec (FR-007) requires that committed assembly output is identical across developers. The assembly script (`core/scripts/bash/assemble-commands.sh`) already accepts `--config=FILE` — we can run it twice with different config files and output directories.

**Design**:
- **Pass 1** (base): `--config=tricycle.config.yml --output-dir=.claude/commands` → committed to VCS
- **Pass 2** (local): `--config=<merged-temp-file> --output-dir=.trc/local/commands` → gitignored
- Pass 2 only runs when `tricycle.config.local.yml` exists
- At runtime, Claude discovers commands from `.claude/commands/`. The session start hook detects local overlay commands in `.trc/local/commands/` and injects a context note telling Claude to prefer those versions when they exist.

**Alternatives considered**:
- Single-pass with merged config: Would cause VCS clashes — rejected
- Restrict overrides to non-assembly-affecting fields only: Simpler but too limiting — users want to enable/disable blocks locally (e.g., QA)
- Symlink replacement at session start: Git shows "typechange" — confusing

## R4: Overridable Field Classification

**Decision**: Whitelist approach — explicitly define which top-level config sections are overridable.

**Overridable sections** (safe for local override):
- `push.*` — push gates are enforced at runtime by scripts
- `qa.*` — QA enforcement is runtime + block-level (handled by two-pass)
- `worktree.*` — worktree behavior is per-developer
- `workflow.blocks.*.enable` / `workflow.blocks.*.disable` — block toggles (handled by two-pass)
- `stealth.*` — VCS exclusion is per-developer (careful: stealth mode in override doesn't trigger gitignore regeneration automatically)

**Non-overridable sections** (warn if present in override):
- `project.*` — project identity must be shared
- `apps.*` — app definitions must be shared (test commands, paths)
- `workflow.chain` — chain structure must be shared
- `branching.*` — branch naming must be shared
- `constitution.*` — constitution must be shared
- `mcp.*` — MCP config must be shared
- `context.*` — session context must be shared

**Rationale**: Whitelist is safer than blacklist — new config sections default to non-overridable. The overridable set aligns with the spec's distinction between "runtime-only" and "shared structure" fields.

## R5: VCS Exclusion Integration

**Decision**: Extend `cmd_generate_gitignore()` to include `tricycle.config.local.yml` and `.trc/local/` in both stealth and normal mode blocks.

**Rationale**: The existing function already manages VCS exclusion via marker blocks. Adding two patterns is minimal. The override file should ALWAYS be excluded regardless of stealth mode setting.

**Normal mode addition**:
```gitignore
# Tricycle local overrides
tricycle.config.local.yml
```

**Stealth mode**: Already covered — `tricycle.config.yml` pattern in stealth block could be extended to `tricycle.config*.yml`, or add explicit `tricycle.config.local.yml` line.

## R6: Error Handling for Override File

**Decision**: Graceful degradation — parse errors and permission issues produce warnings but fall back to base config only.

**Rationale**: FR-009 requires warnings + fallback. A broken override file should never prevent tricycle from functioning. The warning includes the file name and error context so the developer can fix it.

**Implementation**: Wrap the override parsing in a validation step:
1. Check file exists and is readable
2. Attempt `parse_yaml()` — if it fails (exit code), warn and skip
3. Validate all override keys against the overridable whitelist — warn on non-overridable keys, silently accept valid ones
