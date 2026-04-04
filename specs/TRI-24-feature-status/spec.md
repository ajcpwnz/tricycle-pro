# Feature Specification: Tricycle Status Command

**Feature Branch**: `TRI-24-feature-status`
**Created**: 2026-04-04
**Status**: Draft
**Input**: User description: "Add a `tricycle status` CLI command that scans specs/ and displays each feature's progress through the workflow chain"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View All Feature Progress at a Glance (Priority: P1)

As a developer working on a tricycle-managed project, I want to run `tricycle status` and immediately see which workflow stage each feature is at, so I can understand the state of in-flight work without manually inspecting directories.

**Why this priority**: This is the core value proposition — a single command replaces manual directory inspection. Without this, the feature has no purpose.

**Independent Test**: Can be fully tested by creating a specs/ directory with sample feature folders containing various combinations of artifact files, running `tricycle status`, and verifying the output table is accurate and readable.

**Acceptance Scenarios**:

1. **Given** a project with three features at different workflow stages (one with only spec.md, one with spec.md + plan.md + tasks.md, one fully complete), **When** the user runs `tricycle status`, **Then** the output displays a table showing each feature's ID, name, progress bar, and current stage label.
2. **Given** a project with features using `issue-number` branching style (e.g., `TRI-23-local-config-overrides`), **When** the user runs `tricycle status`, **Then** the issue prefix and number are extracted and displayed as a separate column from the feature name slug.
3. **Given** a project where features are at every possible stage (specify, plan, tasks, implement, done), **When** the user runs `tricycle status`, **Then** each stage is correctly identified and the progress bar visually reflects completion percentage.

---

### User Story 2 - Machine-Readable Output for Scripting (Priority: P2)

As a developer who wants to integrate tricycle status into other tools or CI pipelines, I want to run `tricycle status --json` and get structured JSON output, so I can programmatically parse feature progress.

**Why this priority**: Extends the core feature for automation use cases. Valuable but not essential for the primary human-readable use case.

**Independent Test**: Can be tested by running `tricycle status --json` against a known specs/ layout and validating the JSON structure and values with a JSON parser.

**Acceptance Scenarios**:

1. **Given** a project with multiple features at various stages, **When** the user runs `tricycle status --json`, **Then** the output is valid JSON containing an array of objects, each with fields for feature ID, name, stage, and progress percentage.
2. **Given** the JSON output, **When** parsed by a standard JSON tool (e.g., `jq`), **Then** all fields are correctly typed (strings for ID/name/stage, number for progress).

---

### User Story 3 - Status of a Single Feature (Priority: P3)

As a developer focused on one specific feature, I want to run `tricycle status <feature-id>` and see detailed progress for just that feature, so I can quickly check where I left off.

**Why this priority**: Nice-to-have convenience filter. The full list already shows this information, but filtering reduces noise for projects with many features.

**Independent Test**: Can be tested by running `tricycle status TRI-24` and verifying it shows only that feature's progress, or returns a clear "not found" message for unknown IDs.

**Acceptance Scenarios**:

1. **Given** a project with multiple features, **When** the user runs `tricycle status TRI-24`, **Then** only TRI-24's progress is displayed.
2. **Given** a feature ID that does not exist in specs/, **When** the user runs `tricycle status TRI-999`, **Then** a clear error message is shown: "No feature found matching TRI-999".

---

### Edge Cases

- What happens when `specs/` directory does not exist or is empty? Display a message: "No features found. Run /trc.specify to start a new feature."
- What happens when a feature directory exists but contains no recognized artifact files? Show the feature with 0% progress and stage "empty".
- What happens when a feature directory name does not follow the expected naming convention? Include it in the output with the full directory name as the feature name, no parsed ID.
- How does the command handle a feature where tasks.md exists but has no tasks checked off vs. some tasks checked off vs. all tasks checked off? Distinguish between "tasks" stage (tasks generated but not started), "implement" stage (some tasks checked off), and "done" (all tasks checked off).
- What happens when the terminal is narrow? Progress bars should degrade gracefully — shorter bars or text-only fallback.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST scan the `specs/` directory for feature subdirectories.
- **FR-002**: System MUST detect the presence of workflow artifacts (`spec.md`, `plan.md`, `tasks.md`) in each feature directory to determine the current stage.
- **FR-003**: System MUST determine completion by checking whether all task items in `tasks.md` are marked done (checked off).
- **FR-004**: System MUST display output as a formatted table with columns: feature ID, feature name, progress bar, and stage label.
- **FR-005**: System MUST parse feature directory names to extract issue IDs when the branching style is `issue-number` (e.g., `TRI-24-feature-status` → ID: `TRI-24`, name: `feature-status`).
- **FR-006**: System MUST support a `--json` flag that outputs structured JSON instead of the human-readable table.
- **FR-007**: System MUST support an optional positional argument to filter output to a single feature by ID or directory name.
- **FR-008**: System MUST work with Bash 3.2+ (macOS default shell).
- **FR-009**: System MUST display a helpful message when no features are found.
- **FR-010**: System MUST integrate as a new subcommand in the existing `tricycle` CLI entrypoint.

### Key Entities

- **Feature**: A directory under `specs/` representing a unit of work. Has a name, optional issue ID, and a set of workflow artifacts.
- **Workflow Stage**: One of `specify`, `plan`, `tasks`, `implement`, or `done` — derived from which artifacts exist and task completion state.
- **Progress**: A fixed percentage per stage: specify=25%, plan=50%, tasks=75%, implement=80%, done=100%. Features with no artifacts show 0%.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can assess the status of all in-flight features in under 2 seconds by running a single command.
- **SC-002**: The output correctly identifies the workflow stage for 100% of features in the specs/ directory.
- **SC-003**: The command produces valid, parseable JSON when the `--json` flag is used.
- **SC-004**: The command handles projects with zero features, one feature, and ten or more features without errors or degraded readability.

## Clarifications

### Session 2026-04-04

- Q: How should progress percentage scale during the implement stage? → A: Fixed per-stage mapping: specify=25%, plan=50%, tasks=75%, implement=80%, done=100%.

## Assumptions

- The workflow chain is always the default `[specify, plan, tasks, implement]` for progress calculation purposes. Custom chain lengths are out of scope for the initial version.
- Task completion is determined by counting `- [x]` vs `- [ ]` lines in `tasks.md`. No deeper parsing of task structure is needed.
- Feature directories in `specs/` always correspond to real features. Stale or orphaned directories are shown as-is.
- The progress bar uses Unicode block characters (e.g., `█` and `░`). Terminals that do not support Unicode will see fallback characters.
