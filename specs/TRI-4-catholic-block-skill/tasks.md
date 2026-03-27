# Tasks: Catholic Block & Skill

**Input**: Design documents from `specs/TRI-4-catholic-block-skill/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Tests**: Included — project has existing test suite.

**Organization**: Tasks grouped by user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

_(No setup needed — existing project structure)_

---

## Phase 2: Foundational

_(No foundational tasks — all work is self-contained per user story)_

---

## Phase 3: User Story 1 - Catholic Skill (Priority: P1) MVP

**Goal**: Catholic skill installed in `core/skills/catholic/` that instructs Claude to apply Christian verbiage to non-code artifacts.

**Independent Test**: Install skill, invoke `/catholic`, verify output contains faith-inspired language.

### Implementation for User Story 1

- [x] T001 [P] [US1] Create core/skills/catholic/SKILL.md — YAML frontmatter (name: catholic, description) and markdown body with instructions: apply reverent Christian verbiage (blessings, gratitude, Providence references) to specs, plans, tasks, READMEs; explicitly exclude source code, tests, config, shell scripts; tone guide with examples
- [x] T002 [P] [US1] Create core/skills/catholic/README.md — skill description, usage (`/catholic`), how to enable via config, customization notes
- [x] T003 [US1] Create core/skills/catholic/SOURCE — origin vendored:core/skills/catholic with current commit hash and date

**Checkpoint**: Skill exists and can be invoked manually via `/catholic`.

---

## Phase 4: User Story 2 - Catholic Block (Priority: P2)

**Goal**: Optional block fires early in specify step with prayer and closing blessing.

**Independent Test**: Enable block in config, run `tricycle assemble`, verify assembled trc.specify.md contains prayer content.

### Implementation for User Story 2

- [x] T004 [US2] Create core/blocks/optional/specify/catholic.md — frontmatter (name: catholic, step: specify, required: false, default_enabled: false, order: 1) and markdown body with opening prayer for feature success and closing blessing/thanksgiving instruction

**Checkpoint**: Block exists. When enabled via `workflow.blocks.specify.enable: [catholic]` and assembled, trc.specify.md contains the prayer.

---

## Phase 5: User Story 3 - README Update (Priority: P3)

**Goal**: README documents the catholic block and skill.

**Independent Test**: Read README, find catholic section with config examples.

### Implementation for User Story 3

- [x] T005 [US3] Update README.md — add section documenting the catholic block and skill: what they do, how to enable (config example with `workflow.blocks.specify.enable` and `workflow.blocks.specify.skills`), how to disable, tone description

**Checkpoint**: README contains catholic documentation.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T006 [P] Add catholic skill test to tests/run-tests.sh — verify core/skills/catholic/SKILL.md exists, has valid frontmatter with name field, SOURCE file present
- [x] T007 [P] Add catholic block test to tests/run-tests.sh — verify core/blocks/optional/specify/catholic.md exists, has correct frontmatter (order: 1, required: false, default_enabled: false)
- [x] T008 Bump version from 0.6.0 to 0.7.0 in VERSION file
- [x] T009 Run full test suite and fix any failures

---

## Dependencies & Execution Order

### Phase Dependencies

- **US1 (Phase 3)**: No dependencies — start immediately
- **US2 (Phase 4)**: No dependencies — can run in parallel with US1
- **US3 (Phase 5)**: Depends on US1 and US2 being defined (needs to document them)
- **Polish (Phase 6)**: Depends on all user stories complete

### Parallel Opportunities

- T001, T002 — skill files (different files)
- T006, T007 — test additions (different test groups)
- US1 and US2 — entirely independent (different directories)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete US1 (T001-T003) — skill exists
2. **STOP and VALIDATE**: `/catholic` is available as a slash command
3. This alone delivers the core value

### Incremental Delivery

1. US1 → Skill available for manual use
2. US2 → Block auto-triggers prayer during specify
3. US3 → README documents everything
4. Polish → Tests, version bump

---

## Notes

- This is a small feature: 3 new files (skill), 1 new file (block), 1 modified file (README)
- No code logic changes — purely markdown content
- The skill and block are independent: skill works without block, block degrades gracefully without skill
