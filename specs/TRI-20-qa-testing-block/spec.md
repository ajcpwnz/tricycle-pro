# Feature Specification: QA Testing Block

**Feature Branch**: `TRI-20-qa-testing-block`
**Created**: 2026-03-30
**Status**: Draft
**Input**: User description: "QA block: enforce testing in workflow chain before push"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent enforces testing before push (Priority: P1)

A developer runs `/trc.implement` on a project with `qa.enabled: true` in `tricycle.config.yml`. After the agent completes task execution, the assembled implement command includes a QA testing block that instructs the agent to run all configured `apps[].test` commands. The agent runs each test command. If any test fails, the agent halts and does not proceed to push-deploy. The developer can see exactly which tests failed and why.

**Why this priority**: This is the entire reason for the feature. Without this, the agent can skip testing and push broken code. The block makes testing structurally enforced by the assembly pipeline rather than relying on CLAUDE.md honor system.

**Independent Test**: Enable `qa.enabled: true` in config, run `tricycle assemble`, verify the assembled `trc.implement.md` contains the QA testing block between task-execution and push-deploy sections. Manually verify the block content includes configured test commands.

**Acceptance Scenarios**:

1. **Given** a project with `qa.enabled: true` and `apps[].test` defined, **When** `tricycle assemble` runs, **Then** the assembled `trc.implement.md` includes the QA testing block with the configured test commands injected.
2. **Given** the QA testing block is active and a test command fails, **When** the agent reaches the QA block during implement, **Then** the agent halts, reports the failure, and does not proceed to the push-deploy block.
3. **Given** a project with `qa.enabled: false` or `qa` section omitted, **When** `tricycle assemble` runs, **Then** the QA testing block is NOT included in the assembled implement command.

---

### User Story 2 - Multi-step testing with instructions file (Priority: P2)

A developer has a complex testing workflow (Docker services, dev servers, MCP browser testing) that cannot be reduced to a single command. They maintain a `qa/ai-agent-instructions.md` file describing prerequisites, setup order, and operational rules. When the agent reaches the QA block, the block instructs it to read this file and follow the guidance: verifying the local stack is running, asking the user if manual setup is needed, then proceeding through the test sequence.

**Why this priority**: Many real projects (e.g., polst) have multi-step testing that requires Docker, multiple dev servers, environment configuration, and browser-based QA. Instructions belong in a markdown file, not crammed into YAML config.

**Independent Test**: Create `qa/ai-agent-instructions.md` with multi-step setup guidance, enable qa, run `tricycle assemble`, verify the QA block instructs the agent to read the instructions file.

**Acceptance Scenarios**:

1. **Given** a project with `qa/ai-agent-instructions.md` present, **When** the agent reaches the QA block, **Then** it reads the instructions file and follows the guidance before running tests.
2. **Given** a project with `qa.enabled: true` but no instructions file, **When** the agent reaches the QA block, **Then** it proceeds directly to running configured test commands without setup guidance.

---

### User Story 3 - Agent appends testing learnings (Priority: P2)

During the QA process, the agent discovers operational knowledge about the testing workflow — faster ways to spin up the local stack, prerequisite commands that must run first, environment quirks, commands that hang and need flags. The QA block instructs the agent to append these learnings to `qa/ai-agent-instructions.md` so that future sessions benefit from accumulated knowledge.

**Why this priority**: Testing workflows evolve. Without a feedback loop, every session rediscovers the same issues. The instructions file becomes a living document that improves with each implementation cycle.

**Independent Test**: Run an implement cycle with QA enabled. Introduce a scenario where the agent discovers something new (e.g., a service needs a `--wait` flag). Verify the agent appends the learning to the instructions file.

**Acceptance Scenarios**:

1. **Given** the agent encounters a testing issue and resolves it (e.g., "need to run prisma generate before tests"), **When** the QA block completes, **Then** the agent appends the learning to `qa/ai-agent-instructions.md` with a clear heading and date.
2. **Given** the agent has no new learnings (everything worked as documented), **When** the QA block completes, **Then** the instructions file is not modified.
3. **Given** `qa/ai-agent-instructions.md` does not exist, **When** the agent has learnings to record, **Then** the agent creates the file with the learnings.

---

### User Story 4 - QA skill integration (Priority: P3)

A developer has the `qa-run` skill installed (from `modules/qa/`) and `qa.enabled: true`. The QA block includes a skill invocation for `/qa-run` after the unit test commands, enabling the agent to execute the full browser-based QA test plan against the local stack.

**Why this priority**: The `qa-run` skill already exists with Chrome DevTools and Playwright support, suite mapping, and Linear ticket creation for failures. Connecting it to the QA block completes the pipeline without duplicating functionality.

**Independent Test**: Install the qa-run skill, enable qa in config, assemble, and verify the block includes the `/qa-run` skill invocation after test commands.

**Acceptance Scenarios**:

1. **Given** qa-run skill is installed and `qa.enabled: true`, **When** `tricycle assemble` runs, **Then** the QA block includes a skill invocation for `/qa-run` after the configured test commands.
2. **Given** qa-run skill is NOT installed, **When** `tricycle assemble` runs, **Then** the QA block includes only the configured test commands and skips the skill invocation gracefully.

---

### Edge Cases

- What happens when `qa.enabled: true` but no `apps[].test` commands are defined? The block is still included (for `qa.instructions` or skill-only workflows) but warns that no test commands were found.
- What happens when tests fail after maximum retry attempts? The agent halts completely and reports failures. It does NOT fall through to push-deploy.
- What happens when the local stack is not running and cannot be started automatically? The agent follows `qa.instructions` guidance, and if the stack cannot be verified, asks the user for help rather than skipping tests.
- What happens when `qa-testing` block is manually enabled via `workflow.blocks.implement.enable` but `qa.enabled` is false? Manual block enable takes precedence — the block is included. Since the block reads config and files at runtime, it works the same either way.
- What happens when the agent discovers a learning that's already documented in the instructions file? The agent skips appending duplicates — it reads existing content before deciding whether to append.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Assembly pipeline MUST include the `qa-testing` optional block in the implement step when `qa.enabled: true` in config, without requiring manual `workflow.blocks.implement.enable` entry.
- **FR-002**: The QA block MUST instruct the agent to read `tricycle.config.yml` at runtime and run all `apps[].test` commands. No assembly-time injection of test commands.
- **FR-003**: The QA block MUST instruct the agent to halt and not proceed to push-deploy if any test command exits with a non-zero status after retry attempts.
- **FR-004**: The QA block MUST instruct the agent to read `qa/ai-agent-instructions.md` when it exists and follow the guidance before running tests. Instructions live in this file, not in config.
- **FR-005**: The QA block MUST have an order value that places it after task-execution (order 50) and before push-deploy (order 65).
- **FR-006**: The QA block MUST support graceful invocation of the `qa-run` skill when installed, following the existing skill injection pattern.
- **FR-007**: The QA block MUST be a standard optional block file following existing block frontmatter conventions. The block is static markdown with no placeholder markers or assembly-time content injection.
- **FR-008**: The assembly pipeline MUST treat `qa.enabled: true` as an implicit enable for the `qa-testing` block, using the same pattern that config-driven flags use for auto-enabling optional blocks.
- **FR-009**: Manual enable via `workflow.blocks.implement.enable: [qa-testing]` MUST work independently of `qa.enabled`, allowing the block to be enabled without the full qa config section.
- **FR-010**: The QA block MUST instruct the agent to append operational learnings discovered during testing to `qa/ai-agent-instructions.md`, creating the file if it does not exist. Learnings are appended only when the agent encounters new information not already documented.

### Key Entities

- **QA Block**: An optional implement block template — static markdown with runtime instructions for the agent. No assembly-time content injection.
- **QA Instructions File**: `qa/ai-agent-instructions.md` — a living document of testing prerequisites, operational rules, and accumulated learnings. Read by the agent at runtime, appended to when new knowledge is discovered.
- **Config Surface**: `qa.enabled` in `tricycle.config.yml` toggles the block on/off. Test commands come from `apps[].test`. No other qa config fields needed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When QA is enabled, the agent cannot reach the push step without running every configured test command — verified by the presence of the QA block between task-execution and push-deploy in assembled output.
- **SC-002**: A project with multi-step testing requirements (Docker, multiple services, browser QA) can express its full setup workflow in `qa/ai-agent-instructions.md` and have the agent follow it without project-specific block customization.
- **SC-003**: Enabling QA requires only adding `qa.enabled: true` to config and running `tricycle assemble` — no manual block enables, hook installation, or CLAUDE.md changes needed.
- **SC-005**: After three implement cycles with QA enabled, the `qa/ai-agent-instructions.md` file contains accumulated operational knowledge that reduces setup friction in subsequent sessions.
- **SC-004**: Existing projects without `qa.enabled` experience zero changes to their assembled implement command.

## Assumptions

- The QA block is static markdown. The agent reads test commands from `tricycle.config.yml` and instructions from `qa/ai-agent-instructions.md` at runtime. No assembly-time content injection is needed.
- The `qa-run` skill invocation within the QA block follows the existing skill injection pattern — conditional on the skill being installed.
- The block's halt directive is enforced by prompt instructions to the agent (same enforcement model as push-approval in push-deploy), not by hooks or external tooling.
- The `test-local-stack` optional block (order 45) remains a separate, simpler block for projects that want basic integration testing without the full QA pipeline. It is not replaced or absorbed by this feature.
- Learnings appended to `qa/ai-agent-instructions.md` are additive — the agent never rewrites or removes existing content, only appends under a dated section.
