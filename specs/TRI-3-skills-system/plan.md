# Implementation Plan: Skills System

**Branch**: `TRI-3-skills-system` | **Date**: 2026-03-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/TRI-3-skills-system/spec.md`
**Version**: 0.5.1 → 0.6.0 (minor bump — new feature)

## Summary

Add a skills management system to Tricycle Pro that vendors curated default skills from official repositories, supports config-driven installation of external skills from GitHub or local paths, provides a disable mechanism for unwanted defaults, adds a `tricycle skills list` command for inventory, and enables block-skill integration with graceful degradation.

The implementation leverages existing infrastructure: `install_dir()`/`install_file()` for checksum-protected installation, the YAML config parser for new `skills` section, and the lock file system for modification tracking.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Node.js 18+ (tests only)
**Primary Dependencies**: git (for sparse checkout of external skills), standard Unix utilities (awk, sed, grep, find, sha256sum/shasum)
**Storage**: Filesystem — skill directories in `.claude/skills/`, lock entries in `.tricycle.lock`, config in `tricycle.config.yml`
**Testing**: Custom bash test runner (`tests/run-tests.sh`) + `node:test` built-in
**Target Platform**: macOS, Linux (any system with bash 4+ and git)
**Project Type**: CLI tool (pure bash)
**Performance Goals**: N/A — occasional interactive CLI operations
**Constraints**: No external dependencies (no npm packages, no jq, no python); pure bash + standard Unix
**Scale/Scope**: ~5 vendored skills, 0-10 external skills per project

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution not yet populated (placeholder state). Gate: N/A — no violations possible.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-3-skills-system/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — technical decisions
├── data-model.md        # Phase 1 — entities and relationships
├── quickstart.md        # Phase 1 — developer quickstart
├── contracts/
│   └── cli-commands.md  # Phase 1 — CLI command contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (via /trc.tasks)
```

### Source Code (repository root)

```text
bin/
├── tricycle                    # Main CLI — modify cmd_init(), cmd_update(), add cmd_skills()
└── lib/
    └── helpers.sh              # Add install_skills(), fetch_external_skill(), generate_source_file(), skill_checksum()

core/skills/                    # Vendored default skills
├── code-reviewer/
│   ├── SKILL.md
│   ├── README.md
│   ├── SOURCE
│   └── Templates/
├── tdd/
│   ├── SKILL.md
│   ├── README.md
│   └── SOURCE
├── debugging/
│   ├── SKILL.md
│   ├── README.md
│   └── SOURCE
├── document-writer/
│   ├── SKILL.md
│   ├── README.md
│   └── SOURCE
└── monorepo-structure/         # Already exists
    ├── SKILL.md
    ├── README.md
    ├── SOURCE                  # New — add origin tracking
    ├── Templates/
    └── Examples/

tests/
├── run-tests.sh                # Add skill-specific test groups
└── test-skills.js              # New — Node.js tests for skill config parsing
```

**Structure Decision**: Single-app CLI. All changes are in the existing `bin/`, `core/`, and `tests/` directories. No new top-level directories needed.

## Design Decisions

See [research.md](research.md) for full rationale on each decision.

### D1: GitHub Fetching — Sparse Checkout
Use `git clone --depth=1 --filter=blob:none --sparse` for external skill fetching. Clean, standard, no API dependencies.

### D2: SOURCE File — Plain Text Key-Value
Simple `key: value` format parseable with `grep`/`cut`. Fields: origin, commit, installed, checksum.

### D3: Modification Detection — Stored Checksum in SOURCE
Compute and store skill-level checksum at install time. Fully local comparison on update. No network needed.

### D4: Disable Mechanism — Pre-Install Filter
Replace single `install_dir` call with per-skill loop that checks disable list before installing.

### D5: Skills Subcommand — Dispatcher Pattern
`cmd_skills()` routes to `cmd_skills_list()`. Follows existing CLI dispatch pattern.

### D6: Block Integration — Conditional Markdown
Blocks use file-existence checks in natural language. Agent evaluates and skips if missing. No code changes to block system.

### D7: Vendoring — Manual One-Time Copy
Copy skills from anthropics/skills into `core/skills/` with SOURCE files. Future syncs are manual.

## Implementation Approach

### Phase A: Foundation (helpers + config parsing)

1. Add `skill_checksum()`, `generate_source_file()` to `helpers.sh`
2. Add `install_skills()` to `helpers.sh` — iterates `core/skills/*/`, filters disabled, calls `install_dir` per-skill, generates SOURCE
3. Add `fetch_external_skill()` to `helpers.sh` — handles `github:` and `local:` sources

### Phase B: Vendor Default Skills

1. Copy code-reviewer, tdd, debugging, document-writer from anthropics/skills into `core/skills/`
2. Add SOURCE file to each vendored skill (including existing monorepo-structure)
3. Validate each skill has SKILL.md with valid frontmatter

### Phase C: CLI Integration

1. Modify `cmd_init()` — replace `install_dir "$TOOLKIT_ROOT/core/skills" ".claude/skills"` with `install_skills` call, add external skill fetching loop
2. Modify `cmd_update()` — add skills to update mappings with disable filtering, add external skill re-fetch
3. Add `cmd_skills()` and `cmd_skills_list()` — skill inventory command
4. Add `skills` to CLI help text and argument routing

### Phase D: Block Integration

1. Add conditional skill invocation pattern to relevant blocks (e.g., push-deploy block references code-review skill)
2. Document the pattern in a block authoring section

### Phase E: Testing

1. Add test group to `tests/run-tests.sh`: init installs skills, disable skips skills, SOURCE files present, update preserves modifications, skills list output
2. Add `tests/test-skills.js` for config parsing of `skills.install` and `skills.disable` sections

## Complexity Tracking

No constitution violations to justify — constitution not yet populated.
