# Feature Specification: /trc.chain — Workers Run to Commit and Exit; Orchestrator Handles Push

**Feature Branch**: `TRI-30-chain-run-to-commit`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "Fix /trc.chain. Sub-agents do not pause-resume via SendMessage — when Agent() returns, the worker is dead. Redesign: workers run /trc.specify → /trc.plan → /trc.tasks → /trc.implement → git commit → STOP. They never pause, never wait for input. Orchestrator (parent conversation) reads each worker's report, asks the user for push approval, then does git push / gh pr create / gh pr merge / worktree cleanup itself. No SendMessage ever needed."

## Background (non-mandatory but load-bearing)

`/trc.chain` was shipped in v0.17.0 (TRI-27) with a worker contract that assumed Claude Code sub-agents could be paused mid-conversation via `SendMessage` forwarding. **They cannot.** When `Agent()` returns a message, the sub-agent process is terminated; a subsequent `SendMessage` to the same name returns `{"success": true}` but is delivered to a dead inbox.

Tonight's run on POL-568 demonstrated the failure: worker returned a JSON report + a pause question, terminated, and ~30 minutes were lost waiting for the worker to "resume" with the user's approval. It never did.

The fix is a redesign of the worker contract, not a band-aid. Workers must run to a deterministic exit (a local commit) and never wait for input. The orchestrator's parent conversation — which has full tool access and a live conversation with the user — handles every interactive step (push approval, PR creation, merge, cleanup) directly, in plain dialog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Workers run to a clean commit and exit (Priority: P1) 🎯 MVP

As a developer using `/trc.chain` on a batch of tickets, I want each worker to run the full trc workflow up through a local git commit on its own branch in its own worktree, and then exit, so that I never have to wait for a "ghost worker" that has already terminated, and the orchestrator can take over deterministically from a known git state.

**Why this priority**: This is the load-bearing fix. The current command is non-functional precisely because workers are designed to pause; replacing that with a run-to-commit contract restores the entire feature.

**Independent Test**: Spawn a single worker for a well-specified ticket using the new worker brief template. Verify: the worker runs `/trc.specify → /trc.plan → /trc.tasks → /trc.implement → git commit`, returns a structured JSON report, and is terminated. Verify: `git log` in the worktree shows exactly one new commit on the feature branch. Verify: at no point during the worker run did it ask for user input or wait for a `SendMessage`.

**Acceptance Scenarios**:

1. **Given** a ticket with a clear, non-ambiguous body, **When** the orchestrator spawns the worker, **Then** the worker runs the full trc chain end-to-end without pausing, creates a local commit on the feature branch, and returns a final structured JSON report.
2. **Given** the worker has finished, **When** the orchestrator destructures the report, **Then** the report contains `branch`, `commit_sha`, `files_changed`, `lint_status`, `test_status`, and a one-paragraph `summary` — and **never** a pause question.
3. **Given** the worker encountered an error during `/trc.implement`, **When** it cannot proceed, **Then** it returns a `status: "failed"` report with an error description and exits — it does NOT wait for the user to fix the error.

---

### User Story 2 — Orchestrator runs push/PR/merge per ticket, asking the user every time (Priority: P1)

As a developer, I want the orchestrator (the parent conversation, where I am actively talking to Claude) to take each completed worker's commit, show me a one-line summary, ask me explicitly for push approval, and on approval push the branch, create the PR, squash-merge it, and clean up the worktree — with no `SendMessage` round-trips and no pretending that a dead worker is still listening.

**Why this priority**: Push approval is a durable user preference (`feedback_push_approval_every_time`). The whole reason TRI-27 needed the broken pause-relay was to ask for push approval; with workers exiting at commit, the orchestrator can ask in plain dialog instead. This is what makes the feature actually usable.

**Independent Test**: After a worker completes (US1), verify the orchestrator: (a) reads the worker's report, (b) prints a one-line summary `[TRI-NNN] <commit-sha-short> — <files-changed-count> files — lint:pass test:pass`, (c) explicitly asks the user "push?", (d) on user approval, runs `git push -u`, `gh pr create`, `gh pr merge --squash --delete-branch`, and worktree cleanup, (e) marks the ticket completed in chain state. Verify: at no point does the orchestrator try to call `SendMessage` to the worker.

**Acceptance Scenarios**:

1. **Given** a worker has returned a successful report, **When** the orchestrator processes it, **Then** the orchestrator prints a one-line summary AND asks the user for push approval BEFORE running any `git push` or `gh` command.
2. **Given** the user approves the push, **When** the orchestrator runs the push/PR/merge sequence, **Then** all four steps (push, PR create, merge, worktree cleanup) succeed for that ticket and the chain advances to the next.
3. **Given** the user declines the push, **When** the orchestrator records that decision, **Then** the ticket is marked as `committed` (not `completed`), the orchestrator stops the chain, and the local commit + worktree remain for the user to inspect.
4. **Given** any push or merge step fails (network, conflicts, branch protection), **When** the orchestrator detects the failure, **Then** it surfaces the error to the user and stops the chain — it does NOT auto-retry or move on.

---

### User Story 3 — Honest progress trail from dead workers (Priority: P2)

As a developer running `/trc.chain` on a batch of tickets, when a worker dies unexpectedly mid-phase (laptop sleep, OOM, sub-agent crash), I want the progress file in the run directory to honestly reflect *what actually finished*, not *what was about to start*, so that I can resume diagnosis from the last known-good phase rather than guessing.

**Why this priority**: Diagnosability after failures. Not load-bearing for the happy path but high-value when things go wrong, which is when this feature matters most.

**Independent Test**: Have a worker write a `phase_specify_complete` event after `/trc.specify` finishes, then deliberately kill the worker before `/trc.plan` begins. Verify the `<ticket-id>.progress` file contains `phase_specify_complete` (not `phase_plan` and not `phase_specify`). Verify the orchestrator's display of "last known phase" matches reality.

**Acceptance Scenarios**:

1. **Given** the worker has just finished `/trc.specify`, **When** it writes a progress event, **Then** the event payload has `phase: "specify_complete"` (not `phase: "plan"` and not `phase: "specify"`).
2. **Given** a worker dies between phases, **When** the orchestrator reads the progress file, **Then** the displayed phase reflects the last fully-completed phase, not an aspirational next phase.
3. **Given** a worker reaches `git commit`, **When** it writes its final progress event, **Then** the event payload has `phase: "committed"` (the deterministic terminal state for the worker).

---

### User Story 4 — Resumability via git, not via state files (Priority: P2)

As a developer who closed the laptop mid-chain, when I re-invoke `/trc.chain` I want resume detection to verify each ticket's actual git state in the worktree (does the expected commit exist on the expected branch?) rather than trusting only `state.json`, so that resume is correct even if state files are stale or partially written.

**Why this priority**: Strengthens resumability. Together with US3 it makes "I came back the next morning" a first-class workflow rather than a debugging nightmare.

**Independent Test**: Manually simulate an interrupted run: init a chain, mark ticket 1 as `committed` in `state.json`, but also create a real commit in the worktree. Re-invoke `/trc.chain`. Verify the orchestrator's resume flow detects the commit and skips ticket 1 (or asks the user to re-push if not yet pushed), without re-spawning a worker for it.

**Acceptance Scenarios**:

1. **Given** ticket N is marked `committed` in `state.json` AND a commit exists on the expected feature branch, **When** the orchestrator resumes, **Then** it offers to push that commit (US2) without re-running the worker.
2. **Given** ticket N is marked `committed` in `state.json` BUT no matching commit exists in the worktree, **When** the orchestrator resumes, **Then** it warns the user about the inconsistency and asks whether to re-spawn the worker or skip the ticket.
3. **Given** ticket N is marked `pushed` or `merged`, **When** the orchestrator resumes, **Then** it does not touch that ticket again.

---

### Edge Cases

- **Worker crashes mid-implement**: Worker exits without writing a final report. Orchestrator times out (or the user notices the silence) and surfaces `worker_crashed`. Ticket marked `failed` in state. Chain stops per stop-on-failure policy.
- **Worker runs successfully but tests fail**: Worker still commits its work-in-progress (or doesn't, depending on its own gates) and returns `status: "failed", test_status: "fail"`. Orchestrator stops the chain and does NOT push.
- **User approves the push but `git push` is rejected** (force-push needed, branch already exists upstream, etc.): Orchestrator surfaces the error, does NOT auto-resolve, marks ticket `failed`, stops the chain.
- **User approves the push but `gh pr create` fails** (auth expired, repo not configured): Same — surface and stop.
- **User declines push on the first ticket of a multi-ticket chain**: Chain stops; subsequent tickets remain `not_started`. The committed ticket is left as a local branch + worktree for the user to handle manually.
- **A `committed` ticket fails its merge** (merge conflicts after squash): Orchestrator marks `failed`, stops the chain, leaves the worktree intact for manual recovery.
- **Worker writes a progress event then crashes immediately**: The progress file reflects the last completed phase honestly. Orchestrator's resume flow uses git state as the primary source of truth (US4), with the progress file as supporting context only.
- **Existing `committed` status from a prior interrupted run on resume**: Treated per US4 — git state checked first, state.json second.

## Requirements *(mandatory)*

### Functional Requirements

#### Worker contract

- **FR-001**: Each worker spawned by `/trc.chain` MUST run the full trc workflow (`/trc.specify → /trc.plan → /trc.tasks → /trc.implement`) end-to-end and then create a local git commit on its feature branch in its worktree. The commit IS the worker's deterministic exit condition.
- **FR-002**: Workers MUST NOT pause for any user input. They MUST NOT wait for `SendMessage`. They MUST NOT ask clarifying questions back to the orchestrator. If the trc workflow they run encounters an ambiguity, the worker either auto-resolves it with reasonable defaults (per `/trc.headless` semantics) or fails the ticket and exits with a `failed` report.
- **FR-003**: Workers MUST return exactly one final structured JSON report on exit, in a fenced `json` block. The report MUST contain at minimum: `ticket_id`, `status` (`committed` or `failed`), `branch`, `commit_sha` (null on failure), `files_changed` (list or null), `lint_status`, `test_status`, `worker_error` (null on success), `open_questions` (array, may be empty), and `summary` (one-paragraph human description).
- **FR-004**: Workers MUST NOT run `git push`, `gh pr create`, `gh pr merge`, or any other remote-mutating command. Their authority ends at the local commit.
- **FR-005**: Workers MUST run inside their own git worktree, isolated from the orchestrator's checkout and from sibling workers, per the existing `--provision-worktree` mechanism (TRI-26).

#### Worker progress signaling

- **FR-006**: At the END of each trc phase the worker completes (specify, clarify, plan, tasks, analyze, implement), the worker MUST overwrite `specs/.chain-runs/<run-id>/<ticket-id>.progress` with a JSON event of the form `{"phase": "<phase>_complete", "completed_at": "<iso8601>", "ticket_id": "<id>"}`. Events are end-of-phase, not start-of-phase.
- **FR-007**: When the worker reaches its deterministic exit (the local commit), it MUST emit a final progress event with `phase: "committed"` and the commit SHA included in the payload.
- **FR-008**: The orchestrator MUST treat the `<ticket-id>.progress` file as a **trailing record of what completed**, not a prediction of what is about to run. Display logic MUST present "last completed phase" rather than "current phase".

#### Orchestrator contract

- **FR-009**: The orchestrator MUST process tickets serially (per the existing FR-004 in TRI-27's spec — unchanged). For each ticket:
  1. Spawn the worker via `Agent`, in the foreground, blocking on its return.
  2. Parse the structured JSON report from the worker's return message.
  3. If `status: "failed"` → mark the ticket failed, close the chain run with `terminal_status=failed`, stop. (FR-012 stop-on-failure from TRI-27 carries forward.)
  4. If `status: "committed"` → continue to the push gate (FR-010).
- **FR-010**: After receiving a `committed` report, the orchestrator MUST print a one-line summary in the form `[<ticket-id>] <commit-sha-short> — <files-changed-count> files — lint:<status> test:<status>` AND explicitly ask the user for push approval BEFORE running any remote-mutating command. Push approval MUST be requested per ticket; prior approvals never carry over (FR-009 from TRI-27 — unchanged).
- **FR-011**: On push approval, the orchestrator MUST execute, in order: `git push -u origin <branch>`, `gh pr create --base <pr_target> --title <title> --body <body>`, `gh pr merge <pr-number> --squash` (per `push.merge_strategy`, which may also be `merge` or `rebase`), and worktree cleanup (`git worktree remove`, `git branch -d`). If `push.auto_merge` is false, skip the merge step and stop after PR creation, surfacing the URL to the user.
- **FR-012**: On any push/PR/merge failure, the orchestrator MUST surface the error and stop the chain. It MUST NOT auto-retry. It MUST NOT advance to the next ticket. The failed ticket is marked `failed` with the failure reason.
- **FR-013**: The orchestrator MUST NEVER call `SendMessage` to a returned worker. The worker is dead at that point. Any attempt is a contract violation. (This is the load-bearing negative requirement and the entire reason TRI-30 exists.)

#### State helper changes

- **FR-014**: `chain-run.sh update-ticket` MUST accept a new ticket status `committed` between `in_progress` and `completed`. The valid status enum becomes: `not_started, in_progress, committed, pushed, merged, completed, failed, skipped`. The legal forward transitions are: `not_started → in_progress → committed → pushed → merged → completed`, plus `→ failed` from any non-terminal state, plus `→ skipped` from `not_started`.
- **FR-015**: The state-helper validation rules MUST update accordingly: `pr_url` may be set when `status` is `pushed`, `merged`, or `completed` (was previously: only `completed`). Setting `pr_url` while still `in_progress` or `committed` remains an error.
- **FR-016**: New helper subcommand or extended `update-ticket` flag MUST allow recording the `commit_sha` per ticket, persisted in `state.json` under `tickets.<id>.commit_sha`.
- **FR-017**: The `current_index` advancement rule MUST treat `committed`, `pushed`, `merged`, `completed`, and `skipped` as "done enough to advance past" when computing the next index. (Important for resume — see FR-018.)

#### Resume via git state

- **FR-018**: On `/trc.chain` invocation, when a previously interrupted run is detected (`list-interrupted`), the orchestrator MUST cross-check each ticket's state against actual git state in its worktree:
  - For each ticket marked `committed`, `pushed`, or `merged` in `state.json`: check that the expected branch exists and (where applicable) that the expected `commit_sha` is reachable from the branch tip.
  - On mismatch (state.json says `committed` but no matching commit exists, or state.json says `pushed` but `git ls-remote` finds no upstream branch), surface the inconsistency to the user and ask: re-spawn the worker, skip the ticket, or abort.
  - On match, skip the worker entirely and proceed with whichever orchestrator-side step is next (e.g., a `committed` ticket goes straight to the push approval gate).
- **FR-019**: Resume MUST never re-run a worker for a ticket whose work is verifiably already on disk (`committed`) or upstream (`pushed`/`merged`). Re-running a worker would create duplicate commits and waste time.

#### Tests

- **FR-020**: All existing `chain-run.sh` tests MUST be updated for the new status enum. Any test that exercised the pause-relay loop (e.g., the `runtime probe` or any test that stubs `SendMessage`) MUST be removed; the runtime probe itself MUST be removed from `core/commands/trc.chain.md` (see FR-013).
- **FR-021**: New tests MUST cover: the full `not_started → in_progress → committed → pushed → merged → completed` transition path; the new `committed` status validation; the new `commit_sha` field round-trip; the resume-via-git mismatch detection (covered by helper-level tests of `list-interrupted` returning enough information for the orchestrator to do its git checks).
- **FR-022**: An end-to-end bash test MUST exercise: helper init → simulated worker reaches `committed` → orchestrator-side simulated push (mocked `git push` / `gh`) → ticket transitions through `pushed → merged → completed` → run closed.

### Key Entities

- **Worker Report** (revised): The single JSON payload a worker returns on exit. Fields: `ticket_id`, `status` (`committed`|`failed`), `branch`, `commit_sha`, `files_changed`, `lint_status`, `test_status`, `worker_error`, `open_questions`, `summary`. **No pause-question shape exists**; pause questions are not a thing in the new contract.
- **Progress Event** (revised): `{"phase": "<phase>_complete", "completed_at": "<iso8601>", "ticket_id": "<id>", "commit_sha"?: "<sha>"}`. Events name the **completed** phase, not the upcoming one. Final terminal event has `phase: "committed"`.
- **Chain Run State** (extended): `tickets.<id>` entry gains `commit_sha` (string|null). The status enum is extended (FR-014). Everything else from TRI-27's data model carries forward unchanged.
- **Orchestrator Push Step**: A new conceptual stage in the per-ticket loop, owned entirely by the parent conversation, comprising: read report → print summary → ask user → push → PR create → merge → worktree cleanup → mark `completed`. Has no representation in the worker; it lives only in the orchestrator command instructions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A chain of 3 tickets can be executed end-to-end on the new contract with **zero** `SendMessage` calls. (Verified by reading the orchestrator command file and confirming `SendMessage` does not appear in it.)
- **SC-002**: When a worker returns its report, the orchestrator's **next** action is always either (a) printing a one-line summary and asking the user for push approval, or (b) marking the ticket failed and stopping the chain. It is never "send a message back to the worker".
- **SC-003**: A worker, on its first invocation for a well-specified ticket, runs to a local commit and exits, without ever blocking on user input, in a single uninterrupted execution. Verified across at least 3 distinct ticket runs.
- **SC-004**: Push approval is requested **once per ticket, every time**, regardless of how many tickets in the same chain run have already been approved. Verified by counting prompts in a 3-ticket chain run = 3.
- **SC-005**: Resume from an interrupted chain correctly distinguishes the four resume cases (committed-but-not-pushed, pushed-but-not-merged, merged-but-not-completed, mismatched-state), verified across at least one test scenario per case.
- **SC-006**: Existing TRI-27 functionality that is not directly tied to pause-resume — `parse-range`, `init`, `get`, `close`, `list-interrupted`, `progress`, max-8 enforcement, mixed-prefix range rejection, gitignore of `.chain-runs/`, atomic state writes — continues to pass its tests after the redesign. (Regression gate.)
- **SC-007**: After this ticket ships and is merged, running the new `/trc.chain` on a 2-ticket batch (POL-569 / POL-578) completes both tickets without dead-air debugging or ghost-worker waits.

## Assumptions

- The worker's invocation of `/trc.headless` will, on its own, do a final `git commit` at the end of `/trc.implement`. This is consistent with how the existing `trc.headless` and `trc.implement` flows behave (the `lint-test gate` passes, version is bumped, files are committed). If `/trc.headless` does NOT commit, the worker brief will need to add an explicit `git add . && git commit -m "<auto>"` step — but this is the fallback, not the expected path.
- The orchestrator (the parent conversation) has authenticated `gh` available, has push permission on the repo, and is running in a runtime where it can invoke `Agent` for worker spawning. (Same assumption set as TRI-27.)
- The Linear MCP server is reachable at chain start. (Carried forward from TRI-27, FR-002. No change.)
- `push.merge_strategy` is one of `squash`, `merge`, `rebase` and is read from `tricycle.config.yml`. (Already exists from TRI-27.)
- `push.auto_merge` controls whether the orchestrator merges automatically after PR creation or stops at the PR URL. (Already exists from TRI-27.)
- The new `committed` status is forward-compatible: existing chain runs from v0.17.0 with no `committed` value in state.json will continue to load (the helper just won't see that status until updated runs are created post-fix).
- The progress-event semantics change (`phase_X_complete` instead of `phase_X`) is **not** backward-compatible with v0.17.0 progress files — but progress files are ephemeral runtime state, not persisted across chain runs, so this is acceptable.
- `feedback_trc_chain_no_pause_relay` (the memory entry) is the single source of truth for "do not use SendMessage to resume sub-agents". The TRI-30 spec, plan, and command instructions all reinforce this; the memory is what survives across conversations.
