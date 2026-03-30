# Tasks: QA Testing Block

**Input**: Design documents from `/specs/TRI-20-qa-testing-block/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included — the existing test suite (`test-block-assembly.js`) must cover assembly behavior.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this is an existing codebase. Setup covers reading existing code to understand integration points.

- [X] T001 Read `core/scripts/bash/assemble-commands.sh` to identify where `apply_overrides` is called in `assemble_step()` and where feature flag enables should be prepended
- [X] T002 Read `core/scripts/bash/common.sh` to verify `cfg_get` can read `qa.enabled` from config and determine if a `cfg_get_bool` helper is needed
- [X] T003 Read `core/blocks/implement/push-deploy.md` and `core/blocks/implement/task-execution.md` to reference the HALT directive pattern and per-phase test gate pattern

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The auto-enable mechanism must exist before the block can be tested in assembled output.

- [X] T004 Add `compute_feature_flag_enables()` function to `core/scripts/bash/assemble-commands.sh` that reads `qa.enabled` via `cfg_get` and returns `enable=qa-testing` for the implement step when true
- [X] T005 Wire `compute_feature_flag_enables()` into `assemble_step()` — call it after `parse_block_overrides` and prepend the result to the overrides string before passing to `apply_overrides`

**Checkpoint**: The auto-enable mechanism is in place. `qa.enabled: true` in config will now cause `apply_overrides` to look for `qa-testing` block — it won't find one yet (created in Phase 3).

---

## Phase 3: User Story 1 - Agent enforces testing before push (Priority: P1)

**Goal**: QA block exists, auto-enables via config, instructs agent to run all configured tests, and halts before push on failure.

**Independent Test**: Set `qa.enabled: true` in `tricycle.config.yml`, run `tricycle assemble --dry-run`, verify `trc.implement.md` contains QA testing section between task-execution and push-deploy. Set `qa.enabled: false`, re-assemble, verify section is absent.

### Implementation for User Story 1

- [X] T006 [US1] Create `core/blocks/optional/implement/qa-testing.md` with block frontmatter (name: qa-testing, step: implement, order: 55, required: false, default_enabled: false) and core content: read `tricycle.config.yml` for `apps[].test` commands, run each test command, retry logic (max 3 fix attempts), HALT gate (do NOT proceed to push-deploy on failure)
- [X] T007 [US1] Add test case to `tests/test-block-assembly.js` — verify that with `qa.enabled: true` in a test config, assembled `trc.implement.md` includes the qa-testing block content
- [X] T008 [US1] Add test case to `tests/test-block-assembly.js` — verify that with `qa.enabled: false` or qa section absent, assembled `trc.implement.md` does NOT include qa-testing block content
- [X] T009 [US1] Add test case to `tests/test-block-assembly.js` — verify that manual `workflow.blocks.implement.enable: [qa-testing]` includes the block even when `qa.enabled` is absent

**Checkpoint**: QA block assembles correctly based on config. Core enforcement (run tests, halt on failure) is in the block template.

---

## Phase 4: User Story 2 - Multi-step testing with instructions file (Priority: P2)

**Goal**: Block instructs agent to read `qa/ai-agent-instructions.md` before running tests.

**Independent Test**: The instructions-read directive is in the block content — verify by reading the assembled output and confirming it references the instructions file path.

### Implementation for User Story 2

- [X] T010 [US2] Add instructions file reading section to `core/blocks/optional/implement/qa-testing.md` — directive to read `qa/ai-agent-instructions.md` if it exists and follow guidance before running test commands, skip gracefully if file absent

**Checkpoint**: Block now reads external instructions before testing. No assembly changes needed — this is block content only.

---

## Phase 5: User Story 3 - Agent appends testing learnings (Priority: P2)

**Goal**: Block instructs agent to append operational discoveries to the instructions file.

**Independent Test**: Verify the learnings-append directive is present in the assembled block content.

### Implementation for User Story 3

- [X] T011 [US3] Add learnings append section to `core/blocks/optional/implement/qa-testing.md` — directive to append new operational knowledge under a dated `## Learnings` heading, read existing content first to avoid duplicates, create file if absent

**Checkpoint**: Block now has the feedback loop — agent reads instructions, runs tests, and writes back what it learned.

---

## Phase 6: User Story 4 - QA skill integration (Priority: P3)

**Goal**: The `qa-run` skill can be invoked via standard skill injection when installed.

**Independent Test**: Add `qa-run` to `workflow.blocks.implement.skills` in config, assemble, verify the skill invocation section appears in assembled output.

### Implementation for User Story 4

- [X] T012 [US4] Verify existing skill injection handles `qa-run` — add `qa-run` to `workflow.blocks.implement.skills` in a test config and confirm assembled output includes the skill invocation. No code changes expected — this should work with existing skill injection logic.

**Checkpoint**: Full QA pipeline (instructions → unit tests → qa-run skill → learnings) is assembled correctly.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and final validation.

- [X] T013 [P] Update `modules/qa/README.md` to document the qa-testing block, `qa.enabled` config surface, `qa/ai-agent-instructions.md` file convention, and learnings append behavior
- [X] T014 Run full test suite: `bash tests/run-tests.sh` and `node --test tests/test-*.js` — fix any failures
- [X] T015 Run `tricycle validate` to confirm no structural issues
- [X] T016 Run quickstart.md validation — manually verify the user-facing setup steps work

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — read-only exploration
- **Foundational (Phase 2)**: Depends on Setup — creates the auto-enable mechanism
- **US1 (Phase 3)**: Depends on Foundational — creates the block file and tests
- **US2 (Phase 4)**: Depends on US1 — adds content to the block file created in US1
- **US3 (Phase 5)**: Depends on US1 — adds content to the block file created in US1
- **US4 (Phase 6)**: Depends on US1 — validates skill injection with existing mechanism
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational (Phase 2) only — core block + auto-enable
- **US2 (P2)**: Depends on US1 — extends block content (same file)
- **US3 (P2)**: Depends on US1 — extends block content (same file)
- **US4 (P3)**: Depends on US1 — validates existing mechanism against new block

### Within Each User Story

- Block content before tests (block must exist to test assembly)
- Assembly tests validate the assembled output
- T010 and T011 can run in parallel (different sections of the same file, but separate content additions)

### Parallel Opportunities

- T001, T002, T003 (Setup reads) can run in parallel
- T007, T008, T009 (US1 test cases) can run in parallel after T006
- T010 and T011 (US2 + US3 block content) can run in parallel after T006
- T013 (README update) can run in parallel with T014-T016

---

## Parallel Example: User Story 1

```bash
# After T006 (block file created), launch tests in parallel:
Task: "T007 — test qa.enabled: true includes block"
Task: "T008 — test qa.enabled: false excludes block"
Task: "T009 — test manual enable works independently"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (read existing code)
2. Complete Phase 2: Foundational (auto-enable function)
3. Complete Phase 3: User Story 1 (block + tests)
4. **STOP and VALIDATE**: `tricycle assemble --dry-run` with qa enabled/disabled
5. This alone delivers the core value — testing is enforced before push

### Incremental Delivery

1. Setup + Foundational → Auto-enable mechanism ready
2. Add US1 → Core QA block with test enforcement (MVP)
3. Add US2 → Instructions file support for complex workflows
4. Add US3 → Learnings feedback loop
5. Add US4 → QA-run skill integration
6. Polish → Documentation, final validation

---

## Notes

- US2, US3, US4 are all content additions to the same block file created in US1
- The assembly script changes are limited to Phase 2 (~15 lines of bash)
- No changes to `common.sh` if `cfg_get` already handles boolean-like values
- The block file is the primary deliverable — most of the feature is prompt engineering
