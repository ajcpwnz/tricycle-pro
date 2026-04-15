---
description: "Task list for TRI-27-trc-chain-orchestrator"
---

# Tasks: trc.chain — Orchestrate Full TRC Workflow Across a Range of Tickets

**Feature**: TRI-27-trc-chain-orchestrator
**Input**: Design documents from `specs/TRI-27-trc-chain-orchestrator/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/chain-run-helper.md ✅, quickstart.md ✅

**Tests**: INCLUDED. The contract at `contracts/chain-run-helper.md` mandates tests for every helper subcommand (happy path + at least one error code + round-trip). This project follows the existing TRI-26 pattern of `node --test tests/test-*.js` + `tests/run-tests.sh`.

**Organization**: Tasks are grouped by user story from `spec.md`. US1 and US2 are both P1; US1 ships the happy-path chain execution and is the MVP; US2 adds the checkpoint-relay mechanism on top. US3 (stop-on-failure) and US4 (epic brief) layer on after. Resumability (from clarification Q1) is cross-cutting and lives in the Polish phase alongside the `list-interrupted` subcommand (built in Foundational).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All file paths are repo-root-relative unless otherwise noted.

## Path Conventions

Single-project layout (Option 1 from plan.md). Source lives under `core/`, tests under `tests/`, runtime state under `specs/.chain-runs/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repo-level plumbing needed before any code is written.

- [X] T001 Add `specs/.chain-runs/` to `.gitignore` at repo root so runtime chain-run state never leaks into commits
- [X] T002 [P] Create empty helper scaffold at `core/scripts/bash/chain-run.sh` with `#!/usr/bin/env bash`, `set -euo pipefail`, source of `core/scripts/bash/common.sh`, and a top-level subcommand dispatch stub that prints `usage` for unknown commands and exits 2
- [X] T003 [P] Create empty command template at `core/commands/trc.chain.md` with YAML frontmatter (`description: "Run the full trc workflow across a range of Linear tickets serially with fresh context per ticket"`) and placeholder sections (`## User Input`, `## Execution Flow`), so `assemble-commands.sh` picks it up
- [X] T004 Verify `core/scripts/bash/chain-run.sh` is executable (`chmod +x`) and `core/scripts/bash/assemble-commands.sh` does not need updating for this file to be discovered

**Checkpoint**: Scaffold exists. `bash core/scripts/bash/chain-run.sh` prints usage. `core/commands/trc.chain.md` is discoverable. `.gitignore` protects runtime state.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Helper subcommands and state-file mechanics that every user story relies on. Nothing in Phase 3+ can start until this phase is complete.

**⚠️ CRITICAL**: All user story phases depend on Phase 2 completion.

### Helper: state file primitives

- [X] T005 Implement `json_builder.sh`-backed helper function `chain_run_write_state_atomic(run_dir, state_json)` inside `core/scripts/bash/chain-run.sh` that writes to `${run_dir}/state.json.tmp` and `mv`-renames to `${run_dir}/state.json` (atomic update, per research.md R4)
- [X] T006 Implement helper function `chain_run_read_state(run_dir)` inside `core/scripts/bash/chain-run.sh` using a `python3 -c` one-liner to load and echo JSON, returning non-zero if file missing (per research.md R4)
- [X] T007 Implement helper function `chain_run_generate_run_id(first_ticket_id)` inside `core/scripts/bash/chain-run.sh` producing `YYYYMMDDTHHMMSS-${first_ticket_id}` format (per data-model.md)
- [X] T008 Implement helper function `chain_run_iso8601_now()` inside `core/scripts/bash/chain-run.sh` wrapping `date -u +"%Y-%m-%dT%H:%M:%SZ"` for consistent timestamping

### Helper: subcommand `parse-range`

- [X] T009 Implement `parse-range <arg>` subcommand in `core/scripts/bash/chain-run.sh` covering: range form `PREFIX-N..PREFIX-M`, list form `PREFIX-N,PREFIX-M,...`, dedup, max-8 enforcement (FR-003), mixed-prefix rejection in range form, descending-range rejection, malformed-token rejection (per contracts/chain-run-helper.md)
- [X] T010 [P] Write tests for `parse-range` in `tests/test-chain-run-parse-range.js` covering: happy path contiguous range, happy path mixed-prefix list, dedup, count > 8 → ERR_COUNT_EXCEEDED, mixed-prefix range → ERR_RANGE_MIXED_PREFIX, descending → ERR_RANGE_DESCENDING, malformed token → ERR_MALFORMED_TOKEN, empty input → ERR_EMPTY_INPUT

### Helper: subcommand `init`

- [X] T011 Implement `init --ids <json-array> [--brief <path>] [--ids-raw <string>]` subcommand in `core/scripts/bash/chain-run.sh` that: validates ids count (1–8), generates run-id via T007, creates `specs/.chain-runs/<run-id>/`, optionally copies brief to `specs/.chain-runs/<run-id>/epic-brief.md`, writes initial `state.json` with `status=in_progress`, `current_index=0`, and all tickets in `not_started` (per data-model.md)
- [X] T012 [P] Write tests for `init` in `tests/test-chain-run-state.js` covering: happy path creates dir + state.json + returns run_id/state_path/brief_path, brief copy works, brief-missing → ERR_BRIEF_MISSING, ids over 8 → ERR_COUNT_EXCEEDED, ids empty → ERR_COUNT_ZERO, state.json schema matches data-model.md

### Helper: subcommand `get`

- [X] T013 Implement `get --run-id <id>` subcommand in `core/scripts/bash/chain-run.sh` returning the pretty-printed `state.json`, with ERR_RUN_NOT_FOUND (exit 4) when the directory or file is missing
- [X] T014 [P] Add `get` test cases to `tests/test-chain-run-state.js`: happy path after init, ERR_RUN_NOT_FOUND, idempotency (read twice returns identical bytes)

### Helper: subcommand `list-interrupted`

- [X] T015 Implement `list-interrupted` subcommand in `core/scripts/bash/chain-run.sh` that scans `specs/.chain-runs/*/state.json`, filters to `status == "in_progress"`, and emits `{"runs": [...]}` with per-run `run_id`, `created_at`, `updated_at`, `ticket_ids`, `current_index`, and computed `next_ticket_id` (per contracts/chain-run-helper.md)
- [X] T016 [P] Write tests for `list-interrupted` in `tests/test-chain-run-interrupted.js` covering: no runs → `{"runs":[]}`, one in-progress run listed, closed runs (completed/failed/aborted) excluded, multiple in-progress runs sorted by `updated_at` desc, missing state dir → `{"runs":[]}` (not error)

**Checkpoint**: `parse-range`, `init`, `get`, `list-interrupted` all work end-to-end and are covered by tests. User story phases can now begin.

---

## Phase 3: User Story 1 — Run ticket range end-to-end with fresh context per ticket (Priority: P1) 🎯 MVP

**Goal**: A user can invoke `/trc.chain TRI-100..TRI-102` and have each ticket processed serially in its own fresh worker sub-agent, producing branches, PRs, and a final summary table. (Pause handling and richer relay semantics are deferred to US2.)

**Independent Test**: Invoke `/trc.chain` on a 3-ticket range where every ticket's trc.headless run completes without any clarify question or plan approval gate (e.g., well-specified tickets). Verify: each runs in its own worker, each produces a branch, each produces a report, orchestrator's context does not grow with worker transcripts, and a summary table is printed at the end.

### Helper: subcommand `update-ticket` + `close` (needed for US1)

- [X] T017 [US1] Implement `update-ticket --run-id <id> --ticket <tid> --status <s> [options]` subcommand in `core/scripts/bash/chain-run.sh` that: validates run exists (ERR_RUN_NOT_FOUND), validates ticket in ticket_ids (ERR_TICKET_NOT_IN_RUN), validates run not closed (ERR_RUN_CLOSED), validates status is legal (ERR_BAD_STATUS), validates pr requires completed (ERR_PR_REQUIRES_COMPLETED), updates the ticket entry fields, appends `open_questions`, advances `current_index` past any trailing completed/skipped tickets, bumps `updated_at`, and atomically writes via T005
- [X] T018 [P] [US1] Write tests for `update-ticket` in `tests/test-chain-run-update-ticket.js` covering: happy path transition not_started → in_progress → completed, all error codes from contracts/chain-run-helper.md, `--started-now` / `--finished-now` timestamp behavior, `--open-question` repeatable flag, round-trip (update then `get` shows the change)
- [X] T019 [US1] Implement `close --run-id <id> --terminal-status <s> [--reason <string>]` subcommand in `core/scripts/bash/chain-run.sh` that: validates run exists, validates terminal-status (completed/failed/aborted), sets top-level `status` + `terminal_reason`, deletes all `*.progress` files in the run dir, atomically writes, idempotent (already-closed → warning to stderr, exit 0)
- [X] T020 [P] [US1] Write tests for `close` in `tests/test-chain-run-close.js` covering: close completed, close failed with reason, close aborted, ERR_RUN_NOT_FOUND, ERR_BAD_STATUS, idempotent re-close, verify `.progress` files removed

### Orchestrator command: happy-path chain execution

- [X] T021 [US1] In `core/commands/trc.chain.md`, write the `## User Input` parsing section that extracts the range-or-list argument and calls `chain-run.sh parse-range` via Bash tool; on non-zero exit, surface the JSON error from stderr to the user and abort
- [X] T022 [US1] In `core/commands/trc.chain.md`, write the `## Linear Fetch` section instructing the agent to call Linear MCP (`mcp__linear-server__get_issue`) for each parsed ticket ID, collecting `{id, title, body}`, and hard-failing with `ERR_LINEAR_UNREACHABLE` / `ERR_TICKETS_NOT_FOUND` if any fetch errors or returns missing (per FR-002 clarification)
- [X] T023 [US1] In `core/commands/trc.chain.md`, write the `## Scope Confirmation` section that prints the ticket list (ID + title) and asks the user an explicit go/no-go question, aborting cleanly on no (no side effects to undo)
- [X] T024 [US1] In `core/commands/trc.chain.md`, write the `## Run Init` section that calls `chain-run.sh init --ids '<json>'` via Bash tool, captures `run_id` and `state_path`, and stores them in working memory for the rest of the orchestrator's execution
- [X] T025 [US1] In `core/commands/trc.chain.md`, write the `## Per-Ticket Loop` section with precise instructions for each iteration: (a) call `chain-run.sh update-ticket ... --status in_progress --started-now`, (b) construct the worker brief (ticket body + brief path placeholder + explicit `/trc.headless` invocation + instruction to emit phase events per T033), (c) spawn the worker via `Agent({name: "chain-worker-<ticket-id>", subagent_type: "general-purpose", prompt: <brief>, description: "trc.headless for <ticket-id>"})` and **block** on its return, (d) parse the worker's structured return report (branch, pr_url, lint_status, test_status, open_questions), (e) call `chain-run.sh update-ticket ... --status completed --finished-now --branch ... --pr ... --lint ... --test ... --report ...`
- [X] T026 [US1] In `core/commands/trc.chain.md`, document the **Worker Brief Template** that every worker receives: ticket ID + title + body, path to epic brief (if any), path to the run directory, exact instructions to run `/trc.headless`, requirement to emit a phase event file at each phase transition, and the exact structured-report format the worker must return (JSON block with branch, pr_url, lint_status, test_status, open_questions, and a human-readable one-paragraph summary). Worker brief MUST be <~400 words so it fits cleanly in the worker's initial prompt
- [X] T027 [US1] In `core/commands/trc.chain.md`, write the `## Summary` section that, after the loop completes, reads `state.json` via `chain-run.sh get`, builds a markdown table (columns: ticket, branch, PR, lint, test, status), prints it to the user, and calls `chain-run.sh close --terminal-status completed`
- [X] T028 [US1] In `core/commands/trc.chain.md`, add the `## Context Hygiene` guardrail explicitly forbidding the orchestrator from retaining any worker-conversation tool output beyond the destructured fields from the structured report (enforces FR-014)

### Integration test for US1

- [X] T029 [P] [US1] Write a bash-level integration test in `tests/test-chain-run-e2e-happy.sh` that: (a) initializes a fake chain run via `chain-run.sh init`, (b) simulates two ticket completions via `update-ticket`, (c) calls `chain-run.sh get` and asserts expected state, (d) calls `chain-run.sh close --terminal-status completed`, (e) asserts state is terminal and `.progress` files are gone. This exercises the helper contract end-to-end without needing a real sub-agent
- [X] T030 [US1] Hook `tests/test-chain-run-*.js` and `tests/test-chain-run-e2e-happy.sh` into `tests/run-tests.sh` so they run as part of `bash tests/run-tests.sh`

**Checkpoint**: US1 MVP complete. `/trc.chain` can run a well-specified ticket range end-to-end and produce branches, PRs, and a summary. No pause handling yet — any worker pause is currently treated as a worker failure.

---

## Phase 4: User Story 2 — Checkpoint relay for clarify, plan approval, and push approval (Priority: P1)

**Goal**: When a worker pauses for user input (clarify, plan approval, push approval), the orchestrator surfaces `[ticket-id] <question>` to the user and forwards the answer to the **same running worker** via `SendMessage`, preserving worker context. Push approval is requested **every time**, never auto-approved.

**Independent Test**: Run `/trc.chain TRI-200` on a ticket deliberately underspecified so that the worker will raise a clarify question. Verify: the orchestrator prints `[TRI-200] <question>`, waits for input, forwards it via `SendMessage` to the same named worker (not a new one), and the worker resumes with full prior context. Separately verify: push approval is requested for every ticket, even on a 3-ticket chain where all prior pushes were approved.

### Runtime probe + phase display

- [X] T031 [US2] In `core/commands/trc.chain.md`, add a `## Runtime Probe` section at chain start (before any ticket loop) that spawns a throwaway `Agent({name: "chain-probe", prompt: "..."})` and immediately tries `SendMessage({to: "chain-probe", message: "exit"})`. On any failure, abort the chain with a clear error referencing the hard dependency (per research.md R7)
- [X] T032 [US2] In `core/commands/trc.chain.md` Per-Ticket Loop (T025), wrap the worker spawn call in a **pause-relay loop**: when the worker returns **paused** (indicated by a non-terminal return message containing a pause marker), the orchestrator (a) extracts the question, (b) prints `[<ticket-id>] <question>` to the user, (c) waits for the user's reply, (d) calls `SendMessage({to: "chain-worker-<ticket-id>", message: <user reply>})`, (e) continues the loop. Only break out when the worker returns a **terminal** structured report
- [X] T033 [US2] In `core/commands/trc.chain.md` Worker Brief Template (T026), add the phase-event emission instruction: at the start of each trc phase the worker MUST overwrite `specs/.chain-runs/<run-id>/<ticket-id>.progress` with a single-line JSON event `{phase, started_at, ticket_id}` (per research.md R6, FR-023). Include the exact bash one-liner for the worker to run
- [X] T034 [US2] In `core/commands/trc.chain.md`, add a `## Progress Display` helper section describing how the orchestrator updates the user's view between `SendMessage` round-trips: read `<ticket-id>.progress`, format `[<ticket-id>] → <phase> ⏱ <elapsed>`, and update whenever the phase file changes (FR-022). The orchestrator re-reads on a lightweight cadence between worker round-trips — no streaming needed

### Push approval gate

- [X] T035 [US2] In `core/commands/trc.chain.md` Worker Brief Template, add an explicit instruction that the worker MUST pause before `git push` on every ticket and MUST NOT accept a cached or inferred approval from the orchestrator; the orchestrator then relays the approval request to the user per the T032 pause-relay loop. This encodes FR-009 at two layers (worker + orchestrator)
- [X] T036 [US2] In `core/commands/trc.chain.md`, add a `## Push Approval Invariant` note that even within a single chain run, each push is confirmed individually — no "approve all" shortcut, no auto-skip on subsequent tickets

### Tests for US2

- [X] T037 [P] [US2] Write tests for phase-event file handling in `tests/test-chain-run-progress.js`: an agent-simulated worker writes a progress file → a helper function (to be added in T038) reads it → test asserts schema, phase enum validity, latest-write-wins semantics, graceful handling of missing file
- [X] T038 [US2] Add helper function `chain_run_read_progress(run_dir, ticket_id)` inside `core/scripts/bash/chain-run.sh` and a thin `progress --run-id <id> --ticket <tid>` subcommand wrapping it, returning the progress JSON or `{"phase": "unknown"}` if missing. Used by the orchestrator for T034
- [X] T039 [P] [US2] Document the runtime-probe failure path in `tests/test-chain-run-probe-fallback.md` as a manual test procedure (automated test would require mocking the Agent tool, which is out of scope for the shell test suite) — describe exact steps to simulate SendMessage failure and verify clean abort

**Checkpoint**: US2 complete. Workers can pause, the orchestrator relays questions, push approval is enforced every time, phase display works. The feature is now usable on real tickets, not just pre-spec'd happy-path ones.

---

## Phase 5: User Story 3 — Stop-on-failure (Priority: P2)

**Goal**: When one ticket in the chain fails (lint fails, tests fail, worker crashes, push rejected), the orchestrator stops immediately, surfaces the failure with ticket ID and reason, does not spawn a worker for the next ticket, and produces a summary clearly labeling completed/failed/not-started tickets.

**Independent Test**: Run `/trc.chain` on a 3-ticket chain where ticket 2 has a test suite that deliberately fails. Verify: ticket 1 completes normally (branch + PR), ticket 2's worker returns a failure report, orchestrator calls `close --terminal-status failed --reason "..."`, does NOT spawn the ticket-3 worker, and prints a summary where ticket 1 is "completed", ticket 2 is "failed", ticket 3 is "not_started".

### Orchestrator failure handling

- [X] T040 [US3] In `core/commands/trc.chain.md` Per-Ticket Loop (T025), add failure-detection branches: if the worker's structured return report has `lint_status == "fail"` OR `test_status == "fail"` OR an explicit `worker_error` field, OR if the worker returns an error message instead of a structured report, treat the ticket as failed
- [X] T041 [US3] In `core/commands/trc.chain.md`, on detected failure: call `chain-run.sh update-ticket ... --status failed --finished-now` (with fields from whatever partial info is available), **immediately** call `chain-run.sh close --terminal-status failed --reason "<short>"`, print a failure header, and skip all remaining tickets in the list without spawning workers (leave them as `not_started`)
- [X] T042 [US3] In `core/commands/trc.chain.md` Summary section (T027), extend the summary-table builder to clearly render the four possible ticket statuses (completed, failed, skipped, not_started) with distinct visual markers so the failing ticket and the unstarted ones are unambiguous

### Tests for US3

- [X] T043 [P] [US3] Add `tests/test-chain-run-e2e-failure.sh`: initialize a run, mark ticket 1 completed via `update-ticket`, mark ticket 2 failed via `update-ticket --status failed`, call `close --terminal-status failed --reason "test fail"`, then call `get` and assert state has: ticket 1 completed, ticket 2 failed, ticket 3 not_started, top-level status=failed, terminal_reason set
- [X] T044 [US3] Add an assertion to `tests/test-chain-run-e2e-failure.sh` that after `close --terminal-status failed`, `list-interrupted` no longer includes this run

**Checkpoint**: US3 complete. The chain now stops cleanly on failure with clear user-visible state.

---

## Phase 6: User Story 4 — Shared epic-brief.md cross-ticket context (Priority: P3)

**Goal**: Users can optionally supply or create an `epic-brief.md` at chain start. If present, its path is passed to every worker; it is the **only** cross-ticket context workers share. Lives at `specs/.chain-runs/<run-id>/epic-brief.md` per clarification Q2.

**Independent Test**: Invoke `/trc.chain` on a 2-ticket range; when asked about the epic brief, supply a pre-authored brief file. Verify: orchestrator copies it into the run directory, both worker prompts include the brief's path, each worker (via trc.headless) reads the brief as part of its context. Separately verify: declining the brief offer proceeds without one and workers are told so.

### Orchestrator epic-brief flow

- [X] T045 [US4] In `core/commands/trc.chain.md`, after Scope Confirmation (T023) and before Run Init (T024), add an `## Epic Brief Prompt` section that asks the user: "Optional: provide a path to an existing epic brief, create one now, or skip." Handle all three branches explicitly
- [X] T046 [US4] In `core/commands/trc.chain.md` Run Init (T024), pass `--brief <path>` to `chain-run.sh init` if the user provided or created one; capture `brief_path` from the init response
- [X] T047 [US4] In `core/commands/trc.chain.md` Worker Brief Template (T026), add a conditional block: if `brief_path` is non-null, include the line `Read the shared epic brief at: <brief_path>` in the worker prompt; if null, include `No shared epic brief for this run; each ticket is independent.`
- [X] T048 [US4] Handle the "create one now" branch in T045 by prompting the user for the brief content inline (multiline input), writing it to a temp file, then passing that path to `init --brief <tmp>`. `chain-run.sh init` already handles the copy per T011

### Tests for US4

- [X] T049 [P] [US4] Add `tests/test-chain-run-epic-brief.sh`: create a temp file with known content, call `chain-run.sh init --ids '["TRI-1","TRI-2"]' --brief <tmp>`, assert that `specs/.chain-runs/<run-id>/epic-brief.md` exists and matches the original content
- [X] T050 [P] [US4] Add a negative-path test in `tests/test-chain-run-epic-brief.sh`: call `init --brief /nonexistent/path` and assert ERR_BRIEF_MISSING with exit 2

**Checkpoint**: US4 complete. Cross-ticket context works when desired, and is cleanly absent when not.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Resumability (from clarification Q1), Linear-unreachable hard-fail (from clarification Q4), documentation, lint/test gate.

### Resumability (cross-cutting — from clarification Q1, FR-019–FR-021)

- [X] T051 In `core/commands/trc.chain.md`, add a `## Resume Detection` section at the very top of the execution flow (before runtime probe T031): call `chain-run.sh list-interrupted`; if any runs are returned, surface them to the user with the prompt "Found N interrupted chain run(s): ... [R]esume / [D]iscard / [I]gnore" per quickstart.md
- [X] T052 On **Resume** branch in T051: read the interrupted run's `state.json` via `chain-run.sh get`, re-use its `run_id`, identify the next ticket whose status is not `completed`/`skipped`, skip completed tickets entirely, and enter the Per-Ticket Loop starting from that ticket. Re-fetch Linear bodies for remaining tickets only
- [X] T053 On **Discard** branch in T051: call `chain-run.sh close --run-id <id> --terminal-status aborted --reason "user discarded"` for each listed interrupted run, then proceed to normal chain start
- [X] T054 On **Ignore** branch in T051: leave interrupted runs as-is, proceed to normal chain start (the new run gets its own fresh `run_id`)
- [X] T055 [P] Add `tests/test-chain-run-e2e-resume.sh`: simulate an interrupted run (init + partial update-ticket on first ticket only), call `list-interrupted` and assert the run appears with correct `next_ticket_id`, then call `close --terminal-status aborted` and assert `list-interrupted` is empty

### Linear-unreachable hard-fail (FR-002 clarification Q4)

- [X] T056 Verify T022 (`## Linear Fetch`) explicitly handles Linear MCP unreachable (connectivity error) vs. ticket-not-found (404) vs. partial-success cases; all three must abort the chain before any worker is spawned — document the three error codes (`ERR_LINEAR_UNREACHABLE`, `ERR_TICKETS_NOT_FOUND`, `ERR_LINEAR_PARTIAL`) and the exact user-facing messages

### Command assembly + discoverability

- [X] T057 Run `core/scripts/bash/assemble-commands.sh` against the TRI-27 worktree to verify the new `trc.chain.md` is picked up and assembled into the installed `.claude/commands/trc.chain.md` output path; fix any omissions in the assembly script if needed
- [X] T058 [P] Update `README.md` with a one-paragraph mention of `/trc.chain` and a link to the quickstart under `specs/TRI-27-trc-chain-orchestrator/quickstart.md` (or the equivalent post-merge docs location)

### Lint/test gate (constitution — mandatory before PR)

- [X] T059 Run `bash tests/run-tests.sh` and ensure every new test file passes. Fix anything that fails. Do NOT proceed to PR if any test is red
- [X] T060 [P] Run `node --test tests/test-chain-run-*.js` and confirm all node-based tests pass
- [X] T061 [P] Manually walk through `specs/TRI-27-trc-chain-orchestrator/quickstart.md` step-by-step (dry-run mentally against the built command + helper) and fix any documented step that does not match the implemented behavior

### Version bump

- [X] T062 At the very end, update repository `VERSION` file from `0.16.5` to `0.17.0` (minor bump per plan.md rationale: new user-facing command). This is typically done by `/trc.implement` but is listed here explicitly so it is not forgotten

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — can start immediately.
- **Phase 2 (Foundational)**: Depends on Setup (T001–T004). Blocks all user story phases.
- **Phase 3 (US1)**: Depends on Phase 2 completion. Delivers the MVP.
- **Phase 4 (US2)**: Depends on Phase 3 completion (extends the per-ticket loop and worker brief from T025/T026). Cannot ship without US1 scaffolding.
- **Phase 5 (US3)**: Depends on Phase 3 (needs the per-ticket loop and update-ticket helper). US3 is largely orthogonal to US2, but both touch the same loop in `trc.chain.md`, so it is sequenced after US2 to avoid merge pain.
- **Phase 6 (US4)**: Depends on Phase 3 (needs the run-init call site). Independent of US2/US3.
- **Phase 7 (Polish)**: Depends on all user stories being complete. Resumability (T051–T055) touches the top of the orchestrator flow and is sequenced last to avoid reshuffling the execution order repeatedly during earlier phases.

### User Story Dependencies

- **US1**: No dependencies on other stories; depends only on Foundational. Delivers chain happy path.
- **US2**: Layers pause-relay on top of US1's per-ticket loop. Not usable without US1 infrastructure.
- **US3**: Layers failure detection on top of US1's per-ticket loop. Independent of US2.
- **US4**: Layers epic-brief handling at the run-init seam. Independent of US2/US3.

Only US1 is strictly required for the MVP. US2 is needed before the feature is useful on non-trivial tickets. US3 and US4 are incremental quality-of-life additions.

### Within Each Phase

- Helper implementation before its tests (tests are round-trip and need real subcommands to call).
- `parse-range` / `init` / `get` / `list-interrupted` (Phase 2) before any orchestrator code (Phase 3+).
- `update-ticket` / `close` (Phase 3) before the orchestrator per-ticket loop can be meaningfully implemented.
- Worker Brief Template (T026) before any pause-handling work in Phase 4 (pause marker format is defined in the brief).
- Run `tests/run-tests.sh` in Polish phase ONLY after every earlier phase is implemented — intermediate test runs during Phase 3/4/5/6 are valuable for catching regressions but are not gates.

### Parallel Opportunities

Tasks marked `[P]` can run in parallel within their phase:

- **Phase 1**: T002, T003 can run in parallel (different files).
- **Phase 2**: T010, T012, T014, T016 (all test files, each testing a different subcommand) can run in parallel after their respective implementation tasks complete.
- **Phase 3**: T018 (update-ticket tests), T020 (close tests), T029 (e2e happy) can run in parallel with each other once T017/T019 are done.
- **Phase 4**: T037, T039 can run in parallel with T031–T036 orchestrator edits.
- **Phase 5**: T043, T044 can run after T040–T042.
- **Phase 6**: T049, T050 can run after T045–T048.
- **Phase 7**: T055, T058, T060, T061 can run in parallel after the implementation tasks in Phase 7 are complete.

---

## Parallel Example: Foundational test suite

```bash
# After T009, T011, T013, T015 (the four Phase 2 subcommand implementations) are done,
# launch all four test files in parallel:
Task: "Write tests for parse-range in tests/test-chain-run-parse-range.js"
Task: "Write tests for init + get in tests/test-chain-run-state.js"
Task: "Write tests for list-interrupted in tests/test-chain-run-interrupted.js"
Task: "Write tests for update-ticket in tests/test-chain-run-update-ticket.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only — but with a caveat)

1. Complete **Phase 1**: Setup (T001–T004).
2. Complete **Phase 2**: Foundational (T005–T016). This is the biggest single chunk — ~12 tasks, but all the helper surface area lives here.
3. Complete **Phase 3**: User Story 1 (T017–T030). This delivers the MVP for well-specified tickets only.
4. **STOP and VALIDATE**: Run a dry-run chain on a batch of 2 well-specified tickets (tickets whose trc.headless runs will not raise clarify questions). Confirm the summary table, branch creation, and PR flow. `bash tests/run-tests.sh` must be green.

**Caveat**: MVP (US1 alone) is NOT useful for real unspec'd tickets because any worker pause will be treated as a failure. US2 is the real shipping milestone.

### Real Shipping Milestone (US1 + US2)

5. Complete **Phase 4**: User Story 2 (T031–T039). The runtime probe and pause-relay loop make the feature usable on real tickets.
6. **STOP and VALIDATE**: Run the chain on 2 deliberately underspecified tickets. Confirm clarify questions surface correctly, user answers reach the same worker, push approval is requested per ticket.

### Incremental Add-Ons

7. Complete **Phase 5**: User Story 3 (T040–T044). Validate with a deliberately-failing test scenario.
8. Complete **Phase 6**: User Story 4 (T045–T050). Validate with both "provide brief" and "skip brief" paths.
9. Complete **Phase 7**: Polish, resumability, lint/test, version bump (T051–T062). Mandatory before PR — per constitution principle "Lint & Test Before Done".

### Parallel Team Strategy

Single-developer feature; no team parallelization expected. `[P]` markers indicate which tasks are _safe_ to parallelize if staffed, but sequential execution is fine.

---

## Notes

- **File overlap**: The single largest file in this feature is `core/commands/trc.chain.md`, edited across all user story phases. Because of this, cross-phase merge conflicts are a real risk if work is parallelized; the recommended order above avoids this by sequencing the phases serially.
- **Helper file overlap**: `core/scripts/bash/chain-run.sh` is also edited across Phase 2, 3, and 4 (progress subcommand). Same serial-execution recommendation applies.
- **Tests can parallelize freely** because every test file is distinct.
- **Constitution gates** (T059–T061) are non-negotiable before PR. Do not skip. The project's CLAUDE.md has this as a "MANDATORY — NONNEGOTIABLE" section.
- **`SendMessage` viability** is assumed verified by T031 runtime probe. If the probe fails at implementation time, T031 is the right place to fail the entire feature cleanly rather than shipping something that silently breaks.
- **No mocked database tests**: the helper reads/writes real JSON on a temp filesystem location. Tests use `mktemp -d` for run directories and clean up after. This matches the existing TRI-26 pattern.
- **Version bump (T062)** is a hard reminder — the `/trc.implement` skill normally handles this, but leaving it explicit prevents forgetting.

---

## Format Validation

All 62 tasks above follow the required format: `- [ ] T### [P?] [Story?] Description with file path`. Setup (T001–T004), Foundational (T005–T016), and Polish (T051–T062) phases intentionally have no `[Story]` label per instructions. User Story phases (T017–T050) all have their story label. File paths are present in every task.
