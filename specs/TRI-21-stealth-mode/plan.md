# Implementation Plan: Stealth Mode

**Branch**: `TRI-21-stealth-mode` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-21-stealth-mode/spec.md`
**Version**: 0.10.0 → 0.11.0 (minor bump — new feature)

## Summary

Add a `stealth` config section to `tricycle.config.yml` that, when enabled, writes comprehensive gitignore rules to `.git/info/exclude` (default) or `.gitignore` (configurable) so that all tricycle-managed files are invisible to version control. The implementation touches three functions in `bin/tricycle` and adds corresponding tests. Workflow commands require zero changes — stealth only affects VCS visibility.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, tested on macOS zsh)
**Primary Dependencies**: git, awk (for YAML parsing), core POSIX utilities
**Storage**: Filesystem (`.git/info/exclude` or `.gitignore`)
**Testing**: `bash tests/run-tests.sh`, `node --test tests/test-*.js`
**Target Platform**: macOS, Linux
**Project Type**: CLI tool
**Constraints**: POSIX-compatible shell (no bashisms beyond what's already used)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is a placeholder — no gates defined. Passes by default.

**Post-design re-check**: No violations. Feature adds a config field and modifies one function; no new abstractions, no new dependencies.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-21-stealth-mode/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Research decisions
├── data-model.md        # Config schema and ignore block format
├── quickstart.md        # User-facing quick reference
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
bin/
├── tricycle                    # Main CLI — modify cmd_generate_gitignore(), cmd_init()
└── lib/
    └── helpers.sh              # cfg_get() already supports reading stealth.enabled

tests/
├── test-stealth-mode.js        # NEW: stealth mode tests
└── fixtures/                   # test fixtures (if needed)
```

**Structure Decision**: Single-app CLI. All changes are in `bin/tricycle` (the main script) and a new test file. No new directories or modules needed.

## Design

### Config Schema Addition

Add to `tricycle.config.yml`:

```yaml
stealth:
  enabled: false                 # default: normal mode
  ignore_target: exclude         # "exclude" (.git/info/exclude) or "gitignore" (.gitignore)
```

Read via existing `cfg_get`:
- `cfg_get "stealth.enabled"` → `"true"` or `"false"` / empty
- `cfg_get_or "stealth.ignore_target" "exclude"` → `"exclude"` or `"gitignore"`

### Stealth Ignore Block

```
# >>> tricycle stealth (do not edit this block)
.claude/
.trc/
specs/
tricycle.config.yml
.tricycle.lock
.mcp.json
# <<< tricycle stealth
```

Written to the target file. Markers enable clean removal on toggle-off.

### Modified Functions

#### 1. `cmd_generate_gitignore()` (bin/tricycle:483-509)

Current: Writes normal `.claude/*` + negation rules to `.gitignore`.

New behavior:
- Read `stealth.enabled` from config
- If stealth:
  1. Determine target: `.git/info/exclude` or `.gitignore` based on `stealth.ignore_target`
  2. Remove any existing stealth block from BOTH targets (handles target switching)
  3. Remove any existing normal-mode block from `.gitignore` (stealth replaces it)
  4. Write stealth block to target file
- If not stealth (normal):
  1. Remove any existing stealth block from BOTH targets (handles toggle-off)
  2. Write normal-mode block to `.gitignore` (existing behavior)

#### 2. `cmd_init()` (bin/tricycle:88-232)

Current: Calls `cmd_generate_gitignore()` at line 221, after all files are installed.

New behavior: When stealth is enabled, call `cmd_generate_gitignore()` BEFORE `install_dir()` calls (before line 187). This ensures ignore rules are in place before files appear on disk. For normal mode, order is unchanged.

The interactive wizard template (lines 147-174) gains the `stealth:` section with `enabled: false` as default.

#### 3. New helper: `stealth_remove_block()`

Removes the `# >>> tricycle stealth` ... `# <<< tricycle stealth` block from a given file. Used by both stealth-enable and stealth-disable paths.

### Worktree Inheritance

When a worktree is created, `.git/info/exclude` is shared across all worktrees (it lives in the main `.git` directory). So stealth rules in `.git/info/exclude` automatically apply to worktrees. If the user chose `.gitignore` as target, the worktree setup already copies `.gitignore` as part of normal git operations.

No special handling needed.

### What Does NOT Change

- `assemble-commands.sh` — writes to `.claude/commands/` which is under the stealth umbrella
- `cmd_generate_settings()` — writes to `.claude/settings.json` which is under the stealth umbrella
- `session-context.sh` hook — reads files from disk, unaffected by gitignore
- All `/trc.*` workflow commands — operate on filesystem, unaffected by VCS visibility
- `create-new-feature.sh` — creates specs/ dirs which are under the stealth umbrella
- Config reading (`load_config`, `cfg_get`) — reads `tricycle.config.yml` from disk regardless of gitignore

## Testing Strategy

### New test file: `tests/test-stealth-mode.js`

1. **Stealth enable → exclude**: Set `stealth.enabled: true`, run generate, verify `.git/info/exclude` contains stealth block
2. **Stealth enable → gitignore**: Set `stealth.ignore_target: gitignore`, run generate, verify `.gitignore` contains stealth block
3. **Stealth disable**: Enable then disable, verify stealth block removed from target, normal block restored in `.gitignore`
4. **Target switch**: Change from `exclude` to `gitignore`, run generate, verify old target cleaned and new target has block
5. **Idempotent**: Run generate twice with same config, verify no duplicate blocks
6. **Preserve user rules**: Add custom rules to target file, run generate, verify custom rules preserved
7. **Stealth block content**: Verify block contains all required paths (`.claude/`, `.trc/`, `specs/`, `tricycle.config.yml`, `.tricycle.lock`, `.mcp.json`)

## Complexity Tracking

No constitution violations to justify — feature is a single config field with one modified function.
