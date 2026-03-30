# Implementation Plan: SessionStart Context Injection

**Branch**: `TRI-19-session-context-hook` | **Date**: 2026-03-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-19-session-context-hook/spec.md`

## Summary

Add a SessionStart hook to tricycle that auto-injects the project constitution and user-configured context files into every Claude Code session. The hook fires on startup, resume, and compact events. Configuration lives in `tricycle.config.yml` under `context.session_start` with constitution injection enabled by default (opt-out). A generated `.session-context.conf` file decouples the hook from YAML parsing. This is a CLI-only change touching the settings generator, a new hook script, preset configs, validation, and tests.

**Version**: Current `0.8.1`. This is a new feature — warrants minor bump to `0.9.0`.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, tested on macOS zsh)
**Primary Dependencies**: None (pure bash, optional jq for JSON construction)
**Storage**: File-based (tricycle.config.yml, .session-context.conf, settings.json)
**Testing**: `bash tests/run-tests.sh` (shell tests), `node --test tests/test-*.js` (block assembly tests)
**Target Platform**: macOS / Linux (anywhere Claude Code runs)
**Project Type**: CLI tool
**Constraints**: Hook must complete in <10 seconds, no external dependencies beyond bash
**Scale/Scope**: Up to 10 context files per project

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is not yet populated (placeholder only). No gates to evaluate. Proceeding.

**Post-design re-check**: No violations. The feature adds a single hook script and extends the settings generator — no new abstractions, no new dependencies, no architectural changes.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-19-session-context-hook/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── hook-response.md # Hook I/O contract
│   └── config-schema.md # Config YAML schema
└── tasks.md             # Phase 2 output (/trc.tasks)
```

### Source Code (repository root)

```text
core/hooks/
├── block-branch-in-main.sh     # existing
├── block-spec-in-main.sh       # existing
├── post-implement-lint.sh      # existing
└── session-context.sh          # NEW — SessionStart hook script

bin/
├── tricycle                    # MODIFY — cmd_generate_settings(), cmd_validate()
└── lib/
    └── helpers.sh              # reference only (cfg_get, cfg_count)

presets/
├── single-app/tricycle.config.yml          # MODIFY — add context section
├── monorepo-turborepo/tricycle.config.yml  # MODIFY — add context section
├── nextjs-prisma/tricycle.config.yml       # MODIFY — add context section
└── express-prisma/tricycle.config.yml      # MODIFY — add context section

tests/
└── run-tests.sh                # MODIFY — add SessionStart hook tests
```

**Structure Decision**: Single-app CLI project. All changes are in existing directories — no new directories or structural changes needed.

## Complexity Tracking

No constitution violations to justify. Feature is straightforward:
- 1 new file (hook script)
- 1 modified function (cmd_generate_settings)
- 1 validation addition (cmd_validate)
- 4 preset config updates
- ~8 new tests
