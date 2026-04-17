# Tasks: One-way drift check (src → dst)

**Feature**: TRI-34-drift-one-way
**Branch**: `TRI-34-drift-one-way`
**Plan**: [plan.md](./plan.md)
**Spec**: [spec.md](./spec.md)
**Contracts**: [contracts/drift-check.md](./contracts/drift-check.md)

All file paths are repo-root-relative. Absolute worktree root: `/Users/alex/projects/tricycle-pro-TRI-34-drift-one-way/`.

## Legend

- `[P]` — parallelizable with any other `[P]` task in the same phase.
- `[US1]`, `[US2]` — ties the task to the matching user story.
- No story label on Setup, Foundational, or Polish tasks.

## Organizational note

Both user stories in the spec (no false positive / modified-file still caught) are satisfied by the same single-file rewrite. Phase 2 carries the whole implementation; Phase 3/4 are verification-only, each mapped to a quickstart scenario. This is narrower than TRI-33 by design.

---

## Phase 1 — Setup

- [X] T001 Verify worktree + branch: `pwd` must end with `/tricycle-pro-TRI-34-drift-one-way`; `git rev-parse --abbrev-ref HEAD` must print `TRI-34-drift-one-way`. Gate check only; no file written.

---

## Phase 2 — Foundational (blocks both user stories)

The rewrite itself. After this task lands, US1 and US2 are both observable.

- [X] T002 Rewrite `tests/test-dogfood-drift.sh` per `contracts/drift-check.md`. Replace the existing bidirectional `diff -r` loop with a one-way walk: for each mapping pair in the hardcoded table, skip if `<src-dir>` is absent; flag `(missing directory)` if `<dst-dir>` is absent; else `find "$REPO_ROOT/<src-dir>" -type f | sort` and for each file compare to `"$REPO_ROOT/<dst-dir>/<rel>"` via `cmp -s` (happy path) + `diff` (failure-detail fallback). Preserve the v0.20.1 failure output shape: `FAIL: dogfood drift detected...`, `Drifted paths:` block, `Detail:` block with one `--- diff <src> vs <dst> ---` header per diff, and the closing `Fix: run \`tricycle dogfood --yes\`...` line. Keep the consumer-fixture skip path (`dogfood-drift: skipped (not a meta-repo)`). Keep the mapping list hardcoded (do NOT source bin/tricycle).

**Checkpoint**: `bash tests/test-dogfood-drift.sh` runs against the real tricycle-pro-TRI-34-drift-one-way worktree and exits 0 (the worktree is currently in sync). Full suite (`bash tests/run-tests.sh`) is green.

---

## Phase 3 — User Story 1: False positive is gone [P1]

**Story goal**: Runtime-generated files in managed paths (e.g. `.claude/hooks/.session-context.conf`) no longer trigger drift.

**Independent test (from `quickstart.md` Test 1)**: After `tricycle generate settings` has written `.claude/hooks/.session-context.conf`, `bash tests/test-dogfood-drift.sh` exits 0 with `dogfood-drift: OK`.

- [X] T003 [US1] Manually exercise Test 1 from `quickstart.md` in the worktree: run `tricycle generate settings` (if `.claude/hooks/.session-context.conf` doesn't already exist locally; it does in the main checkout), then run `bash tests/test-dogfood-drift.sh`. Assert exit 0 and `dogfood-drift: OK`. Record result as a one-line note in the commit message.

---

## Phase 4 — User Story 2: Modified-file drift still caught [P1]

**Story goal**: The test still reports real drift with actionable diff output.

**Independent test (from `quickstart.md` Tests 2+3+5)**: Appending a byte to a `core/` file produces exit 1 with the drifted path and the content diff. Removing a destination file produces exit 1 with `(missing)`. Multiple simultaneous drifts all appear in the output.

- [X] T004 [US2] Manually exercise Tests 2, 3, and 5 from `quickstart.md`:
  - Test 2: append to `core/scripts/bash/derive-branch-name.sh`, run drift test, expect exit 1 with that path named and diff shown; `git checkout --` to restore; rerun, expect exit 0.
  - Test 3: `mv` a destination file aside, run drift test, expect exit 1 with `(missing)` suffix; restore file; rerun, expect exit 0.
  - Test 5: drift two different `core/` files at once, run drift test, expect both paths in `Drifted paths:` block and both diffs in `Detail:` block; `git checkout --` to restore.

---

## Phase 5 — Polish & Cross-Cutting Concerns

- [X] T005 [P] Run `bash tests/run-tests.sh` end-to-end. Must be green — confirms no regression from the rewrite, and confirms the drift test itself exits 0 against the current worktree (which is in sync).
- [X] T006 [P] Confirm `CLAUDE.md` "Recent Changes" entry for TRI-34 landed cleanly from `update-agent-context.sh claude` (already auto-generated during `/trc.plan`).
- [X] T007 Bump `VERSION` from `0.20.1` to `0.20.2` in the final implementation commit (not a separate commit). Rationale: patch bump per `plan.md`.

---

## Dependencies

```text
Phase 1 (T001) ──▶ Phase 2 (T002) ──┬──▶ Phase 3 (T003)   [US1]
                                     ├──▶ Phase 4 (T004)   [US2]
                                     └──▶ Phase 5 (T005–T007)

Phases 3 and 4 are independent of each other (different quickstart
scenarios) and both run against the same rewritten test file. They can
proceed in parallel with each other and with Phase 5 once Phase 2 is in.
```

---

## Parallel execution opportunities

Phase 2 is a single task — no parallelism inside. Phases 3/4/5 tasks are all `[P]`-ish (independent quickstart scenarios + independent polish items); in practice a single agent handles them sequentially since each is <60 s of work.

---

## Implementation strategy (MVP first, incremental)

**MVP = Phase 1 + Phase 2 + T005**: Rewrite the test, confirm full suite green. That's the entire deliverable — US1 and US2 are both verified implicitly by the suite's green-on-real-repo signal (the real tricycle-pro-TRI-34-drift-one-way worktree has both runtime-generated files present AND is fully synced). Phases 3 and 4 are explicit quickstart walks that produce no additional artifacts; they're documentation of the verification, not incremental implementation.

**Practically**: land T001 → T002 → run T005. If green, ship. Run T003/T004 interactively during the PR walk-through as extra confidence checks.

---

## Format validation

Every task above begins with `- [ ]`, carries a sequential `T0NN` ID, has a `[P]` marker only when genuinely parallelizable, and includes the concrete file path (or explicit no-file note for gate/verification tasks). Story labels appear only on Phase 3/4 tasks. Confirmed.

## Task totals

- Setup (Phase 1): 1 task
- Foundational (Phase 2): 1 task
- US1 (Phase 3): 1 task
- US2 (Phase 4): 1 task
- Polish (Phase 5): 3 tasks

**Total: 7 tasks.** Smallest feature in this chain.

Suggested MVP: Phase 1 + Phase 2 + T005 (~3 tasks, delivers both user stories in one green suite run).
