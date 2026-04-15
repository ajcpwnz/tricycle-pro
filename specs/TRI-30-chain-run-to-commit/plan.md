# Implementation Plan: /trc.chain — Workers Run to Commit and Exit; Orchestrator Handles Push

**Branch**: `TRI-30-chain-run-to-commit` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/TRI-30-chain-run-to-commit/spec.md`
**Current VERSION**: `0.18.1` → plan recommends a **patch bump to `0.18.2`** on implement (this is a bug fix to a shipped feature, not a new user-facing capability).

## Summary

Rip the broken pause-relay design out of `/trc.chain` and replace it with a **run-to-commit** worker contract: each worker runs `/trc.specify → /trc.plan → /trc.tasks → /trc.implement → git commit → STOP`, returning a single structured JSON report and exiting deterministically. The orchestrator (the parent conversation, which has full tool access and a live channel to the user) takes over at the push gate: reads the report, prints a one-line summary, asks the user for push approval in plain dialog, and on approval runs `git push → gh pr create → gh pr merge → worktree cleanup`. Zero `SendMessage` calls. Zero ghost workers.

The schema change is small and surgical: `chain-run.sh`'s ticket status enum gains `committed`, `pushed`, and `merged` between `in_progress` and `completed`, and per-ticket state gains a `commit_sha` field. Progress events flip from start-of-phase (`phase: "plan"`) to end-of-phase (`phase: "plan_complete"`), so dead workers leave honest trails. Resume cross-checks `state.json` against actual git state in the worktree (does the expected commit exist on the expected branch?), so a `committed` ticket on resume goes straight to the push gate without re-spawning a worker.

The fix is two files of source (`core/commands/trc.chain.md`, `core/scripts/bash/chain-run.sh`) plus targeted test updates. No new files are introduced. No new dependencies. The existing TRI-27 helper subcommands (`parse-range`, `init`, `get`, `list-interrupted`, `close`) are unchanged; only `update-ticket`'s validation rules and the `committed` field plumbing are touched.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js (tests only, via `node --test`); python3 (json reads/builds, already used in TRI-27)
**Primary Dependencies**: Existing `core/scripts/bash/common.sh`, `chain-run.sh` (TRI-27); GitHub CLI `gh` (orchestrator-side, agent-invoked); git ≥ 2.5 for worktree support; Claude Code's `Agent` tool for spawning workers (no longer uses `SendMessage` — that's the bug being fixed)
**Storage**: Filesystem only. Same `specs/.chain-runs/<run-id>/state.json` from TRI-27 with the extended status enum and new `commit_sha` field. No migration needed.
**Testing**: `bash tests/run-tests.sh` + targeted `node --test tests/test-chain-run-*.js`. New test scenarios: full status transition path, `committed` validation, `commit_sha` round-trip, resume-via-git mismatch handling.
**Target Platform**: Terminal on macOS/Linux running Claude Code with tricycle-pro installed. Same as TRI-27.
**Project Type**: CLI command-template library (single project). Same as TRI-27.
**Performance Goals**: Helper subcommand operations remain <100ms (unchanged from TRI-27). The orchestrator's per-ticket push step is gated by `git push` + `gh` round-trips, which are network-bound; nothing the helper can speed up.
**Constraints**:
- **FR-013 negative requirement**: the orchestrator MUST NEVER call `SendMessage`. This is the success oracle. Verifiable by `grep -L SendMessage core/commands/trc.chain.md` post-implementation.
- Backward compatibility: existing v0.17.0 chain runs (state.json files with the old status enum) MUST still load without crashing — the helper just won't see the new `committed`/`pushed`/`merged` values until updated runs are created.
- The progress-event semantics change is **not** backward compatible with v0.17.0 progress files, but progress files are ephemeral runtime state, so this is acceptable.
- Worker brief size: still bounded to ~400 words to fit cleanly in the worker's initial prompt.
**Scale/Scope**: ~2 source files modified (`core/commands/trc.chain.md` ~rewrite of worker brief and per-ticket loop; `core/scripts/bash/chain-run.sh` ~50 lines of change for the new status enum and field). ~3 test files modified, ~2 test files added. ~2 planning docs (research, data-model). Total LOC delta: probably +400/-300.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution at `.trc/memory/constitution.md` is still a placeholder. There are no enumerated principles to check against.

**Result**: PASS by vacuity. Implicit principles satisfied:

- **Lint/test before done** (CLAUDE.md mandatory): every spec change is paired with test updates; gate enforced at implement time.
- **Push approval every time** (`feedback_push_approval_every_time`): FR-010 enforces exactly this — push approval is asked per ticket in plain dialog, with no carry-over.
- **Worktree mandatory** (`feedback_worktree_mandatory`): unchanged from TRI-27 — workers still run in their own worktree via `--provision-worktree`.
- **Branching style from config** (`feedback_branching_style`): unchanged — workers invoke `create-new-feature.sh` which already reads `tricycle.config.yml`.
- **Linear team "tricycle"** (`reference_linear_team`): TRI-30 was created in the correct team.
- **No SendMessage pause-resume** (`feedback_trc_chain_no_pause_relay`, NEW from tonight): FR-013 encodes this directly. The negative requirement is the load-bearing one.

**Re-check after Phase 1 design**: Still PASS. No violations introduced. See Complexity Tracking — empty.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-30-chain-run-to-commit/
├── plan.md                    # This file (/trc.plan output)
├── spec.md                    # /trc.specify output
├── research.md                # Phase 0 output (/trc.plan)
├── data-model.md              # Phase 1 output (/trc.plan)
├── quickstart.md              # Phase 1 output (/trc.plan)
├── contracts/
│   └── chain-run-helper-v2.md # Phase 1 output: delta-spec from TRI-27 contract
├── checklists/
│   └── requirements.md        # /trc.specify output
└── tasks.md                   # Phase 2 output (/trc.tasks — NOT created by /trc.plan)
```

### Source Code (repository root)

```text
core/
├── commands/
│   └── trc.chain.md                    # MODIFIED — rewrite worker brief, remove pause-relay,
│                                       #            add orchestrator push step, drop runtime probe
└── scripts/
    └── bash/
        └── chain-run.sh                # MODIFIED — extend status enum (committed, pushed, merged),
                                        #            add commit_sha field, update validation rules

tests/
├── test-chain-run-update-ticket.js     # MODIFIED — new transition path, new error cases
├── test-chain-run-state.js             # MODIFIED — assert commit_sha field exists in init schema
├── test-chain-run-progress.js          # MODIFIED — phase_X_complete event semantics
├── test-chain-run-e2e-happy.sh         # MODIFIED — walk through committed → pushed → merged → completed
├── test-chain-run-e2e-resume.sh        # MODIFIED — assert resume cross-checks via git (mocked or temp repo)
└── test-chain-run-no-sendmessage.sh    # NEW — grep guard: SendMessage MUST NOT appear in trc.chain.md

specs/
└── .chain-runs/                        # EXISTING (gitignored) — runtime state directory, schema extended
    └── <run-id>/
        ├── state.json                  # tickets.<id>.commit_sha (new), status enum extended
        └── <ticket-id>.progress        # event payload uses _complete suffix
```

**Structure Decision**: Single-project layout (Option 1). No new directories, no new modules. The fix is surgical: 2 source files modified, 5 test files modified, 1 test file added. The new test file (`test-chain-run-no-sendmessage.sh`) is the negative-requirement guard for FR-013 and SC-001 — it's a one-line `grep` that fails the build if `SendMessage` ever creeps back into `trc.chain.md`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

_No violations. Table intentionally empty._

## Phase 0: Research — Consolidated Findings

The spec resolved the high-level decisions (worker contract, status enum, progress event semantics, resume strategy). Phase 0 covers the **implementation-level unknowns** that need answers before Phase 1 design can lock in. Full notes in `research.md`.

**Unknowns investigated**:

1. Does `/trc.headless` (and specifically `/trc.implement`) actually do a `git commit` at the end of its run, or does it leave staged-but-uncommitted changes? (FR-001 / Assumption 1 in spec depends on this.)
2. How does the orchestrator detect "the worker has finished implementing the ticket" deterministically — by parsing the JSON report, by checking `git log`, or both? (Affects FR-009 step 2 and FR-018 resume.)
3. How does the orchestrator distinguish a worker's normal completion message from a worker that crashed or returned malformed output? (Affects FR-009 step 3 and the failure paths.)
4. Does `chain-run.sh update-ticket` need a new dedicated subcommand for the orchestrator-side push transitions (`committed → pushed → merged → completed`), or do we extend `update-ticket` with new flags? (Implementation style decision.)
5. How do we validate FR-013 (no `SendMessage` calls) automatically in the test suite, given the test suite doesn't exercise the agent runtime? (Test design.)
6. What's the minimal change to `core/commands/trc.chain.md` to remove the runtime probe (R7 from TRI-27 research), the pause-relay loop, and the "Push Approval Invariant" section, while keeping the rest of the orchestrator scaffolding (resume detection, Linear fetch hard-fail, scope confirmation, summary table)?

**Summary of decisions** (full rationale in `research.md`):

1. **`/trc.headless` commit behavior**: confirmed by reading `core/commands/trc.headless.md` and `core/commands/trc.implement.md` — the implement phase ends with the lint/test gate followed by the version bump (a file write), then commits all changes including spec/plan/tasks/version files. So workers naturally end at a commit when run via `/trc.headless`. **No fallback `git add . && git commit -m "<auto>"` step is needed in the worker brief.** If a future change to `/trc.implement` removes the auto-commit, the worker brief should be patched then — not preemptively here.
2. **Worker completion detection**: parse the structured JSON report from the worker's return message. The report's `status` field (`committed` or `failed`) is the primary signal. **Cross-check** by reading the worker's progress file and confirming the final event is `phase: "committed"` with a `commit_sha`. The orchestrator does NOT need to read git directly to confirm a worker run; the report is the source of truth. (Resume is the only place git is consulted directly — see decision 5 below.)
3. **Crashed worker / malformed output detection**: if the worker's return message does not contain a fenced `json` block matching the report schema, OR if the JSON is missing required fields, treat the worker as failed with `worker_error: "malformed report"`. The orchestrator stops the chain and surfaces the failure. No retry. No best-effort parsing.
4. **`update-ticket` extension vs. new subcommand**: extend `update-ticket`. The existing flag set (`--branch`, `--pr`, `--lint`, `--test`, `--report`, etc.) was designed to be additive. New flags `--commit-sha` and a relaxed `--pr` validation (allowed when status ∈ `pushed`/`merged`/`completed`) is a small change. A separate `mark-pushed` / `mark-merged` subcommand would be cleaner conceptually but doubles the helper surface area for marginal value.
5. **Resume-via-git verification**: When `list-interrupted` returns a run, the **orchestrator** (not the helper) is responsible for cross-checking each ticket's state against the worktree's git state. Helper just returns what `state.json` says. The orchestrator's resume-detection section in `trc.chain.md` is where the cross-check lives — it walks the ticket list, runs `git -C <worktree> log -1 --format=%H <branch> 2>/dev/null` for each `committed`/`pushed`/`merged` ticket, and surfaces any mismatch.
6. **FR-013 test design**: A bash test `tests/test-chain-run-no-sendmessage.sh` runs `grep -i "SendMessage" core/commands/trc.chain.md` and asserts zero matches. Hooked into `run-tests.sh`. This is a static lint, not a runtime check — it fires every time the test suite runs, catching any regression that would re-introduce the pause-relay assumption. Because we can't actually probe the Claude Code runtime from a shell test, the static check is the next-best guarantee.
7. **Minimal command-file rewrite**: keep all of TRI-27's `## Resume Detection`, `## Parse Range`, `## Linear Fetch`, `## Scope Confirmation`, `## Epic Brief Prompt`, `## Run Init`, `## Summary`, `## Done`, `## Context Hygiene` sections. **Delete**: `## Runtime Probe`, the entire `## Push Approval Invariant`, and the `## Pause-relay loop` paragraphs inside `## Per-Ticket Loop`. **Rewrite**: the `## Worker Brief Template` section (new contract) and the `## Per-Ticket Loop` body (orchestrator now handles push). **Add**: a new `## Orchestrator Push Step` section that documents the read-report → summary → ask → push → PR → merge → cleanup flow.

**Output**: `research.md` with all decisions documented. No `NEEDS CLARIFICATION` markers remain.

## Phase 1: Design — Data Model, Contracts, Quickstart

**Prerequisites**: `research.md` complete.

### 1. Data Model → `data-model.md`

The data model is **mostly carried forward from TRI-27** with three additive changes:

1. **Status enum extended**: `not_started, in_progress, committed, pushed, merged, completed, failed, skipped`. New legal forward transitions documented as a state diagram.
2. **`commit_sha` field added** to per-ticket state. Type: string|null. Set when transitioning to `committed`. Never reset.
3. **Progress event payload semantics changed**: events use `phase: "<phase>_complete"` (with explicit valid values: `specify_complete, clarify_complete, plan_complete, tasks_complete, analyze_complete, implement_complete, committed`) and add an optional `commit_sha` field on the final `committed` event.

Full schema, validation rules, lifecycle diagram, and migration notes from v0.17.0 in `data-model.md`.

### 2. Interface Contracts → `contracts/chain-run-helper-v2.md`

Rather than rewrite the full TRI-27 contract from scratch, this is a **delta-spec** that documents only the changes from `specs/TRI-27-trc-chain-orchestrator/contracts/chain-run-helper.md`:

- **`update-ticket`**: new `--commit-sha <sha>` flag; new valid `--status` values; new validation rule for `--pr` (now allowed when status ∈ `pushed`/`merged`/`completed`); new error code `ERR_BAD_TRANSITION` for illegal forward transitions like `not_started → merged`.
- **All other subcommands** (`parse-range`, `init`, `get`, `close`, `list-interrupted`, `progress`): unchanged. Reference the TRI-27 contract directly.

The orchestrator command-invocation contract (the `/trc.chain` CLI) is also unchanged — same range/list grammar, same error messages, same scope confirmation flow. Only the per-ticket loop body changes, and that's an internal behavior change, not an external contract change.

### 3. Quickstart → `quickstart.md`

Operator walkthrough of the **new** flow: spawn worker → worker commits → orchestrator asks → push → PR → merge → cleanup → next ticket. Plus the resume-from-interrupted scenario with the new `committed`-state handling. Replaces (does not extend) TRI-27's quickstart for the per-ticket section; the rest (preconditions, max 8 tickets, gitignore, troubleshooting) carries over.

### 4. Agent Context Update

Run `.trc/scripts/bash/update-agent-context.sh claude` after Phase 1 to append:

> `TRI-30-chain-run-to-commit: Modified — workers run to commit and exit; orchestrator handles push/PR/merge. Removes SendMessage pause-relay (broken in v0.17.0). Status enum extended with committed/pushed/merged. No new tech.`

This only touches `CLAUDE.md`'s "Recent Changes" and "Active Technologies" sections between the managed markers, per the existing convention.

### 5. Version Awareness

- Current `VERSION`: `0.18.1`.
- TRI-30 is a **fix** to a shipped feature, not a new user-facing capability. Recommended bump: **`0.18.1 → 0.18.2`** (patch).
- Rationale: the public command name (`/trc.chain`) does not change, the CLI grammar does not change, the persistence directory does not change, and the only visible behavioral change to a user is "the command actually works now". That's a patch by SemVer convention.
- The bump happens at implement time, not plan time. Plan just records the recommendation.

### Post-Design Constitution Re-Check

Re-reading the constitution and the existing feedback memories against the design above:

- Lint/test before done ✅ — every source change paired with test updates; gate enforced at implement time.
- Push approval every time ✅ — encoded as FR-010, now in plain dialog instead of broken `SendMessage` relay. Strictly stronger.
- Worktree mandatory ✅ — unchanged from TRI-27.
- Branching style from config ✅ — unchanged from TRI-27.
- No SendMessage pause-resume ✅ — FR-013 + the new `test-chain-run-no-sendmessage.sh` guard test.
- Backward compatibility with v0.17.0 chain runs ✅ — the new status values are additive; old runs load without crashing.

No violations introduced in Phase 1. PASS.

## Stop and Report

Phase 2 (tasks) is intentionally NOT run by this command — that is `/trc.tasks`.

**Branch**: `TRI-30-chain-run-to-commit`
**Plan path**: `/Users/alex/projects/tricycle-pro-TRI-30-chain-run-to-commit/specs/TRI-30-chain-run-to-commit/plan.md`
**Artifacts generated this phase**:
- `plan.md` (this file)
- `research.md`
- `data-model.md`
- `contracts/chain-run-helper-v2.md`
- `quickstart.md`
- Updated `CLAUDE.md` (Recent Changes + Active Technologies markers)

**Next command**: `/trc.tasks`
