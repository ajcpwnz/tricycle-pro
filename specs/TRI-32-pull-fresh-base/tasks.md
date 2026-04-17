# Tasks: Pull fresh base branch before cutting new feature branch

**Feature**: TRI-32-pull-fresh-base
**Branch**: `TRI-32-pull-fresh-base`
**Plan**: [plan.md](./plan.md)
**Spec**: [spec.md](./spec.md)
**Contracts**: [contracts/refresh-base-branch.md](./contracts/refresh-base-branch.md)

All file paths are repo-root-relative. Absolute worktree root: `/Users/alex/projects/tricycle-pro-TRI-32-pull-fresh-base/`.

## Legend

- `[P]` — parallelizable with any other `[P]` task in the same phase (different files, no mutual dependency).
- `[US1]`, `[US2]`, `[US3]` — ties the task to the matching user story in `spec.md`.
- No story label on Setup, Foundational, or Polish tasks.

## Organizational note

The spec defines three user stories, but all three are satisfied by the SAME code change — the `refresh_base_branch` function inside `core/scripts/bash/create-new-feature.sh`, which every kickoff command routes through (FR-002, research R3). Per-story phases are therefore short: the foundational phase carries the whole implementation, and US1/US2/US3 phases each verify the story-specific path exists and is exercised, without new code.

---

## Phase 1 — Setup

- [X] T001 Verify worktree + branch by running `pwd` (must end with `/tricycle-pro-TRI-32-pull-fresh-base`) and `git rev-parse --abbrev-ref HEAD` (must print `TRI-32-pull-fresh-base`). Gate check only; no file written.

---

## Phase 2 — Foundational (blocks all user stories)

The entire implementation lands here. US1/US2/US3 phases below only verify story-specific behavior without adding new code.

- [X] T002 Add `read_pr_target` helper in `core/scripts/bash/create-new-feature.sh` that reads `push.pr_target` from `tricycle.config.yml` using the same single-purpose awk pattern as the existing `read_project_name`. Return empty string if absent; caller will default to `main`.
- [X] T003 Add `--no-base-refresh` flag parsing in `core/scripts/bash/create-new-feature.sh`. Introduce a new module-level `SKIP_BASE_REFRESH=false` variable; set to `true` when the flag is present. Thread the env-var alternative: at parse-time, honor `TRC_SKIP_BASE_REFRESH=1` by setting `SKIP_BASE_REFRESH=true`.
- [X] T004 Add `refresh_base_branch <repo_root> <base_branch>` function in `core/scripts/bash/create-new-feature.sh` matching `contracts/refresh-base-branch.md`. Order of checks inside the function: opt-out → `HAS_GIT` gate → reachability probe (`git fetch --dry-run origin <base>`, with network-error signature matching for offline degradation) → current-HEAD dispatch (`git pull --ff-only` when on base + dirty-tree guard, or `git fetch origin <base>:<base>` otherwise) → advance-detection for the success log line. Use exit codes 20 (dirty), 21 (divergent).
- [X] T005 Invoke `refresh_base_branch "$REPO_ROOT" "$BASE_BRANCH"` from the main flow of `core/scripts/bash/create-new-feature.sh`, immediately after `cd "$REPO_ROOT"` (line ~266) and before any branch-creation git command. Derive `BASE_BRANCH` from `read_pr_target`, defaulting to `main`. Propagate exit codes 20/21 from the function directly (do not wrap or re-interpret).
- [X] T006 Update the `--help` output in `core/scripts/bash/create-new-feature.sh` to document `--no-base-refresh` (and mention the equivalent `TRC_SKIP_BASE_REFRESH=1` env var).
- [X] T007 [P] Add `tests/test-refresh-base-branch.sh` covering all 8 paths from `quickstart.md`:
  (a) stale local `main` behind `origin/main` is fast-forwarded; new branch points at fresh tip;
  (b) up-to-date local `main` produces no stderr output on the refresh step;
  (c) dirty base checkout halts with exit 20 and does not create the branch;
  (d) unreachable origin (point `origin` at an invalid URL) warns and continues with exit 0;
  (e) divergent local `main` (local has a commit origin lacks, origin has a conflicting commit) halts with exit 21;
  (f) `--no-base-refresh` flag skips silently (no `[specify]` refresh line on stderr);
  (g) `TRC_SKIP_BASE_REFRESH=1` env var skips silently;
  (h) non-git fixture (call the script from a non-git dir or with `HAS_GIT=false` stub) is a silent no-op.
  Use a bare-repo fixture pattern consistent with `tests/test-derive-branch-name.sh`.
- [X] T008 [P] Wire `tests/test-refresh-base-branch.sh` into `tests/run-tests.sh` under a new section header (e.g. `Pull fresh base branch (TRI-32):`) placed near the existing `Session rename hook (TRI-31):` block. Use `chmod +x` on the new test.

**Checkpoint**: `bash tests/run-tests.sh` green. Running any kickoff against a repo with stale main fast-forwards local main before the new branch is cut.

---

## Phase 3 — User Story 1: Solo `/trc.specify` branches off fresh upstream [P1]

**Story goal**: Verify the foundational code path is exercised by a solo `/trc.specify` invocation. No new code.

**Independent test**: On a repo where local `main` trails `origin/main`, run `/trc.specify` (or invoke `.trc/scripts/bash/create-new-feature.sh` directly, which is what the template does). Confirm local main is fast-forwarded and the new branch's HEAD matches the freshly-pulled main.

- [X] T009 [US1] Confirm the solo-specify path in `tests/test-refresh-base-branch.sh` case (a) produces a branch rooted at `origin/<base>`'s tip SHA. If the foundational test already covers this (it does, by design), no new work is needed — just confirm the assertion exists and is named clearly for US1.

**Checkpoint**: Test (a) covers User Story 1 end-to-end with no template changes required.

---

## Phase 4 — User Story 2: `/trc.chain` workers branch off cumulative progress [P1]

**Story goal**: Verify that when `/trc.chain` merges ticket N and spawns the worker for ticket N+1, the worker's base SHA reflects ticket N's merge. No new code — the orchestrator already calls `create-new-feature.sh` for each ticket, and the foundational refresh logic runs once per call.

**Independent test**: Two-ticket chain where ticket 1 merges cleanly. Before ticket 2's worker is spawned, `main` has been fast-forwarded by `gh pr merge`'s local sync OR by this feature's refresh (whichever wins the race). Either way, ticket 2's worker worktree is rooted at ticket 1's squash-commit SHA.

- [X] T010 [US2] Add a dedicated scenario in `tests/test-refresh-base-branch.sh` (case (i)) simulating the chain path: two back-to-back `create-new-feature.sh` invocations against the same bare-repo fixture, where between the two the fixture advances `origin/main` with a sentinel commit. Assert the second invocation's branch is rooted at the sentinel commit's SHA, not at the first invocation's starting SHA. This is the programmatic proxy for User Story 2's acceptance scenario.

**Checkpoint**: Case (i) pins the chain-worker freshness invariant against the real script, not just the internal refresh function.

---

## Phase 5 — User Story 3: `/trc.headless` inherits the refresh [P2]

**Story goal**: Verify `/trc.headless` gets the refresh for free because it funnels into the same `create-new-feature.sh` call.

**Independent test**: Same mechanics as User Story 1 via the headless entry point.

- [X] T011 [US3] Grep `core/commands/trc.headless.md` to confirm it invokes `.trc/scripts/bash/create-new-feature.sh` (it does today) — add a one-line contract anchor in `tests/test-command-rename-fallback.sh` (or a new `tests/test-headless-kickoff-path.sh` if the existing file's scope doesn't fit) asserting the invocation remains. This prevents a future edit from rerouting headless around the script and silently dropping the refresh.

**Checkpoint**: Static guard pins the headless → create-new-feature.sh path.

---

## Phase 6 — Polish & Cross-Cutting Concerns

- [X] T012 Walk `quickstart.md` manually against a real scratch repo (or `../polst`). Record any divergence between documented behavior and observed behavior as a blocker — do NOT declare `/trc.implement` done until all 8 quickstart tests pass or are explicitly deferred with a follow-up ticket.
- [X] T013 [P] Run `bash tests/run-tests.sh` end-to-end. Must be green (108 pre-existing + the new TRI-32 tests).
- [X] T014 [P] Confirm no regression against existing "Branch naming styles", "--no-checkout flag", and "--provision-worktree flag" test blocks — the refactor must not change their output.
- [X] T015 [P] Verify `CLAUDE.md` "Recent Changes" entry for TRI-32 landed cleanly from `.trc/scripts/bash/update-agent-context.sh claude` (already auto-generated during `/trc.plan`).
- [X] T016 Bump `VERSION` from `0.19.1` to `0.20.0` in the final implementation commit (not a separate commit, per repo convention). Rationale captured in `plan.md` version-awareness section.

---

## Dependencies

```text
Phase 1 (T001) ──▶ Phase 2 (T002–T008) ──┬──▶ Phase 3 (T009)   [US1]
                                          ├──▶ Phase 4 (T010)   [US2]
                                          └──▶ Phase 5 (T011)   [US3]

Phase 3, 4, 5 are independent of each other — they can proceed in parallel
once Phase 2 is complete.

Phase 6 (T012–T016) requires all prior phases complete.
```

Inside Phase 2:

- T002 must land before T004 (the function reads pr_target via T002's helper).
- T003 must land before T005 (the invocation is gated on `SKIP_BASE_REFRESH` from T003).
- T004 blocks T005 (T005 calls the function T004 defines).
- T005 blocks T007 (tests exercise the integrated flow, not the function in isolation).
- T006 can land in parallel with T004/T005 (help text is independent of the function body).
- T008 blocks on T007 (can't wire a test that doesn't exist yet).

---

## Parallel execution opportunities

**Phase 2 fast lane**: T002 and T003 can run concurrently (they touch disjoint sections of create-new-feature.sh — one adds a helper near `read_project_name`, the other adds flag parsing near the argument loop). T006 runs concurrent with T004/T005 (different region of the same file — if conflicts arise, serialize, but the --help block is self-contained). T008 runs as soon as T007 is in. Net: 3–4 serial chunks instead of 7.

**Phase 3/4/5**: Fully independent of each other — case (a), (i), and the headless anchor touch different test files or different cases in the same file. One agent per story works.

---

## Implementation strategy (MVP first, incremental)

**MVP (Phase 1 + Phase 2 + T009)**: Ship the `refresh_base_branch` function, the CLI flag, the env-var opt-out, the full 8-case test suite, and the parity check that solo `/trc.specify` works. That delivers User Story 1's value in full — the most-common kickoff path stops starting from stale main. If time runs out before US2/US3 polish, the MVP alone is strict improvement.

**Increment 2 (US2)**: Add the chain-specific proxy test (T010). Unlocks confidence in the motivating scenario.

**Increment 3 (US3)**: Add the headless-path static guard (T011). Closes coverage.

**Polish (Phase 6)**: Manual quickstart + full-suite regression + VERSION bump. Version lands in the final implementation commit.

---

## Format validation

Every task above begins with `- [ ]`, carries a sequential `T0NN` ID, has a `[P]` marker only when genuinely parallelizable, and includes the concrete file path (or explicit no-file-written note for gate/verification tasks). Story labels appear only on Phase 3/4/5 tasks. Confirmed.

## Task totals

- Setup (Phase 1): 1 task
- Foundational (Phase 2): 7 tasks (T002–T008)
- US1 (Phase 3): 1 task (T009)
- US2 (Phase 4): 1 task (T010)
- US3 (Phase 5): 1 task (T011)
- Polish (Phase 6): 5 tasks (T012–T016)

**Total: 16 tasks.**

Independent test criteria: each user-story phase's verification lives in `tests/test-refresh-base-branch.sh` cases or an adjacent test file; each is runnable standalone via `bash tests/test-refresh-base-branch.sh` and as part of the full suite.

Suggested MVP: Phase 1 + Phase 2 + T009 + T013 polish sweep (≈10 tasks, delivers User Story 1 end-to-end and unlocks the rest for free).
