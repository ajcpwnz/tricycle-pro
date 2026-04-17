# Tasks: Keep tricycle-pro's own `.trc/` in sync with `core/`

**Feature**: TRI-33-dogfood-core-sync
**Branch**: `TRI-33-dogfood-core-sync`
**Plan**: [plan.md](./plan.md)
**Spec**: [spec.md](./spec.md)
**Contracts**: [contracts/dogfood.md](./contracts/dogfood.md)

All file paths are repo-root-relative. Absolute worktree root: `/Users/alex/projects/tricycle-pro-TRI-33-dogfood-core-sync/`.

## Legend

- `[P]` — parallelizable with any other `[P]` task in the same phase (different files, no mutual dependency).
- `[US1]`, `[US2]`, `[US3]` — ties the task to the matching user story in `spec.md`.
- No story label on Setup, Foundational, or Polish tasks.

## Organizational note

User Story 1 (contributor can sync) and User Story 3 (CI catches drift) both require the same foundational code (the subcommand + shared mapping). US2 (ordinary consumers unaffected) is satisfied structurally by the meta-repo detection guard inside the subcommand — no dedicated code, just a verification test. The phases below reflect that: Phase 2 is heavy; Phase 3/4/5 are mostly test-level verifications.

---

## Phase 1 — Setup

- [X] T001 Verify worktree + branch by running `pwd` (must end `/tricycle-pro-TRI-33-dogfood-core-sync`) and `git rev-parse --abbrev-ref HEAD` (must print `TRI-33-dogfood-core-sync`). Gate check only.

---

## Phase 2 — Foundational (blocks all user stories)

Core CLI surface and the shared mapping table. US1/US2/US3 verifications in later phases all depend on this code landing first.

- [X] T002 Declare `TRICYCLE_MANAGED_PATHS` bash array near the top of `bin/tricycle` (in the module-level init region, alongside `VERSION` parsing). Value per `contracts/dogfood.md` — five entries: `core/commands:.claude/commands`, `core/templates:.trc/templates`, `core/scripts/bash:.trc/scripts/bash`, `core/hooks:.claude/hooks`, `core/blocks:.trc/blocks`.
- [X] T003 Refactor `cmd_update` in `bin/tricycle` to iterate over `"${TRICYCLE_MANAGED_PATHS[@]}"` instead of its current inline for-loop literal. Behavior must be byte-identical to pre-refactor — verified by running the existing `tests/test-tricycle-update-adopt.sh` green (expected to pass without modification).
- [X] T004 Add `cmd_dogfood` function in `bin/tricycle` per `contracts/dogfood.md`. Flow: (a) parse `--yes`/`-y` flag into a local `DO_WRITE` variable; (b) meta-repo detection — if `$CWD/core/` is not a directory, print the one-line skip message and `return 0`; (c) dry-run pass that walks each mapping's source files and categorizes each dst as `ADD` / `WRITE` / unchanged; (d) unmapped-core guard that collects files under `core/` not covered by any mapping prefix; (e) confirmation gate — if `DO_WRITE` is false after the dry-run, print `Dry run. Re-run with --yes to apply.` and exit 0; (f) write pass that `cp -f`s each flagged file, preserves `+x` for `.sh` files, and calls `lock_set "<dst>" "<checksum>" "false"` for each; (g) `save_lock` after the write pass; (h) summary line.
- [X] T005 Add dispatch entry `dogfood)    cmd_dogfood ;;` to the case statement near the bottom of `bin/tricycle` (alongside `update)`, `update-self)`, etc.).
- [X] T006 Update `show_help` in `bin/tricycle` to include the new subcommand:
  ```
    tricycle dogfood [--yes]           Mirror this repo's core/ into .trc/ and .claude/ (contributor-only)
  ```
  Place the line after `update-self` so it reads contiguously with other "repo-maintenance" commands.
- [X] T007 Handle `--yes` / `-y` flag at the top-level argument parser in `bin/tricycle` so it survives into `cmd_dogfood` via `POSITIONALS` or a dedicated flag variable. Check the existing flag-parsing structure and match the pattern (e.g. `--dry-run` already threads through).

**Checkpoint**: `bash tests/run-tests.sh` green (mapping refactor must not regress existing update tests); `tricycle dogfood --help` mentions the subcommand; `tricycle dogfood` in tricycle-pro root runs clean dry-run.

---

## Phase 3 — User Story 1: Contributor syncs without manual patching [P1]

**Story goal**: A contributor in tricycle-pro can run `tricycle dogfood --yes` and get `.trc/` + `.claude/` byte-matching `core/`, with `.tricycle.lock` updated so subsequent `tricycle update` runs don't SKIP those paths.

**Independent test (from `spec.md` User Story 1 and `quickstart.md` Tests 1–3 + 8)**: Create a deliberate drift (edit a `core/` file), run `tricycle dogfood` (dry-run reports WRITE), run `tricycle dogfood --yes` (writes land), `diff -r core/ .trc/` clean, `tricycle update --dry-run` shows no SKIPs on mirrored paths, and exec bits preserved on `.sh` files.

- [X] T008 [US1] Add `tests/test-dogfood-cmd.sh` that builds a synthetic meta-repo fixture under `mktemp -d`: copy `bin/` + `bin/lib/` + synthetic `core/` tree + seed `.tricycle.lock`. Exercise: (a) `tricycle dogfood` dry-run on a clean mirror → "Nothing to do"; (b) edit a fixture `core/foo.sh`, run dogfood dry-run → reports `WRITE .trc/scripts/bash/foo.sh` and exits 0 with dry-run message, no file changes; (c) run with `--yes` → file overwrites, `.tricycle.lock` adopts the new checksum with `customized: false`, `+x` preserved; (d) add a new `core/bar.sh`, run with `--yes` → reports `ADD`, new file created at mapped dst; (e) add an unmapped file `core/uncharted/wild.md`, run dry-run → warning block lists it, file is NOT mirrored.

**Checkpoint**: `bash tests/test-dogfood-cmd.sh` green.

---

## Phase 4 — User Story 2: Ordinary consumer repo is unaffected [P1]

**Story goal**: `tricycle dogfood` in a consumer repo (no `core/`) is a silent, harmless no-op. `tricycle update` in a consumer repo produces byte-identical output before and after this feature lands.

**Independent test (from `spec.md` User Story 2 and `quickstart.md` Tests 4 + 7)**: Consumer-fixture repo with `tricycle.config.yml` + managed files + NO `core/`. Run `tricycle dogfood` → one-line skip, exit 0, no file changes. Run `tricycle update` → output matches the pre-TRI-33 baseline (existing `test-tricycle-update-adopt.sh` still green).

- [X] T009 [US2] Extend `tests/test-dogfood-cmd.sh` (from T008) with a "no-core fixture" case: set up a consumer fixture (no `core/` directory at root), run `tricycle dogfood`, assert exit 0, assert stdout matches `Not a tricycle-pro meta-repo (no core/ directory at repo root); nothing to do.`, assert no files written (verifiable by capturing `find fixture -newer ref` count).
- [X] T010 [US2] Verify the existing `tests/test-tricycle-update-adopt.sh` still passes unchanged after the T003 refactor. No new code — just confirm during the Phase 2 gate. If it fails, T003's refactor is wrong and must be fixed before Phase 4 can be checkpointed.

**Checkpoint**: Both tests green. Consumer fixture shows zero regression.

---

## Phase 5 — User Story 3: Drift is caught automatically [P2]

**Story goal**: `bash tests/run-tests.sh` fails with a clear message if `core/` and its mirrored paths drift in tricycle-pro itself. Silent pass when `core/` is absent.

**Independent test (from `spec.md` User Story 3 and `quickstart.md` Test 5)**: In tricycle-pro, sync everything (`tricycle dogfood --yes`), run `bash tests/run-tests.sh` → green with `dogfood-drift: OK`. Intentionally drift a path (append to `.trc/scripts/bash/derive-branch-name.sh`), rerun → test fails listing the drifted path with actual diff. Restore via `git checkout --`, rerun → green.

- [X] T011 [US3] Add `tests/test-dogfood-drift.sh` that: (a) checks `$REPO_ROOT/core/` existence; if absent, prints `dogfood-drift: skipped (not a meta-repo)` and exits 0; (b) otherwise loops over the same five mapping pairs hardcoded here (the test script doesn't source `bin/tricycle`; hardcoded because it's a separate process and the overhead of sourcing bash-sourced-only vars isn't worth the coupling); (c) for each pair, runs `diff -r "$REPO_ROOT/<src>" "$REPO_ROOT/<dst>"`; (d) collects any non-empty diffs; (e) if any pair drifted, prints each offending path + the actual `diff -r` output, exits 1; (f) otherwise prints `dogfood-drift: OK` and exits 0.
- [X] T012 [P] [US3] Wire `tests/test-dogfood-drift.sh` into `tests/run-tests.sh` under a new section header `Dogfood drift sync (TRI-33):` placed near the end (after the TRI-32 block, before `trc.review` block). Also wire T008/T009's `tests/test-dogfood-cmd.sh` into the same section.

**Checkpoint**: `bash tests/run-tests.sh` green with the new `Dogfood drift sync (TRI-33):` block visible.

---

## Phase 6 — Polish & Cross-Cutting Concerns

- [X] T013 Walk `quickstart.md` manually in the real tricycle-pro repo: Tests 1–3 (dry-run, --yes, post-sync update no-SKIP), Test 8 (exec-bit preserved), Test 6 (unmapped-core warning). Record divergences as blockers.
- [X] T014 [P] Run `bash tests/run-tests.sh` end-to-end. Must be green.
- [X] T015 [P] Confirm no regression against the existing `test-tricycle-update-adopt.sh` and the branch-naming / provision-worktree / TRI-31 / TRI-32 blocks — the shared-mapping refactor must not alter their output.
- [X] T016 [P] Confirm `CLAUDE.md` "Recent Changes" entry for TRI-33 landed cleanly from `.trc/scripts/bash/update-agent-context.sh claude` (already auto-generated during `/trc.plan`).
- [X] T017 Bump `VERSION` from `0.20.0` to `0.20.1` in the final implementation commit (not a separate commit). Rationale: patch bump, per `plan.md` — feature is contributor-only with zero observable change for ordinary consumers.

---

## Dependencies

```text
Phase 1 (T001) ──▶ Phase 2 (T002–T007) ──┬──▶ Phase 3 (T008)        [US1]
                                          ├──▶ Phase 4 (T009–T010)   [US2]
                                          └──▶ Phase 5 (T011–T012)   [US3]

Phase 3, 4, 5 are independent of each other — they can proceed in
parallel once Phase 2 is complete. Phase 3 and 4 both extend
test-dogfood-cmd.sh; if done by separate agents, serialize those tasks
at the file level even though the phases are independent.

Phase 6 (T013–T017) requires all prior phases complete.
```

Inside Phase 2:

- T002 blocks T003 (refactor references the array).
- T002 blocks T004 (cmd_dogfood iterates the array).
- T007 blocks T004 (flag parsing must exist before cmd_dogfood can read it).
- T005 blocks nothing functionally (pure dispatch wiring) but is required for manual invocation during Phase 3/4/5 checkpoints.
- T006 can run in parallel with T004/T005 (different region of the same file).

---

## Parallel execution opportunities

**Phase 2 fast lane**: T002 first, then T003 ∥ T004 (they touch different functions within `bin/tricycle`; serialize at the file-edit level if needed) ∥ T006 ∥ T007. T005 once T004 lands. Net ~3 serial chunks instead of 6.

**Phases 3/4/5**: Phases 4 and 5 each have independent file-level scope (`test-dogfood-cmd.sh` for 3+4, `test-dogfood-drift.sh` for 5) — one agent per phase works if test-cmd tasks are serialized. Or a single agent handles all three phases since they're small.

---

## Implementation strategy (MVP first, incremental)

**MVP (Phases 1 + 2 + T008 + T014)**: Ship the subcommand + shared mapping + the US1 cmd-behavior test. That delivers the primary contributor value end-to-end — `tricycle dogfood --yes` works in tricycle-pro and the cmd is tested against a fixture. If time runs out before US2/US3 polish, the MVP alone closes 80% of the gap.

**Increment 2 (US2 — T009 + T010)**: Verify consumer fixtures are unaffected by extending the cmd test and confirming the update-adopt test stays green.

**Increment 3 (US3 — T011 + T012)**: Add the drift test and wire it into the suite. CI-visible regression alarm.

**Polish (Phase 6)**: Manual quickstart + full-suite regression + VERSION bump.

---

## Format validation

Every task above begins with `- [ ]`, carries a sequential `T0NN` ID, has a `[P]` marker only when genuinely parallelizable, and includes the concrete file path (or explicit no-file note for gate tasks). Story labels appear only on Phase 3/4/5 tasks. Confirmed.

## Task totals

- Setup (Phase 1): 1 task
- Foundational (Phase 2): 6 tasks (T002–T007)
- US1 (Phase 3): 1 task (T008)
- US2 (Phase 4): 2 tasks (T009–T010)
- US3 (Phase 5): 2 tasks (T011–T012)
- Polish (Phase 6): 5 tasks (T013–T017)

**Total: 17 tasks.**

Independent test criteria: each user-story phase has its own verification (`tests/test-dogfood-cmd.sh` for US1/US2 and `tests/test-dogfood-drift.sh` for US3); each is directly runnable standalone via `bash tests/<name>.sh` and as part of the full suite.

Suggested MVP: Phases 1 + 2 + T008 + T014 (~9 tasks, delivers User Story 1 end-to-end with a fixture-backed test).
