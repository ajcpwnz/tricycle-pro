# Tasks: Workflow Chains & Pluggable Blocks

**Input**: Design documents from `/specs/003-workflow-chains-blocks/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story. Block decomposition (US4) is placed in the Foundational phase because all other stories depend on blocks existing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory structure and foundational utility functions

- [X] T001 Create block directory structure: `core/blocks/specify/`, `core/blocks/plan/`, `core/blocks/tasks/`, `core/blocks/implement/`, `core/blocks/optional/implement/`
- [X] T002 Add block frontmatter parsing functions to `core/scripts/bash/common.sh`: `parse_block_frontmatter()` (extracts name, step, required, default_enabled, order from YAML frontmatter), `list_blocks_for_step()` (lists .md files in a step's block directory), `read_block_content()` (extracts body content below frontmatter)
- [X] T003 Add YAML workflow config parsing functions to `core/scripts/bash/common.sh`: `parse_chain_config()` (reads `workflow.chain` from `tricycle.config.yml`, defaults to full chain), `parse_block_overrides()` (reads `workflow.blocks.{step}.disable/enable/custom`), `validate_chain()` (checks chain is one of three valid variants, returns error message if invalid)

**Checkpoint**: Utility functions available for all subsequent tasks

---

## Phase 2: Foundational (Block Decomposition + Assembly Infrastructure)

**Purpose**: Decompose existing commands into blocks and build the assembly script. MUST complete before ANY user story work.

**⚠️ CRITICAL**: No chain or block feature work can begin until this phase is complete.

### Decompose trc.specify.md into blocks

- [X] T004 [P] Create `core/blocks/specify/feature-setup.md` — Extract the branch creation and `create-new-feature.sh` invocation logic from `.claude/commands/trc.specify.md` (the "Generate short name" + "Create feature branch" sections). Frontmatter: `name: feature-setup, step: specify, required: true, default_enabled: true, order: 10`
- [X] T005 [P] Create `core/blocks/specify/spec-writer.md` — Extract the spec content generation logic from `.claude/commands/trc.specify.md` (the "Load template", "Follow execution flow", "Write specification" sections including the Quick Guidelines, Section Requirements, and AI Generation guidance). Frontmatter: `name: spec-writer, step: specify, required: false, default_enabled: true, order: 40`
- [X] T006 [P] Create `core/blocks/specify/quality-validation.md` — Extract the quality validation workflow from `.claude/commands/trc.specify.md` (the "Specification Quality Validation" section including checklist creation, validation loop, NEEDS CLARIFICATION handling, and completion reporting). Frontmatter: `name: quality-validation, step: specify, required: false, default_enabled: true, order: 50`

### Decompose trc.plan.md into blocks

- [X] T007 [P] Create `core/blocks/plan/setup-context.md` — Extract from `.claude/commands/trc.plan.md` outline step 1 (run `setup-plan.sh --json`) and step 2 (load FEATURE_SPEC, constitution, IMPL_PLAN template). Frontmatter: `name: setup-context, step: plan, required: true, default_enabled: true, order: 20`
- [X] T008 [P] Create `core/blocks/plan/constitution-check.md` — Extract the Constitution Check section and gate evaluation from `.claude/commands/trc.plan.md` outline step 3 (fill Constitution Check, evaluate gates, re-evaluate post-design). Frontmatter: `name: constitution-check, step: plan, required: false, default_enabled: true, order: 30`
- [X] T009 [P] Create `core/blocks/plan/research.md` — Extract Phase 0 (Outline & Research) from `.claude/commands/trc.plan.md` (extract unknowns, generate research agents, consolidate findings into research.md). Frontmatter: `name: research, step: plan, required: false, default_enabled: true, order: 40`
- [X] T010 [P] Create `core/blocks/plan/design-contracts.md` — Extract Phase 1 (Design & Contracts) from `.claude/commands/trc.plan.md` (extract entities → data-model.md, define interface contracts → /contracts/, generate quickstart.md). Frontmatter: `name: design-contracts, step: plan, required: false, default_enabled: true, order: 50`
- [X] T011 [P] Create `core/blocks/plan/agent-context.md` — Extract the agent context update step from `.claude/commands/trc.plan.md` (run `update-agent-context.sh claude`). Frontmatter: `name: agent-context, step: plan, required: false, default_enabled: true, order: 60`
- [X] T012 [P] Create `core/blocks/plan/version-awareness.md` — Extract version awareness from `.claude/commands/trc.plan.md` outline step 4 (read VERSION file, note current version, plan minor/patch bump). Frontmatter: `name: version-awareness, step: plan, required: false, default_enabled: true, order: 70`

### Decompose trc.tasks.md into blocks

- [X] T013 [P] Create `core/blocks/tasks/prerequisites.md` — Extract from `.claude/commands/trc.tasks.md` outline step 1 (run `check-prerequisites.sh --json`, parse FEATURE_DIR and AVAILABLE_DOCS). Frontmatter: `name: prerequisites, step: tasks, required: true, default_enabled: true, order: 20`
- [X] T014 [P] Create `core/blocks/tasks/task-generation.md` — Extract from `.claude/commands/trc.tasks.md` outline steps 2-4 (load design documents, execute task generation workflow, generate tasks.md with phase structure) and the entire Task Generation Rules section (checklist format, task organization, phase structure). Frontmatter: `name: task-generation, step: tasks, required: false, default_enabled: true, order: 30`
- [X] T015 [P] Create `core/blocks/tasks/dependency-graph.md` — Extract from `.claude/commands/trc.tasks.md` outline step 5 (report with task counts, parallel opportunities, dependency graph, MVP scope, format validation). Frontmatter: `name: dependency-graph, step: tasks, required: false, default_enabled: true, order: 40`

### Decompose trc.implement.md into blocks

- [X] T016 [P] Create `core/blocks/implement/prerequisites.md` — Extract from `.claude/commands/trc.implement.md` outline step 1 (run `check-prerequisites.sh --json --require-tasks --include-tasks`). Do NOT include extensions.yml hook checking (deprecated per FR-020). Frontmatter: `name: prerequisites, step: implement, required: true, default_enabled: true, order: 20`
- [X] T017 [P] Create `core/blocks/implement/checklist-validation.md` — Extract from `.claude/commands/trc.implement.md` outline step 2 (scan checklists, create status table, ask user to proceed if incomplete). Frontmatter: `name: checklist-validation, step: implement, required: false, default_enabled: true, order: 30`
- [X] T018 [P] Create `core/blocks/implement/project-setup.md` — Extract from `.claude/commands/trc.implement.md` outline step 4 (Project Setup Verification — detect and create/verify ignore files for all technology stacks). Frontmatter: `name: project-setup, step: implement, required: false, default_enabled: true, order: 40`
- [X] T019 [P] Create `core/blocks/implement/task-execution.md` — Extract from `.claude/commands/trc.implement.md` outline steps 3, 5-9 (load context, parse tasks, execute phase-by-phase, TDD approach, progress tracking, error handling, completion validation). Frontmatter: `name: task-execution, step: implement, required: false, default_enabled: true, order: 50`
- [X] T020 [P] Create `core/blocks/implement/version-bump.md` — Extract from `.claude/commands/trc.implement.md` outline step 10 (read VERSION, bump minor/patch, write VERSION, include in final commit). Frontmatter: `name: version-bump, step: implement, required: false, default_enabled: true, order: 60`

### Create optional blocks

- [X] T021 [P] Create `core/blocks/optional/implement/test-local-stack.md` — New block with instructions for testing against a local infrastructure stack (Docker, local databases, dev servers). Frontmatter: `name: test-local-stack, step: implement, required: false, default_enabled: false, order: 45`

### Build assembly infrastructure

- [X] T022 Create the assembly script `core/scripts/bash/assemble-commands.sh` — Main assembly entry point that: (1) sources common.sh, (2) reads workflow config via `parse_chain_config()` and `parse_block_overrides()`, (3) validates chain via `validate_chain()`, (4) for each step in chain calls `assemble_step()` (collects blocks, applies overrides, sorts by order, concatenates content, writes to `core/commands/trc.{step}.md`), (5) for omitted steps calls `generate_blocked_stub()`, (6) calls `generate_headless()` for trc.headless.md, (7) supports `--dry-run` and `--verbose` flags per assembly-cli.md contract
- [X] T023 Create the assembly library `bin/lib/assemble.sh` — Library sourced by `bin/tricycle` that: (1) defines `cmd_assemble()` function, (2) parses `--dry-run` and `--verbose` CLI flags, (3) calls `core/scripts/bash/assemble-commands.sh` with appropriate arguments, (4) reports success/failure with file counts
- [X] T024 Add `assemble` subcommand to `bin/tricycle` — Register the assemble command in the main CLI dispatch: source `bin/lib/assemble.sh`, add `assemble` case to the command router, add help text entry for `tricycle assemble [--dry-run] [--verbose]`
- [X] T025 Verify default assembly produces identical output — Run `assemble-commands.sh` with default config (full chain, no block overrides) and diff the generated `core/commands/trc.{specify,plan,tasks,implement,headless}.md` files against the current versions. Fix any discrepancies until output matches exactly (zero regression baseline).

**Checkpoint**: All blocks exist, assembly script works, default assembly reproduces current behavior. User story work can now begin.

---

## Phase 3: User Story 1 - Configure Workflow Chain in YAML (Priority: P1) 🎯 MVP

**Goal**: Users can set `workflow.chain` in `tricycle.config.yml` and the system respects it across all commands.

**Independent Test**: Edit config to `chain: [specify, implement]`, run `tricycle assemble`, verify only specify + implement commands are full and others are blocked stubs. Run `/trc.headless` and verify only 2 phases execute.

### Implementation for User Story 1

- [X] T026 [US1] Create `core/blocks/specify/chain-validation.md` — Block that reads `tricycle.config.yml`, extracts `workflow.chain` (defaulting to full chain if missing), validates the chain is one of three valid variants, and checks that `specify` is in the chain (if not, outputs error and stops). Frontmatter: `name: chain-validation, step: specify, required: true, default_enabled: true, order: 20`
- [X] T027 [P] [US1] Create `core/blocks/plan/chain-validation.md` — Same pattern as T026 but checks that `plan` is in the configured chain. Frontmatter: `name: chain-validation, step: plan, required: true, default_enabled: true, order: 10`
- [X] T028 [P] [US1] Create `core/blocks/tasks/chain-validation.md` — Same pattern as T026 but checks that `tasks` is in the configured chain. Frontmatter: `name: chain-validation, step: tasks, required: true, default_enabled: true, order: 10`
- [X] T029 [P] [US1] Create `core/blocks/implement/chain-validation.md` — Same pattern as T026 but checks that `implement` is in the configured chain. Frontmatter: `name: chain-validation, step: implement, required: true, default_enabled: true, order: 10`
- [X] T030 [US1] Implement `generate_blocked_stub()` in `core/scripts/bash/assemble-commands.sh` — Function that generates a minimal command file for steps not in the chain. The stub contains YAML frontmatter with a description, the standard `## User Input` section, and a single instruction: "Error: Step '{step}' is not part of the configured workflow chain [{chain}]. To use this step, update `workflow.chain` in `tricycle.config.yml` and run `tricycle assemble`."
- [X] T031 [US1] Implement `generate_headless()` in `core/scripts/bash/assemble-commands.sh` — Function that generates `trc.headless.md` from the configured chain: (1) dynamically sets phase count to chain length, (2) generates Phase N/M sections for each chain step, (3) preserves headless behavior overrides (auto-continue, auto-resolve, pause rules) from the current trc.headless.md, (4) adjusts completion summary to list only chain-relevant artifacts
- [X] T032 [US1] Reassemble all commands with chain support — Run `assemble-commands.sh` with default config (full chain) to regenerate all `core/commands/trc.*.md` files. Verify chain-validation blocks are included. Test with `chain: [specify, plan, implement]` and `chain: [specify, implement]` to verify blocked stubs and headless adaptation.

**Checkpoint**: Chain configuration works. Commands blocked for omitted steps. Headless adapts to chain length.

---

## Phase 4: User Story 2 - Smart Step Absorption (Priority: P2)

**Goal**: Omitted steps' blocks merge into the preceding step during assembly, preserving capabilities.

**Independent Test**: Set `chain: [specify, plan, implement]`, run assembly, verify `trc.plan.md` contains task-generation and dependency-graph block content after plan's own blocks.

### Implementation for User Story 2

- [X] T033 [US2] Implement `get_absorbed_blocks()` in `core/scripts/bash/assemble-commands.sh` — Function that: (1) takes the configured chain and full canonical chain `[specify, plan, tasks, implement]`, (2) identifies omitted steps, (3) for each omitted step collects its non-required default-enabled blocks, (4) determines the absorption target (preceding step in canonical order), (5) applies order offset (+100 per absorbed step level), (6) returns the list of absorbed blocks with adjusted order values
- [X] T034 [US2] Integrate absorption into `assemble_step()` in `core/scripts/bash/assemble-commands.sh` — Modify the step assembly function to: (1) call `get_absorbed_blocks()`, (2) merge absorbed blocks with the step's own blocks, (3) sort combined list by order, (4) concatenate all content. Include a `## Absorbed from [{step}]` comment separator before absorbed block content for traceability.
- [X] T035 [US2] Verify absorption output for all chain variants — Test assembly with `[specify, plan, implement]` (tasks absorbed into plan) and `[specify, implement]` (plan+tasks absorbed into specify). Verify: (1) absorbed block content is present in the target command, (2) order values place absorbed content after the step's own content, (3) default full chain produces no absorption.

**Checkpoint**: Step absorption works. Shortened chains preserve all capabilities through block merging.

---

## Phase 5: User Story 3 - Input Validation for Shortened Chains (Priority: P3)

**Goal**: Specify step rejects too-concise prompts when the chain is shortened.

**Independent Test**: Set `chain: [specify, implement]`, run `/trc.specify "add auth"`, verify rejection. Run with detailed prompt, verify acceptance.

### Implementation for User Story 3

- [X] T036 [US3] Create `core/blocks/specify/input-validation.md` — Block containing chain-length-aware input validation guidelines: (1) Read the configured chain from `tricycle.config.yml`, (2) For full chain `[S,P,T,I]`: accept any non-empty prompt, (3) For 3-step `[S,P,I]`: prompt must describe scope and expected outcomes — reject if under ~2 sentences with guidance on what to add, (4) For 2-step `[S,I]`: prompt must describe scope, expected behavior, technical constraints, and acceptance criteria — reject if lacking these with specific guidance. Include example rejection messages. Frontmatter: `name: input-validation, step: specify, required: true, default_enabled: true, order: 30`
- [X] T037 [US3] Reassemble specify command and verify validation — Run assembly, verify the input-validation block appears in `trc.specify.md` between chain-validation (order 20) and spec-writer (order 40). Manually test with brief and detailed prompts for each chain length.

**Checkpoint**: Input validation prevents low-quality input for shortened chains.

---

## Phase 6: User Story 5 - Enable/Disable Blocks per Project (Priority: P5)

**Goal**: Users can customize which blocks are active via config overrides and custom block files.

**Independent Test**: Add `workflow.blocks.plan.disable: [design-contracts]` to config, run assembly, verify plan command skips contract generation content.

### Implementation for User Story 5

- [X] T038 [US5] Implement block override application in `assemble_step()` in `core/scripts/bash/assemble-commands.sh` — Extend the assembly function to: (1) read `workflow.blocks.{step}.disable` and remove matching blocks (error if block is `required: true`), (2) read `workflow.blocks.{step}.enable` and add matching optional blocks, (3) read `workflow.blocks.{step}.custom` and load custom block files (validate frontmatter step scope matches), (4) error if custom block file not found
- [X] T039 [US5] Implement all-blocks-disabled warning in `assemble_step()` in `core/scripts/bash/assemble-commands.sh` — After applying overrides, if zero blocks remain for a step (excluding required blocks which can't be disabled), output a warning: "Warning: All optional blocks disabled for step '{step}'. The step will only contain infrastructure blocks (chain validation, prerequisites)."
- [X] T040 [US5] Implement block scope validation in `core/scripts/bash/assemble-commands.sh` — When loading custom blocks, verify the block's `step` frontmatter matches the config section it's referenced in. If mismatched, error: "Block '{name}' declares step '{declared_step}' but is configured under '{config_step}'. Blocks can only be assigned to their declared step."
- [X] T041 [US5] Verify block customization end-to-end — Test: (1) disable `design-contracts` for plan, verify contracts content absent, (2) enable `test-local-stack` for implement, verify testing content present, (3) create a custom block file at `.trc/blocks/custom/test-custom.md` and reference it in config, verify content appears in assembled command, (4) attempt to disable required block, verify error, (5) attempt scope mismatch, verify error.

**Checkpoint**: Full block customization works. Users can disable, enable, and add custom blocks.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Constitution update, deprecation, init/update integration, tests, version bump

- [X] T042 Amend Constitution Principle I in `.trc/memory/constitution.md` — Update text from "Every feature MUST follow specify → plan → tasks → implement" to "Every feature MUST follow the configured workflow chain. The default chain is specify → plan → tasks → implement. Shortened chains are supported when configured in `tricycle.config.yml`." Bump version from 1.0.0 to 1.1.0. Update Sync Impact Report comment.
- [X] T043 [P] Remove extensions.yml hook checking from implement and tasks blocks — Verify that `core/blocks/implement/prerequisites.md` and `core/blocks/tasks/prerequisites.md` do NOT include any `.trc/extensions.yml` checking logic (it should have been excluded during decomposition in T013/T016, but verify and clean up if any remnants exist)
- [X] T044 [P] Update `bin/lib/init.sh` to sync blocks during `tricycle init` — Add block directory sync: copy `core/blocks/` to `.trc/blocks/` (same pattern as templates and scripts sync). Add block files to `.tricycle.lock` tracking with checksums. Ensure `tricycle init` also runs assembly after syncing blocks.
- [X] T045 [P] Update `bin/lib/update.sh` to handle block updates during `tricycle update` — Add block file update logic: compare checksums, update non-customized blocks, skip customized blocks with warning. Re-run assembly after block updates.
- [X] T046 [P] Write chain validation tests in `tests/test-chain-validation.js` — Test cases: (1) default chain when no workflow config, (2) all three valid chain variants accepted, (3) invalid chains rejected (missing specify, wrong order, unknown steps, duplicates), (4) chain with only specify or only implement rejected
- [X] T047 [P] Write block assembly tests in `tests/test-block-assembly.js` — Test cases: (1) default assembly matches current commands (regression test), (2) blocked stub generated for omitted steps, (3) absorption produces correct output for 3-step and 2-step chains, (4) block ordering is correct (lower order first), (5) custom blocks inserted at correct position
- [X] T048 [P] Write config parsing tests in `tests/test-config-parsing.js` — Test cases: (1) parse workflow.chain from YAML, (2) parse workflow.blocks overrides, (3) missing workflow section defaults correctly, (4) disable required block produces error, (5) custom block with wrong step scope produces error, (6) missing custom block file produces error
- [X] T049 Run full regression — Execute `tricycle assemble` with default config, diff all generated commands against pre-feature baseline. Run `npm run lint` and `node --test tests/` to verify all existing and new tests pass. Fix any issues.
- [X] T050 Version bump — Update `VERSION` file from `0.2.0` to `0.3.0`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) — BLOCKS all user stories
- **US1 Chain Config (Phase 3)**: Depends on Foundational (Phase 2)
- **US2 Absorption (Phase 4)**: Depends on US1 (Phase 3) — needs chain awareness in assembly
- **US3 Input Validation (Phase 5)**: Depends on US1 (Phase 3) — needs chain reading
- **US5 Block Customization (Phase 6)**: Depends on Foundational (Phase 2) — independent of US1-US3
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 2 — needs blocks + assembly infrastructure
- **US2 (P2)**: Depends on US1 — needs chain config to know what's omitted
- **US3 (P3)**: Depends on US1 — needs chain config for validation thresholds
- **US5 (P5)**: Depends on Phase 2 only — block overrides work independently of chain config
- **US4 (P4)**: Implemented in Phase 2 (Foundational) as prerequisite for all stories

### Within Each Phase

- Block decomposition tasks (T004-T021) are all [P] — independent files
- Assembly infrastructure (T022-T025) is sequential: script → library → CLI → verify
- Chain validation blocks (T026-T029) are mostly [P] except T026 (specify, the template)
- Absorption tasks (T033-T035) are sequential
- Polish tasks (T042-T048) are mostly [P] except T049 (regression depends on all others)

### Parallel Opportunities

- **Phase 2**: All block decomposition tasks (T004-T021) can run in parallel — they write to different files
- **Phase 3**: Chain validation blocks T027-T029 can run in parallel after T026
- **Phase 6**: US5 can run in parallel with US2 and US3 (if Phase 2 complete)
- **Phase 7**: T042-T048 can run in parallel; T049 must be last

---

## Parallel Example: Phase 2 Block Decomposition

```
# All block files can be created simultaneously:
T004: core/blocks/specify/feature-setup.md
T005: core/blocks/specify/spec-writer.md
T006: core/blocks/specify/quality-validation.md
T007: core/blocks/plan/setup-context.md
T008: core/blocks/plan/constitution-check.md
T009: core/blocks/plan/research.md
T010: core/blocks/plan/design-contracts.md
T011: core/blocks/plan/agent-context.md
T012: core/blocks/plan/version-awareness.md
T013: core/blocks/tasks/prerequisites.md
T014: core/blocks/tasks/task-generation.md
T015: core/blocks/tasks/dependency-graph.md
T016: core/blocks/implement/prerequisites.md
T017: core/blocks/implement/checklist-validation.md
T018: core/blocks/implement/project-setup.md
T019: core/blocks/implement/task-execution.md
T020: core/blocks/implement/version-bump.md
T021: core/blocks/optional/implement/test-local-stack.md
```

---

## Implementation Strategy

### MVP First (US1 Only — Chain Configuration)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational — Block decomposition + assembly (T004-T025)
3. Complete Phase 3: US1 — Chain config (T026-T032)
4. **STOP and VALIDATE**: Test all three chain variants, verify blocked stubs, verify headless adaptation
5. This delivers: configurable chains, block architecture, assembly system

### Incremental Delivery

1. Setup + Foundational → Block system works, default assembly reproduces current behavior
2. Add US1 → Chain configuration works (MVP!)
3. Add US2 → Absorption makes shortened chains viable
4. Add US3 → Input validation catches under-specified prompts
5. Add US5 → Full block customization for users
6. Polish → Constitution, tests, deprecation, version bump

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- US4 (Block Decomposition) is implemented in Phase 2 since all other stories depend on it
- The extensions.yml deprecation (FR-020) is handled by NOT including its logic in decomposed blocks
- Chain-validation blocks are per-step (not shared) because each checks its own step name
- Assembly script is the central piece — it must be robust and well-tested
- Default assembly MUST produce identical output to current commands (T025 baseline check)
