# Feature Specification: trc.chain — Orchestrate Full TRC Workflow Across a Range of Tickets

**Feature Branch**: `TRI-27-trc-chain-orchestrator`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "trc.chain — spec for TRC agent. Run the full trc workflow (specify → clarify → plan → tasks → analyze → implement → push) across a small range of Linear tickets (typically 2–8) without quality degradation. Invocation: /trc.chain <ticket-ids-or-range>. Core principle: fresh context per ticket. Spawn a fresh worker agent per ticket in its own worktree, serial execution, orchestrator relays checkpoints, never auto-approves pushes, stops chain on failure."

## Clarifications

### Session 2026-04-15

- Q: If the orchestrator conversation is interrupted mid-chain (crash, context exhaustion, user closes session), is the chain resumable? → A: Persist chain state to disk and auto-detect interrupted runs at invocation, prompting the user to resume or restart.
- Q: Where does the optional shared `epic-brief.md` live? → A: Co-located with persisted chain state at `specs/.chain-runs/<run-id>/epic-brief.md`.
- Q: What does the user see while a worker is running between checkpoints? → A: Phase markers (`[ticket-id] → <phase>`) plus a spinner/elapsed-time indicator for the current phase. No worker transcript.
- Q: What happens if Linear MCP is unreachable or a ticket ID is not found at chain start? → A: Hard-fail. Abort the chain before spawning any worker and report which IDs failed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a ticket range end-to-end with fresh context per ticket (Priority: P1)

As a developer working through a set of closely related Linear tickets, I want to invoke a single command that walks the full trc workflow on each ticket in order — each ticket getting a clean, uncontaminated agent context — so that I can hand off a batch of work without babysitting every phase and without seeing quality collapse on the third or fourth ticket.

**Why this priority**: This is the entire point of the feature. Without fresh-context-per-ticket serial execution, there is no value — the user could already chain workflows manually in one conversation, which is the failure mode being solved.

**Independent Test**: Invoke `/trc.chain TRI-100..TRI-102` on a sample of three tickets. Verify that each ticket runs in its own worker agent, produces its own branch, its own spec/plan/tasks/implementation, and its own structured report. Verify the orchestrator's own context never grows with worker internals.

**Acceptance Scenarios**:

1. **Given** the user has 3 backlog tickets `TRI-100`, `TRI-101`, `TRI-102`, **When** the user runs `/trc.chain TRI-100..TRI-102`, **Then** the orchestrator lists the three ticket titles, asks for go/no-go confirmation, and on approval processes them serially, one at a time.
2. **Given** ticket 1 completes successfully, **When** the orchestrator moves on, **Then** a fresh worker agent is spawned for ticket 2 with no memory of ticket 1's context beyond the (optional) shared `epic-brief.md`.
3. **Given** all tickets in the range complete, **When** the chain finishes, **Then** the orchestrator presents a summary table of ticket → branch → PR URL → test/lint status.

---

### User Story 2 - Checkpoint relay for clarify, plan approval, and push approval (Priority: P1)

When a worker pauses for user input (a `/trc.clarify` question, a plan-approval gate, or a push-approval gate), I want the orchestrator to surface the question to me with the ticket ID attached, wait for my answer, and forward the answer back to the *same running worker* — not start a new one — so that my context is preserved and I am never surprised by automatic pushes or merges.

**Why this priority**: Push approval is a durable user preference and a safety gate. Losing worker state mid-question (by spawning a new agent to answer it) would destroy the very context isolation this feature is built to preserve, and would risk duplicate/wrong work.

**Independent Test**: Run the chain on a single ticket that is intentionally underspecified so that the worker raises a clarify question. Verify the orchestrator surfaces `[TRI-XXX] <question>` and that the user's answer is routed back to the same worker without spawning a new agent. Verify push approval is requested explicitly every time.

**Acceptance Scenarios**:

1. **Given** a worker raises a clarify question, **When** the orchestrator receives the pause signal, **Then** it prints `[ticket-id] <question>` to the user and waits for a reply.
2. **Given** the user provides an answer, **When** the orchestrator relays it, **Then** the message is forwarded to the *running* worker agent (not a new one) and the worker resumes.
3. **Given** a worker reaches the push phase, **When** it requests push approval, **Then** the orchestrator always asks the user explicitly — never auto-approves — even if the user previously approved a push in the same chain run.

---

### User Story 3 - Stop-on-failure surfacing (Priority: P2)

When one ticket in the chain fails (lint failure, test failure, worker error, unresolvable conflict), I want the orchestrator to stop immediately, surface the failure with the ticket ID and a short reason, and *not* advance to the next ticket — so that I can diagnose and fix without a cascade of half-finished branches.

**Why this priority**: Important for reliability and trust in the feature, but the P1 stories can deliver value on their own if only the happy path works. This is the guardrail on top.

**Independent Test**: Run a chain of three tickets where the second ticket's tests fail. Verify that ticket 1 completes normally, ticket 2 stops with a clear error, and ticket 3 is never started. Verify the summary reflects this state accurately.

**Acceptance Scenarios**:

1. **Given** the worker on ticket N reports failure (non-zero exit, failing tests, or unresolved error), **When** the orchestrator receives the report, **Then** it stops the chain, prints the failure summary, and does not spawn a worker for ticket N+1.
2. **Given** a chain has stopped on failure, **When** the summary is produced, **Then** completed tickets, the failing ticket, and unstarted tickets are all clearly labeled.

---

### User Story 4 - Shared epic-brief.md cross-ticket context (Priority: P3)

As a developer running a chain of related tickets that share a common goal or context (e.g., an epic), I want to optionally author or read a single `epic-brief.md` document that is passed to every worker — and is the *only* cross-ticket context they share — so that workers have the minimal shared understanding needed without accumulating full conversation history from sibling tickets.

**Why this priority**: Useful for coherence across an epic, but not required for the core fresh-context-serial-execution value. Workers can still do good work with just their own ticket body.

**Independent Test**: Create an `epic-brief.md` in a known location, invoke the chain, and verify each worker receives the path to it and reads it as part of its prompt. Verify no other cross-ticket context leaks between workers.

**Acceptance Scenarios**:

1. **Given** the user has an existing `epic-brief.md`, **When** the chain starts, **Then** the path is included in every worker's prompt.
2. **Given** no `epic-brief.md` exists, **When** the chain starts, **Then** the orchestrator optionally offers to create one, and on decline proceeds without one.

---

### Edge Cases

- **Range too large**: What happens when the user passes a range of 9+ tickets? Orchestrator refuses the run and redirects the user to break it into smaller batches (quality-to-effort ratio degrades beyond 8).
- **Empty or invalid range**: What happens when the range resolves to zero tickets or contains a ticket ID that does not exist in Linear? Orchestrator reports the invalid/missing IDs and asks the user to confirm whether to proceed with the remainder or abort.
- **Ticket already has a branch**: What happens when a ticket in the range already has an existing branch or PR? Orchestrator surfaces this to the user and asks whether to skip, resume, or abort the chain.
- **User interrupts mid-chain**: What happens when the user cancels during ticket N? Completed tickets remain as-is; the in-progress worker is stopped; subsequent tickets are not started; a partial summary is shown.
- **Worker takes too long / appears stuck**: The orchestrator has no automatic timeout mechanism, but surfaces the worker's last reported phase so the user can decide whether to intervene.
- **Duplicate ticket IDs in input** (e.g., `TRI-100,TRI-100`): Orchestrator deduplicates silently and processes each ticket at most once.
- **Mixed prefixes in a range** (e.g., `TRI-100..POL-105`): Not supported as a single range; comma-separated lists may mix prefixes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST accept a ticket specification in two forms: a contiguous range (`PREFIX-###..PREFIX-###`) and a comma-separated list (`PREFIX-###,PREFIX-###,...`). Mixed prefixes are permitted only in the comma-separated form.
- **FR-002**: The system MUST fetch each ticket's title and body from Linear and present the list to the user for go/no-go confirmation before any worker is spawned. If the Linear MCP is unreachable, or if any requested ticket ID returns not-found, the system MUST hard-fail: abort the chain before spawning any worker, report the specific failure (connectivity error or the list of missing IDs), and not prompt the user to proceed with a partial set.
- **FR-003**: The system MUST reject ranges resolving to more than 8 tickets and redirect the user to break the range into smaller batches.
- **FR-004**: The system MUST process tickets **strictly serially** — never in parallel — to avoid worktree, database, port, and checkpoint-relay contention.
- **FR-005**: For each ticket, the system MUST spawn a **fresh worker agent** with no memory of prior tickets' internal context. The only cross-ticket context permitted is the optional shared `epic-brief.md`.
- **FR-006**: Each worker MUST run in its own isolated git worktree so that branches, working-copy changes, and any per-ticket setup do not interfere with other tickets or the main checkout.
- **FR-007**: Each worker MUST execute the full configured trc workflow chain end-to-end (`trc.headless` behavior: specify → clarify → plan → tasks → analyze → implement → push, honoring the project's configured chain).
- **FR-008**: Each worker MUST enforce the project's standard quality gates before requesting push approval: lint green, tests green, local stack/UI testing for user-facing changes, and QA test cases added for user-facing features when the project has QA enabled.
- **FR-009**: The system MUST **never auto-approve pushes**. Push approval MUST be requested from the user explicitly for every ticket, every time, regardless of prior approvals in the same chain run.
- **FR-010**: When a worker pauses for user input (clarify, plan approval, push approval, or any other gate), the orchestrator MUST surface the question to the user in the format `[ticket-id] <question>` and wait for a reply.
- **FR-011**: When the user answers a pause, the orchestrator MUST forward the answer to the **same running worker agent** — it MUST NOT spawn a new agent to deliver the answer, because that would destroy the worker's context.
- **FR-012**: On worker failure (non-zero exit, failing tests, unresolved error, or worker-reported failure), the orchestrator MUST stop the chain immediately, surface the failing ticket ID and reason, and NOT advance to the next ticket.
- **FR-013**: After the chain completes (success, partial, or stopped-on-failure), the orchestrator MUST produce a summary table listing each ticket with its branch name, PR URL (if any), and overall status (completed / failed / skipped / not-started).
- **FR-014**: The orchestrator's own context MUST contain only ticket metadata and each worker's final structured report. It MUST NOT accumulate worker conversation transcripts, intermediate tool outputs, or per-phase logs.
- **FR-015**: Each worker's structured report MUST be concise (under ~300 words) and include at minimum: branch name, PR URL (or "not pushed"), lint/test status, and any open questions or caveats for the user.
- **FR-016**: The system MUST support an optional shared `epic-brief.md` co-located with the persisted chain-run state at `specs/.chain-runs/<run-id>/epic-brief.md`. On chain start the orchestrator MUST check for an existing brief at that path; if present, its path MUST be passed to every worker in the chain; if absent, the orchestrator MAY offer to create one at that location, and MUST allow the user to decline and proceed without one. On resume of an interrupted chain run, the existing brief at the run's path MUST be reused automatically.
- **FR-017**: The system MUST deduplicate ticket IDs in the input silently so that each ticket is processed at most once per chain run.
- **FR-018**: The system MUST detect tickets that already have an existing branch or open PR and present options to the user (skip, resume, abort) before spawning a worker for that ticket.
- **FR-019**: The system MUST persist chain-run state to disk (ticket list, per-ticket status, current position, worker reports collected so far) at every state transition, so that the run survives orchestrator conversation termination.
- **FR-020**: On invocation of `/trc.chain`, the system MUST detect any previously-interrupted chain run (persisted state where the run is neither completed nor aborted) and prompt the user with the options: resume from the next unprocessed ticket, restart the whole chain, or abort/discard the prior state.
- **FR-021**: When a chain run reaches a terminal state (all tickets completed, stop-on-failure, or user-aborted), the system MUST mark the persisted state as closed so it is not offered for resume on subsequent invocations.
- **FR-022**: While a worker is running between checkpoints, the orchestrator MUST display a lightweight progress indicator consisting of: (a) a phase marker of the form `[ticket-id] → <phase>` printed whenever the worker transitions into a new trc workflow phase (specify, clarify, plan, tasks, analyze, implement, push), and (b) an elapsed-time indicator (e.g., spinner or counter) for the currently-active phase. The orchestrator MUST NOT stream worker transcripts or intermediate tool output, preserving the context-hygiene guarantee in FR-014.
- **FR-023**: Phase transitions MUST be signaled by the worker to the orchestrator via a lightweight structured event (not free-text log scraping), so that the orchestrator can update the display without parsing worker conversation output.

### Key Entities *(include if feature involves data)*

- **Ticket**: A Linear issue identified by `PREFIX-###`. Carries an ID, title, and body. Input to exactly one worker run within a chain.
- **Chain Run**: A single invocation of `/trc.chain` covering an ordered list of tickets. Holds ticket metadata, per-ticket status, collected worker reports, and the final summary. Persisted to disk at every state transition so that it survives orchestrator conversation termination and can be resumed. Each chain run has a terminal state (completed, failed, aborted) after which it is no longer offered for resume.
- **Worker Agent**: A freshly spawned sub-agent with isolated context, bound 1:1 to a single ticket. Owns its worktree, its workflow execution, and produces exactly one structured report.
- **Worker Report**: Concise (<300 words) structured output from a worker: branch name, PR URL, lint/test status, open questions. The only thing the orchestrator retains from the worker.
- **Epic Brief**: Optional shared markdown document stored at `specs/.chain-runs/<run-id>/epic-brief.md`, co-located with persisted chain-run state. Contains cross-ticket context; read-only to workers; the *only* channel for cross-ticket information. Tied to a specific chain run, so different chains (different epics) cannot collide.
- **Worktree**: Isolated git working copy per ticket, preventing cross-ticket contamination of working-copy state, branches, and setup artifacts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A chain of 5 tickets can be executed end-to-end with a single invocation, requiring from the user only: one go/no-go confirmation up front, plus each ticket's clarify answers and push approval.
- **SC-002**: The quality of output (as judged by the user) on ticket 5 of a 5-ticket chain is indistinguishable from the quality on ticket 1 — i.e., no observable degradation from context pollution.
- **SC-003**: The orchestrator's own context at the end of a 5-ticket chain is no larger than (ticket metadata + 5 × ~300-word reports), demonstrating that no worker transcripts leak into orchestrator context.
- **SC-004**: Zero pushes happen without an explicit per-ticket user approval, verified across at least 10 chain runs.
- **SC-005**: When a worker fails mid-chain, no subsequent ticket is started, verified by at least one deliberately-failing test scenario.
- **SC-006**: Attempted ranges of 9+ tickets are rejected 100% of the time with a clear redirect message.
- **SC-007**: When the user answers a paused worker's question, the answer reaches the *same* worker agent 100% of the time — never a newly-spawned agent.

## Assumptions

- The project already has the trc workflow (`specify`, `clarify`, `plan`, `tasks`, `analyze`, `implement`, `push`, and the `trc.headless` composite) in place and working on a single-ticket basis. This feature orchestrates existing skills; it does not reinvent them.
- The project has a working Linear MCP integration so the orchestrator can resolve `PREFIX-###` IDs to ticket titles and bodies.
- The project has a worktree-provisioning mechanism already in place that a worker can invoke (e.g., `create-new-feature.sh --provision-worktree` or equivalent). This feature does not re-implement worktree creation.
- The `SendMessage` mechanism for forwarding user input to a running sub-agent is available in the host environment. Without it, FR-011 cannot be satisfied and the feature is not viable.
- Quality-gate configuration (lint, tests, QA, push approval) is read from the project's existing config, not redefined by this feature.
- 8 tickets is a judgment-call upper bound drawn from the input; it is intentionally conservative and can be revisited after real usage.
