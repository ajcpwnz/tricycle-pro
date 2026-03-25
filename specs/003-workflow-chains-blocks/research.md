# Research: Workflow Chains & Pluggable Blocks

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## Decision 1: Block File Format

**Decision**: Markdown files with YAML frontmatter

**Rationale**: Consistent with existing command and template file patterns. Block content is prompt text (markdown), frontmatter provides structured metadata for assembly.

**Alternatives considered**:
- Pure YAML (rejected — poor ergonomics for multi-paragraph prompt content)
- JSON (rejected — not human-friendly for editing prompt text)
- Plain markdown without frontmatter (rejected — no structured metadata for assembly)

## Decision 2: Assembly Mechanism

**Decision**: Build-time assembly via bash script (`assemble-commands.sh`)

**Rationale**: Assembled command files are static — Claude Code reads them directly without understanding the block system. No runtime overhead, no extra tool calls. Consistent with project's bash-first approach (feature 002).

**Alternatives considered**:
- Runtime assembly where AI reads block files at invocation (rejected — adds tool calls, context consumption, complexity)
- Node.js assembly script (rejected — project moving toward pure bash)

## Decision 3: Block Storage & Distribution

**Decision**: Blocks in `core/blocks/{step}/`, synced to `.specify/blocks/` during init

**Rationale**: Follows established sync pattern (`core/templates/` → `.specify/templates/`, `core/scripts/` → `.specify/scripts/`). Users can customize blocks locally; `.tricycle.lock` tracks checksums.

**Alternatives considered**:
- Blocks only in core/ (rejected — user projects need them for local assembly)
- Blocks embedded in YAML config (rejected — prompt content too large for config values)

## Decision 4: Chain Configuration Location

**Decision**: `workflow` section in `tricycle.config.yml`

**Rationale**: Extends existing config without breaking changes. Groups chain + block settings under a single namespace.

**Alternatives considered**:
- Separate `workflow.yml` (rejected — file fragmentation)
- Environment variable (rejected — not persistent or project-scoped)

## Decision 5: Input Validation Approach

**Decision**: AI judgment with structured guidelines per chain length, embedded in the input-validation block

**Rationale**: More nuanced than mechanical checks. The AI already processes the prompt and can evaluate quality.

**Guidelines per chain length**:
- Full chain `[specify, plan, tasks, implement]`: No minimum
- 3-step `[specify, plan, implement]`: Prompt should describe scope + expected outcomes
- 2-step `[specify, implement]`: Prompt must describe scope, expected behavior, technical constraints, and acceptance criteria

**Alternatives considered**:
- Word/character count threshold (rejected — measures length, not quality)
- Required field detection via regex (rejected — too rigid)

## Decision 6: Absorption Mechanism

**Decision**: Build-time block merging — omitted steps' blocks appended to preceding step during assembly

**Rationale**: No runtime complexity. Assembled command is self-contained. AI doesn't need to understand absorption.

**Merge order**: Absorbed blocks appended after the step's own blocks. Plan blocks come before tasks blocks (canonical chain order). Absorbed blocks get order values offset by +100 per absorbed step to avoid conflicts.

**Alternatives considered**:
- Runtime absorption where AI resolves at invocation (rejected — adds complexity, requires chain awareness in every command)

## Decision 7: Constitution Principle I Amendment

**Decision**: Amend Principle I to acknowledge flexible chains

**Current**: "Every feature MUST follow specify → plan → tasks → implement"
**Proposed**: "Every feature MUST follow the configured workflow chain. The default chain is specify → plan → tasks → implement. Shortened chains are supported when configured."

**Rationale**: Current principle directly conflicts with this feature. Amendment preserves spec-first intent while allowing flexibility.

## Decision 8: Headless Command Assembly

**Decision**: Headless command assembled per-chain with static phase numbering

**Rationale**: Static assembly is simpler than runtime chain reading. Regenerated when chain changes via `tricycle assemble`.

**Alternatives considered**:
- Runtime chain reading in headless (rejected — adds YAML parsing at invocation time)

## Decision 9: Blocked Command Handling

**Decision**: Generate minimal "blocked" stub command files for steps not in the chain

**Rationale**: Friendlier than removing command files entirely. Users see a clear error explaining why the command is unavailable.

**Alternatives considered**:
- Delete command files for blocked steps (rejected — confuses users who expect the command)
- Allow commands to run outside chain (rejected — contradicts clarification that chain is project-wide)
