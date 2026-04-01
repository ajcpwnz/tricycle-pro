# Tasks: Local Config Overrides

**Input**: Design documents from `/specs/TRI-23-local-config-overrides/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Included — plan.md specifies `tests/test-local-config.js` as a deliverable.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No new project structure needed — this feature modifies existing files only.

- [x] T001 Verify working directory and branch are correct (TRI-23-local-config-overrides worktree)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core merge infrastructure that all user stories depend on.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Add OVERRIDABLE_PREFIXES whitelist array constant in bin/lib/helpers.sh — define overridable prefixes: `push.`, `qa.`, `worktree.`, `workflow.blocks.`, `stealth.`
- [x] T003 Implement `merge_config_data()` function in bin/lib/helpers.sh — accepts two flat key-value datasets (base, override), returns merged dataset where override scalars win and override arrays replace base arrays entirely (detect arrays by numeric index pattern `prefix.N.` or `prefix.N=`)
- [x] T004 Implement `validate_override()` function in bin/lib/helpers.sh — iterate override keys, warn on any key whose prefix is not in OVERRIDABLE_PREFIXES, return filtered override data containing only valid keys

**Checkpoint**: Core merge functions ready — user story implementation can begin.

---

## Phase 3: User Story 1 — Developer creates a local config override (Priority: P1) MVP

**Goal**: A developer can create `tricycle.config.local.yml` with a subset of fields and have tricycle automatically merge them over the base config at runtime.

**Independent Test**: Create an override file with `qa: { enabled: true }` when base has it disabled, run a tricycle command, verify `cfg_get qa.enabled` returns `true`.

### Implementation for User Story 1

- [x] T005 [US1] Modify `load_config()` in bin/lib/helpers.sh to detect `$CWD/tricycle.config.local.yml`, parse it with `parse_yaml()`, call `validate_override()` and `merge_config_data()`, and set CONFIG_DATA to the merged result
- [x] T006 [US1] Add graceful degradation in `load_config()` in bin/lib/helpers.sh — if override file exists but is unreadable or has invalid YAML, emit warning with filename and error context, fall back to base config only (FR-009)
- [x] T007 [US1] Handle edge case in `load_config()` in bin/lib/helpers.sh — if override file is empty or contains no valid overridable keys, behavior is identical to no override file (no error, no warning unless non-overridable keys are present)

**Checkpoint**: Local config override loading works end-to-end. All tricycle commands that call `load_config()` automatically get merged config.

---

## Phase 4: User Story 2 — Override file stays out of version control (Priority: P1)

**Goal**: The override file is automatically excluded from VCS so developers cannot accidentally commit personal config.

**Independent Test**: Create `tricycle.config.local.yml`, run `git status`, verify it does not appear as untracked.

### Implementation for User Story 2

- [x] T008 [P] [US2] Update `cmd_generate_gitignore()` normal-mode block in bin/tricycle — add `tricycle.config.local.yml` pattern to the gitignore block (after the `.tricycle.lock` line)
- [x] T009 [P] [US2] Update `cmd_generate_gitignore()` stealth-mode block in bin/tricycle — add explicit `tricycle.config.local.yml` line to stealth block (or widen `tricycle.config.yml` to `tricycle.config*.yml`)
- [x] T010 [US2] Ensure `.trc/local/` directory is excluded in both normal and stealth mode blocks in bin/tricycle — add `.trc/local/` pattern for the local overlay commands directory

**Checkpoint**: Override file and local overlay directory are invisible to git in both normal and stealth modes.

---

## Phase 5: User Story 3 — Assemble output does not clash between developers (Priority: P1)

**Goal**: Two developers with different local overrides produce identical committed assembly output. Local differences are isolated in a gitignored overlay directory.

**Independent Test**: Run `tricycle assemble` with and without an override file, verify `.claude/commands/` output is identical in both cases while `.trc/local/commands/` contains the locally-influenced variant.

### Implementation for User Story 3

- [x] T011 [US3] Implement `flat_to_yaml()` helper function in bin/lib/helpers.sh — reconstruct valid YAML from merged flat key-value data so the assembly script can consume it via `--config=<file>`
- [x] T012 [US3] Modify `cmd_assemble()` in bin/lib/assemble.sh — after pass 1 (base config → `.claude/commands/`), detect `$CWD/tricycle.config.local.yml`; if present, generate merged temp YAML via `flat_to_yaml()`, run pass 2 with `--config=<temp> --output-dir=$CWD/.trc/local/commands`, clean up temp file
- [x] T013 [US3] Update `core/hooks/session-context.sh` to detect `.trc/local/commands/` at session start — if overlay directory exists and contains `.md` files, append a context note listing available local command variants and instructing Claude to prefer them

**Checkpoint**: Assembly two-pass strategy works. Committed commands are always from base config. Local overlay commands are generated when overrides exist.

---

## Phase 6: User Story 4 — Developer discovers which fields are overridable (Priority: P2)

**Goal**: Clear feedback when a developer tries to override a non-overridable field, plus documentation of what is overridable.

**Independent Test**: Create an override file with `project: { name: "wrong" }`, run a tricycle command, verify a warning is emitted naming the field and suggesting it cannot be overridden locally.

### Implementation for User Story 4

- [x] T014 [US4] Enhance `validate_override()` in bin/lib/helpers.sh — emit a specific warning per non-overridable key with format: `Warning: '${key}' cannot be overridden locally (shared team config). Overridable sections: push, qa, worktree, workflow.blocks, stealth.`

**Checkpoint**: Developers get actionable feedback when they attempt to override non-overridable fields.

---

## Phase 7: User Story 5 — Override file supports minimal content (Priority: P2)

**Goal**: An override file with as little as a single key-value pair works correctly with no boilerplate.

**Independent Test**: Create an override file containing only `worktree:\n  enabled: true`, run `load_config()`, verify worktree.enabled is true while all other config fields remain from base.

### Implementation for User Story 5

- [x] T015 [US5] Verify and handle edge cases in `merge_config_data()` in bin/lib/helpers.sh — single key override, deeply nested partial override (e.g., only `push.require_approval`), override with only array content, override with all empty values

**Checkpoint**: Minimal override files work exactly as expected with zero boilerplate.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Tests, validation, and cleanup across all user stories.

- [x] T016 [P] Create tests/test-local-config.js — test merge_config_data() with scalar override, array replacement, mixed overrides; test validate_override() with valid and invalid keys; test load_config() with override present, missing, empty, and invalid; test flat_to_yaml() round-trip
- [x] T017 [P] Add assembly two-pass tests to tests/test-local-config.js — test that cmd_assemble produces identical `.claude/commands/` output with and without override; test that `.trc/local/commands/` is generated only when override exists
- [x] T018 [P] Add VCS exclusion tests to tests/test-local-config.js — test normal-mode gitignore includes override file pattern; test stealth-mode block includes override file pattern; test `.trc/local/` is excluded
- [x] T019 Update tests/run-tests.sh to include test-local-config.js in the test suite
- [x] T020 Run full test suite (`bash tests/run-tests.sh`) and fix any failures
- [x] T021 Run quickstart.md validation — verify the documented workflow in specs/TRI-23-local-config-overrides/quickstart.md matches actual behavior

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — verify environment
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational (T002–T004) — core override loading
- **US2 (Phase 4)**: Depends on Setup only — can run in PARALLEL with US1 (different files: bin/tricycle vs bin/lib/helpers.sh)
- **US3 (Phase 5)**: Depends on US1 (needs merge logic) — two-pass assembly
- **US4 (Phase 6)**: Depends on Foundational (T004 validate_override exists) — can run in PARALLEL with US1/US3
- **US5 (Phase 7)**: Depends on US1 (needs load_config merge working) — edge case hardening
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — core feature
- **US2 (P1)**: No dependency on other stories — VCS exclusion is independent
- **US3 (P1)**: Depends on US1 — needs merge_config_data() and load_config() for temp YAML generation
- **US4 (P2)**: Depends on Foundational (validate_override) — enhancement to existing function
- **US5 (P2)**: Depends on US1 — edge case validation of merge logic

### Within Each User Story

- Core function implementation before integration
- Integration before edge case handling
- All changes validated by test suite in Polish phase

### Parallel Opportunities

- **T008 + T009**: Both update cmd_generate_gitignore() but different code blocks (normal vs stealth) — parallel with caution (same file)
- **US2 (Phase 4) || US1 (Phase 3)**: Different files entirely — full parallel
- **US4 (Phase 6) || US3 (Phase 5)**: Different files/functions — full parallel
- **T016 + T017 + T018**: All create/extend tests/test-local-config.js — sequential within file, but can be authored as one pass
- **Foundational T002 + T003 + T004**: All in helpers.sh but logically independent functions — sequential (same file)

---

## Parallel Example: After Foundational Phase

```bash
# These can run in parallel (different files):
# Stream A (bin/lib/helpers.sh):
Task: T005 [US1] Modify load_config() for override detection
Task: T006 [US1] Graceful degradation
Task: T007 [US1] Empty override edge case

# Stream B (bin/tricycle):
Task: T008 [US2] Normal-mode gitignore update
Task: T009 [US2] Stealth-mode gitignore update
Task: T010 [US2] .trc/local/ exclusion
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2 Only)

1. Complete Phase 2: Foundational (merge infra)
2. Complete Phase 3: US1 (override loading) + Phase 4: US2 (VCS exclusion) — in parallel
3. **STOP and VALIDATE**: Create a test `tricycle.config.local.yml`, run commands, verify overrides apply and file is gitignored
4. This delivers core value — developers can override config locally

### Incremental Delivery

1. Foundational → merge functions ready
2. US1 + US2 → Local override works, excluded from VCS (MVP!)
3. US3 → Two-pass assembly prevents committed output clashes
4. US4 → Validation warnings guide developers
5. US5 → Minimal content edge cases hardened
6. Polish → Tests, full validation

---

## Notes

- All implementation is in bash — no new language dependencies
- `parse_yaml()` is reused as-is for override file parsing
- `cfg_get()` / `cfg_has()` / `cfg_count()` require no changes — they read from CONFIG_DATA which is set by load_config()
- Assembly script (`core/scripts/bash/assemble-commands.sh`) requires no changes — it already accepts `--config=FILE` and `--output-dir=DIR`
- The override file name `tricycle.config.local.yml` follows `.local` convention (like `.env.local`)
