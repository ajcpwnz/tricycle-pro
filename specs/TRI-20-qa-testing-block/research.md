# Research: QA Testing Block

**Date**: 2026-03-30
**Branch**: TRI-20-qa-testing-block

## R1: Auto-Enable Pattern for Config-Driven Feature Flags

**Decision**: Add a `compute_feature_flag_enables()` function in `assemble-commands.sh` that reads feature flags (like `qa.enabled`) and injects them into the overrides before `apply_overrides` runs.

**Rationale**: Currently, optional blocks are only enabled via `workflow.blocks.{step}.enable: [block-name]`. There is no mechanism to translate a top-level config flag (like `qa.enabled: true`) into an automatic block enable. The assembly script's `apply_overrides` function consumes an `enabled` array — the simplest approach is to prepend computed enable entries to the overrides string before it's parsed.

**Alternatives considered**:
- **Set `default_enabled: true` on the block**: Rejected — this would include the QA block in ALL projects, even those without `qa.enabled`. The block should be opt-in.
- **Require manual `workflow.blocks.implement.enable: [qa-testing]`**: Rejected — FR-008 requires `qa.enabled: true` alone to activate the block. Users shouldn't configure the same thing in two places.
- **Add a new config section `workflow.blocks.implement.auto_enable_from`**: Over-engineered. A simple function that maps known feature flags to block names is sufficient.

**Code path**: In `assemble_step()`, after calling `parse_block_overrides` and before passing to `apply_overrides`, prepend any feature-flag-derived enables. The function reads `qa.enabled` via `cfg_get` and, if true, adds `enable=qa-testing` to the overrides string.

## R2: Block Halt Pattern

**Decision**: Use the same plain-language HALT directive pattern as `push-deploy.md`.

**Rationale**: The push-deploy block enforces halting via explicit English instructions ("HALT and wait", "Do NOT proceed", "Do NOT push"). This is proven to work — it's the same enforcement model used for push approval. The QA block uses the same approach: "If ANY test fails after 3 fix attempts, HALT. Do NOT proceed to the next block."

**Alternatives considered**:
- **Hook-based enforcement (PreToolUse gate on commit)**: Rejected earlier in design discussion — testing is multi-step and can't be gated by a single check.
- **Marker file + hook**: Rejected — adds state management complexity for no benefit over directive-based enforcement.

## R3: Runtime Config Reading vs Assembly-Time Injection

**Decision**: The QA block reads `tricycle.config.yml` and `qa/ai-agent-instructions.md` at runtime. No assembly-time injection.

**Rationale**: The `task-execution` block already reads `apps[].test` and `apps[].lint` from config at runtime (per-phase test gate). The QA block follows the same pattern. This means the block file is static markdown — no placeholder markers, no injection logic in the assembly script. The only assembly change is the auto-enable logic.

**Alternatives considered**:
- **Assembly-time injection of test commands**: Rejected — unnecessary. Agent reads config at runtime already. Would require new injection infrastructure in the assembly script.
- **Assembly-time injection of `qa.instructions`**: Rejected — instructions moved to a file (`qa/ai-agent-instructions.md`), not config.

## R4: QA-Run Skill Injection

**Decision**: Use the existing skill injection pattern. If `qa-run` is listed in `workflow.blocks.implement.skills`, it gets injected via the standard "Skill Invocations" section at the end of the assembled command.

**Rationale**: The assembly script already generates conditional skill invocations. No special handling needed — the `qa-run` skill is just another skill entry.

**Alternatives considered**:
- **Hard-code qa-run invocation in the block template**: Rejected — would bypass the skill injection system and break if the skill isn't installed.
- **Auto-add qa-run to skills when qa.enabled**: Possible future enhancement but not needed for MVP. Users can add it explicitly to `workflow.blocks.implement.skills: [qa-run]`.

## R5: Learnings Append Pattern

**Decision**: The block instructs the agent to append learnings to `qa/ai-agent-instructions.md` under a dated `## Learnings` section at the end of the file. The agent reads existing content first to avoid duplicates.

**Rationale**: This is a prompt-level directive — the block tells the agent what to do. No tooling or scripting needed. The agent creates the file if it doesn't exist, appends under a clearly marked section if it does.

**Alternatives considered**:
- **Separate learnings file**: Rejected — fragments the testing knowledge. One file is simpler.
- **Structured YAML/JSON learnings format**: Over-engineered. Free-form markdown is easier for the agent to read and write.
