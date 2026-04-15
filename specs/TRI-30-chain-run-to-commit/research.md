# Phase 0 Research: TRI-30 — /trc.chain run-to-commit

**Feature**: TRI-30-chain-run-to-commit
**Date**: 2026-04-15

The spec already resolved the high-level design (worker contract, status enum, progress event semantics, resume strategy). This document covers the **implementation-level unknowns** that needed answers before Phase 1 design could lock in.

---

## R1 — Does `/trc.implement` actually `git commit` at the end of its run?

**Verified by reading `core/commands/trc.implement.md`**.

**Finding**: The current `trc.implement` command template references "the final commit" (line 191: *"Include the version bump in the final commit"*) but does **NOT** contain an explicit `git add` / `git commit` instruction step. The "Push, PR & Deploy" subsection (lines 196+) jumps straight from the lint/test gate and version bump to `git push`, with no explicit commit between them.

In practice, when `trc.implement` runs in a normal interactive session, the agent typically uses the `/commit` skill or does an inline `git commit` because the user expects committed work. But this is **convention**, not contract.

**Decision**: The worker brief in `core/commands/trc.chain.md` MUST include an **explicit commit step** at the end of the worker's instructions, after `/trc.implement` finishes:

```
After /trc.implement completes successfully (lint+test green, version bumped):
1. git add -A
2. git commit -m "<ticket-id>: <one-line summary>"
3. capture commit_sha = $(git rev-parse HEAD)
4. emit final progress event {"phase":"committed","commit_sha":"<sha>",...}
5. return final JSON report and exit
```

**Rationale**: Workers must end at a deterministic commit (FR-001/FR-007). Relying on `/trc.implement` to commit on its own is a load-bearing assumption I cannot verify without changing `trc.implement.md` itself, which is out of scope for TRI-30. Making the commit explicit in the worker brief is a one-line addition with zero downside.

**Alternatives considered**:
- *Modify `trc.implement.md` to always commit*: rejected — out of scope; would affect non-chain users of `/trc.implement` and risks regressions in other workflows.
- *Trust the convention*: rejected — the entire reason TRI-30 exists is that TRI-27 trusted an unverified assumption (`SendMessage` works) and lost 30 minutes of debugging. Making the commit explicit costs nothing and removes a class of failure.

---

## R2 — How does the orchestrator detect worker completion?

**Decision**: Parse the structured JSON report from the worker's return message. The report's `status` field (`committed` or `failed`) is the **primary** signal. **Cross-check** by reading the worker's progress file and confirming the final event has `phase: "committed"` with a non-null `commit_sha`. If either check fails, treat the worker as failed.

**Rationale**:
- The return message is the authoritative communication channel from worker to orchestrator. Any other channel (filesystem polling, git inspection) is secondary.
- The cross-check exists to catch the failure mode where a worker writes a "successful" report but its progress file says it crashed mid-implement. This shouldn't happen with a well-behaved worker, but a static cross-check costs nothing and adds a layer of safety.

**Alternatives considered**:
- *Read git directly*: rejected as the primary signal because the orchestrator and worker are in different worktrees, and git operations across worktrees are clunkier than reading a state file. Used only at resume time (R5).
- *Best-effort parse with retry*: rejected per spec FR-009 step 3 — malformed reports = stop the chain. No retries, no guesses.

---

## R3 — Crashed worker / malformed output detection

**Decision**: If the worker's return message does not contain a fenced ` ```json ... ``` ` block matching the report schema, OR if required fields (`ticket_id`, `status`, `branch`, `lint_status`, `test_status`, `summary`) are missing, OR if the JSON fails to parse, treat the worker as failed with `worker_error: "malformed report"`. The orchestrator stops the chain and surfaces the failure. **No retry. No best-effort parsing. No partial salvage.**

**Rationale**: Tonight's debugging session was caused by trusting a "happy path" return message and ignoring all the signs that something was off. A strict parser at the worker → orchestrator boundary is the cheapest way to make failures **loud** instead of **silent**.

**Implementation note**: The schema validation happens entirely in the orchestrator's command-template instructions (markdown). It's a read-and-check, not a runtime function. The orchestrator extracts the JSON block with a regex-style fence match, runs `python3 -m json.tool` to validate parseability, then asserts each required field is present.

---

## R4 — `update-ticket` extension vs. new helper subcommand

**Decision**: **Extend `update-ticket`** with new flags and relax existing validation rules. No new subcommand.

Specifically:
- New flag `--commit-sha <sha>` — populates `tickets.<id>.commit_sha`.
- New valid `--status` values: `committed`, `pushed`, `merged`.
- Relaxed `--pr` validation: now allowed when status ∈ `pushed`, `merged`, `completed` (was: only `completed` in TRI-27).
- New error code `ERR_BAD_TRANSITION` for illegal forward transitions (e.g., `not_started → merged` should fail; only `not_started → in_progress → committed → pushed → merged → completed` is legal forward, plus `→ failed` from any non-terminal state).

**Rationale**:
- `update-ticket` was designed to be additive — its flag set is already a long list, and adding two more is consistent.
- Separate `mark-committed` / `mark-pushed` / `mark-merged` subcommands would split the helper surface into 4× the number of code paths for marginal conceptual gain.
- The orchestrator already calls `update-ticket` at every state transition; keeping the same call site means less rewriting in `trc.chain.md`.

**Alternatives considered**:
- *Separate `mark-pushed` / `mark-merged` subcommands*: rejected — surface-area cost not worth it.
- *A dedicated `transition` subcommand that takes `--from` and `--to`*: rejected as over-engineering for a 6-state machine.

---

## R5 — Resume-via-git verification

**Decision**: When `list-interrupted` returns a run, the **orchestrator** (not the helper) is responsible for cross-checking each ticket's recorded state against the worktree's git state.

The helper continues to return only what `state.json` says. The orchestrator's resume-detection section in `trc.chain.md` walks the ticket list and, for each ticket marked `committed`, `pushed`, or `merged`:

1. Locates the ticket's worktree (`worktree_path` from state.json).
2. Runs `git -C "$worktree_path" rev-parse "$branch"` to confirm the branch exists locally.
3. For `committed`: confirms `git -C "$worktree_path" rev-parse HEAD == commit_sha`.
4. For `pushed`: confirms `git -C "$worktree_path" ls-remote origin "$branch"` returns a matching SHA.
5. For `merged`: confirms via `gh pr view <pr_url> --json state` that the PR is `MERGED`.

On any mismatch, surface to the user: re-spawn the worker, skip the ticket, or abort.

**Rationale**:
- The helper's job is to manage the state file, not to do git or network operations. Mixing those concerns would bloat it.
- The orchestrator is already a context full of git knowledge (it does its own `git push`/`gh pr create`); making it responsible for the verification is a natural fit.
- The verification is a **belt-and-suspenders** check — it catches the case where state.json was written before a crash but git was not, or vice versa.

**Alternatives considered**:
- *Helper does the git checks*: rejected — pollutes the helper's deterministic-state-machine purity, makes it harder to test in isolation.
- *Trust state.json blindly*: rejected — exactly the kind of unverified assumption that caused TRI-30 in the first place.

---

## R6 — How do we test FR-013 (no `SendMessage` calls)?

**Decision**: Add a static `grep` test, `tests/test-chain-run-no-sendmessage.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
TARGET="$REPO_ROOT/core/commands/trc.chain.md"
if grep -i "SendMessage" "$TARGET" > /dev/null; then
    echo "FR-013 violation: trc.chain.md references SendMessage" >&2
    grep -in "SendMessage" "$TARGET" >&2
    exit 1
fi
echo "no-sendmessage: OK"
```

Hooked into `run-tests.sh`. Fires every test run.

**Rationale**:
- We **cannot** test the agent runtime from a shell test — there's no way to spawn a real Claude Code sub-agent and verify its message-handling behavior.
- A static check is the next-best guarantee: if `SendMessage` ever creeps back into the command file (during a regression, or during a careless future edit), the test suite fails immediately.
- This is the test-suite equivalent of a load-bearing assertion. It's cheap, it's clear, and it directly enforces the spec's most important negative requirement.

**Alternatives considered**:
- *Mock the Agent runtime in tests*: rejected — Claude Code's tool layer isn't mockable from bash, and writing a mock harness would dwarf the actual fix.
- *Document and hope*: rejected — the whole point of TRI-30 is that documentation alone didn't prevent the original bug.

---

## R7 — Minimal command-file rewrite scope

**Decision**: Surgical edit, not a rewrite. From `core/commands/trc.chain.md`:

**KEEP** unchanged:
- `## Pre-Flight Validation`
- `## Resume Detection` (header — content is updated for new statuses but section structure stays)
- `## Parse Range`
- `## Linear Fetch`
- `## Scope Confirmation`
- `## Epic Brief Prompt`
- `## Run Init`
- `## Summary`
- `## Done`
- `## Context Hygiene` (FR-014 from TRI-27 carries forward)

**DELETE entirely**:
- `## Runtime Probe` (R7 from TRI-27 research — the SendMessage probe is meaningless when SendMessage is not used)
- `## Push Approval Invariant` (the standalone block; the actual invariant moves into the new orchestrator push step)

**REWRITE**:
- `## Worker Brief Template` — new worker contract per FR-001 to FR-007. Worker runs `/trc.headless`, then explicit `git add -A && git commit`, emits final progress event, returns structured JSON, exits.
- `## Per-Ticket Loop` — strip the pause-relay loop entirely. New body: spawn worker → block on return → parse report (R2/R3) → branch on status → either mark failed and stop, OR call new orchestrator push step.

**ADD**:
- `## Orchestrator Push Step` — new section documenting: read report → print one-line summary → ask user "push?" → on approval run `git push -u`, `gh pr create`, `gh pr merge --squash --delete-branch`, worktree cleanup → `update-ticket --status pushed/merged/completed` at each transition.

**Rationale**: Keeps the file's structure stable so reviewers can diff it cleanly, focuses the rewrite on exactly the parts that were broken, and minimizes the chance of accidentally touching working code.

---

## All clarifications resolved

No `NEEDS CLARIFICATION` markers remain. Phase 1 design can proceed.
