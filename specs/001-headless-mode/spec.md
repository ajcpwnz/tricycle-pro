# Feature Specification: Headless Mode

**Feature Branch**: `001-headless-mode`
**Created**: 2026-03-24
**Status**: Draft
**Input**: User description: "Add headless mode. When running '/trc.headless <prompt>', it should go through specify-plan-tasks-implement chain automatically without skipping any steps and not waiting for user input unless critical clarifications needed or destructive actions are pending."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - End-to-End Headless Execution (Priority: P1)

A developer has a feature idea and wants to go from description to
working implementation with a single command. They run
`/trc.headless <prompt>` and the system executes the full
specify → plan → tasks → implement chain automatically, producing
all standard artifacts (spec.md, plan.md, tasks.md, code) without
requiring interaction at each phase transition.

**Why this priority**: This is the core value proposition — reducing
the multi-step manual workflow to a single invocation. Without this,
the feature has no purpose.

**Independent Test**: Run `/trc.headless "add a hello-world CLI
command"` on a clean project and verify that spec.md, plan.md,
tasks.md are all created, implementation code is written, and
lint/tests pass — all without any user interaction.

**Acceptance Scenarios**:

1. **Given** a project with Tricycle Pro initialized,
   **When** the user runs `/trc.headless "add a config validation
   command"`,
   **Then** the system creates a feature branch, generates spec.md,
   plan.md, tasks.md, implements all tasks, and runs lint/tests —
   completing the full chain without pausing.

2. **Given** a headless run is in progress,
   **When** the specify phase completes,
   **Then** the plan phase begins automatically using the generated
   spec without waiting for user confirmation.

3. **Given** a headless run reaches the implement phase,
   **When** all tasks are executed and lint/tests pass,
   **Then** the system reports completion with a summary of all
   artifacts produced and test results, but does NOT push code or
   create a PR (push gating still applies).

---

### User Story 2 - Critical Pause Points (Priority: P2)

During headless execution, the system encounters a situation that
requires human judgment — either a critical ambiguity in the
feature description that cannot be safely resolved with defaults,
or a destructive action is about to be performed. The system pauses,
presents the issue clearly, waits for user input, and then resumes
the chain from where it left off.

**Why this priority**: Without pause points, headless mode could
silently make wrong decisions or perform irreversible actions. This
is the safety mechanism that makes headless mode trustworthy.

**Independent Test**: Run `/trc.headless` with a deliberately
ambiguous prompt that triggers a clarification question. Verify the
system pauses, accepts input, updates the spec, and resumes the
chain automatically.

**Acceptance Scenarios**:

1. **Given** a headless run is in the specify phase,
   **When** a critical clarification is needed (scope-impacting
   ambiguity with no reasonable default),
   **Then** the system pauses, presents the question with options,
   waits for the user's answer, incorporates it into the spec, and
   resumes the chain.

2. **Given** a headless run has completed implementation,
   **When** the user is asked about pushing code,
   **Then** the system always pauses for explicit push approval per
   constitution Principle III (this is never auto-resolved).

3. **Given** a headless run encounters a destructive action (file
   deletion, branch reset, database migration),
   **Then** the system pauses with a clear description of what it
   intends to do and waits for user approval before proceeding.

4. **Given** a headless run pauses for user input,
   **When** the user provides their response,
   **Then** the chain resumes from the exact point it paused — it
   does not restart the current phase or skip ahead.

---

### User Story 3 - Progress Visibility (Priority: P3)

During a headless run, the developer wants to know what phase the
system is currently executing and see a completion summary when the
chain finishes. This provides confidence that no steps were skipped
and all artifacts were properly produced.

**Why this priority**: Useful for trust and debugging but the chain
functions correctly without it. Enhances usability rather than
enabling core functionality.

**Independent Test**: Run `/trc.headless` with a simple feature and
verify that phase transition messages appear during execution and
a structured summary is printed at completion.

**Acceptance Scenarios**:

1. **Given** a headless run is in progress,
   **When** the system transitions from one phase to the next,
   **Then** a brief status message is displayed indicating the
   completed phase and the next phase starting.

2. **Given** a headless run completes successfully,
   **When** all phases have finished,
   **Then** a completion summary is displayed listing: branch name,
   all artifacts produced (with file paths), lint/test results,
   and any actions still requiring user approval (e.g., push).

3. **Given** a headless run fails mid-chain,
   **When** a phase cannot complete (e.g., lint failure after
   retry attempts),
   **Then** the system reports which phase failed, what the error
   was, what artifacts were successfully produced up to that point,
   and suggests next steps.

---

### Edge Cases

- What happens when the user provides an empty prompt?
  The system MUST reject the invocation immediately with a clear
  error message: "No feature description provided."

- What happens when lint or tests fail during implementation?
  The system MUST attempt to diagnose and fix the issue (up to 3
  retry cycles). If still failing, it MUST pause and report the
  failure to the user rather than silently continuing.

- What happens when the feature description is so vague that
  multiple phases produce low-quality artifacts?
  The specify phase's existing 3-clarification limit applies.
  Non-critical gaps are filled with informed guesses and documented
  as assumptions. The system does not add additional pause points
  beyond what each individual phase already defines.

- What happens if Tricycle Pro is not initialized in the project?
  The system MUST detect missing prerequisites (tricycle.config.yml,
  .trc/ directory) and fail fast with an actionable error.

- What happens if a previous headless run left partial artifacts?
  The system MUST detect existing spec directories for the same
  feature and warn the user, offering to resume or start fresh.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `/trc.headless <prompt>` MUST execute the full
  specify → plan → tasks → implement chain in strict sequence,
  with no phases skipped.
- **FR-002**: Each phase MUST complete fully and produce its
  standard artifacts before the next phase begins.
- **FR-003**: The system MUST auto-resolve non-critical decisions
  using informed guesses and reasonable defaults, documenting
  assumptions made.
- **FR-004**: The system MUST pause for user input only when:
  (a) a critical clarification is needed that cannot be safely
  defaulted, (b) a destructive or irreversible action is pending,
  or (c) push/PR approval is required (per constitution).
- **FR-005**: After a pause, the chain MUST resume from the exact
  point where it paused — no phase restarts or skips.
- **FR-006**: The system MUST enforce all constitution principles
  during headless execution, including lint/test gates and push
  approval requirements.
- **FR-007**: The system MUST display phase transition messages
  and a completion summary.
- **FR-008**: The system MUST fail fast with a clear error if
  prerequisites are missing (empty prompt, uninitialized project).
- **FR-009**: The system MUST pass the feature description through
  to the specify phase unmodified — the headless command is an
  orchestrator, not a transformer of user intent.
- **FR-010**: The system MUST produce all artifacts that the
  individual commands would produce when run manually (spec.md,
  plan.md, research.md, data-model.md, contracts/, tasks.md,
  and implementation code).

### Key Entities

- **Headless Session**: A single end-to-end execution of the
  specify → plan → tasks → implement chain, initiated by one
  `/trc.headless` invocation. Tracks current phase, pause state,
  and produced artifacts.
- **Phase**: One step in the chain (specify, plan, tasks,
  implement). Has a defined entry condition, execution logic,
  exit condition, and set of artifacts it produces.
- **Pause Point**: A moment where the system halts automatic
  execution and requests user input. Categorized as: critical
  clarification, destructive action, or push approval.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can go from feature idea to working
  implementation with lint/tests passing using a single command
  invocation (excluding pause points for critical decisions).
- **SC-002**: 100% of artifacts produced by individual manual
  commands are also produced during headless execution — no
  artifacts are skipped or incomplete.
- **SC-003**: The system never performs a destructive action or
  pushes code without explicit user approval during headless mode.
- **SC-004**: Phase transitions happen automatically without user
  intervention for features that have no critical ambiguities.
- **SC-005**: When a pause is required, the user can provide input
  and the chain resumes without re-executing completed work.
