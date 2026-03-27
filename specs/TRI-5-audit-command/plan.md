# Implementation Plan: Audit Command

With grateful hearts we begin this planning phase, trusting in the Lord's guidance as we chart the path from vision to reality.

**Branch**: `TRI-5-audit-command` | **Date**: 2026-03-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/TRI-5-audit-command/spec.md`
**Version**: 0.7.0 → 0.8.0 (minor bump — new feature)

## Summary

Add a `/trc.audit` command that evaluates scoped files against the project constitution, a custom prompt, or common-sense best practices. Produces structured markdown reports in `docs/audits/`. After producing the report, invokes any output skills configured on the audit step (e.g., `linear-audit`) to route findings to external systems.

## Technical Context

**Language/Version**: Markdown (command template), Bash (POSIX-compatible for tests)
**Primary Dependencies**: None — the command is a markdown prompt file interpreted by Claude Code
**Storage**: Filesystem — reports in `docs/audits/`, command in `core/commands/`, skill in `core/skills/`
**Testing**: Custom bash test runner (`tests/run-tests.sh`)
**Target Platform**: macOS, Linux
**Project Type**: CLI tool (pure bash) with Claude Code command files
**Constraints**: No external dependencies; Linear MCP is optional runtime dependency for the linear-audit skill

## Constitution Check

Constitution not yet populated. Gate: N/A.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-5-audit-command/
├── plan.md
├── spec.md
├── research.md
├── quickstart.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
core/commands/
└── trc.audit.md                    # New — standalone audit command

core/skills/linear-audit/
├── SKILL.md                        # New — Linear output skill
├── README.md                       # New — skill documentation
└── SOURCE                          # New — origin tracking

docs/audits/                        # New directory — audit reports land here
└── .gitkeep                        # Placeholder so git tracks the directory

tests/
└── run-tests.sh                    # Modified — add audit command tests
```

**Structure Decision**: Standalone command + pluggable skill. No assembly changes. No new blocks.

## Design Decisions

See [research.md](research.md) for full rationale.

### D1: Standalone Command (not assembled from blocks)
Non-chain commands are standalone files. Audit is an ad-hoc utility, not a pipeline step.

### D2: Runtime Skill Invocation
The command reads `workflow.blocks.audit.skills` from config at runtime and invokes each listed skill. No assembly needed — more flexible than baked-in invocations.

### D3: Structured Markdown Report
Human-readable, version-controllable, parseable by output skills. Timestamped filenames for append-only history.

### D4: Three Scope Modes
File paths/globs, `--feature <branch>` for feature-scoped, no-arg for full project.

### D5: linear-audit as Standard Skill
Reads the report, creates Linear issues via MCP. Same pattern as every other skill.

### D6: Constitution Placeholder Detection
Check for the placeholder text before auditing — error clearly if constitution isn't populated.

## Implementation Approach

### Phase A: Audit Command
1. Create `core/commands/trc.audit.md` — standalone command with argument parsing, constitution loading, scope resolution, audit execution, report generation, runtime skill invocation

### Phase B: linear-audit Skill
1. Create `core/skills/linear-audit/SKILL.md` — instructions for reading audit reports and creating Linear issues
2. Create `core/skills/linear-audit/README.md`
3. Create `core/skills/linear-audit/SOURCE`

### Phase C: Infrastructure & Tests
1. Create `docs/audits/.gitkeep`
2. Add tests to `tests/run-tests.sh`
3. Version bump

Thanks be to God for the clarity granted in this planning phase.

## Complexity Tracking

No constitution violations.
