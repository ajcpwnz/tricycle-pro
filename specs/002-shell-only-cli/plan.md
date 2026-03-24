# Implementation Plan: Shell-Only CLI

**Branch**: `002-shell-only-cli` | **Date**: 2026-03-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-shell-only-cli/spec.md`

## Summary

Rewrite the Tricycle Pro CLI from a Node.js script (`bin/tricycle.js` + `package.json` + `yaml` dependency) to a pure bash implementation (`bin/tricycle` + sourced library scripts). The shell CLI must be a drop-in replacement producing identical output files, with zero external dependencies beyond bash 3.2+ and standard Unix utilities. Additionally, provide a bootstrapper script for one-off execution and system installation without any package manager.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default), 4.0+ (Linux)
**Primary Dependencies**: None — standard Unix utilities only (`sed`, `awk`, `grep`, `find`, `chmod`, `mkdir`, `cat`, `shasum`/`sha256sum`)
**Storage**: File-based (YAML config input, JSON output, template files)
**Testing**: Plain shell test scripts using `test`/`[` assertions, no framework
**Target Platform**: macOS (bash 3.2+), Linux (bash 4.0+)
**Project Type**: CLI scaffolding tool
**Performance Goals**: N/A — one-shot CLI, not a server
**Constraints**: Bash 3.2 compatibility (no associative arrays, no `mapfile`); no external dependencies
**Scale/Scope**: ~600 lines of Node.js → estimated ~800-1000 lines of bash across 5 files

## Constitution Check

*No constitution file exists. Gate passes by default — no principles to violate.*

## Project Structure

### Documentation (this feature)

```text
specs/002-shell-only-cli/
├── plan.md              # This file
├── research.md          # Phase 0 output — technology decisions
├── data-model.md        # Phase 1 output — parsed config shape, lock file schema
├── quickstart.md        # Phase 1 output — dev setup guide
├── contracts/
│   └── cli-interface.md # Phase 1 output — command interface contract
└── tasks.md             # Phase 2 output (/trc.tasks command)
```

### Source Code (repository root)

```text
bin/
├── tricycle              # Main entry point (bash, replaces tricycle.js)
└── lib/
    ├── yaml_parser.sh    # YAML subset parser → flat KEY=VALUE pairs
    ├── json_builder.sh   # JSON generation helpers (printf-based)
    ├── template_engine.sh # {{var}}, {{#each}}, {{#if}} processor
    └── helpers.sh        # Shared utilities: checksum, file ops, prompts

install.sh                # Bootstrapper: one-off execution + system install

tests/
└── run-tests.sh          # Test runner (replaces cli.test.js)

# REMOVED:
# bin/tricycle.js          (replaced by bin/tricycle)
# package.json             (no longer needed)
# package-lock.json        (no longer needed)
# eslint.config.js         (no longer needed — no JS to lint)
# node_modules/            (no longer needed)

# UNCHANGED:
core/                     # Commands, hooks, templates, scripts, skills
generators/sections/       # CLAUDE.md template sections (.md.tpl files)
modules/                  # Optional add-on modules
presets/                  # Preset configurations
docs/                     # Documentation
```

**Structure Decision**: Single CLI entry point (`bin/tricycle`) with sourced library files in `bin/lib/`. This keeps the code modular and testable while maintaining a single executable. The library files are sourced (not executed as subprocesses) so all functions share the same shell context. Bash 3.2 compatibility means no associative arrays — config values are stored as a newline-delimited string of `KEY=VALUE` pairs and searched with `grep -m1`.

## Architecture

### Component Breakdown

**1. YAML Parser (`bin/lib/yaml_parser.sh`)**

Converts `tricycle.config.yml` into flat `KEY=VALUE` lines. Implemented as an `awk` script that:
- Tracks indentation depth to determine nesting
- Maintains a key prefix stack based on indent level
- Detects array items (lines starting with `- `) and auto-increments indices
- Handles inline JSON arrays (`["a", "b"]`) by splitting on commas
- Strips comments, blank lines, and surrounding quotes
- Emits one `KEY=VALUE` line per leaf node

Output stored in a variable (`CONFIG_DATA`) for lookup by other components.

**2. Config Access (`bin/lib/helpers.sh`)**

```
cfg_get <key> → value (or empty string if not found)
cfg_has <key> → exit 0 if key exists, 1 if not
cfg_count <prefix> → number of array items under prefix
cfg_get_or <key> <default> → value or default
```

Implemented as `grep` + `sed` over `CONFIG_DATA`. Each lookup is O(n) over the flat list but n is small (<100 entries for the largest preset).

**3. JSON Builder (`bin/lib/json_builder.sh`)**

Functions for constructing JSON output without `jq`:
- `json_escape <string>` — escape `"` and `\`
- `json_kv <key> <value>` — emit `"key": "value"`
- `json_kv_bool <key> <value>` — emit `"key": true/false` (unquoted)
- `json_kv_raw <key> <raw>` — emit `"key": <raw>` (for nested objects/arrays)
- `json_array <items...>` — emit `["item1", "item2"]`

Used by `generate settings`, `generate mcp`, lock file writes, and `init` (YAML output for config).

**4. Template Engine (`bin/lib/template_engine.sh`)**

Two-pass processor:
- **Pass 1** (`awk`): Resolve `{{#each apps}}...{{/each}}` by repeating the block body for each app, and `{{#if key}}...{{/if}}` by including/omitting based on config truthiness.
- **Pass 2** (`sed`): Replace all remaining `{{variable}}` placeholders with values from config.

Handles the same substitution patterns as the Node.js `substituteVars()` and `substituteAppVars()` functions.

**5. Main CLI (`bin/tricycle`)**

Entry point that:
1. Resolves its own location (`TOOLKIT_ROOT`) via `readlink`/`dirname`
2. Sources all `bin/lib/*.sh` files
3. Parses arguments (subcommand + flags)
4. Dispatches to command functions: `cmd_init`, `cmd_add`, `cmd_generate`, `cmd_update`, `cmd_validate`

Each command function is a direct port of its Node.js equivalent, using the YAML parser, JSON builder, and template engine as needed.

**6. Bootstrapper (`install.sh`)**

Standalone script (no sourced dependencies) that:
- Detects mode: `--install [path]` vs subcommand passthrough
- **One-off mode**: clones repo to `mktemp -d`, runs `bin/tricycle <args>`, removes temp dir
- **Install mode**: clones to target path, creates symlink, prints instructions

### Data Flow

```
tricycle.config.yml
        │
        ▼
  yaml_parser.sh ──► CONFIG_DATA (flat KEY=VALUE string)
        │
        ├──► cfg_get/cfg_has (helpers.sh) ──► command logic
        │
        ├──► template_engine.sh ──► generators/sections/*.md.tpl ──► CLAUDE.md
        │
        ├──► json_builder.sh ──► .claude/settings.json
        │                    ──► .mcp.json
        │                    ──► .tricycle.lock
        │
        └──► file install helpers (helpers.sh) ──► core/*/  →  .claude/*, .specify/*
```

## Bash 3.2 Compatibility Notes

macOS ships bash 3.2 (2007). Key restrictions:
- **No associative arrays** (`declare -A`) — use newline-delimited `KEY=VALUE` string + `grep`
- **No `mapfile`/`readarray`** — use `while IFS= read -r line` loops
- **No `${var,,}` lowercase** — use `tr '[:upper:]' '[:lower:]'`
- **No `|&` pipe stderr** — use `2>&1 |`
- **`local -n` nameref not available** — pass variable names and use `eval` sparingly, or return via stdout

## YAML Output (for `tricycle init`)

The `init` command writes `tricycle.config.yml`. The Node.js version uses `YAML.stringify()`. The bash version will use `printf` with proper indentation to emit YAML directly — this is simpler than building a data structure and serializing it, since the output format is fixed and known at code time.

## Migration Checklist

Files to **create**:
- `bin/tricycle` (main CLI)
- `bin/lib/yaml_parser.sh`
- `bin/lib/json_builder.sh`
- `bin/lib/template_engine.sh`
- `bin/lib/helpers.sh`
- `install.sh` (bootstrapper)
- `tests/run-tests.sh`

Files to **remove**:
- `bin/tricycle.js`
- `package.json`
- `package-lock.json`
- `eslint.config.js`
- `node_modules/` (if present)

Files to **update**:
- `CLAUDE.md` — update commands section (lint/test scripts change)
- `tricycle.config.yml` — update lint/test commands for the project itself
