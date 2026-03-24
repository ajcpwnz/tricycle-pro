# Tasks: Headless Mode

**Input**: Design documents from `/specs/001-headless-mode/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No test tasks generated — tests were not explicitly requested in the spec. Existing test suite (`tests/cli.test.js`) is updated in the Polish phase to cover the new command file.

**Organization**: Tasks are grouped by user story. Since this feature is primarily a single markdown command file, US1 creates the file with core orchestration logic, US2 adds pause-point rules, and US3 adds progress/summary formatting. Each story's additions are independently valuable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the command file skeleton

- [X] T001 Create core/commands/trc.headless.md with YAML frontmatter (description field, no handoffs) and the User Input section with $ARGUMENTS placeholder

---

## Phase 2: User Story 1 - End-to-End Headless Execution (Priority: P1) MVP

**Goal**: A single `/trc.headless <prompt>` command that runs the full specify → plan → tasks → implement chain without stopping at phase transitions.

**Independent Test**: Run `/trc.headless "add a hello-world CLI command"` and verify spec.md, plan.md, tasks.md are created and implementation code is written — all without user interaction.

### Implementation for User Story 1

- [X] T002 [US1] Write the input validation section in core/commands/trc.headless.md: reject empty prompts with "No feature description provided", check for tricycle.config.yml and .specify/ directory existence, detect partial artifacts from prior runs
- [X] T003 [US1] Write the specify phase orchestration section in core/commands/trc.headless.md: invoke /trc.specify with the user's prompt, instruct auto-resolution of non-critical clarifications with informed guesses (max 3 NEEDS CLARIFICATION markers, auto-resolve where possible), auto-proceed through checklist validation
- [X] T004 [US1] Write the plan phase orchestration section in core/commands/trc.headless.md: invoke /trc.plan using the generated spec, auto-continue without waiting for user input
- [X] T005 [US1] Write the tasks phase orchestration section in core/commands/trc.headless.md: invoke /trc.tasks using the generated plan, auto-continue without waiting for user input
- [X] T006 [US1] Write the implement phase orchestration section in core/commands/trc.headless.md: invoke /trc.implement using the generated tasks, enforce lint/test gates per constitution Principle II, do NOT push code or create PR (push gating per Principle III)

**Checkpoint**: At this point, `/trc.headless` should execute the full chain for unambiguous feature descriptions without any pauses.

---

## Phase 3: User Story 2 - Critical Pause Points (Priority: P2)

**Goal**: The system pauses for critical clarifications, destructive actions, and push approval, then resumes the chain from the exact pause point.

**Independent Test**: Run `/trc.headless "add authentication"` (deliberately vague) and verify the system pauses for clarification, accepts input, and resumes the chain.

### Implementation for User Story 2

- [X] T007 [US2] Add pause point rules section in core/commands/trc.headless.md: define the three pause categories (critical clarification with no safe default, destructive/irreversible action, push/PR approval per constitution Principle III), specify that push approval is NEVER auto-resolved
- [X] T008 [US2] Add resume behavior instructions in core/commands/trc.headless.md: after user responds to a pause, continue the chain from the exact point where it paused — no phase restarts, no skips. Include lint/test failure handling (attempt fix up to 3 retries, then pause and report)

**Checkpoint**: At this point, `/trc.headless` should correctly pause for critical situations and resume after user input.

---

## Phase 4: User Story 3 - Progress Visibility (Priority: P3)

**Goal**: Phase transition messages and a structured completion/failure summary give the user confidence that no steps were skipped.

**Independent Test**: Run `/trc.headless` with a simple feature and verify phase transition messages and completion summary appear.

### Implementation for User Story 3

- [X] T009 [US3] Add phase transition message format in core/commands/trc.headless.md: output "--- Phase N/4: [Phase Name] --- [status]" between phases
- [X] T010 [US3] Add completion summary format in core/commands/trc.headless.md: on success, display branch name, all artifact paths, lint/test results, and pending actions (push approval). On failure, display failed phase, error description, completed artifacts, and suggested next steps.

**Checkpoint**: At this point, `/trc.headless` is fully functional with all three user stories implemented.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Install the command, update tests, validate

- [X] T011 [P] Copy core/commands/trc.headless.md to .claude/commands/trc.headless.md
- [X] T012 [P] Add 'trc.headless.md' to the expected commands array in tests/cli.test.js (line ~68 in the 'all command templates exist' test)
- [X] T013 Run lint for all affected code: npm run lint
- [X] T014 Run tests: node --test tests/

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **User Story 1 (Phase 2)**: Depends on T001 (file must exist to write into)
- **User Story 2 (Phase 3)**: Depends on US1 completion (pause rules augment the orchestration logic)
- **User Story 3 (Phase 4)**: Depends on US1 completion (progress messages wrap the orchestration logic)
- **Polish (Phase 5)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Setup — no dependencies on other stories
- **User Story 2 (P2)**: Depends on US1 — pause rules reference the phase execution sections
- **User Story 3 (P3)**: Depends on US1 — progress messages reference phase transitions. Can run in parallel with US2.

### Within Each User Story

- T002 before T003 (validation before orchestration)
- T003 → T004 → T005 → T006 (phases are sequential sections in the file)
- T007 before T008 (define pauses before resume behavior)
- T009 and T010 can run in parallel (independent sections)

### Parallel Opportunities

- T011 and T012 are parallel (different files)
- T009 and T010 are parallel within US3 (independent sections)
- US2 and US3 can run in parallel after US1 completes (but since all write to the same file, sequential is safer)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: User Story 1 (T002-T006)
3. **STOP and VALIDATE**: Test with a simple feature description
4. The command should run the full chain without pauses

### Incremental Delivery

1. Setup → US1 → Test (MVP: full chain works)
2. Add US2 → Test (pause points work)
3. Add US3 → Test (progress messages appear)
4. Polish → Install + tests pass

---

## Notes

- All tasks modify or create files in core/commands/ and tests/
- The primary deliverable is a single markdown file (core/commands/trc.headless.md)
- Tasks T002-T010 all write to the same file — execute sequentially
- T011 and T012 touch different files — safe to parallelize
- No new npm dependencies required
- Commit after each phase or logical group
