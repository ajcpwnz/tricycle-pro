# Feature Specification: Workflow Chains & Pluggable Blocks

**Feature Branch**: `003-workflow-chains-blocks`
**Created**: 2026-03-24
**Status**: Draft
**Input**: User description: "Support flexible workflow chains (specify-implement, specify-plan-implement) configured in YAML, and introduce pluggable blocks system replacing hardcoded step behavior"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Workflow Chain in YAML (Priority: P1)

A project maintainer wants to choose which workflow steps their project uses. They edit `tricycle.config.yml` to define the chain — for example, a solo developer working on a small feature chooses `[specify, implement]` to skip planning overhead, while a team working on a complex feature uses the full `[specify, plan, tasks, implement]`. When any command runs (`/trc.headless`, `/trc.specify`, etc.), the system reads the chain config and adjusts behavior accordingly.

**Why this priority**: This is the foundational capability that enables all other workflow flexibility. Without chain configuration, shortened workflows cannot exist.

**Independent Test**: Can be fully tested by editing `tricycle.config.yml` with a chain value and running any workflow command — the system should execute only the configured steps and block commands for omitted steps.

**Acceptance Scenarios**:

1. **Given** a project with `chain: [specify, plan, tasks, implement]` in config, **When** the user runs `/trc.headless`, **Then** all four phases execute in order (current default behavior preserved).
2. **Given** a project with `chain: [specify, plan, implement]` in config, **When** the user runs `/trc.headless`, **Then** only specify, plan, and implement phases execute — the tasks phase is skipped and its responsibilities are absorbed by the plan phase.
3. **Given** a project with `chain: [specify, implement]` in config, **When** the user runs `/trc.headless`, **Then** only specify and implement phases execute — plan and tasks responsibilities are absorbed by the specify phase.
4. **Given** a project with no `chain` key in config, **When** the user runs any workflow command, **Then** the system defaults to `[specify, plan, tasks, implement]` (backward compatible).
5. **Given** a project with an invalid chain (e.g., `[implement]` without specify, or `[tasks, specify]` in wrong order), **When** any command runs, **Then** the system rejects it with a clear error explaining valid chain configurations.
6. **Given** a project with `chain: [specify, implement]`, **When** the user directly invokes `/trc.plan` or `/trc.tasks`, **Then** the system blocks execution with an error explaining that the step is not part of the configured chain.

---

### User Story 2 - Smart Step Absorption for Shortened Chains (Priority: P2)

When steps are omitted from the workflow chain, the preceding step absorbs the omitted step's responsibilities so that no capability is lost. If `tasks` is omitted, the plan step produces both the implementation plan and dependency-ordered tasks. If both `plan` and `tasks` are omitted, the specify step performs technical planning and produces implementation-ready output alongside the specification.

**Why this priority**: This is the behavioral mechanism that makes shortened chains viable — without it, omitting steps would lose critical output.

**Independent Test**: Can be tested by running a specify-plan-implement chain and verifying that the plan output includes both planning artifacts and task breakdown.

**Acceptance Scenarios**:

1. **Given** a `[specify, plan, implement]` chain, **When** the plan phase completes, **Then** the plan output includes a dependency-ordered task breakdown (equivalent to what `/trc.tasks` would produce) in addition to the standard plan artifacts.
2. **Given** a `[specify, implement]` chain, **When** the specify phase completes, **Then** the specify output includes technical planning decisions and an implementation-ready task breakdown alongside the feature specification.
3. **Given** a `[specify, plan, tasks, implement]` chain, **When** each step runs, **Then** each step produces only its standard output (no absorption occurs — current behavior preserved).

---

### User Story 3 - Input Validation for Shortened Chains (Priority: P3)

When a workflow chain omits steps, the system requires proportionally more detailed user input to compensate for the reduced planning phases. A brief two-sentence prompt is acceptable for the full chain (where planning and task generation flesh out the details), but the same brevity is rejected for a specify-implement chain where the specify step must also plan and generate tasks.

**Why this priority**: Prevents users from getting poor results by running shortened chains with insufficient input detail.

**Independent Test**: Can be tested by providing a short prompt to `/trc.specify` with a `[specify, implement]` chain and verifying rejection with guidance.

**Acceptance Scenarios**:

1. **Given** a `[specify, implement]` chain, **When** the user provides a prompt under a minimum detail threshold, **Then** the system rejects the input and explains what additional detail is needed (technical constraints, expected behavior, scope boundaries).
2. **Given** a `[specify, plan, tasks, implement]` chain (full chain), **When** the user provides the same brief prompt, **Then** the system accepts it (planning phases will flesh out the details).
3. **Given** a `[specify, plan, implement]` chain, **When** the user provides a moderately detailed prompt, **Then** the system accepts it (plan phase handles technical planning, only task detail needs to be absorbed).
4. **Given** any chain, **When** the user provides a highly detailed prompt exceeding all thresholds, **Then** the system always accepts it regardless of chain length.

---

### User Story 4 - Decompose Step Behavior into Pluggable Blocks (Priority: P4)

All existing hardcoded behavior within each workflow step is decomposed into named blocks. A block is a partial system prompt that contributes specific behavior to a step. For example, the specify step's current behavior is broken into blocks like "spec writer", "quality validation", "checklist generation". The plan step is broken into blocks like "research phase", "constitution check", "design & contracts", "agent context update". All current behavior is preserved through default blocks that are enabled out of the box.

**Why this priority**: Enables the pluggable architecture that US5 builds on. Must decompose existing behavior before users can select/deselect blocks.

**Independent Test**: Can be tested by verifying that a step assembled from its default blocks produces output identical to the current hardcoded step behavior.

**Acceptance Scenarios**:

1. **Given** the default block configuration, **When** any workflow step executes, **Then** the output is identical to the current hardcoded behavior (zero regression).
2. **Given** the specify step, **When** inspecting its block composition, **Then** each major piece of functionality (spec writing, validation, checklist generation) is a separate, named block.
3. **Given** multiple blocks enabled for a single step, **When** the step executes, **Then** all block prompts are composed into a single coherent system prompt in a defined order.
4. **Given** a block definition, **When** inspecting it, **Then** it declares which step it belongs to (blocks cannot be used in arbitrary steps).

---

### User Story 5 - Enable/Disable Blocks per Project (Priority: P5)

Users can configure which blocks are active for each step via `tricycle.config.yml`. They can disable default blocks they don't need (e.g., disable "contract generation" for a simple script project) and enable optional blocks (e.g., enable "test against local stack" for the implement step). Custom user-defined blocks can be added as files in the project.

**Why this priority**: This is the user-facing customization capability that makes the block system valuable beyond decomposition.

**Independent Test**: Can be tested by disabling a default block in config and verifying the step no longer performs that behavior, then enabling an optional block and verifying new behavior appears.

**Acceptance Scenarios**:

1. **Given** a user disables the "contract generation" block for the plan step, **When** the plan phase runs, **Then** no contracts/ directory is created and the plan skips contract-related work.
2. **Given** a user enables the "test against local stack" block for the implement step, **When** implementation runs, **Then** the implement phase includes local stack testing instructions in its behavior.
3. **Given** a user creates a custom block file in the project, **When** they reference it in the blocks config for a step, **Then** that block's prompt content is included in the step's assembled prompt.
4. **Given** a user attempts to assign a block to a step it doesn't belong to (e.g., "spec writer" block on the implement step), **When** the config is loaded, **Then** the system rejects it with a clear error.
5. **Given** no blocks configuration in `tricycle.config.yml`, **When** any step runs, **Then** the default block set is used (backward compatible).

---

### Edge Cases

- What happens when a user configures a chain that omits `specify`? The system rejects it — specify is always required as the entry point.
- What happens when a user disables all blocks for a step? The system warns that the step will have no behavior and asks for confirmation.
- How does the system handle conflicting blocks (two blocks that produce contradictory instructions)? The system relies on block ordering — later blocks take precedence where conflicts exist.
- What happens when a project upgrades from the old system (no chain/blocks config)? Full backward compatibility — missing config means defaults, which reproduce current behavior.
- How does the `clarify` step interact with the chain? Clarify remains an independent optional command, not part of the chain configuration. It can be invoked manually between any steps.
- What happens when a custom block file is deleted but still referenced in config? The system reports an error at config load time with the missing block path.
- How does step absorption interact with blocks? When a step is omitted from the chain, its default blocks are merged into the preceding step's block set, maintaining the omitted step's capabilities.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support a `chain` configuration key in `tricycle.config.yml` that defines the ordered sequence of workflow steps.
- **FR-002**: System MUST support exactly three chain variants: `[specify, plan, tasks, implement]` (default), `[specify, plan, implement]`, and `[specify, implement]`.
- **FR-003**: System MUST default to `[specify, plan, tasks, implement]` when no chain is configured (backward compatibility).
- **FR-004**: System MUST validate chain configuration at command startup and reject invalid chains with actionable error messages before performing any work.
- **FR-005**: When `tasks` step is omitted from the chain, the `plan` step MUST produce dependency-ordered tasks alongside standard plan artifacts.
- **FR-006**: When `plan` and `tasks` steps are omitted, the `specify` step MUST perform technical planning and produce implementation-ready output alongside the specification.
- **FR-007**: System MUST validate user input detail proportional to chain length — shorter chains MUST require more detailed input.
- **FR-008**: System MUST reject too-concise user prompts for shortened chains with clear guidance explaining what additional detail is needed.
- **FR-009**: System MUST decompose all existing step behaviors into named, discrete blocks (partial system prompts).
- **FR-010**: Each block MUST be scoped to exactly one step type and MUST NOT be assignable to other steps.
- **FR-011**: System MUST provide default block sets for each step that reproduce current behavior exactly when all defaults are enabled.
- **FR-012**: Multiple blocks within the same step MUST compose into a single coherent prompt in a defined, deterministic order.
- **FR-013**: Users MUST be able to enable or disable blocks per step via `tricycle.config.yml`.
- **FR-014**: Users MUST be able to create custom block files and reference them in the blocks configuration.
- **FR-015**: ALL workflow commands (`/trc.specify`, `/trc.plan`, `/trc.tasks`, `/trc.implement`, `/trc.headless`) MUST respect the configured chain. The chain is a project-level setting, not headless-specific.
- **FR-015a**: Commands for steps not present in the configured chain MUST be blocked with an error explaining that the step is not part of the chain. `/trc.headless` executes exactly the configured chain steps in order.
- **FR-016**: When a step is omitted from the chain, its default blocks MUST be merged into the preceding step's block set to preserve capabilities.
- **FR-017**: System MUST reject block assignments where the block's declared step scope does not match the step it is being assigned to (except for absorption from omitted steps, which is handled automatically).
- **FR-018**: Enforcement hooks (branch protection, spec protection, post-implement lint) MUST continue to function independently of the block system — blocks replace content customization, not system enforcement.
- **FR-019**: System MUST warn when all blocks are disabled for a configured step, as this would result in a step with no behavior.
- **FR-020**: The `extensions.yml` hook system MUST be fully deprecated and replaced by the block system. Projects currently using `extensions.yml` for content customization MUST migrate to block configuration.

### Key Entities

- **Workflow Chain**: An ordered sequence of step names (e.g., `[specify, plan, implement]`) that defines which phases the project's workflow includes. Configured per project. Always starts with `specify` and ends with `implement`.
- **Step**: A named phase in the workflow — one of `specify`, `plan`, `tasks`, or `implement`. Each step has a set of associated blocks that define its behavior. The `clarify` step remains independent and is not part of the chain.
- **Block**: A named partial system prompt scoped to a specific step. Has a name, description, step scope, content (prompt text), and default-enabled status. Blocks are the atomic unit of step behavior.
- **Block Registry**: The complete collection of available blocks (built-in and custom), organized by step. Used to validate configuration and assemble step prompts.
- **Block Configuration**: Per-project settings in `tricycle.config.yml` that define which blocks are enabled or disabled for each step, and reference any custom block files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can configure and execute all three chain variants without errors within a single configuration change to `tricycle.config.yml`.
- **SC-002**: Existing projects with no chain or blocks configuration work identically to current behavior — zero regressions across all workflow commands.
- **SC-003**: Users can enable or disable a block and observe the changed step behavior on the very next command invocation.
- **SC-004**: All current workflow capabilities are preserved and fully accessible through the default block configuration.
- **SC-005**: Invalid chain configurations are rejected with actionable error messages before any work begins — no partial execution on bad config.
- **SC-006**: Shortened chains produce equivalent quality output to the full chain when given appropriately detailed input.
- **SC-007**: Custom blocks created as files by users are picked up and composed into step prompts without requiring changes to core system files.
- **SC-008**: Step absorption (blocks from omitted steps merging into preceding steps) works transparently — users do not need to manually reconfigure blocks when changing chain length.

## Clarifications

### Session 2026-03-24

- Q: When a user directly invokes a command for a step not in the configured chain (e.g., `/trc.plan` when chain is `[specify, implement]`), what happens? → A: Chain config is project-wide — commands for omitted steps are blocked. Chain works regardless of headless mode; headless simply executes the current chain.
- Q: What happens to `extensions.yml` when blocks are introduced? → A: Extensions.yml is fully deprecated and replaced by blocks. Projects using it must migrate to block configuration.

## Assumptions

- The `clarify` step remains an independent optional command and is not part of the configurable chain. Users invoke it manually when needed.
- Enforcement hooks (branch protection, spec protection, lint gate) are a separate concern from blocks. Blocks replace the content customization mechanism, not the system enforcement mechanism (shell-based hooks).
- `extensions.yml` is fully deprecated by blocks. No coexistence — projects must migrate extension hooks to block configuration.
- Block ordering within a step is deterministic — built-in blocks execute in their defined order, custom blocks are appended after built-in blocks unless explicitly ordered.
- The `analyze` and `checklist` commands are utility commands and are not part of the workflow chain.
- When blocks from an omitted step are absorbed into the preceding step, they are appended after that step's own blocks.
- The minimum input detail thresholds for shortened chains are configurable but have sensible defaults.
