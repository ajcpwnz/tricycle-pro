# Tasks: Tricycle Status Command

**Input**: Design documents from `/specs/TRI-24-feature-status/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create the status module and wire it into the CLI

- [x] T001 Create `bin/lib/status.sh` with file header, function stubs for `status_detect_stage`, `status_parse_dir_name`, `status_progress_for_stage`, `status_render_bar`, and `status_scan`
- [x] T002 Add `source "$SCRIPT_DIR/lib/status.sh"` to the library loading section in `bin/tricycle`
- [x] T003 Add `status` subcommand to the dispatch `case` statement and `show_help()` in `bin/tricycle`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core detection and parsing functions that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement `status_detect_stage DIR_PATH` in `bin/lib/status.sh` — check for `tasks.md` (count `- [x]` vs `- [ ]`), then `plan.md`, then `spec.md` existence; return stage string (done/implement/tasks/plan/specify/empty)
- [x] T005 [P] Implement `status_parse_dir_name DIR_NAME` in `bin/lib/status.sh` — parse `TRI-XX-slug` pattern (set `STATUS_ID` and `STATUS_NAME`), fall back to `NNN-slug`, fall back to full dir name
- [x] T006 [P] Implement `status_progress_for_stage STAGE` in `bin/lib/status.sh` — return fixed percentage: empty=0, specify=25, plan=50, tasks=75, implement=80, done=100

**Checkpoint**: Core detection functions ready — user story implementation can begin

---

## Phase 3: User Story 1 — View All Feature Progress (Priority: P1) MVP

**Goal**: `tricycle status` scans `specs/` and displays a formatted table with ID, name, progress bar, and stage for every feature

**Independent Test**: Create temp dir with sample specs/ subdirectories at various stages, run `tricycle status`, verify table output matches expected format

### Implementation for User Story 1

- [x] T007 [US1] Implement `status_render_bar PROGRESS` in `bin/lib/status.sh` — render 12-char Unicode progress bar using `█` (filled) and `░` (empty) based on percentage
- [x] T008 [US1] Implement `status_scan` table output path in `bin/lib/status.sh` — iterate `specs/*/`, call detect/parse/progress/render for each, printf aligned columns (ID, name, bar, stage)
- [x] T009 [US1] Implement `cmd_status` in `bin/tricycle` — call `status_scan` with appropriate args, handle empty specs/ message ("No features found. Run /trc.specify to start a new feature.")
- [x] T010 [US1] Add integration tests for `tricycle status` table output in `tests/run-tests.sh` — create temp dir with 3 feature dirs at different stages, verify output contains expected IDs and stage labels

**Checkpoint**: `tricycle status` displays a table of all features with progress bars

---

## Phase 4: User Story 2 — Machine-Readable JSON Output (Priority: P2)

**Goal**: `tricycle status --json` outputs a valid JSON array with feature objects

**Independent Test**: Run `tricycle status --json` against known specs/ layout, pipe through a JSON validator

### Implementation for User Story 2

- [x] T011 [US2] Add `--json` flag parsing to the argument parser in `bin/tricycle` (set `STATUS_JSON=1`), pass to `cmd_status`
- [x] T012 [US2] Implement JSON output path in `status_scan` in `bin/lib/status.sh` — use `json_kv`, `json_kv_raw`, `json_escape` from `json_builder.sh` to emit `[{"id":...,"name":...,"dir":...,"stage":...,"progress":N},...]`
- [x] T013 [US2] Add integration tests for `--json` output in `tests/run-tests.sh` — verify output is valid JSON (parseable by `node -e`), contains expected fields and types

**Checkpoint**: `tricycle status --json` produces valid, parseable JSON

---

## Phase 5: User Story 3 — Single Feature Filter (Priority: P3)

**Goal**: `tricycle status TRI-24` shows only the matching feature, or a clear error for unknown IDs

**Independent Test**: Run with a known feature ID and verify single-row output; run with unknown ID and verify error message

### Implementation for User Story 3

- [x] T014 [US3] Add filter positional argument handling in `cmd_status` in `bin/tricycle` — pass filter string to `status_scan`
- [x] T015 [US3] Implement filter logic in `status_scan` in `bin/lib/status.sh` — match filter against `STATUS_ID` or dir name, skip non-matching entries, print "No feature found matching <filter>" if no matches
- [x] T016 [US3] Add integration tests for filter in `tests/run-tests.sh` — test matching by ID, matching by dir name, and not-found error message

**Checkpoint**: All three user stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, comprehensive tests, and cleanup

- [x] T017 [P] Add Node.js unit tests in `tests/test-status.js` — test `status_detect_stage` with all stage combinations (empty dir, spec-only, plan+spec, tasks with 0/some/all checked), test `status_parse_dir_name` with TRI-XX, NNN, and freeform dir names
- [x] T018 [P] Add edge case integration tests in `tests/run-tests.sh` — empty specs/ dir, feature dir with no artifacts (stage=empty), non-standard directory names
- [x] T019 Run full test suite (`bash tests/run-tests.sh`) and fix any failures

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001 (status.sh exists) — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 completion
- **US2 (Phase 4)**: Depends on Phase 2 + T009 (cmd_status wired up)
- **US3 (Phase 5)**: Depends on Phase 2 + T009 (cmd_status wired up)
- **Polish (Phase 6)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: After Foundational — no dependencies on other stories
- **US2 (P2)**: After Foundational + T009 — uses same scan loop, adds JSON branch
- **US3 (P3)**: After Foundational + T009 — uses same scan loop, adds filter branch

### Within Each User Story

- Implementation before tests (tests validate the implementation)
- Core logic before CLI wiring

### Parallel Opportunities

- T005 and T006 can run in parallel (different functions, no dependencies)
- T017 and T018 can run in parallel (different test files)
- US2 and US3 could theoretically run in parallel after US1

---

## Parallel Example: Foundational Phase

```bash
# After T004, these can run in parallel:
Task: "T005 — Implement status_parse_dir_name in bin/lib/status.sh"
Task: "T006 — Implement status_progress_for_stage in bin/lib/status.sh"
```

## Parallel Example: Polish Phase

```bash
# These can run in parallel:
Task: "T017 — Node.js unit tests in tests/test-status.js"
Task: "T018 — Edge case integration tests in tests/run-tests.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T006)
3. Complete Phase 3: User Story 1 (T007-T010)
4. **STOP and VALIDATE**: Run `tricycle status` against real specs/ directory
5. Demo-ready with table output

### Incremental Delivery

1. Setup + Foundational → Core functions ready
2. Add US1 → Table output works → Demo-ready MVP
3. Add US2 → JSON output works → Scriptable
4. Add US3 → Filtering works → Polished
5. Polish → Edge cases handled, full test coverage

---

## Notes

- All code must be Bash 3.2+ compatible (no associative arrays, no `mapfile`)
- Reuse existing `json_builder.sh` for JSON — do not add `jq` dependency
- `status.sh` follows the same pattern as `helpers.sh`, `assemble.sh` — sourced library, no standalone execution
- 19 total tasks across 6 phases
