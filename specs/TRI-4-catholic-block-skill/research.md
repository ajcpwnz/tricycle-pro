# Research: TRI-4 Catholic Block & Skill

**Date**: 2026-03-27
**Branch**: TRI-4-catholic-block-skill

## Decision 1: Block Placement

**Decision**: Place the catholic block in `core/blocks/optional/specify/catholic.md` with `order: 1` (fires before all other blocks).

**Rationale**: The block is optional (`default_enabled: false`), so it belongs in `optional/`. Order 1 ensures the prayer appears before spec writing begins. The existing chain-validation block has order 5, so the prayer fires first.

**Alternatives considered**:
- `core/blocks/specify/catholic.md` with `default_enabled: false`: Works but convention is optional blocks go in `optional/` subdirectory.
- Higher order number: Would fire after some blocks, defeating the "pray first" requirement.

## Decision 2: Skill Scope — What Gets Blessed

**Decision**: The skill instructs the agent to apply Christian verbiage to ALL non-code artifacts: specs, plans, tasks, READMEs, changelogs, commit messages (PR descriptions). It explicitly excludes: source code, test files, config files (YAML/JSON), shell scripts, and any executable content.

**Rationale**: Clear boundary. Artifacts are documents humans read. Code is for machines and linters. Mixing religious language into code would break conventions, confuse parsers, and be disrespectful to the language itself.

## Decision 3: Verbiage Tone

**Decision**: Broadly ecumenical Catholic — blessings, gratitude, references to Providence, divine guidance, the intercession of saints. Not doctrinal, not preachy, not quoting scripture at length. Brief and woven into the natural flow of the document.

**Rationale**: The goal is a reverent tone, not a catechism lesson. The artifacts must remain functionally useful as engineering documents.

**Examples**:
- Spec opening: "May this specification, crafted with care and guided by Providence, serve as a faithful blueprint..."
- Plan completion: "Thanks be to God for the clarity granted in this planning phase."
- Task list header: "With the Lord's blessing, we proceed to the following tasks..."

## Decision 4: Skill Activation Mode

**Decision**: The catholic skill is `user-invocable: true` (default) — available as `/catholic` slash command. It is NOT a background skill (`user-invocable: false`) because forcing religious tone on all output without explicit opt-in would be inappropriate.

**Rationale**: Users should consciously choose to apply religious verbiage. The block handles automatic invocation during workflow steps for users who enable it.
