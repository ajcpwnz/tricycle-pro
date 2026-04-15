---
description: "Task list for TRI-30-chain-run-to-commit"
---

# Tasks: TRI-30 — /trc.chain workers run-to-commit; orchestrator handles push

**Feature**: TRI-30-chain-run-to-commit
**Input**: Design documents from `specs/TRI-30-chain-run-to-commit/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/chain-run-helper-v2.md ✅, quickstart.md ✅

**Tests**: INCLUDED. The contract delta mandates new test cases for every new error code and the full transition path, plus a static FR-013 guard test (`test-chain-run-no-sendmessage.sh`). All test files live under `tests/` and run via `bash tests/run-tests.sh`.

**Organization**: Tasks are grouped by user story from `spec.md`. US1 (worker run-to-commit) and US2 (orchestrator handles push) are both P1 — US1 changes the worker brief and the helper's status enum; US2 changes the orchestrator's per-ticket loop and adds the push step. US3 (honest progress trail) and US4 (resume via git) layer on after.

This is a **fix to a shipped feature**, so most tasks are MODIFY rather than CREATE. File paths refer to the existing TRI-27 files unless otherwise noted.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All file paths are repo-root-relative.

## Path Conventions

Single-project layout (Option 1 from plan.md). Source under `core/`, tests under `tests/`, runtime state under `specs/.chain-runs/`. Same as TRI-27.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: This is a fix to an existing feature; there is no new infrastructure to set up. Phase 1 is **empty by design**. Skip directly to Phase 2.

_(intentionally no tasks)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Helper-side schema changes that all user stories depend on. The new status enum, the `commit_sha` field, and the forward-transition validator must exist in `chain-run.sh` before any user story phase can be implemented.

**⚠️ CRITICAL**: All US phases depend on Phase 2 completion.

### Helper: status enum and rank validator

- [X] T001 In `core/scripts/bash/chain-run.sh` `py_update_ticket`, extend the valid status set from `{not_started, in_progress, completed, failed, skipped}` to `{not_started, in_progress, committed, pushed, merged, completed, failed, skipped}`. Update the early `if status not in (...)` check accordingly.
- [X] T002 In `core/scripts/bash/chain-run.sh` `py_update_ticket`, add a forward-rank table (`{not_started:0, in_progress:1, committed:2, pushed:3, merged:4, completed:5}`) and a transition validator: legal iff (new_rank > old_rank) OR (new_status == "failed") OR (new_status == "skipped" AND old_status == "not_started"). On illegal transition, exit 2 with `{"error":"...","code":"ERR_BAD_TRANSITION"}` to stderr.
- [X] T003 In `core/scripts/bash/chain-run.sh` `py_update_ticket`, change the `current_index` advancement loop from `["completed", "skipped"]` to `["committed", "pushed", "merged", "completed", "skipped"]`, so that a `committed` ticket on resume does not block index advancement.

### Helper: commit_sha field

- [X] T004 In `core/scripts/bash/chain-run.sh` `py_build_initial_state`, add `"commit_sha": None` to the per-ticket dict in the dict comprehension (between `branch` and `worktree_path` for diff-readability — order is not load-bearing).
- [X] T005 In `core/scripts/bash/chain-run.sh` `sub_update_ticket`, add a new flag `--commit-sha <sha>` parser branch, store into local `commit_sha=""`, and pass it as a new positional arg to `py_update_ticket`.
- [X] T006 In `core/scripts/bash/chain-run.sh` `py_update_ticket`, accept the new `commit_sha` positional arg, set `t["commit_sha"] = commit_sha if commit_sha else t.get("commit_sha")`, AND enforce two new validation rules: (a) if status == "committed" and not (commit_sha or t.get("commit_sha")) → exit 2 with `ERR_COMMIT_SHA_REQUIRED`; (b) if commit_sha and t.get("commit_sha") and commit_sha != t["commit_sha"] → exit 2 with `ERR_COMMIT_SHA_IMMUTABLE`.

### Helper: relaxed pr validation

- [X] T007 In `core/scripts/bash/chain-run.sh` `py_update_ticket`, change the `pr` validation from `if pr and status != "completed"` to `if pr and status not in ("pushed", "merged", "completed")`. Update the error message to `"pr_url is only allowed when status is pushed, merged, or completed"`. Keep the error code `ERR_PR_REQUIRES_COMPLETED` unchanged for backward-compat in tests, OR rename to `ERR_PR_REQUIRES_PUSHED_OR_LATER` if T011 is updated in lockstep.
- [X] T008 [P] Update existing tests in `tests/test-chain-run-update-ticket.js` for the renamed-or-relaxed pr validation: the existing test "pr_url without completed status returns ERR_PR_REQUIRES_COMPLETED" should now use `--status in_progress` (still illegal — pr requires pushed-or-later) and accept either the old or new error code name (whichever T007 chose).

### Existing schema tests get the new field

- [X] T009 [P] Update `tests/test-chain-run-state.js` "init happy path" assertions: assert that `state.tickets[tid].commit_sha === null` for every ticket after init. (Just adds one assertion line per ticket; does not change other behavior.)

**Checkpoint**: `chain-run.sh` understands the new status enum, the `commit_sha` field, and the forward-transition rules. All existing TRI-27 tests pass with minimal updates. User story phases can now begin.

---

## Phase 3: User Story 1 — Workers run to a clean commit and exit (Priority: P1) 🎯 MVP

**Goal**: A worker spawned by `/trc.chain` runs the full trc workflow up through a local commit on its feature branch and exits. The worker never pauses, never asks for input, and returns a single structured JSON report.

**Independent Test**: Walk through the helper-side state transitions for a single ticket using the new flags: `init` → `update-ticket --status in_progress --started-now` → `update-ticket --status committed --commit-sha <sha> --branch <name> --lint pass --test pass`. Verify state.json reflects each transition correctly. Verify forward-transition validator rejects illegal jumps.

### Worker brief rewrite

- [X] T010 [US1] In `core/commands/trc.chain.md`, locate the `## Worker Brief Template` section (the one created by TRI-27) and replace its body. New content: worker is told to run `/trc.headless` end-to-end; after `/trc.headless` finishes (lint+test green, version bumped), worker MUST run `git add -A && git commit -m "<ticket-id>: <one-line summary>"` explicitly; capture `commit_sha=$(git rev-parse HEAD)`; emit final progress event `{"phase":"committed","completed_at":"<iso>","ticket_id":"<id>","commit_sha":"<sha>"}` to `specs/.chain-runs/<run-id>/<ticket-id>.progress`; return final JSON report (schema in T011); exit. Worker MUST NOT push, MUST NOT pause, MUST NOT ask questions, MUST NOT call `SendMessage`.
- [X] T011 [US1] In `core/commands/trc.chain.md` Worker Brief Template (T010), document the exact JSON report schema the worker must return: `{ticket_id, status: "committed"|"failed", branch, commit_sha (null on failure), files_changed (list or null), lint_status, test_status, worker_error (null on success), open_questions (array, may be empty), summary (one paragraph)}`. Wrap in fenced ```json``` block. Tell the worker explicitly: "After this JSON block, write nothing else."
- [X] T012 [US1] In `core/commands/trc.chain.md` Worker Brief Template, keep the brief under ~400 words. Trim TRI-27's old "5. PAUSE BEHAVIOR" subsection entirely. Trim "2. NEVER auto-approve pushes" wording (the worker doesn't push at all in the new contract; the orchestrator handles push). Verify total word count fits.

### Tests for US1 helper changes

- [X] T013 [P] [US1] Add new test cases to `tests/test-chain-run-update-ticket.js`: (a) happy path `not_started → in_progress → committed → pushed → merged → completed` walking each transition with appropriate flags; (b) `committed` requires `--commit-sha` → ERR_COMMIT_SHA_REQUIRED; (c) `--commit-sha` immutable on second different value → ERR_COMMIT_SHA_IMMUTABLE; (d) backward transition (`committed → in_progress`) → ERR_BAD_TRANSITION; (e) skip transition (`not_started → merged`) → ERR_BAD_TRANSITION; (f) `failed` legal from `in_progress`, `committed`, `pushed`, `merged`; (g) `skipped` legal only from `not_started` (in_progress → skipped → ERR_BAD_TRANSITION).
- [X] T014 [P] [US1] Add round-trip test: after `update-ticket --status committed --commit-sha abc123`, calling `get` returns `commit_sha: "abc123"`, and a subsequent `update-ticket --status pushed --pr <url>` retains the `commit_sha` value unchanged.

### FR-013 static guard

- [X] T015 [US1] Create `tests/test-chain-run-no-sendmessage.sh`: bash script that grep-checks `core/commands/trc.chain.md` for any case-insensitive `SendMessage` substring. Exit 0 if zero matches, exit 1 with the offending line numbers if any match. Make it executable.

**Checkpoint**: Worker brief is rewritten. Helper validates the new transition rules. The `SendMessage` static guard is in place. The new contract is fully expressed in source; what remains is the orchestrator's per-ticket loop wiring (US2).

---

## Phase 4: User Story 2 — Orchestrator runs push/PR/merge per ticket, asking the user every time (Priority: P1)

**Goal**: After a worker returns a `committed` report, the orchestrator prints a one-line summary, asks the user "push?" in plain dialog, and on approval runs `git push → gh pr create → gh pr merge → worktree cleanup`, marking each ticket transition in state.json. No `SendMessage` ever called.

**Independent Test**: After the helper-side T013 test passes, walk through an end-to-end bash test that simulates the full transition path with simulated git/gh calls (or real ones in a temp repo). Verify each `update-ticket` call succeeds and final state has `status: "completed"` with `commit_sha`, `pr_url`, and timestamps.

### Orchestrator command-file edits

- [X] T016 [US2] In `core/commands/trc.chain.md`, **delete** the entire `## Runtime Probe` section (T031 in TRI-27). The probe was a `SendMessage`-based check for a feature that doesn't exist; removing it is a no-op for users.
- [X] T017 [US2] In `core/commands/trc.chain.md`, **delete** the entire `## Push Approval Invariant` section. The invariant moves into the new orchestrator push step (T019) — keeping it as a separate section creates two sources of truth.
- [X] T018 [US2] In `core/commands/trc.chain.md` `## Per-Ticket Loop`, **delete** the pause-relay loop (the `3. **Pause-relay loop**` step from TRI-27 with all its `SendMessage` instructions). Replace with: "3. **Block on worker return.** When the worker's `Agent()` call returns, the worker is dead. Parse the return message as a structured JSON report (per the Worker Brief Template). If the JSON is missing, malformed, or has missing required fields, treat as `worker_error: 'malformed report'` and proceed to step 5b (failure path)."
- [X] T019 [US2] In `core/commands/trc.chain.md` `## Per-Ticket Loop`, replace step 5 ("Record terminal state") with two branches: **5a (committed report)** — call `chain-run.sh update-ticket --status committed --commit-sha <sha> --branch <name> --lint <s> --test <s>`, then proceed to the new `## Orchestrator Push Step`. **5b (failed report)** — call `update-ticket --status failed --finished-now --lint <s> --test <s>`, immediately `chain-run.sh close --terminal-status failed --reason "<short>"`, jump to Summary, do NOT advance.
- [X] T020 [US2] In `core/commands/trc.chain.md`, **add** a new top-level section `## Orchestrator Push Step` after `## Per-Ticket Loop`. Body documents, in order: (1) print one-line summary `[<ticket-id>] <commit-sha-short> — <files-changed-count> files — lint:<s> test:<s>` followed by the worker's `summary` paragraph; (2) explicitly ask the user "Push <ticket-id>? (yes/no)" and **wait for their reply in plain dialog**; (3) on `no` → orchestrator stops the chain, leaves the ticket as `committed`, leaves the worktree intact, jumps to Summary; (4) on `yes` → run `git -C <worktree_path> push -u origin <branch>`, on success call `update-ticket --status pushed --pr <url>` (use `gh pr create` to get the URL), then `gh pr merge <num> --squash --delete-branch` (per `push.merge_strategy` and `push.auto_merge` from config), then `update-ticket --status merged`, then worktree cleanup (`git worktree remove`, `git branch -d`), then `update-ticket --status completed --finished-now`; (5) any failure in steps (4) → `update-ticket --status failed`, `close --terminal-status failed --reason "<step that failed>"`, jump to Summary; (6) on success of all (4) → continue per-ticket loop to next ticket.
- [X] T021 [US2] In `core/commands/trc.chain.md` `## Orchestrator Push Step`, add an **explicit invariant note**: "Push approval is asked once per ticket, every time. Prior approvals never carry over. Even if the user approved 5 pushes already in this chain run, the 6th still requires a fresh 'yes'." This is the relocated `## Push Approval Invariant` content from T017.
- [X] T022 [US2] In `core/commands/trc.chain.md`, **remove every reference to `SendMessage`** from the file. Search the file for `SendMessage` (case-insensitive) and delete or rewrite each occurrence. The static guard test (T015) will catch any miss.

### Tests for US2 orchestrator integration (helper-level, since the orchestrator is markdown not code)

- [X] T023 [P] [US2] Update `tests/test-chain-run-e2e-happy.sh` (TRI-27's existing happy-path bash test): walk through the new full transition path. After the existing init + 2 ticket-completion update calls, replace the "completed" call with the new sequence: `update-ticket --status committed --commit-sha $(echo "fake-sha-$tid" | sha256sum | head -c 40) --branch $tid-feat --lint pass --test pass`, then `update-ticket --status pushed --pr "https://example.com/pr/$tid"`, then `update-ticket --status merged`, then `update-ticket --status completed --finished-now`. Assert state at each step.

### Documentation

- [X] T024 [P] [US2] In `core/commands/trc.chain.md` `## Context Hygiene` (carried over from TRI-27), keep the existing rules and **add** one bullet: "The orchestrator MUST NEVER call `SendMessage` to a returned worker. The worker is dead at that point. Any attempt is a contract violation, mechanically enforced by tests/test-chain-run-no-sendmessage.sh."

**Checkpoint**: US2 complete. The orchestrator handles the entire push/PR/merge cycle in plain dialog. No `SendMessage` references remain anywhere in `trc.chain.md`. The static guard test is wired up. The feature is now functional end-to-end with the new contract.

---

## Phase 5: User Story 3 — Honest progress trail from dead workers (Priority: P2)

**Goal**: When a worker dies unexpectedly mid-phase, the `<ticket-id>.progress` file reflects what actually completed (not what was about to start), so the user can resume from the last known-good phase.

**Independent Test**: Manually write a `phase_specify_complete` event to a progress file, then call `chain-run.sh progress` and assert the returned phase is `specify_complete`. Update the existing progress test for the new event format.

### Worker brief: end-of-phase event semantics

- [X] T025 [US3] In `core/commands/trc.chain.md` Worker Brief Template (T010), add the explicit phase-event instruction: "At the **END** of each completed trc phase (`/trc.specify`, `/trc.clarify`, `/trc.plan`, `/trc.tasks`, `/trc.analyze`, `/trc.implement`), write `{\"phase\":\"<phase>_complete\",\"completed_at\":\"<iso>\",\"ticket_id\":\"<id>\"}` to `specs/.chain-runs/<run-id>/<ticket-id>.progress` (overwrite, not append). Use the exact phase suffixes: `specify_complete, clarify_complete, plan_complete, tasks_complete, analyze_complete, implement_complete`. After the explicit `git commit`, write the final event with `phase:\"committed\"` and the `commit_sha` field included."

### Helper: progress display reads `_complete`

- [X] T026 [US3] In `core/commands/trc.chain.md` `## Progress Display` section (carried over from TRI-27), update the display logic to render "last completed phase" rather than "current phase". E.g., `[<ticket-id>] last completed: <phase> ⏱ <elapsed>s` where `<phase>` is read from `chain-run.sh progress` and stripped of the `_complete` suffix for display.

### Tests for US3

- [X] T027 [P] [US3] Update `tests/test-chain-run-progress.js`: change all test-written progress events from `{"phase": "plan", ...}` to `{"phase": "plan_complete", ...}`. Add a new test case "final committed event includes commit_sha": write `{"phase":"committed","commit_sha":"abc123","ticket_id":"TRI-X"}` and assert `progress` returns the phase and (via JSON parse of stdout) the `commit_sha` field.

**Checkpoint**: US3 complete. Progress trail is honest. Workers leave end-of-phase markers so dead workers don't lie about what was about to run.

---

## Phase 6: User Story 4 — Resume via git, not state files alone (Priority: P2)

**Goal**: On resume, the orchestrator cross-checks each ticket's recorded state against actual git state in the worktree. A `committed` ticket whose `commit_sha` matches the worktree's HEAD is skipped (worker not re-spawned) and goes straight to the push gate.

**Independent Test**: Create a temp git repo, init a chain run with the temp repo as the worktree path, mark a ticket `committed` with `commit_sha` matching the temp repo's HEAD, then call the orchestrator's resume path (manually, since the orchestrator is markdown). Assert the resume detection logic identifies the match correctly.

### Orchestrator command-file: cross-check on resume

- [X] T028 [US4] In `core/commands/trc.chain.md` `## Resume Detection` section (carried over from TRI-27), add a sub-step **before** offering Resume/Discard/Ignore: for each ticket in the interrupted run with status ∈ {`committed`, `pushed`, `merged`}, run a git cross-check. Pseudocode in the markdown: `for each ticket marked committed/pushed/merged: locate worktree at tickets[id].worktree_path; run "git -C <wt> rev-parse HEAD" and compare to commit_sha; for pushed: also run "git -C <wt> ls-remote origin <branch>" and compare; for merged: run "gh pr view <pr_url> --json state" and assert state==MERGED. On any mismatch, surface it: '[<ticket-id>] state.json says <status> but git/gh disagrees: <details>. Re-spawn worker / Skip / Abort?' Wait for user choice.`
- [X] T029 [US4] In `core/commands/trc.chain.md` Resume Detection, document the resume entry-point logic per ticket status: **completed/skipped** → not touched, no worker; **merged** → not touched (already shipped); **pushed** → orchestrator can either jump to merge step (if `gh pr view` says still OPEN) or mark `merged` (if already merged); **committed** → jump straight to the Orchestrator Push Step (T020) without spawning a worker; **in_progress / not_started** → spawn a fresh worker via the per-ticket loop.

### Tests for US4 (helper-level cross-check support)

- [X] T030 [P] [US4] Update `tests/test-chain-run-e2e-resume.sh`: after marking a ticket `committed` (with a fake commit_sha and worktree path), assert that `list-interrupted` returns the run with the `current_index` advanced past the `committed` ticket (so resume jumps to the next un-spawned ticket). Add a second scenario: mark a ticket `pushed` with a `pr_url`, assert `list-interrupted` still shows the run as in_progress (we haven't called `close` yet, since later tickets remain).
- [X] T031 [P] [US4] Update `tests/test-chain-run-interrupted.js` for the new `current_index` advancement rule from T003: assert that a chain with `[TRI-1: committed, TRI-2: not_started]` shows `next_ticket_id: "TRI-2"` (not `"TRI-1"`).

**Checkpoint**: US4 complete. Resume cross-checks git state, never re-runs a worker for verifiably-already-done work, and surfaces inconsistencies to the user instead of silently re-doing work.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Wire new tests into the runner, run the gate, version bump.

- [X] T032 In `tests/run-tests.sh`, under the existing `# ── chain-run.sh (TRI-27) ──` section, add a new line: `run_test "FR-013 no SendMessage in trc.chain.md" bash "$REPO_ROOT/tests/test-chain-run-no-sendmessage.sh"`. Place it adjacent to the other chain-run tests.
- [X] T033 In `tests/run-tests.sh`, the existing `node --test tests/test-chain-run-*.js` line already picks up the modified test files via glob; verify nothing needs changing.
- [X] T034 Run `bash tests/run-tests.sh` and ensure all tests pass (including the new T013, T014, T015, T023, T027, T030, T031 tests). Fix any failures. Do NOT proceed to PR if anything is red.
- [X] T035 [P] Run `node --test tests/test-chain-run-*.js` directly to confirm the node-level test suite passes in isolation as well.
- [X] T036 [P] Manually walk through `specs/TRI-30-chain-run-to-commit/quickstart.md` step-by-step against the implemented changes; fix any drift between the doc and the actual implementation.
- [X] T037 At the very end, update repository `VERSION` from `0.18.1` to `0.18.2` (patch bump per plan.md rationale: fix to a shipped feature). This is typically done by `/trc.implement` itself, but listing it explicitly so it cannot be forgotten.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Empty by design.
- **Phase 2 (Foundational)**: T001–T009. Strictly serial within `chain-run.sh` (single file), parallel only for the test edits T008/T009. Blocks all user story phases.
- **Phase 3 (US1)**: T010–T015. Worker brief rewrite + helper test additions + static guard. Depends on Phase 2.
- **Phase 4 (US2)**: T016–T024. Orchestrator command-file edits + e2e bash test. **Depends on Phase 3** (T015 guard test must exist before T022 deletes the last `SendMessage` references, so we can verify the deletion).
- **Phase 5 (US3)**: T025–T027. Worker brief addition + display update + progress test update. Depends on Phase 3 (touches the same Worker Brief Template).
- **Phase 6 (US4)**: T028–T031. Orchestrator resume edits + helper tests for resume. Depends on Phase 4 (Orchestrator Push Step must exist for resume to jump into it).
- **Phase 7 (Polish)**: T032–T037. Test-runner wiring + final gate + version bump. Depends on all earlier phases.

### User Story Dependencies

- **US1**: depends on Phase 2 (the helper schema). Delivers the worker contract.
- **US2**: depends on US1 (the worker brief is the input the orchestrator parses; the static guard catches `SendMessage` regressions while we delete them).
- **US3**: depends on US1 (extends the same Worker Brief Template). Independent of US2 in content.
- **US4**: depends on US2 (Resume needs the Orchestrator Push Step to jump into).

Strict serial execution recommended. The `core/commands/trc.chain.md` file is touched by US1, US2, US3, and US4 — parallel work would create merge pain.

### Within Each Phase

- Helper code edits before helper tests (tests need real subcommands to exercise).
- Worker Brief Template (T010–T012) before Per-Ticket Loop edits (T018–T019), since the loop parses what the brief produces.
- Orchestrator Push Step (T020) before Resume cross-check (T028), since resume jumps into the push step.
- The `## Resume Detection` edit (T028) goes last so it can reference all other sections that exist.

### Parallel Opportunities

`[P]` tasks within a phase can run in parallel:
- **Phase 2**: T008, T009 are test-file edits in different files — parallelizable after T001–T007.
- **Phase 3**: T013, T014 are test-file edits in the same file (`test-chain-run-update-ticket.js`) so they should be combined into one writer pass; T015 (new file) is parallel.
- **Phase 4**: T023, T024 are independent of T016–T022's command-file edits — parallelizable.
- **Phase 5**: T027 is parallel with T025/T026.
- **Phase 6**: T030, T031 are different test files — parallelizable.
- **Phase 7**: T035, T036 can run in parallel after T034 passes.

---

## Parallel Example: Phase 2 test updates

```bash
# After T001–T007 (all single-file edits to chain-run.sh) are done:
Task: "Update tests/test-chain-run-update-ticket.js for relaxed pr validation (T008)"
Task: "Update tests/test-chain-run-state.js init schema assertions for commit_sha (T009)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 — both required)

US1 alone is **not shippable**. The worker brief change (US1) without the corresponding orchestrator push step (US2) leaves a worker that commits-and-exits with no one to push it. Both P1 stories are needed for the first usable build.

1. **Phase 2 (Foundational)** — T001–T009. Helper schema. Run helper tests after each subcommand edit to catch regressions early.
2. **Phase 3 (US1)** — T010–T015. Worker brief rewrite. Static guard in place.
3. **Phase 4 (US2)** — T016–T024. Orchestrator wired up. Static guard now catches any `SendMessage` regression.
4. **STOP and VALIDATE**: Run `bash tests/run-tests.sh`. Manually re-read `core/commands/trc.chain.md` end-to-end to confirm: no `SendMessage` references; the per-ticket loop is single-pass; the orchestrator push step is plain dialog; the worker brief explicitly commits. The feature is now shippable.

### Incremental polish

5. **Phase 5 (US3)** — T025–T027. Honest progress trail. Diagnosability bonus.
6. **Phase 6 (US4)** — T028–T031. Resume via git. Robustness bonus.
7. **Phase 7 (Polish)** — T032–T037. Test wiring, gate, version bump. Mandatory before PR.

### Parallel team strategy

Single-developer feature; no team parallelization expected. The serial order above avoids `core/commands/trc.chain.md` merge pain.

---

## Notes

- **The single largest file edit** is `core/commands/trc.chain.md`. It is touched in phases 3, 4, 5, and 6 — but each phase touches different sections (Worker Brief, Per-Ticket Loop, Resume Detection). The serial order avoids cross-phase conflicts within the same section.
- **The single largest helper edit** is `core/scripts/bash/chain-run.sh`. It is touched only in Phase 2; no later phase modifies it. This is intentional — keep the helper changes contained.
- **The static FR-013 guard (T015)** is the most important test in this feature. It is the mechanical enforcement of the negative requirement that defines TRI-30. Do not skip it. Do not weaken it (e.g., to a comment-aware grep). The literal `grep -i SendMessage` is the contract.
- **Constitution gates** (T034) are non-negotiable before PR. The CLAUDE.md "Lint & Test Before Done" rule applies as always.
- **No new files** introduced except `tests/test-chain-run-no-sendmessage.sh`. Everything else is a modification.
- **Version bump (T037)**: `0.18.1 → 0.18.2`. Patch only — this is a fix to a shipped feature, not a new capability.

---

## Format Validation

All 37 tasks above follow the required format: `- [ ] T### [P?] [Story?] Description with file path`. Phase 1 is empty by design. Foundational and Polish phases have no `[Story]` label. User Story phases (T010–T031) all have story labels. File paths are present in every task.
