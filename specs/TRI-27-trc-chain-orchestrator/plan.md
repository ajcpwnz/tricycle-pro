# Implementation Plan: trc.chain — Orchestrate Full TRC Workflow Across a Range of Tickets

**Branch**: `TRI-27-trc-chain-orchestrator` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/TRI-27-trc-chain-orchestrator/spec.md`
**Current VERSION**: `0.16.5` → plan recommends a **minor bump to `0.17.0`** on implement (new user-facing command).

## Summary

Add a new `/trc.chain` command to tricycle-pro that orchestrates the existing trc workflow (`specify → clarify → plan → tasks → analyze → implement → push`) across a small range of Linear tickets (2–8) serially, spawning a **fresh sub-agent per ticket** so quality does not degrade from context pollution. Each worker runs in its own git worktree and executes `/trc.headless` end-to-end. The orchestrator never accumulates worker transcripts (FR-014), persists chain-run state to disk so interrupted runs can be resumed (FR-019–FR-021), relays pause-points (clarify/plan approval/push approval) back to the **running** worker via `SendMessage` (FR-011), never auto-approves pushes (FR-009), and stops the chain on failure (FR-012).

The technical approach is two-part:

1. **A new command template** `core/commands/trc.chain.md` that encodes the orchestrator's *agent behavior* — when to spawn workers, what prompt to give them, how to relay checkpoints, how to present the progress display, and how to detect/resume interrupted runs. This is the majority of the feature: most of the "implementation" is prompt engineering, not code.
2. **A small bash helper** `core/scripts/bash/chain-run.sh` that handles the deterministic, side-effect-y bits the agent should not reinvent on every run: range parsing, run-id generation, atomic JSON state read/write, listing interrupted runs, and closing terminal runs. The helper mirrors the existing style of `create-new-feature.sh` / `setup-plan.sh` and reuses `common.sh` + `json_builder.sh`.

All state lives under `specs/.chain-runs/<run-id>/` (state.json + optional epic-brief.md), co-located per FR-016 clarification.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js (tests only, via `node --test`)
**Primary Dependencies**: Existing `core/scripts/bash/common.sh`, `json_builder.sh`, `helpers.sh`; Linear MCP server (runtime, agent-side); Claude Code's `Agent` + `SendMessage` tools (runtime, agent-side)
**Storage**: JSON files on the filesystem under `specs/.chain-runs/<run-id>/state.json`. No database. Epic brief as adjacent markdown file.
**Testing**: `bash tests/run-tests.sh` (project-wide shell tests) and `node --test tests/test-chain-run-*.js` for helper unit/integration tests, matching the existing pattern from TRI-26.
**Target Platform**: Terminal on macOS/Linux running Claude Code with tricycle-pro installed.
**Project Type**: CLI command-template library (single project, no frontend/backend split).
**Performance Goals**: Not latency-sensitive. Helper script operations (state read/write, range parse) must complete in <100ms so they do not visibly stall the agent. Worker orchestration itself is bounded only by how long each ticket's trc workflow takes.
**Constraints**:
- Max 8 tickets per chain run (FR-003) — hard-enforced in helper.
- Serial execution only (FR-004) — no parallel workers; no file-locking complexity.
- No accumulation of worker transcripts in orchestrator context (FR-014) — each worker returns a single <300-word structured report.
- `SendMessage` availability is a hard viability constraint (Assumption in spec) — without it, FR-011 cannot be satisfied and the feature cannot ship.
**Scale/Scope**: ~1 new command template (~400–600 lines of markdown instructions), ~1 new bash helper (~250–350 lines), ~2–3 test files, ~3 planning docs (research, data-model, quickstart). No source-code rewrites of existing commands — `trc.chain` invokes `trc.headless` via sub-agent, does not reimplement it.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution at `.trc/memory/constitution.md` is currently a placeholder (`_Run /trc.constitution to populate this file._`). There are no enumerated principles to check against.

**Result**: PASS by vacuity. The plan aligns with the implicit principles visible in the existing codebase (bash-first, JSON-builder patterns, minimal dependencies, feature worktree workflow, lint/test-before-done) and in the project's recurring feedback memories (push approval every time, worktree mandatory, lint/test green before PR). These are encoded as functional requirements (FR-009, FR-006, FR-008) in the spec and re-checked post-design below.

**Re-check after Phase 1 design**: Still PASS. No violations introduced. See Complexity Tracking — empty.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-27-trc-chain-orchestrator/
├── plan.md                    # This file (/trc.plan output)
├── spec.md                    # /trc.specify + /trc.clarify output
├── research.md                # Phase 0 output (/trc.plan)
├── data-model.md              # Phase 1 output (/trc.plan)
├── quickstart.md              # Phase 1 output (/trc.plan)
├── contracts/
│   └── chain-run-helper.md    # Phase 1 output: CLI contract for chain-run.sh
├── checklists/
│   └── requirements.md        # /trc.specify output
└── tasks.md                   # Phase 2 output (/trc.tasks — NOT created by /trc.plan)
```

### Source Code (repository root)

```text
core/
├── commands/
│   └── trc.chain.md                    # NEW — orchestrator agent behavior (the main deliverable)
├── scripts/
│   └── bash/
│       ├── chain-run.sh                # NEW — state + range helper (subcommands: parse-range, init, get, update-ticket, list-interrupted, close)
│       ├── common.sh                   # EXISTING — reused
│       ├── create-new-feature.sh       # EXISTING — referenced by worker prompts
│       └── setup-plan.sh               # EXISTING — referenced by worker prompts
└── templates/
    └── (no new templates; trc.chain.md is stored directly under core/commands/)

tests/
├── run-tests.sh                        # EXISTING — runs everything
├── test-chain-run-parse-range.js       # NEW — range/list parsing edge cases
├── test-chain-run-state.js             # NEW — state file init/update/close/load
└── test-chain-run-interrupted.js       # NEW — interrupted-run detection

specs/
└── .chain-runs/                        # NEW (gitignored) — runtime state directory
    └── <run-id>/
        ├── state.json                  # Persisted chain run state
        └── epic-brief.md               # Optional cross-ticket context (FR-016)
```

**Structure Decision**: Single-project layout (Option 1). tricycle-pro is a command-template library with bash helpers and shell/Node tests — no frontend, backend, or mobile split. The new feature touches exactly three directories: `core/commands/` (new command markdown), `core/scripts/bash/` (new helper), and `tests/` (new tests). Runtime state lives under a new gitignored `specs/.chain-runs/` directory that is created on first use.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

_No violations. Table intentionally empty._

## Phase 0: Research — Consolidated Findings

All spec-level ambiguities were resolved in `/trc.clarify` (4 questions answered and recorded in `spec.md` → `## Clarifications`). The research phase focuses on **implementation-level unknowns** not covered by the spec. See `research.md` for full notes.

**Unknowns investigated**:

1. How to spawn a sub-agent from inside a Claude Code command template (the `Agent` tool's shape and parameters).
2. How to forward user input to a **running** sub-agent (the `SendMessage` tool's shape and contract, since this is the hard viability constraint for FR-011).
3. How to parse a Linear ticket range (`PREFIX-100..PREFIX-105`) including mixed-prefix rejection rules.
4. How to do atomic JSON state writes in pure bash on macOS (no `jq` assumption) — or whether to take a `jq` dependency.
5. How to gitignore `specs/.chain-runs/` without breaking existing spec-directory listing behavior.
6. How existing commands handle worker phase signaling (is there a convention for structured events from a sub-agent to its parent?) → needed for FR-022/FR-023.

**Summary of decisions** (full rationale in `research.md`):

- **Sub-agent spawn**: Use `Agent` tool with `subagent_type: general-purpose`, passing the full worker prompt inline. Name each agent `chain-worker-<ticket-id>` so the orchestrator can address it later via `SendMessage({to: "chain-worker-<ticket-id>", message: ...})`.
- **Pause/resume relay**: Workers pause naturally when they ask questions (clarify, plan approval, push approval). The orchestrator receives the pause as the agent's return message, surfaces `[ticket-id] <question>` to the user, waits for the answer, and forwards it via `SendMessage` to the same named agent — which resumes with full context. **This is the load-bearing mechanism; if `SendMessage` to running agents is not supported in the target runtime, the feature must fail loudly at chain start rather than silently spawn a fresh agent.**
- **Range parsing**: Accept two forms per FR-001 — `PREFIX-N..PREFIX-M` (contiguous, same prefix) and `PREFIX-N,PREFIX-M,OTHER-X` (comma list, mixed prefixes allowed). Mixed-prefix ranges (`TRI-1..POL-5`) are rejected with a clear error. Implemented in pure bash using `[[ =~ ]]` regex; no external parser.
- **JSON state writes**: Use the existing `json_builder.sh` (already in the repo) for writes, and a small `python3 -c "import json,sys..."` one-liner for reads — `python3` is universally available on macOS/Linux and `jq` is not guaranteed. This matches the strategy used by `create-new-feature.sh` and avoids adding a new hard dependency. Writes are atomic via `mv tmp → final`.
- **Gitignore**: Append `specs/.chain-runs/` to the root `.gitignore`. The leading dot prevents it from being picked up by the existing `ls specs/` → feature-directory listing in `check-prerequisites.sh`.
- **Phase signaling (FR-023)**: No existing convention. Decision: workers emit phase markers by writing a single-line JSON event to `specs/.chain-runs/<run-id>/<ticket-id>.progress` (overwritten each transition). The orchestrator polls this file between `SendMessage` round-trips (lightweight `tail` / `cat`). This avoids needing bidirectional streaming and is resilient to worker restart. **Trade-off accepted**: this is a file-based IPC, not in-memory; adds ~1 FS write per phase transition (≤7 per worker) — negligible.

**Output**: `research.md` with all unknowns resolved. No `NEEDS CLARIFICATION` markers remain.

## Phase 1: Design — Data Model, Contracts, Quickstart

**Prerequisites**: `research.md` complete.

### 1. Data Model → `data-model.md`

Six entities from the spec (`Ticket`, `Chain Run`, `Worker Agent`, `Worker Report`, `Epic Brief`, `Worktree`) plus one new implementation-only entity (`Progress Event`) introduced by the phase-signaling decision above. Only three of these have persistent on-disk representation:

- **Chain Run state** (`state.json`) — the main persisted object. Schema, state transitions, and validation rules detailed in `data-model.md`.
- **Epic Brief** (`epic-brief.md`) — opaque markdown content, no schema; referenced by path from `state.json`.
- **Progress Event** (`<ticket-id>.progress`) — single-line JSON, overwritten per phase transition.

All others (`Ticket`, `Worker Agent`, `Worker Report`, `Worktree`) are in-memory / ephemeral and described for completeness only.

### 2. Interface Contracts → `contracts/`

tricycle-pro's public "interface" for this feature is two-sided:

1. **The `/trc.chain` command invocation** (user ↔ orchestrator). Invocation syntax, argument grammar, and error codes documented in `contracts/chain-run-helper.md` (under the "Command Invocation" section).
2. **The `core/scripts/bash/chain-run.sh` helper CLI** (orchestrator ↔ helper). This is the testable contract — subcommands, flags, stdout schema (JSON), stderr schema, and exit codes. Documented in `contracts/chain-run-helper.md` (main body).

Subcommands (preview — full contract in `contracts/chain-run-helper.md`):

| Subcommand | Purpose | Stdout |
|---|---|---|
| `parse-range <arg>` | Parse `PREFIX-N..PREFIX-M` or comma list into deduped ticket list. Rejects >8 and mixed-prefix ranges. | JSON: `{"ids": [...], "count": N}` |
| `init --ids <json> [--brief <path>]` | Create a new run-id and state.json. | JSON: `{"run_id": "...", "state_path": "...", "brief_path": "..."}` |
| `get --run-id <id>` | Read full state. | JSON: state.json contents |
| `update-ticket --run-id <id> --ticket <id> --status <s> [--branch <b>] [--pr <url>] [--report <path>]` | Transition one ticket. | JSON: updated state |
| `list-interrupted` | List non-terminal runs. | JSON: `{"runs": [...]}` |
| `close --run-id <id> --terminal-status <completed\|failed\|aborted>` | Mark run terminal. | JSON: closed state |

All subcommands exit 0 on success, non-zero with `{"error": "..."}` on stderr on failure. This mirrors the existing `--json` convention in `create-new-feature.sh` / `setup-plan.sh`.

### 3. Quickstart → `quickstart.md`

Operator-facing walkthrough: install preconditions, `/trc.chain TRI-100..TRI-102` happy path, interrupted-run resume flow, stop-on-failure recovery, and cleanup of stale `.chain-runs/` directories. Written for a developer reading this feature for the first time — no assumed knowledge of tricycle internals.

### 4. Agent Context Update

Run `.trc/scripts/bash/update-agent-context.sh claude` after Phase 1 to append the new tech entry:

> `TRI-27-trc-chain-orchestrator: Added Bash 3.2+ (macOS default), Node.js (tests only), python3 (json reads) + None new — reuses existing common.sh, json_builder.sh, and the sub-agent orchestration pattern via Agent + SendMessage tools`

This only touches `CLAUDE.md`'s "Recent Changes" and "Active Technologies" sections between the managed markers, per the existing convention.

### 5. Version Awareness

- Current `VERSION`: `0.16.5`.
- `/trc.chain` is a **new user-facing command**, so `/trc.implement` should bump to **`0.17.0`** (minor bump), not a patch bump.
- The bump happens at implement time, not plan time. Plan just records the recommendation.

### Post-Design Constitution Re-Check

Re-reading the constitution and the existing feedback memories against the design above:

- Worktree mandatory ✅ — worker prompts explicitly require `create-new-feature.sh --provision-worktree` (TRI-26 hook)
- Lint/test before done ✅ — FR-008 enforced by worker; helper ships with tests
- Push approval every time ✅ — FR-009 encoded; orchestrator relays every push gate individually
- Branching style from config ✅ — worker prompts do not hard-code; they rely on `create-new-feature.sh` which already reads `tricycle.config.yml`
- Linear team "tricycle" for tricycle-pro issues ✅ — not applicable to this feature's code, but relevant to the TRI-27 parent ticket, which was created in the correct team

No violations introduced in Phase 1. PASS.

## Stop and Report

Phase 2 (tasks) is intentionally NOT run by this command — that is `/trc.tasks`.

**Branch**: `TRI-27-trc-chain-orchestrator`
**Plan path**: `/Users/alex/projects/tricycle-pro-TRI-27-trc-chain-orchestrator/specs/TRI-27-trc-chain-orchestrator/plan.md`
**Artifacts generated this phase**:
- `plan.md` (this file)
- `research.md`
- `data-model.md`
- `contracts/chain-run-helper.md`
- `quickstart.md`
- Updated `CLAUDE.md` (Recent Changes + Active Technologies markers)

**Next command**: `/trc.tasks`
