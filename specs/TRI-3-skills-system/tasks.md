# Tasks: Skills System

**Input**: Design documents from `specs/TRI-3-skills-system/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Included — the project has an existing test suite and CLAUDE.md mandates passing tests before completion.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project setup needed — existing project structure with established patterns.

_(No tasks — project is already initialized with bin/, core/, tests/ structure)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Helper functions in `bin/lib/helpers.sh` that are shared across multiple user stories. These MUST be complete before any user story work begins.

- [x] T001 Add `skill_checksum()` function to bin/lib/helpers.sh — finds all files in a skill directory (excluding SOURCE), sorts by relative path, concatenates contents, returns SHA256 (first 16 chars) via `sha256_str`
- [x] T002 Add `generate_source_file()` function to bin/lib/helpers.sh — accepts skill_dir, origin, and commit args; calls `skill_checksum` to compute checksum; writes SOURCE file in plain-text key-value format (origin, commit, installed date, checksum)
- [x] T003 Add `install_skills()` function to bin/lib/helpers.sh — iterates subdirectories of a source skills dir, reads `skills.disable` list from CONFIG_DATA via `cfg_get`, skips disabled skills with info message, calls `install_dir` per non-disabled skill, then calls `generate_source_file` for each installed skill
- [x] T004 Add `fetch_external_skill()` function to bin/lib/helpers.sh — parses source URI (github: or local:), for github sources uses `git clone --depth=1 --filter=blob:none --sparse` into temp dir then sparse-checkout and copy, for local sources validates path and copies directory, generates SOURCE file, returns 0 on success / 1 on failure

**Checkpoint**: All helper functions ready — user story implementation can now begin.

---

## Phase 3: User Story 1 - Default Skills Available After Init (Priority: P1) MVP

**Goal**: Users get 5 curated default skills (code-reviewer, tdd, debugging, document-writer, monorepo-structure) installed in `.claude/skills/` when they run `tricycle init`.

**Independent Test**: Run `tricycle init` in a fresh temp directory and verify all 5 skills are present in `.claude/skills/` with SKILL.md and SOURCE files.

### Implementation for User Story 1

- [x] T005 [P] [US1] Create code-reviewer skill in core/skills/code-reviewer/ — add SKILL.md (with name, description, user-invocable frontmatter), README.md, and SOURCE file noting origin as vendored:core/skills/code-reviewer from anthropics/skills
- [x] T006 [P] [US1] Create tdd skill in core/skills/tdd/ — add SKILL.md (Red-Green-Refactor workflow), README.md, and SOURCE file noting origin as vendored:core/skills/tdd from anthropics/skills
- [x] T007 [P] [US1] Create debugging skill in core/skills/debugging/ — add SKILL.md (structured reproduce-isolate-fix workflow), README.md, and SOURCE file noting origin as vendored:core/skills/debugging from anthropics/skills
- [x] T008 [P] [US1] Create document-writer skill in core/skills/document-writer/ — add SKILL.md (DOCX/PDF/PPTX generation), README.md, and SOURCE file noting origin as vendored:core/skills/document-writer from anthropics/skills
- [x] T009 [US1] Add SOURCE file to existing core/skills/monorepo-structure/SOURCE — record origin as vendored:core/skills/monorepo-structure with current commit hash
- [x] T010 [US1] Modify `cmd_init()` in bin/tricycle — replace `install_dir "$TOOLKIT_ROOT/core/skills" ".claude/skills"` (line ~190) with call to `install_skills "$TOOLKIT_ROOT/core/skills" ".claude/skills"`, then add loop over `skills.install` entries calling `fetch_external_skill`
- [x] T011 [US1] Add skills to `cmd_update()` in bin/tricycle — add skills update logic using `install_skills` with the same disable filtering, iterate skills with per-directory checksum comparison (vendored skills), and add external skill re-fetch for `skills.install` entries

**Checkpoint**: `tricycle init` installs all 5 default skills with SOURCE files. `tricycle update` includes skills in its update cycle. User Story 1 is fully functional.

---

## Phase 4: User Story 2 - Disable Unwanted Default Skills (Priority: P2)

**Goal**: Users can add skill names to `skills.disable` in config to prevent those skills from being installed during init or update.

**Independent Test**: Add `skills.disable: [tdd, document-writer]` to tricycle.config.yml, run `tricycle init`, verify tdd and document-writer are absent while others are present.

### Implementation for User Story 2

- [x] T012 [US2] Add already-installed disabled skill detection to `install_skills()` in bin/lib/helpers.sh — when a skill is disabled but already exists in `.claude/skills/`, output info message: "NOTICE: .claude/skills/<name> is disabled but still installed (delete manually if unwanted)"

**Checkpoint**: Disable filtering works for both init and update. Core disable logic was built into `install_skills()` in T003. T012 adds the info message for the edge case of pre-existing disabled skills.

---

## Phase 5: User Story 3 - Install External Skills from Config (Priority: P2)

**Goal**: Users can specify external skill sources (GitHub repos or local paths) in `skills.install` config and have them fetched during init/update.

**Independent Test**: Add `skills.install: [{source: "local:.trc/skills/test-skill"}]` to config, create a test skill at that path, run `tricycle update`, verify it appears in `.claude/skills/`.

### Implementation for User Story 3

- [x] T013 [US3] Add external skill install loop to `cmd_init()` in bin/tricycle — after vendored skill installation, iterate `skills.install` entries via `cfg_count`/`cfg_get`, call `fetch_external_skill` for each, continue on failure per FR-012
- [x] T014 [US3] Add external skill install loop to `cmd_update()` in bin/tricycle — same pattern as init; skip if skill already installed and not modified; re-fetch if SOURCE checksum differs from current
- [x] T015 [US3] Handle name collision between external and vendored skills in `install_skills()` in bin/lib/helpers.sh — if an external skill has the same name as a vendored skill, external takes precedence with warning: "WARNING: external skill '<name>' overrides vendored default"

**Checkpoint**: External skills install from both GitHub and local sources. Failed fetches don't block other skills. Name collisions resolved with external precedence.

---

## Phase 6: User Story 4 - List Installed Skills (Priority: P3)

**Goal**: Users can run `tricycle skills list` to see all installed skills with source and modification status.

**Independent Test**: Install default + external skills, modify one, run `tricycle skills list`, verify output shows correct source types and modification status.

### Implementation for User Story 4

- [x] T016 [US4] Add `cmd_skills()` dispatcher and `cmd_skills_list()` to bin/tricycle — `cmd_skills` routes subcommands (only `list` for now), `cmd_skills_list` iterates `.claude/skills/*/`, reads SOURCE files, computes current checksum via `skill_checksum`, compares to stored checksum, formats tabular output with name/source/status columns per contracts/cli-commands.md
- [x] T017 [US4] Add "skills" to CLI argument routing and help text in bin/tricycle — add `skills)` case to the main command dispatch, add usage line to help output

**Checkpoint**: `tricycle skills list` displays all installed skills with accurate source and modification information.

---

## Phase 7: User Story 5 - Block Integration with Skills (Priority: P3)

**Goal**: Workflow blocks can reference installed skills with graceful degradation when skills are missing.

**Independent Test**: Verify block markdown includes conditional skill invocation pattern. Verify that when skill directory is absent, the agent skips the instruction.

### Implementation for User Story 5

- [x] T018 [US5] Add conditional skill invocation to push-deploy block in core/blocks/implement/push-deploy.md — add instruction: "If `.claude/skills/code-review/SKILL.md` exists, invoke `/code-review` on staged changes before requesting push approval. If the skill is not installed, skip this step."

**Checkpoint**: Push-deploy block references code-review skill with graceful degradation. Pattern is documented for future block authors.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Testing, validation, and version management.

- [x] T019 [P] Add skills test group to tests/run-tests.sh — test cases: init installs all 5 vendored skills, SOURCE files present with correct format, disable config skips listed skills, update preserves modified skills, skills list command outputs correctly, invalid skill names rejected
- [x] T020 [P] Create tests/test-skills.js — Node.js tests for skills config parsing: verify yaml_parser handles skills.install and skills.disable sections, verify cfg_count and cfg_get return correct values for skills config
- [x] T021 Bump version from 0.5.1 to 0.6.0 in VERSION file
- [x] T022 Run full test suite (`bash tests/run-tests.sh` and `node --test tests/test-*.js`) and fix any failures

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: N/A — existing project
- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS all user stories.
- **US1 (Phase 3)**: Depends on Foundational (T001-T004). This is the MVP.
- **US2 (Phase 4)**: Depends on US1 (T003 provides install_skills with disable support, T010-T011 integrate it).
- **US3 (Phase 5)**: Depends on Foundational (T004 provides fetch_external_skill) and US1 (T010-T011 for CLI integration points).
- **US4 (Phase 6)**: Depends on Foundational (T001-T002 for checksum/source functions). Can run in parallel with US2/US3.
- **US5 (Phase 7)**: No code dependencies — can run in parallel with US2/US3/US4.
- **Polish (Phase 8)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — MVP, no cross-story dependencies
- **US2 (P2)**: Depends on US1 (install_skills function and CLI integration)
- **US3 (P2)**: Depends on Foundational + US1 (CLI integration points)
- **US4 (P3)**: Depends on Foundational only — reads .claude/skills/ state, no write dependencies
- **US5 (P3)**: No dependencies — pure markdown edit

### Within Each User Story

- Vendored skill creation tasks (T005-T008) can all run in parallel
- CLI integration tasks (T010-T011) must follow helper function creation
- Test tasks (T019-T020) can run in parallel with each other

### Parallel Opportunities

- T005, T006, T007, T008 — all vendor skill creation tasks (different directories)
- T016, T017 — skills list implementation and CLI routing (different functions)
- T019, T020 — bash and Node.js test files (different files)
- US4 and US5 — no mutual dependencies, can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all vendored skill creation tasks together:
Task: "Create code-reviewer skill in core/skills/code-reviewer/"
Task: "Create tdd skill in core/skills/tdd/"
Task: "Create debugging skill in core/skills/debugging/"
Task: "Create document-writer skill in core/skills/document-writer/"

# Then sequentially:
Task: "Add SOURCE to monorepo-structure"
Task: "Modify cmd_init() to use install_skills()"
Task: "Add skills to cmd_update()"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T001-T004)
2. Complete Phase 3: User Story 1 (T005-T011)
3. **STOP and VALIDATE**: Run `tricycle init` in a temp dir, verify 5 skills installed
4. This alone delivers significant value — users get curated defaults

### Incremental Delivery

1. Foundational → helpers ready
2. US1 → Default skills ship with init (MVP!)
3. US2 → Users can disable unwanted skills
4. US3 → Users can install external skills
5. US4 → Users can see skill inventory
6. US5 → Blocks reference skills
7. Polish → Tests, version bump, validation
8. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Vendoring skills (T005-T008) requires checking anthropics/skills repo for current skill content and adapting to Tricycle's SKILL.md format
- The existing `install_dir()`/`install_file()` infrastructure handles checksum tracking automatically — no custom lock logic needed for vendored skills
- External skill fetching (T004) requires git to be installed; the function should validate this before attempting sparse checkout
