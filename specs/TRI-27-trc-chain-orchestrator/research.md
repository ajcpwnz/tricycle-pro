# Phase 0 Research: trc.chain

**Feature**: TRI-27-trc-chain-orchestrator
**Date**: 2026-04-15

All spec-level ambiguities were resolved in the preceding `/trc.clarify` session (see `spec.md` → `## Clarifications`). This document captures **implementation-level** unknowns that had to be resolved before Phase 1 design could start.

---

## R1 — Sub-agent spawning from inside a command template

**Unknown**: How does an orchestrator command (markdown instructions run by the top-level Claude Code agent) spawn a fresh sub-agent that will run `/trc.headless` in its own conversation context?

**Decision**: Use the `Agent` tool with `subagent_type: general-purpose`. The orchestrator calls `Agent({name: "chain-worker-<ticket-id>", description: "trc.headless for <ticket-id>", subagent_type: "general-purpose", prompt: "<full worker brief>"})` for each ticket, serially.

**Rationale**:
- `Agent` is the standard mechanism in Claude Code for delegating work with isolated context.
- `subagent_type: general-purpose` is required because the worker must have the full tool set (shell, git, Linear MCP, Agent for nested spawns if needed, file I/O).
- Giving the agent a **name** is critical: without a name, `SendMessage` cannot address it later (see R2).
- Each worker is spawned in the **foreground** (not `run_in_background: true`), because the orchestrator must wait for each ticket to complete before advancing (FR-004 serial execution).

**Alternatives considered**:
- *Nested slash-commands without `Agent`*: rejected — a slash command runs in the same context as the caller, so there is no context isolation (defeats the core principle).
- *Separate CLI process spawn (bash `&`)*: rejected — Claude Code slash commands are agent-driven; a bash-spawned process cannot invoke Claude tools or talk back through the orchestrator chat.
- *`run_in_background: true` parallel workers*: rejected — explicit non-goal in the spec (FR-004 serial only).

---

## R2 — Forwarding user input to a running sub-agent (`SendMessage`)

**Unknown**: When a worker pauses waiting for a clarification or approval, how does the orchestrator deliver the user's answer back to the **same** running worker (not a new one)?

**Decision**: Use `SendMessage({to: "chain-worker-<ticket-id>", message: "<user answer>"})`. `SendMessage` resumes a running (paused) sub-agent with new input and preserves its full conversation context.

**Rationale**:
- The Agent tool documentation is explicit: *"To continue a previously spawned agent, use SendMessage with the agent's ID or name as the `to` field — that resumes it with full context. A new Agent call starts a fresh agent with no memory of prior runs."*
- This is the load-bearing mechanism for FR-011. Every clarify/plan/push pause goes through this path.
- Naming convention `chain-worker-<ticket-id>` makes addressing unambiguous and collision-free (ticket IDs are unique within a Linear workspace).

**Hard viability constraint**: If the host runtime does not support `SendMessage` forwarding to paused sub-agents, the feature cannot ship as specified. The orchestrator MUST detect this at chain start (see R7) and fail loudly rather than silently lose context.

**Alternatives considered**:
- *Spawning a new `Agent` with the user's answer embedded in a reconstructed prompt*: rejected — this is exactly the failure mode the feature is designed to prevent (fresh context per resume = loss of all prior work, roll-back, retry).
- *Worker polls a file for new user input*: rejected — adds timing complexity, race conditions, and couples worker implementation to orchestrator's FS layout.

---

## R3 — Linear ticket range parsing

**Unknown**: Two input forms (`PREFIX-N..PREFIX-M` range and `PREFIX-N,PREFIX-M,...` list) must be parsed, normalized, deduplicated, and validated (max 8, mixed-prefix rules).

**Decision**: Implement as a pure-bash subcommand `chain-run.sh parse-range <arg>` using `[[ =~ ]]` regex. Two mutually exclusive paths based on whether the input contains `..` or `,`:

- `..` path: require same prefix on both sides, extract numeric range, reject `N > M`, reject mixed-prefix (`TRI-1..POL-5` → error), expand into list.
- `,` path: split on commas, validate each `LETTERS-DIGITS`, dedup preserving order, allow mixed prefixes.

After either path: reject count > 8 with a clear "break the range into smaller batches" message (FR-003), reject count == 0, reject any token that fails the `^[A-Z][A-Z0-9]*-[0-9]+$` regex.

**Rationale**:
- Pure bash keeps the helper dependency-free and matches the existing style of `create-new-feature.sh`.
- Regex-based parsing is simple enough that a full parser is overkill; edge cases (dedup, max count, mixed-prefix rejection) are handled in ~30 lines.
- Output is JSON on stdout via `json_builder.sh`, so the orchestrator consumes it without re-parsing.

**Alternatives considered**:
- *Node.js helper*: rejected — adds a runtime dependency just for string parsing; the project only uses Node for tests.
- *Pushing parsing into the agent markdown*: rejected — non-deterministic, hard to unit-test, and duplicates logic each time the agent reasons about it.

---

## R4 — Atomic JSON state writes without `jq`

**Unknown**: `state.json` must be updated at every ticket transition. macOS default shell toolchain does not include `jq`. How do we do partial-object updates atomically?

**Decision**:
- **Writes**: Use the existing `json_builder.sh` helpers to construct the full object in memory, write to a sibling `state.json.tmp`, then `mv state.json.tmp state.json` for atomicity. The state object is small (<~4 KB for 8 tickets), so rewriting the whole file on every transition is fine.
- **Reads**: Use a `python3 -c "import json, sys; print(json.load(sys.stdin)[...])"` one-liner. `python3` is present on every modern macOS/Linux and is already implicitly assumed by other tools in the repo.

**Rationale**:
- Avoids adding `jq` as a hard dependency (current project has zero non-shell runtime deps for the core flow).
- `mv` on POSIX is atomic within a single filesystem — standard pattern for lockfree state stores.
- Whole-file rewrite is fine at this scale; partial JSON patching is a premature optimization.

**Alternatives considered**:
- *Adopt `jq`*: rejected — adds install friction, diverges from current repo style.
- *Store state as multiple small files (one per field)*: rejected — harder to reason about, no atomicity across fields.
- *SQLite*: rejected — massively over-engineered for 8-ticket runs.

---

## R5 — Gitignoring `specs/.chain-runs/` without breaking existing listings

**Unknown**: The existing `check-prerequisites.sh` and similar helpers list `specs/*` to discover feature directories. Will a new `specs/.chain-runs/` directory interfere?

**Decision**: The directory name starts with `.`, so standard `ls` (without `-a`) and bash glob `specs/*` both skip it by default. Add `specs/.chain-runs/` to the repo root `.gitignore` so runtime state never leaks into commits.

**Verification**: Confirmed by inspecting `create-new-feature.sh` and `check-prerequisites.sh` — they iterate `specs/` with glob patterns like `specs/[0-9]*` and `specs/TRI-*`, neither of which would match a dot-prefixed directory.

**Alternatives considered**:
- *Store state under `.trc/chain-runs/`*: rejected — `.trc/` is gitignored in some setups but not others, and mixing runtime state with templates/scripts is messy.
- *Store state under `$HOME/.tricycle/chain-runs/`*: rejected — per-repo state should live in the repo directory tree so it naturally scopes to the project and is cleaned up with the worktree.

---

## R6 — Phase-transition signaling from worker to orchestrator (FR-022/FR-023)

**Unknown**: The orchestrator must display phase markers (`[ticket-id] → plan`) plus an elapsed-time indicator while a worker is running. How does it learn about phase transitions without streaming worker transcripts (which would violate FR-014 context hygiene)?

**Decision**: File-based progress events. Workers write a single-line JSON event to `specs/.chain-runs/<run-id>/<ticket-id>.progress` each time they transition phases. The file is **overwritten**, not appended — it always holds the current phase only. The orchestrator reads this file between `SendMessage` round-trips and on a lightweight schedule while the worker is running.

Event schema:
```json
{"phase": "plan", "started_at": "2026-04-15T12:34:56Z", "ticket_id": "TRI-100"}
```

The `trc.chain.md` command template includes a standing instruction in the worker prompt: *"At the start of each trc phase (specify, clarify, plan, tasks, analyze, implement, push), overwrite `specs/.chain-runs/<run-id>/<ticket-id>.progress` with a JSON event containing `{phase, started_at, ticket_id}`."*

**Rationale**:
- No need to invent in-conversation events — workers just write a file.
- Orchestrator reading the file is cheap (cached by the OS, <1 ms).
- Survives worker restart: the file is the source of truth for "current phase," so a resumed worker can pick up where the previous left off just by reading and then overwriting it.
- Matches the existing project style (filesystem as the integration surface between shell tools).

**Trade-offs accepted**:
- Elapsed-time display precision is bounded by how often the orchestrator reads the file. A 1–2 second poll interval is more than enough for user-facing feedback.
- Requires the worker to remember to write the event — enforced by the command template instructions and validated in the worker's structured return report.

**Alternatives considered**:
- *Worker emits events through its return message*: rejected — only sent on pause/completion, no live progress.
- *Bidirectional pipe/socket*: rejected — order of magnitude more complexity, not supported in Claude Code agent model.
- *Parse worker conversation output*: rejected — orchestrator explicitly must not see transcripts (FR-014).

---

## R7 — Detecting `SendMessage` runtime support at chain start

**Unknown**: FR-011 (forward to same running worker) is a hard viability constraint. If `SendMessage` is not available in the runtime, the feature must fail loudly *before* spawning the first worker.

**Decision**: At chain start, the orchestrator runs a lightweight self-check by spawning a trivial dummy sub-agent (`Agent({name: "chain-probe", prompt: "Say READY and wait for my next message."})`), then attempts `SendMessage({to: "chain-probe", message: "exit"})`. If either step fails, abort the chain with a clear message: *"This runtime does not support SendMessage forwarding to paused sub-agents, which is required for trc.chain checkpoint relay. Contact support or use /trc.headless per ticket."*

**Rationale**:
- Fail loudly, fail early (aligned with the spec's stop-on-failure philosophy).
- A one-shot probe is cheap (~2 seconds of agent time) and removes any doubt about later cascading failures.
- Surfaces the problem once per chain invocation, not once per ticket.

**Alternatives considered**:
- *Assume it works and fail at first pause*: rejected — that's exactly the "quality collapse" failure mode the feature exists to prevent; by then the orchestrator has already committed to a ticket.
- *Add a config flag `require_sendmessage: true` that user sets manually*: rejected — users won't know until it breaks; auto-detect is always better.

---

## All clarifications resolved

No `NEEDS CLARIFICATION` markers remain. Phase 1 design can proceed.
