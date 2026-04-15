# Quickstart: trc.chain

**Feature**: TRI-27-trc-chain-orchestrator
**Audience**: A developer using tricycle-pro who wants to run the full trc workflow across a small batch of related Linear tickets.

---

## Prerequisites

- tricycle-pro installed and the project initialized (`tricycle.config.yml` + `.trc/` present).
- Linear MCP server configured and reachable. The orchestrator hard-fails at chain start if it cannot reach Linear or any ticket ID is not found.
- A clean working tree on the main branch (or any branch — the orchestrator uses worktrees, so your current checkout is not touched).
- `SendMessage`-to-running-subagent support in your Claude Code runtime. The orchestrator probes for this at chain start; if it's missing, the run aborts before spawning any worker.

## Happy path: three consecutive tickets

```text
/trc.chain TRI-100..TRI-102
```

What happens, in order:

1. **Runtime probe**. Orchestrator spawns a throwaway sub-agent and sends it a message to confirm forwarding works. If this fails, chain aborts immediately with a clear error.
2. **Ticket fetch**. Orchestrator resolves `TRI-100`, `TRI-101`, `TRI-102` via Linear MCP. If any is unreachable or not found, chain aborts before any worker is spawned.
3. **Interrupted-run check**. Orchestrator calls `chain-run.sh list-interrupted`. If there are stale runs, it prompts you to resume, restart, or ignore before starting a new one.
4. **Scope confirmation**. Orchestrator prints the three ticket titles and asks **go/no-go**. Reply `yes` (or `no` to abort).
5. **Epic brief prompt**. Orchestrator asks whether you want to create an `epic-brief.md` for this run. Decline to skip.
6. **Run init**. `chain-run.sh init` creates `specs/.chain-runs/<run-id>/state.json`. Run-id is echoed.
7. **Per-ticket loop (serial)**:
    - Orchestrator: `update-ticket --status in_progress --started-now` for TRI-100.
    - Orchestrator spawns `chain-worker-TRI-100` and hands it the ticket body + brief path + the instruction to run `/trc.headless` end-to-end.
    - While the worker runs, orchestrator displays `[TRI-100] → specify ⏱  00:14` style progress, updating the phase marker each time the worker writes a new `.progress` file.
    - When the worker reaches a pause point (clarify question, plan approval, push approval), orchestrator surfaces `[TRI-100] <question>` to you and waits. Your answer is forwarded to the **same running worker** via `SendMessage`.
    - Worker returns a structured report (<300 words: branch, PR URL, lint/test status, open questions). Orchestrator stores the destructured fields in `state.json` and forgets the raw transcript.
    - `update-ticket --status completed --finished-now --branch ... --pr ... --lint pass --test pass`.
    - Loop to TRI-101, then TRI-102.
8. **Close**. `chain-run.sh close --terminal-status completed`.
9. **Summary**. Orchestrator prints a table of `ticket → branch → PR → status` for all three.

Expected total interaction from you: one go/no-go, one epic-brief decision, N clarify answers per ticket, and one push approval per ticket. Everything else is automatic.

## Resuming an interrupted run

Whatever ended the session (crash, context exhaustion, laptop lid closed), the next time you run `/trc.chain` on **any** input the orchestrator first calls `list-interrupted` and surfaces:

```text
Found 1 interrupted chain run:
  - 20260415T123456-TRI-100 (3 tickets, 1 completed, next: TRI-101, last active 2h ago)

Options: [R]esume, [D]iscard, [I]gnore and start new run.
```

- **R**esume: the orchestrator re-reads `state.json`, skips tickets whose status is already `completed`, and spawns a fresh worker for the next `not_started` or `in_progress` ticket. Any progress files from the prior worker are overwritten; no stale data leaks in.
- **D**iscard: calls `close --terminal-status aborted --reason "user discarded"` and wipes the `.progress` files, then continues to the next question.
- **I**gnore: leaves the interrupted run alone and starts the new one you just invoked.

Completed tickets from the interrupted run remain untouched — their branches and PRs are already real git state.

## Stop-on-failure

If the worker on TRI-101 fails (lint fails, tests fail, worker crashes, push rejected, etc.), the orchestrator:

1. Receives the failure report from the worker.
2. Calls `update-ticket TRI-101 --status failed --finished-now`.
3. Calls `close --terminal-status failed --reason "<short reason>"`.
4. Prints the summary table (TRI-100 completed, TRI-101 failed, TRI-102 not started).
5. Does **not** spawn a worker for TRI-102.

The failed ticket's branch and (partial) worktree remain for you to inspect and fix. Once fixed, re-invoke `/trc.chain TRI-101,TRI-102` to continue.

## Cleanup

`specs/.chain-runs/` accumulates state from every run. It's gitignored, so it never leaks into commits, but you may want to prune it occasionally:

```bash
# Inspect
ls specs/.chain-runs/

# Nuke terminally-closed runs older than 30 days
find specs/.chain-runs -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
```

`list-interrupted` only considers runs whose top-level `status == "in_progress"`, so closed runs never interfere — pruning is purely cosmetic.

## Troubleshooting

**"This runtime does not support SendMessage forwarding..."** — Your Claude Code runtime can't deliver messages to paused sub-agents. This is a hard dependency. Run tickets one at a time with `/trc.headless` until runtime support is available.

**"Range resolves to 9 tickets. Maximum is 8."** — Intentional. Break your batch into `/trc.chain TRI-100..TRI-105` followed by `/trc.chain TRI-106..TRI-108`. Quality degrades beyond ~8 per user session even with fresh worker contexts, because the orchestrator's own context fills up with summaries.

**"Linear MCP unreachable at chain start."** — Restart your MCP server (`.mcp.json` tells you how it's configured) and re-invoke `/trc.chain`. The orchestrator never proceeds with a partial ticket set.

**"Run not found: <id>"** — The `specs/.chain-runs/<id>/` directory was deleted or corrupted. Check with `ls specs/.chain-runs/`. If the run was already complete, this is fine — nothing to resume.

**Worker seems stuck on a phase for a long time.** — There is no automatic timeout. Check the `.progress` file directly:

```bash
cat specs/.chain-runs/<run-id>/<ticket-id>.progress
```

If the phase hasn't changed in a long time, you can kill the session and resume — the partially-completed ticket will restart from scratch on resume (re-running a phase is idempotent for the trc workflow).
