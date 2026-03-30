# Tasks: Stealth Mode

**Input**: Design documents from `/specs/TRI-21-stealth-mode/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Included — plan.md defines 7 test cases in `tests/test-stealth-mode.js`.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No external dependencies to install. Ensure `.git/info/exclude` directory structure exists for the default stealth target.

- [x] T001 Ensure `.git/info/` directory exists and `exclude` file is present in bin/tricycle (add to `cmd_generate_gitignore`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The marker-based block removal helper is needed by all stealth operations (enable, disable, target switch).

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Add `stealth_remove_block()` helper function to bin/tricycle — accepts a file path, removes everything between `# >>> tricycle stealth` and `# <<< tricycle stealth` markers (inclusive), preserves all other content

**Checkpoint**: Helper ready — stealth enable/disable paths can now be implemented.

---

## Phase 3: User Story 1 + User Story 2 — Enable Stealth Mode & Assemble Respects It (Priority: P1) MVP

**Goal**: When `stealth.enabled: true` is set in config, `cmd_generate_gitignore()` writes a comprehensive ignore block to the configured target file (`.git/info/exclude` by default). All tricycle-managed paths are invisible to git. Assemble inherits this because it calls `cmd_generate_gitignore()`.

**Independent Test**: Set `stealth.enabled: true` in `tricycle.config.yml`, run `tricycle generate gitignore`, verify `.git/info/exclude` contains the stealth block and `git status` shows no tricycle files.

### Implementation

- [x] T003 [US1] Refactor `cmd_generate_gitignore()` in bin/tricycle:483-509 — read `stealth.enabled` and `stealth.ignore_target` via `cfg_get`/`cfg_get_or`; branch into stealth vs normal paths
- [x] T004 [US1] Implement stealth path in `cmd_generate_gitignore()` in bin/tricycle — determine target file (`$CWD/.git/info/exclude` or `$CWD/.gitignore`), call `stealth_remove_block` on BOTH targets, write stealth block with markers to chosen target
- [x] T005 [US1] Implement normal path in `cmd_generate_gitignore()` in bin/tricycle — call `stealth_remove_block` on both targets (handles toggle-off), then write existing normal-mode block to `.gitignore` (preserve current behavior)
- [x] T006 [US2] Verify assemble integration — run `tricycle assemble` with stealth enabled, confirm `.claude/commands/` output is covered by stealth ignore rules (no code change expected; validation only)

**Checkpoint**: Stealth mode can be enabled. All tricycle files are invisible to git. Assemble output is covered.

---

## Phase 4: User Story 3 — Switching Between Stealth and Normal Mode (Priority: P2)

**Goal**: Toggling `stealth.enabled` between `true` and `false` and re-running generate cleanly adds or removes stealth rules without disturbing user-authored ignore rules.

**Independent Test**: Enable stealth, run generate, verify stealth block present. Disable stealth, run generate, verify stealth block removed AND normal-mode block restored in `.gitignore`.

### Implementation

- [x] T007 [US3] Add idempotency guard in `cmd_generate_gitignore()` in bin/tricycle — check if stealth block already exists before writing (prevent duplicates on repeated runs)
- [x] T008 [US3] Handle target switching in `cmd_generate_gitignore()` in bin/tricycle — when `ignore_target` changes, remove block from old target before writing to new target (already covered by "remove from BOTH" strategy; add test to validate)

**Checkpoint**: Mode can be toggled freely. Rules are cleanly added/removed.

---

## Phase 5: User Story 4 — Stealth Config Not Committed + Init Integration (Priority: P2)

**Goal**: The stealth config itself (`tricycle.config.yml`) is invisible to git. `cmd_init()` writes ignore rules BEFORE installing files so nothing ever appears in `git status`.

**Independent Test**: Run `tricycle init` with stealth preset/config, verify `tricycle.config.yml` never appears in `git status` at any point during init.

### Implementation

- [x] T009 [US4] Modify `cmd_init()` in bin/tricycle:88-232 — when `stealth.enabled` is true in the loaded config, call `cmd_generate_gitignore()` immediately after config write (line ~178) and BEFORE `install_dir()` calls (line ~187)
- [x] T010 [US4] Update interactive wizard config template in bin/tricycle:147-174 — add `stealth:` section with `enabled: false` and `ignore_target: exclude` defaults
- [x] T011 [P] [US4] Update preset config templates (if any exist in presets/) — add `stealth:` section with defaults

**Checkpoint**: Init workflow fully supports stealth. Config is self-hiding.

---

## Phase 6: Tests

**Purpose**: Validate all stealth mode behaviors.

- [x] T012 [P] Create test file tests/test-stealth-mode.js — set up test scaffolding with temp git repos, config fixture helpers, and `cmd_generate_gitignore` invocation wrapper
- [x] T013 [P] Test stealth enable → exclude target in tests/test-stealth-mode.js — set `stealth.enabled: true`, run generate, assert `.git/info/exclude` contains stealth block with all 6 paths
- [x] T014 [P] Test stealth enable → gitignore target in tests/test-stealth-mode.js — set `ignore_target: gitignore`, run generate, assert `.gitignore` contains stealth block
- [x] T015 [P] Test stealth disable (toggle off) in tests/test-stealth-mode.js — enable then disable, assert stealth block removed from target AND normal block restored in `.gitignore`
- [x] T016 [P] Test target switch in tests/test-stealth-mode.js — switch from `exclude` to `gitignore`, assert old target cleaned, new target has block
- [x] T017 [P] Test idempotent writes in tests/test-stealth-mode.js — run generate twice with same config, assert no duplicate blocks
- [x] T018 [P] Test user rules preserved in tests/test-stealth-mode.js — add custom rules to target file, run generate, assert custom rules intact

**Checkpoint**: All 7 test cases pass. `bash tests/run-tests.sh` green.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T019 Bump VERSION file from 0.10.0 to 0.11.0 in VERSION
- [x] T020 Run full test suite via `bash tests/run-tests.sh` and `node --test tests/test-*.js`
- [x] T021 Run quickstart.md validation — walk through quickstart steps in a temp repo to verify accuracy

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No dependencies on Phase 1 (can start in parallel)
- **US1+US2 (Phase 3)**: Depends on Phase 2 (needs `stealth_remove_block` helper)
- **US3 (Phase 4)**: Depends on Phase 3 (needs stealth path implemented)
- **US4 (Phase 5)**: Depends on Phase 3 (needs `cmd_generate_gitignore` stealth-aware)
- **Tests (Phase 6)**: Depends on Phase 3 (needs stealth functionality to test)
- **Polish (Phase 7)**: Depends on all previous phases

### User Story Dependencies

- **US1+US2 (P1)**: Can start after Foundational (Phase 2) — no other story dependencies
- **US3 (P2)**: Depends on US1+US2 (toggle-off needs the stealth path to exist)
- **US4 (P2)**: Depends on US1+US2 (init integration needs `cmd_generate_gitignore` stealth-aware); can run in parallel with US3

### Within Each User Story

- T003 before T004 (refactor sets up branch, stealth path fills it)
- T004 before T005 (stealth path before normal path, but both in same function)
- T009 before T010 (init logic before template)

### Parallel Opportunities

- T001 and T002 can run in parallel (different concerns)
- T004 and T005 can potentially be done together (same function, different branches)
- T010 and T011 can run in parallel (different files)
- All test tasks T012-T018 can be written in parallel (same file, different test blocks)
- US3 (Phase 4) and US4 (Phase 5) can run in parallel after Phase 3

---

## Parallel Example: Tests (Phase 6)

```bash
# All test cases can be written together:
Task: "Test stealth enable → exclude in tests/test-stealth-mode.js"
Task: "Test stealth enable → gitignore in tests/test-stealth-mode.js"
Task: "Test stealth disable in tests/test-stealth-mode.js"
Task: "Test target switch in tests/test-stealth-mode.js"
Task: "Test idempotent writes in tests/test-stealth-mode.js"
Task: "Test user rules preserved in tests/test-stealth-mode.js"
```

---

## Implementation Strategy

### MVP First (User Stories 1+2 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002)
3. Complete Phase 3: US1+US2 (T003-T006)
4. **STOP and VALIDATE**: Test stealth enable manually — `git status` should show no tricycle files
5. This is a usable feature at this point

### Incremental Delivery

1. Setup + Foundational → Helper ready
2. Add US1+US2 → Stealth works (MVP!)
3. Add US3 → Toggle on/off cleanly
4. Add US4 → Init workflow supports stealth from first run
5. Add Tests → Regression protection
6. Polish → Version bump, validation

---

## Notes

- All changes are in `bin/tricycle` (single file) plus one new test file
- No changes to `assemble-commands.sh`, workflow commands, or session hooks
- The stealth block content (6 paths) is defined in data-model.md
- Marker format (`# >>> tricycle stealth` / `# <<< tricycle stealth`) enables clean removal
