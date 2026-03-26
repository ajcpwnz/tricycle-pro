# Tasks: Configurable Branch Naming Styles

**Input**: Design documents from `/specs/004-branch-naming-styles/`
**Prerequisites**: plan.md (required), spec.md (required), data-model.md, contracts/script-interface.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Parse new `--style`, `--issue`, `--prefix` flags in `create-new-feature.sh` without changing existing behavior

- [x] T001 Add `--style`, `--issue`, and `--prefix` flag parsing to the argument loop in `core/scripts/bash/create-new-feature.sh` — new variables `STYLE=""`, `ISSUE_ID=""`, `ISSUE_PREFIX=""` with the same `--flag value` pattern used by `--short-name` and `--number`
- [x] T002 Add style validation after argument parsing in `core/scripts/bash/create-new-feature.sh` — if `STYLE` is non-empty and not one of `feature-name`, `issue-number`, `ordered`, print error and exit 1. Default `STYLE` to `ordered` when not provided (backward compat)
- [x] T003 Update `--help` output in `core/scripts/bash/create-new-feature.sh` to document `--style`, `--issue`, and `--prefix` flags with examples for each style

**Checkpoint**: Script accepts new flags without error, existing behavior unchanged when flags are omitted

---

## Phase 2: Foundational — Refactor Branch Name Generation

**Purpose**: Split the branch naming logic into style-aware code paths

- [x] T004 Extract the current numeric-prefix branch naming logic in `core/scripts/bash/create-new-feature.sh` (lines ~236-280) into a function `generate_ordered_branch()` that sets `BRANCH_NAME` and `FEATURE_NUM` — no behavior change, just isolation
- [x] T005 Create `generate_feature_name_branch()` function in `core/scripts/bash/create-new-feature.sh` — uses `generate_branch_name()` or `$SHORT_NAME` to produce slug, sets `BRANCH_NAME="$slug"` and `FEATURE_NUM=""`
- [x] T006 Create `generate_issue_number_branch()` function in `core/scripts/bash/create-new-feature.sh` — implements issue extraction: (1) if `$ISSUE_ID` is set, use it; (2) else if `$ISSUE_PREFIX` is set, grep description for `<PREFIX>-[0-9]+` case-insensitive; (3) else grep for generic `[A-Z]+-[0-9]+`; (4) if no match, exit 2 with message "Issue number required". Sets `BRANCH_NAME="$issue_id-$slug"` and `FEATURE_NUM="$issue_id"`
- [x] T007 Replace the inline branch naming logic with a style dispatcher: `case "$STYLE" in feature-name) ... ;; issue-number) ... ;; ordered) ... ;; esac` in `core/scripts/bash/create-new-feature.sh`

**Checkpoint**: `--style feature-name` produces slug-only branches, `--style ordered` produces `###-slug` branches (same as before), `--style issue-number --issue TRI-042` produces `TRI-042-slug` branches

---

## Phase 3: User Story 1 — Feature-Name Style (Priority: P1) 🎯 MVP

**Goal**: `feature-name` style works end-to-end as the new default

**Independent Test**: Run `create-new-feature.sh "Add dark mode" --style feature-name --short-name "dark-mode" --json` and verify branch name is `dark-mode` with no numeric prefix

### Implementation for User Story 1

- [x] T008 [US1] Add `branching` section to `presets/single-app/tricycle.config.yml` with `style: feature-name`
- [x] T009 [P] [US1] Add `branching` section to `presets/nextjs-prisma/tricycle.config.yml` with `style: feature-name`
- [x] T010 [P] [US1] Add `branching` section to `presets/express-prisma/tricycle.config.yml` with `style: feature-name`
- [x] T011 [P] [US1] Add `branching` section to `presets/monorepo-turborepo/tricycle.config.yml` with `style: feature-name`
- [x] T012 [US1] Update `core/blocks/specify/feature-setup.md` — add step 0 before branch creation: read `tricycle.config.yml` and extract `branching.style` (default `feature-name`) and `branching.prefix`. Pass `--style <value>` to `create-new-feature.sh`. For `feature-name` style, the block generates a short name and passes `--style feature-name --short-name "<slug>"`
- [x] T013 [US1] Add test to `tests/run-tests.sh` — "feature-name style produces slug-only branch": run `create-new-feature.sh "Add dark mode toggle" --style feature-name --short-name "dark-mode" --json` in a temp dir, parse JSON, verify `BRANCH_NAME` is `dark-mode` (no numeric prefix)
- [x] T014 [US1] Add test to `tests/run-tests.sh` — "default style without flag is ordered": run `create-new-feature.sh "Add something" --short-name "something" --json` in a temp dir (no `--style`), verify `BRANCH_NAME` matches `###-something` pattern

**Checkpoint**: Feature-name style works. Presets default to it. Existing no-flag behavior unchanged.

---

## Phase 4: User Story 2 — Issue-Number Style (Priority: P2)

**Goal**: `issue-number` style extracts ticket IDs from prompts and handles missing IDs via exit code 2

**Independent Test**: Run `create-new-feature.sh "TRI-042 Add export" --style issue-number --prefix TRI --short-name "export" --json` and verify branch is `TRI-042-export`

### Implementation for User Story 2

- [x] T015 [US2] Update `core/blocks/specify/feature-setup.md` — add `issue-number` handling: if `branching.style` is `issue-number`, scan the user's description for `<PREFIX>-<DIGITS>` pattern. If found, pass `--issue <ID>` to the script. If not found, present a question to the user asking for the issue number (e.g., "What is the issue number? (e.g., TRI-042)"), wait for response, then pass `--issue <response>` to the script
- [x] T016 [US2] Add test to `tests/run-tests.sh` — "issue-number style with explicit issue": run `create-new-feature.sh "Add export" --style issue-number --issue TRI-042 --short-name "export" --json`, verify `BRANCH_NAME` is `TRI-042-export`
- [x] T017 [US2] Add test to `tests/run-tests.sh` — "issue-number style extracts from description": run `create-new-feature.sh "TRI-042 Add export feature" --style issue-number --prefix TRI --short-name "export" --json`, verify `BRANCH_NAME` is `TRI-042-export`
- [x] T018 [US2] Add test to `tests/run-tests.sh` — "issue-number style exits 2 when no issue found": run `create-new-feature.sh "Add export" --style issue-number --short-name "export" --json`, verify exit code is 2

**Checkpoint**: Issue-number style extracts IDs, handles missing IDs with exit code 2, block prompts user when needed

---

## Phase 5: User Story 3 — Ordered Style Preserved (Priority: P3)

**Goal**: Existing ordered behavior is unchanged and explicitly selectable via `--style ordered`

**Independent Test**: Run `create-new-feature.sh "Add notifications" --style ordered --short-name "notifications" --json` in a dir with existing `specs/001-*/` through `specs/003-*/` and verify branch is `004-notifications`

### Implementation for User Story 3

- [x] T019 [US3] Update `core/blocks/specify/feature-setup.md` — add `ordered` handling: if `branching.style` is `ordered`, pass `--style ordered` to the script (current behavior, no `--short-name` override needed since the script already generates names)
- [x] T020 [US3] Add test to `tests/run-tests.sh` — "ordered style produces numbered branch": run `create-new-feature.sh "Add notifications" --style ordered --short-name "notifications" --json` in a temp dir, verify `BRANCH_NAME` matches `###-notifications` pattern

**Checkpoint**: Ordered style works identically to current behavior, explicitly selectable

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T021 Update `core/scripts/bash/create-new-feature.sh` help examples to show all three styles
- [x] T022 Run `bash tests/run-tests.sh` and `node --test tests/test-*.js` to verify all existing + new tests pass
- [x] T023 Run `tricycle validate` to confirm project integrity after all changes

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (flag parsing must exist before style dispatch)
- **US1 (Phase 3)**: Depends on Phase 2 (style dispatch must work)
- **US2 (Phase 4)**: Depends on Phase 2 (style dispatch must work), independent of US1
- **US3 (Phase 5)**: Depends on Phase 2 (style dispatch must work), independent of US1/US2
- **Polish (Phase 6)**: Depends on all user stories

### User Story Dependencies

- **US1 (feature-name)**: Independent — only needs foundational dispatch
- **US2 (issue-number)**: Independent — only needs foundational dispatch
- **US3 (ordered)**: Independent — only needs foundational dispatch

### Parallel Opportunities

- T009, T010, T011 can run in parallel (different preset files)
- US1, US2, US3 can all proceed in parallel after Phase 2

---

## Parallel Example: Preset Config Updates

```text
# These touch different files and can run simultaneously:
Task T009: Add branching to presets/nextjs-prisma/tricycle.config.yml
Task T010: Add branching to presets/express-prisma/tricycle.config.yml
Task T011: Add branching to presets/monorepo-turborepo/tricycle.config.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Flag parsing
2. Complete Phase 2: Style dispatch refactor
3. Complete Phase 3: Feature-name style + presets + block + tests
4. **STOP and VALIDATE**: Test feature-name style end-to-end
5. Ship as 0.4.0

### Incremental Delivery

1. Setup + Foundational → Script accepts `--style`
2. Add US1 (feature-name) → New default works → Ship
3. Add US2 (issue-number) → Team workflows supported → Ship
4. Add US3 (ordered) → Backward compat explicitly tested → Ship
5. Polish → Docs, validation, cleanup
