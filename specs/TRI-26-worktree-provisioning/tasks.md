# Tasks: Fix /trc.specify worktree provisioning gap

**Input**: Design documents from `specs/TRI-26-worktree-provisioning/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/create-new-feature-cli.md, contracts/worktree-setup-handoff.md, quickstart.md

**Tests**: Tests are INCLUDED in this plan. CLAUDE.md marks `bash tests/run-tests.sh` + `node --test tests/test-*.js` as MANDATORY NONNEGOTIABLE exit gates, and the contract artifact lists 11 required test cases. Test tasks are therefore first-class citizens here, not optional.

**Organization**: Tasks are grouped by user story from `spec.md` (US1 = fully provisioned worktree, US2 = backward compatibility, US3 = generic package manager). Each story is independently completable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths below are relative to the worktree root `/Users/alex/projects/tricycle-pro-TRI-26-worktree-provisioning/`

## Path Conventions

- Single-app `.trc/` layout. "Source" lives under `.trc/scripts/bash/` and `.trc/blocks/`. Tests live under `tests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the working environment and seed the fixture directory the tests will reuse.

- [X] T001 Verify worktree is on branch `TRI-26-worktree-provisioning` and `.trc/` is populated; run `git status && git branch --show-current` in the worktree root and confirm clean-plus-specs-dir state
- [X] T002 [P] Create test fixtures directory `tests/fixtures/worktree-provisioning/` with a committed `.gitkeep` so later tests can drop per-case seed configs into it
- [X] T003 [P] Add a top-of-file comment block to `.trc/scripts/bash/create-new-feature.sh` reserving exit codes 10–15 for provisioning (see `specs/TRI-26-worktree-provisioning/data-model.md` §3); comment must name each code so future edits cannot reuse them

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core parse helper + flag plumbing that every user story depends on. No user story can begin until these land.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Add `parse_worktree_config` helper to `.trc/scripts/bash/common.sh` that reads `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` from `tricycle.config.yml` using the same line-based YAML idiom as the existing `parse_chain_config` / `parse_block_overrides` helpers (see `research.md` Decision 2); emit as `package_manager=...\nsetup_script=...\nenv_copy=...` lines, one `env_copy=` line per entry
- [X] T005 [P] Add `--provision-worktree` flag parsing to `.trc/scripts/bash/create-new-feature.sh` in the existing `while [ $i -le $# ]` loop; set `PROVISION_WORKTREE=true` and force `NO_CHECKOUT=true` when seen (see `contracts/create-new-feature-cli.md` §Semantics step 2)
- [X] T006 [P] Add fallback defaults for `PACKAGE_MANAGER="npm"`, `SETUP_SCRIPT=""`, `ENV_COPY=()` near the top of `.trc/scripts/bash/create-new-feature.sh` so the variables are always defined even when `parse_worktree_config` is never called
- [X] T007 Extend `.trc/scripts/bash/create-new-feature.sh --help` text to document `--provision-worktree` with one-line description matching `contracts/create-new-feature-cli.md` §Synopsis
- [X] T008 Add a `provision_worktree()` Bash function in `.trc/scripts/bash/create-new-feature.sh` that takes `$WORKTREE_PATH`, `$MAIN_TRC_SOURCE`, and sources the parsed config; the function is a stub that returns 0 for now (implementation fills in during US1). This isolates the call site so later tasks only edit the function body, not the call site.
- [X] T009 Wire the new JSON output key `WORKTREE_PATH` into the `$JSON_MODE` branch in `.trc/scripts/bash/create-new-feature.sh` (only when `PROVISION_WORKTREE=true`); use the same `jq` vs `json_escape` split that's already there. Do not emit the key otherwise (backward compat — see `contracts/create-new-feature-cli.md` §JSON Output).

**Checkpoint**: Flag parses, helper exists, function stub is called in the right place, JSON output is correct for the no-op case. User story implementation can now begin.

---

## Phase 3: User Story 1 - Feature work begins in a fully provisioned worktree (Priority: P1) 🎯 MVP

**Goal**: Running `/trc.specify "<feature>"` on a project with `worktree.enabled: true`, `package_manager`, `setup_script`, and `env_copy` set leaves the agent in a ready-to-code worktree with zero additional prompts.

**Independent Test**: Run the quickstart (`specs/TRI-26-worktree-provisioning/quickstart.md` §4) against `/tmp/prov-demo`. Expect `node_modules/` present, `.env.local` present, exit 0, JSON output includes `WORKTREE_PATH`.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST; confirm they fail against the stub from T008 before filling in the body.**

- [X] T010 [P] [US1] Create `tests/test-worktree-provisioning.js` with a Node test harness that shells out to `.trc/scripts/bash/create-new-feature.sh` inside a temp directory seeded from `tests/fixtures/worktree-provisioning/`; add the happy-path case from `contracts/create-new-feature-cli.md` §Test Hooks #1 (all four sub-steps succeed, exit 0, JSON contains `WORKTREE_PATH`)
- [X] T011 [P] [US1] Add test case #2 to `tests/test-worktree-provisioning.js`: `setup_script` not set → sub-step is a no-op, command still exits 0
- [X] T012 [P] [US1] Add test case #3 to `tests/test-worktree-provisioning.js`: `env_copy` empty → verification sub-step is a no-op, command still exits 0
- [X] T013 [P] [US1] Add negative-path test cases #5–#10 (install fails → exit 11, setup_script missing → exit 12, setup_script not executable → exit 13, setup_script exits non-zero → exit 14, one `env_copy` path missing → exit 15 with one-line error, multiple `env_copy` paths missing → exit 15 with multi-line error) to `tests/test-worktree-provisioning.js`
- [X] T014 [P] [US1] Append `node --test tests/test-worktree-provisioning.js` to `tests/run-tests.sh` so the new file is exercised by the mandatory test gate

### Implementation for User Story 1

- [X] T015 [US1] Implement `.trc/ copy` step inside `provision_worktree()` in `.trc/scripts/bash/create-new-feature.sh`: `cp -r "$MAIN_TRC_SOURCE" "$WORKTREE_PATH/.trc"` guarded by `[ ! -e "$WORKTREE_PATH/.trc" ]`; on copy failure exit 10 with `Error: failed to copy .trc/ into worktree at $WORKTREE_PATH: <reason>` (see `data-model.md` §3 row exit 10)
- [X] T016 [US1] Implement package-manager install step inside `provision_worktree()` in `.trc/scripts/bash/create-new-feature.sh`: `cd "$WORKTREE_PATH" && "$PACKAGE_MANAGER" install`; on non-zero exit 11 with `Error: '$PACKAGE_MANAGER install' failed with exit $N in $WORKTREE_PATH` (see `data-model.md` §3 row exit 11)
- [X] T017 [US1] Implement `setup_script` execution inside `provision_worktree()` in `.trc/scripts/bash/create-new-feature.sh`: preflight `[ -e "$WORKTREE_PATH/$SETUP_SCRIPT" ]` (exit 12 if missing), `[ -x "$WORKTREE_PATH/$SETUP_SCRIPT" ]` (exit 13 if not executable), then `(cd "$WORKTREE_PATH" && "./$SETUP_SCRIPT")` (exit 14 if non-zero); skip entire block if `SETUP_SCRIPT` is empty (see `data-model.md` §3 rows exits 12/13/14)
- [X] T018 [US1] Implement `env_copy` verification inside `provision_worktree()` in `.trc/scripts/bash/create-new-feature.sh`: loop over `ENV_COPY[@]`, collect every `[ ! -e "$WORKTREE_PATH/$p" ]` into a `MISSING=()` array, exit 15 with the multi-line message format from `contracts/create-new-feature-cli.md` §Error Message Format; skip if `ENV_COPY` is empty
- [X] T019 [US1] Move the spec-directory-and-template creation (`mkdir -p "$FEATURE_DIR" && cp "$TEMPLATE" "$SPEC_FILE"`) into the `PROVISION_WORKTREE=true` path in `.trc/scripts/bash/create-new-feature.sh` so it runs inside the worktree (adjust `FEATURE_DIR` / `SPEC_FILE` to the worktree path); existing non-provision path remains unchanged
- [X] T020 [US1] Update `.trc/blocks/specify/feature-setup.md` Step 2b so it calls `create-new-feature.sh ... --provision-worktree` as a single invocation and removes the manual `git worktree add`, `cp -r .trc`, `mkdir specs`, and `cp spec-template.md` sub-steps (see `contracts/worktree-setup-handoff.md` §Updated feature-setup.md Step 2b)
- [X] T021 [US1] Update `.trc/blocks/optional/specify/worktree-setup.md` Configuration section to list `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` per `contracts/worktree-setup-handoff.md` §New handoff surface; preserve the existing `WORKTREE_MODE` detection block unchanged
- [X] T022 [US1] Run `bash tests/run-tests.sh` and `node --test tests/test-worktree-provisioning.js`; all happy- and negative-path cases from T010–T013 must pass

**Checkpoint**: US1 complete. Running `/trc.specify` in a fully configured project leaves a ready worktree with zero follow-up instructions (SC-001, SC-005).

---

## Phase 4: User Story 2 - Projects without worktree provisioning still work unchanged (Priority: P1)

**Goal**: Projects with `worktree.enabled: true` but no `setup_script` and no `env_copy` — and projects with `worktree.enabled: false` — continue to behave exactly as they did before the fix. No new required config, no new failure modes.

**Independent Test**: Run the backward-compat quickstart (`specs/TRI-26-worktree-provisioning/quickstart.md` §7) against `/tmp/prov-demo-plain`. Expect the original (pre-fix) JSON output shape and side-effects identical to the `main` branch's behavior.

### Tests for User Story 2 ⚠️

- [X] T023 [P] [US2] Add test case #11 to `tests/test-worktree-provisioning.js`: invoking `create-new-feature.sh` WITHOUT `--provision-worktree` produces the pre-TRI-26 JSON shape (no `WORKTREE_PATH` key) and the branch is checked out in the main checkout — snapshot the output against a golden file committed in `tests/fixtures/worktree-provisioning/golden-no-provision.json`
- [X] T024 [P] [US2] Add test case: `worktree.enabled: false` in the seeded `tricycle.config.yml` combined with the block enabled — assert the script still runs, skips provisioning, and exits 0 (matches SC-002)

### Implementation for User Story 2

- [X] T025 [US2] Audit the `PROVISION_WORKTREE=false` path in `.trc/scripts/bash/create-new-feature.sh` by running `git diff main -- .trc/scripts/bash/create-new-feature.sh` and confirming only additive lines in the provision path; if any line in the non-provision path changed, revert it
- [X] T026 [US2] Confirm `parse_worktree_config` returns sensible defaults (`package_manager=npm`, `setup_script=` empty, `env_copy=` empty) when the `worktree:` section is absent from `tricycle.config.yml`; add a unit assertion in `tests/test-config-parsing.js` (the existing file)
- [X] T027 [US2] Run `bash tests/run-tests.sh` + `node --test tests/test-*.js`. All pre-existing tests must pass unchanged. This is the SC-002 regression gate.

**Checkpoint**: US2 complete. Both the "simpler project" path and the "worktree disabled" path are verified unchanged (FR-004, SC-002, SC-006).

---

## Phase 5: User Story 3 - Package manager is selected from config, not hardcoded (Priority: P2)

**Goal**: `bun`, `npm`, `pnpm`, and `yarn` all produce the correct `<pm> install` command when declared as `project.package_manager`. No test relies on the literal string `bun`.

**Independent Test**: Parameterized test that sets `project.package_manager` to each of the four supported values and asserts the script's install sub-step invokes the matching binary. See `spec.md` User Story 3 Acceptance Scenarios.

### Tests for User Story 3 ⚠️

- [X] T028 [P] [US3] Add a parameterized test to `tests/test-worktree-provisioning.js` that iterates over `['bun','npm','pnpm','yarn']` and, for each, seeds `tricycle.config.yml` with the matching `project.package_manager`, stubs the binary on `PATH` to a shim that writes its `$0` to a sentinel file, runs the script, and asserts the sentinel contains the expected PM name
- [X] T029 [P] [US3] Add a test case that omits `project.package_manager` entirely and asserts the fallback is `npm` (matches `data-model.md` §1 defaults and `research.md` Decision 2)

### Implementation for User Story 3

- [X] T030 [US3] In `provision_worktree()` inside `.trc/scripts/bash/create-new-feature.sh`, guard the install call with `if ! command -v "$PACKAGE_MANAGER" >/dev/null 2>&1; then exit 11 with "Error: package manager '$PACKAGE_MANAGER' not found on PATH"; fi` so the exit-11 message from T016 is distinguishable from generic install failures
- [X] T031 [US3] Run the parameterized test from T028 and the fallback test from T029; both must pass without any code hardcoding the string `bun`

**Checkpoint**: US3 complete. Install command is config-driven (FR-005, SC-003).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanups, version bump, constraint verification, and the mandatory test gate.

- [X] T032 [P] Bump `VERSION` from `0.16.4` to `0.16.5` (patch bump per plan summary — correctness fix, not new feature)
- [X] T033 [P] Add a `Recent Changes` entry for TRI-26 via `.trc/scripts/bash/update-agent-context.sh claude` (already done during /trc.plan, re-run to pick up any further drift and leave the worktree's `CLAUDE.md` consistent)
- [X] T034 Verify SC-006: run `git diff main -- CLAUDE.md` against the **main checkout's** `CLAUDE.md` (not the worktree copy, which update-agent-context.sh intentionally edits). Must show zero lines changed. If non-empty, fail loudly and identify which sub-task leaked an edit back to the main CLAUDE.md.
- [X] T035 [P] Run `bash tests/run-tests.sh` as the MANDATORY gate from CLAUDE.md; must pass
- [X] T036 [P] Run `node --test tests/test-*.js` as the other half of the mandatory gate; must pass including every case in `tests/test-worktree-provisioning.js`
- [X] T037 Run the full `quickstart.md` §1–§7 end-to-end against a throwaway `/tmp/prov-demo` directory; capture the happy-path JSON output and paste it into a PR comment as evidence
- [X] T038 [P] Add a short entry to the `Recent Changes` section of `CLAUDE.md` IN THE WORKTREE ONLY (automated via T033), never in the main checkout — this is the compliance proof for SC-006

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately. T002 and T003 can run in parallel with T001.
- **Foundational (Phase 2)**: Depends on Setup. T004 must land first (helper is the linchpin); T005 and T006 can run in parallel after T004; T007 depends on T005; T008 depends on T005+T006; T009 depends on T008.
- **User Story 1 (Phase 3)**: Depends on Foundational. Tests T010–T014 run in parallel (different files or additive edits to the new test file). Implementation T015→T016→T017→T018 is a sequential chain inside `provision_worktree()`, then T019, T020, T021, T022 close out.
- **User Story 2 (Phase 4)**: Depends on Foundational. Can run in parallel with US1 in principle, but T025/T026 touch code US1 is already editing — easier to sequence it after US1.
- **User Story 3 (Phase 5)**: Depends on Foundational + US1 (reuses the `provision_worktree()` function and `tests/test-worktree-provisioning.js`). Must sequence after US1.
- **Polish (Phase 6)**: Depends on US1 + US2 + US3 all complete. T032/T033/T035/T036/T038 can run in parallel; T034 depends on T020/T021/T033; T037 depends on all prior implementation work.

### User Story Dependencies

- **US1 (P1)**: Blocks US3 (shared function and test file). Does not block US2 in principle; sequenced for convenience.
- **US2 (P1)**: Independent in principle, sequenced after US1 to avoid edit conflicts in the same script.
- **US3 (P2)**: Depends on US1 — can only start after the `provision_worktree()` body exists.

### Within Each User Story

- Tests are written FIRST and must fail against the T008 stub before implementation begins.
- Implementation is sequential inside `provision_worktree()` because every step edits the same function body.
- Markdown block updates (T020, T021) can run in parallel with each other but must follow the script changes.

### Parallel Opportunities

- T002 + T003 (Phase 1)
- T005 + T006 (after T004, Phase 2)
- T010 + T011 + T012 + T013 + T014 (Phase 3 tests — T014 edits `run-tests.sh`, others edit the new test file; all non-overlapping)
- T023 + T024 (Phase 4 tests)
- T028 + T029 (Phase 5 tests)
- T032 + T033 + T035 + T036 + T038 (Phase 6 final batch)

---

## Parallel Example: User Story 1 Tests

```bash
# Launch all US1 test cases at once — each is an additive append to the same new file,
# or a completely separate file. No conflicts.
Task: "T010 [P] [US1] Create tests/test-worktree-provisioning.js happy-path case"
Task: "T011 [P] [US1] Add no-setup-script case to tests/test-worktree-provisioning.js"
Task: "T012 [P] [US1] Add empty-env-copy case to tests/test-worktree-provisioning.js"
Task: "T013 [P] [US1] Add negative-path cases to tests/test-worktree-provisioning.js"
Task: "T014 [P] [US1] Wire new test file into tests/run-tests.sh"
```

When tests are run concurrently on separate files, there is no conflict. When T011–T013 append to the same file, sequence them serially but keep the diffs small.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Run `quickstart.md` §1–§6 against `/tmp/prov-demo`
5. Deploy/demo if ready — this alone closes the bug the ticket was filed for

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 → `/tmp/prov-demo` quickstart passes → Demo MVP
3. Add US2 → Backward-compat regression gate passes → Demo
4. Add US3 → Parameterized PM test passes → Demo
5. Polish: VERSION bump, final test run, SC-006 check, PR

### Parallel Team Strategy

Not applicable — solo implementation. Single developer runs all phases sequentially.

---

## Suggested MVP Scope

**Minimum viable ticket closure = Phase 1 + Phase 2 + Phase 3 (US1)**. This alone fixes the reported bug. US2 adds the backward-compat safety net, US3 generalizes beyond `bun`. Phase 6 is always required (mandatory test gate + VERSION bump).

## Independent Test Criteria (copied from spec.md for traceability)

- **US1**: `ls node_modules && ls .env.local && ls specs/<branch>/spec.md && ls .trc/blocks/` inside the generated worktree all succeed, exit 0.
- **US2**: `git diff main -- .trc/scripts/bash/create-new-feature.sh` in the non-provision path shows zero unrelated changes; pre-existing tests pass unchanged.
- **US3**: Parameterized test covers all four supported package managers; no test source contains the literal string `bun` as a hardcoded value.

## Total Task Count

- **Phase 1 (Setup)**: 3 tasks (T001–T003)
- **Phase 2 (Foundational)**: 6 tasks (T004–T009)
- **Phase 3 (US1)**: 13 tasks (T010–T022)
- **Phase 4 (US2)**: 5 tasks (T023–T027)
- **Phase 5 (US3)**: 4 tasks (T028–T031)
- **Phase 6 (Polish)**: 7 tasks (T032–T038)
- **Total**: 38 tasks

---

## Notes

- [P] tasks = different files or non-overlapping additive edits, no dependencies on incomplete tasks
- Every task names an exact file path (no vague "update the script" — always the full path)
- Tests are a first-class part of this plan because the root cause of the bug is an untestable markdown recipe
- Commit after each logical group (end of phase, or end of each US implementation chain)
- Stop at any checkpoint to validate the story independently
- Do not introduce any edit to `CLAUDE.md` in the main checkout (SC-006) — only the worktree copy is touched, and only by `update-agent-context.sh`
