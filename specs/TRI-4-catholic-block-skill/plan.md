# Implementation Plan: Catholic Block & Skill

**Branch**: `TRI-4-catholic-block-skill` | **Date**: 2026-03-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/TRI-4-catholic-block-skill/spec.md`
**Version**: 0.6.0 → 0.7.0 (minor bump — new feature)

## Summary

Add a `catholic` skill that guides Claude to use reverent, faith-inspired language in non-code artifacts, and a `catholic` block that fires early in the specify step to pray for the feature's success. Both are opt-in. Update README to document them.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown
**Primary Dependencies**: None — pure markdown content files
**Storage**: Filesystem — skill in `core/skills/catholic/`, block in `core/blocks/optional/specify/`
**Testing**: Custom bash test runner (`tests/run-tests.sh`)
**Target Platform**: macOS, Linux
**Project Type**: CLI tool (pure bash)
**Performance Goals**: N/A
**Constraints**: No external dependencies
**Scale/Scope**: 2 new markdown files + README update

## Constitution Check

Constitution not yet populated. Gate: N/A.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-4-catholic-block-skill/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Technical decisions
├── quickstart.md        # Verification guide
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
core/skills/catholic/
├── SKILL.md             # New — catholic skill definition
├── README.md            # New — skill documentation
└── SOURCE               # New — origin tracking

core/blocks/optional/specify/
└── catholic.md          # New — prayer block for specify step

README.md                # Modified — add catholic section
```

**Structure Decision**: Two new files in existing directories. No structural changes.

## Design Decisions

See [research.md](research.md) for full rationale.

### D1: Block in optional/specify/ with order 1
Fires before all other specify blocks. Optional, not default-enabled.

### D2: Skill excludes all code/config files
Clear boundary: artifacts (markdown) get blessed, code stays secular.

### D3: Ecumenical Catholic tone
Blessings, gratitude, Providence — not doctrinal or preachy.

### D4: User-invocable skill (not background)
Explicit opt-in only. Block handles automatic invocation for users who enable it.

## Implementation Approach

### Phase A: Catholic Skill
1. Create `core/skills/catholic/SKILL.md` with frontmatter and verbiage instructions
2. Create `core/skills/catholic/README.md`
3. Create `core/skills/catholic/SOURCE`

### Phase B: Catholic Block
1. Create `core/blocks/optional/specify/catholic.md` with frontmatter (name, step, order, required: false, default_enabled: false) and prayer/blessing content

### Phase C: README & Tests
1. Update README.md with catholic block/skill documentation
2. Add test: block file exists with correct frontmatter
3. Add test: skill files exist

## Complexity Tracking

No constitution violations.
