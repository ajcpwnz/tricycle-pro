# Implementation Plan: QA Testing Block

**Branch**: `TRI-20-qa-testing-block` | **Date**: 2026-03-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-20-qa-testing-block/spec.md`
**Version**: 0.9.0 → 0.10.0 (minor bump — new feature)

## Summary

Add a QA testing block to the implement workflow that enforces test execution before push. The block is an optional implement block (`core/blocks/optional/implement/qa-testing.md`) auto-enabled when `qa.enabled: true` in config. It's static markdown — the agent reads test commands from `tricycle.config.yml` and setup instructions from `qa/ai-agent-instructions.md` at runtime. Agent appends testing learnings back to the instructions file. Assembly changes are minimal: a feature-flag-to-block-enable translation before `apply_overrides` runs.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, tested on macOS zsh)
**Primary Dependencies**: None (pure bash, existing yaml parser via `cfg_get`)
**Storage**: File-based (block markdown, config YAML, instructions markdown)
**Testing**: `bash tests/run-tests.sh`, `node --test tests/test-*.js`
**Target Platform**: macOS/Linux (Claude Code CLI)
**Project Type**: CLI toolkit
**Performance Goals**: N/A (assembly-time script, runs once)
**Constraints**: No new dependencies, POSIX-compatible bash
**Scale/Scope**: 1 new block file, 1 assembly script modification, tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is unpopulated (placeholder only). No gates to evaluate. Proceeding.

**Post-design re-check**: No violations. The feature adds one optional block and minimal assembly logic — no new dependencies, no new abstractions, no complexity beyond the existing patterns.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-20-qa-testing-block/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── block-frontmatter.md
│   └── auto-enable-interface.md
├── checklists/
│   └── requirements.md
└── tasks.md              (created by /trc.tasks)
```

### Source Code (repository root)

```text
core/blocks/optional/implement/
└── qa-testing.md              # NEW — the QA block template

core/scripts/bash/
├── assemble-commands.sh       # MODIFY — add feature flag auto-enable
└── common.sh                  # MODIFY (if needed) — cfg_get_bool helper

tests/
├── test-block-assembly.js     # MODIFY — add QA assembly tests
└── run-tests.sh               # UNCHANGED

modules/qa/
└── README.md                  # MODIFY — document the block integration
```

**Structure Decision**: Single-app CLI toolkit. All changes are in existing directories — one new block file, modifications to assembly script and tests.

## Design Decisions

### D1: Block Template Content

The QA block is static markdown following the same patterns as `push-deploy.md` and `task-execution.md`. It contains:

1. **Instructions file read** — "If `qa/ai-agent-instructions.md` exists, read it and follow all guidance before proceeding."
2. **Test execution** — "Read `tricycle.config.yml`. For each app with a `test` field, run the command. All must exit 0."
3. **Retry logic** — "If any test fails, attempt fix (max 3 attempts). Re-run ALL test commands after each fix."
4. **HALT gate** — "If still failing after 3 attempts, HALT. Do NOT proceed to push-deploy."
5. **Learnings append** — "If you discovered new operational knowledge during testing, append to `qa/ai-agent-instructions.md`."

Order 55 places it after task-execution (50) and before push-deploy (65).

### D2: Assembly Auto-Enable

In `assemble-commands.sh`, add a function `compute_feature_flag_enables()` called per-step in `assemble_step()`. For the `implement` step, it checks `qa.enabled` via `cfg_get` and prepends `enable=qa-testing` to the overrides string if true.

This is ~15 lines of bash. The function is extensible — future feature flags can be added with the same pattern.

### D3: Learnings Append Format

The block instructs the agent to append under a `## Learnings` heading at the end of the file:

```markdown
## Learnings

### 2026-03-30
- Need to run `prisma generate` before backend tests
- Docker compose `--wait` flag avoids manual polling
```

Agent reads existing content first to avoid duplicates. Creates the file with a basic header if it doesn't exist.

## Complexity Tracking

No constitution violations. No complexity justification needed.
