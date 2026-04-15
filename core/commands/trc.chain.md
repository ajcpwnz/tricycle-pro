---
description: >-
  Run the full trc workflow (specify → clarify → plan → tasks → analyze →
  implement → push) across a small range of Linear tickets (2–8) serially,
  with fresh context per ticket. Each ticket runs in its own sub-agent and
  its own git worktree; the orchestrator relays checkpoints back to the user
  and never auto-approves pushes.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

`/trc.chain <range-or-list>` orchestrates `/trc.headless` across 2–8 Linear
tickets **serially**, preserving output quality by giving each ticket a
fresh sub-agent context. This command is an orchestrator: it spawns
workers, relays checkpoint questions, and produces a final summary. It
never reimplements the trc workflow itself — workers do that via
`/trc.headless`.

**Core principle**: Fresh context per ticket. Never run multiple tickets'
workflows in one conversation — quality collapses by ticket 3+ from context
pollution and stale assumptions.

## Pre-Flight Validation

Before doing anything:

1. **Empty input check**. If `$ARGUMENTS` is empty or only whitespace, STOP
   and output:
   ```
   Error: No ticket range provided.
   Usage: /trc.chain <range-or-list>
   Examples: /trc.chain TRI-100..TRI-105
             /trc.chain TRI-100,TRI-103,POL-42
   ```

2. **Project init check**. Verify `tricycle.config.yml` and `.trc/` exist.
   If either is missing, STOP and tell the user to run `npx tricycle-pro init`.

## Resume Detection

Call the helper to find any interrupted runs from a previous session:

```bash
bash core/scripts/bash/chain-run.sh list-interrupted
```

Parse the JSON. If `runs` is non-empty, surface each one to the user:

```
Found N interrupted chain run(s):
  - <run_id>: <count> tickets, <completed> completed, next: <next_ticket_id>,
    last updated <updated_at>

Options for each: [R]esume, [D]iscard, [I]gnore and start new.
```

Wait for the user's choice for each run before proceeding.

- **Resume**: skip `parse-range` and `init` entirely — re-read the interrupted
  run's `state.json` via `chain-run.sh get --run-id <id>`, identify the next
  ticket whose status is not `completed`/`skipped`, and jump directly to the
  Per-Ticket Loop starting from that ticket. Re-fetch Linear bodies for the
  remaining tickets only.
- **Discard**: call `chain-run.sh close --run-id <id> --terminal-status aborted
  --reason "user discarded"`, then continue to Parse Range with the user's
  new input.
- **Ignore**: leave the interrupted run untouched, continue to Parse Range.

## Parse Range

Call:

```bash
bash core/scripts/bash/chain-run.sh parse-range "$ARGUMENTS"
```

On non-zero exit, the stderr JSON contains the error code and message —
surface it directly to the user and abort. Error codes map to user-facing
messages documented in
`specs/TRI-27-trc-chain-orchestrator/contracts/chain-run-helper.md`.

On success the stdout JSON has `{"ids": [...], "count": N}`. Capture the
`ids` array.

## Runtime Probe

**Critical**: verify the runtime supports `SendMessage` forwarding to
running sub-agents **before** spawning any worker. If this fails, the
feature cannot work — abort loudly instead of silently losing worker
context on the first pause.

Procedure:

1. Spawn a throwaway probe agent:
   ```
   Agent({
     name: "chain-probe",
     subagent_type: "general-purpose",
     description: "SendMessage probe for /trc.chain",
     prompt: "Respond exactly with the token READY and then wait for my next message. When you receive any reply, exit immediately."
   })
   ```
2. Immediately attempt:
   ```
   SendMessage({to: "chain-probe", message: "exit"})
   ```
3. If either step fails (tool unavailable, agent not addressable, error
   response), STOP and output:
   ```
   Error: This runtime does not support SendMessage forwarding to paused
   sub-agents, which is required for /trc.chain checkpoint relay.
   Fall back to /trc.headless per ticket.
   ```

## Linear Fetch

For each ticket ID from `parse-range`, fetch its title and body from Linear:

```
mcp__linear-server__get_issue({id: "<ticket-id>"})
```

**Hard-fail policy** (per FR-002 clarification):

- If the Linear MCP server is unreachable (connectivity error, MCP tool
  unavailable), abort the chain with `ERR_LINEAR_UNREACHABLE`:
  ```
  Error: Linear MCP unreachable. Restart your MCP server and retry.
  ```
- If any ticket ID returns not-found, collect all missing IDs and abort
  with `ERR_TICKETS_NOT_FOUND`:
  ```
  Error: Ticket(s) not found in Linear: TRI-999, POL-404
  ```
- If some fetches succeed and some fail, still abort — do NOT prompt to
  proceed with a partial set.

Do not spawn any worker until every ticket body is in hand.

## Scope Confirmation

Print the ticket list for the user to review:

```
Ready to run /trc.chain on these tickets:

  1. TRI-100 — Add user authentication
  2. TRI-101 — Profile page
  3. TRI-102 — Password reset flow

Proceed? (yes / no)
```

Wait for the user's explicit `yes` (or equivalent). On `no` or any
rejection, abort cleanly — no side effects to undo at this point.

## Epic Brief Prompt

After scope confirmation, ask the user about the shared epic brief:

```
Optional: would you like to attach a shared epic-brief.md to this chain?
This is the ONLY cross-ticket context workers will share.

  [P]ath — provide a path to an existing brief
  [C]reate — I'll prompt you for the content inline
  [S]kip — no shared brief
```

- **Path**: ask for the path, verify it exists, remember it for `init`.
- **Create**: prompt the user for the content (multiline input), write it
  to a temp file with `mktemp`, remember that path for `init`.
- **Skip**: no brief path; remember `null`.

## Run Init

Call the helper with the parsed ids and (optionally) the brief:

```bash
bash core/scripts/bash/chain-run.sh init \
  --ids '<json-array-of-ids>' \
  --ids-raw '<original-user-input>' \
  [--brief '<path-if-any>']
```

Capture `run_id`, `state_path`, `brief_path` from the stdout JSON. Store
them as orchestrator working memory for the rest of the execution. On any
helper error, surface it and abort.

## Worker Brief Template

Each worker receives a brief of the following shape (substitute the
placeholders at spawn time):

```
You are a /trc.chain worker for ticket <ticket-id>.

TICKET: <ticket-id> — <title>

BODY:
<ticket body from Linear>

SHARED EPIC BRIEF:
<if brief_path is null: "No shared epic brief for this run; each ticket is independent.">
<if brief_path is non-null: "Read the shared epic brief at: <brief_path>">

RUN DIRECTORY: specs/.chain-runs/<run-id>/

TASK: Execute the full /trc.headless workflow end-to-end for this ticket.

HARD REQUIREMENTS:
1. PHASE EVENTS: At the START of each trc phase (specify, clarify, plan,
   tasks, analyze, implement, push), overwrite the progress file:
     printf '{"phase":"<phase>","started_at":"%s","ticket_id":"<ticket-id>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.chain-runs/<run-id>/<ticket-id>.progress
   Use the exact phase names above. When the run finishes, write phase=done.

2. NEVER auto-approve pushes. Always pause and wait for explicit approval
   via SendMessage, even though your parent is an orchestrator.

3. QUALITY GATES: lint must be green, tests must be green, local stack test
   for user-facing changes, QA test cases added for user-facing features.
   Do not request push approval until all gates pass.

4. FINAL REPORT: When you finish (or if you cannot proceed), return a
   single structured JSON object as your final message, wrapped in
   ```json ... ``` fences, with these fields:
     {
       "ticket_id":  "<ticket-id>",
       "status":     "completed" | "failed",
       "branch":     "<branch-name or null>",
       "pr_url":     "<github-pr-url or null>",
       "lint_status": "pass" | "fail" | "skipped",
       "test_status": "pass" | "fail" | "skipped",
       "worker_error": null | "<short-error>",
       "open_questions": ["<optional-caveat-1>", ...],
       "summary":    "<one-paragraph human summary>"
     }
   Follow the JSON block with nothing else. The orchestrator destructures
   these fields and does NOT retain your conversation transcript.

5. PAUSE BEHAVIOR: If the trc workflow pauses for a clarify question, a
   plan-approval gate, a push-approval gate, or any other user input,
   simply return the question as your pause message. The orchestrator will
   forward my next reply to you via SendMessage; you resume with full
   context. Do NOT synthesize an answer on my behalf for non-trivial pauses.
```

Keep this brief under ~400 words so it fits cleanly in the worker's
initial prompt.

## Per-Ticket Loop

For each ticket ID in order:

1. **Mark in_progress**:
   ```bash
   bash core/scripts/bash/chain-run.sh update-ticket \
     --run-id "<run_id>" --ticket "<ticket-id>" \
     --status in_progress --started-now
   ```

2. **Spawn the worker** using `Agent` with `name: "chain-worker-<ticket-id>"`.
   This name MUST be unique across the chain run and MUST be used as the
   `to:` field in all `SendMessage` calls for this ticket.

3. **Pause-relay loop**. The worker's return message is either a pause
   (waiting for user input) or the final structured report. Distinguish:

   - **Final report**: a fenced ```json``` block matching the schema in
     the Worker Brief Template. Destructure it (branch, pr_url,
     lint_status, test_status, open_questions, summary), discard the
     conversation transcript (do NOT keep raw worker output beyond the
     destructured fields — FR-014), and break out of the pause-relay loop.

   - **Pause**: any other return shape — treat it as a question. Surface
     to the user:
     ```
     [<ticket-id>] <question text>
     ```
     Wait for the user's reply. Then call:
     ```
     SendMessage({to: "chain-worker-<ticket-id>", message: "<user reply>"})
     ```
     The worker resumes with full context. Loop back to step 3.

4. **Progress display** (FR-022). Between `SendMessage` round-trips (or
   while waiting for a worker that has not yet returned), read the
   progress file and show:
   ```
   [<ticket-id>] → <phase> ⏱ <elapsed-seconds>s
   ```
   Re-read via:
   ```bash
   bash core/scripts/bash/chain-run.sh progress \
     --run-id "<run_id>" --ticket "<ticket-id>"
   ```
   Update the display whenever the phase changes. Do NOT stream the
   worker's transcript.

5. **Record terminal state**:

   - **On completed report** (`status=completed`, lint/test=pass):
     ```bash
     bash core/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status completed --finished-now \
       --branch "<branch>" --pr "<pr_url>" \
       --lint pass --test pass
     ```
     Continue to the next ticket.

   - **On failed report** (`status=failed`, OR lint/test=fail, OR
     worker_error non-null, OR worker returned an error instead of a
     structured report): update as `failed`, **immediately close the run**
     with terminal-status `failed`, stop the chain, and jump to Summary:
     ```bash
     bash core/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status failed --finished-now \
       --lint "<lint_status>" --test "<test_status>"
     bash core/scripts/bash/chain-run.sh close \
       --run-id "<run_id>" --terminal-status failed \
       --reason "<short-reason>"
     ```
     Do NOT spawn a worker for any remaining ticket. Leave them
     `not_started`. Per FR-012: stop-on-failure means **stop**.

## Context Hygiene (FR-014)

The orchestrator's context MUST contain only:

- The original user input
- Ticket metadata (id, title, body)
- Worker final reports (destructured fields only — branch, pr_url,
  lint_status, test_status, open_questions, one-paragraph summary)
- Helper subcommand stdout when needed for decisions

The orchestrator MUST NOT retain:

- Raw worker conversation output beyond the structured report
- Intermediate tool outputs produced by the worker
- Per-phase logs from the worker

If you find yourself re-reading a worker's transcript, you are violating
the context-hygiene contract.

## Push Approval Invariant (FR-009)

Push approval MUST be requested **once per ticket**. A prior approval in
the same chain run does NOT carry over. The orchestrator NEVER auto-approves
a push, even if the previous N pushes were all approved by the same user
in the same session.

This is enforced at two layers:

1. The worker prompt above explicitly tells the worker to pause on push.
2. The orchestrator pause-relay loop (step 3 of Per-Ticket Loop) never
   bypasses a pause — every question the worker raises gets routed back to
   the user.

## Summary

After the loop completes (successfully, partially, or stopped-on-failure):

1. Read the final state:
   ```bash
   bash core/scripts/bash/chain-run.sh get --run-id "<run_id>"
   ```

2. Render a markdown summary table with columns:
   `| Ticket | Branch | PR | Lint | Test | Status |`

   Use distinct markers for the four ticket statuses so it's unambiguous
   which tickets completed, which failed, which were skipped, and which
   were never started:

   - `completed` → ✓ or "done"
   - `failed` → ✗ or "FAILED"
   - `skipped` → "skipped"
   - `not_started` → "—"

3. If the run is not already terminally closed (it is if we hit
   stop-on-failure), call:
   ```bash
   bash core/scripts/bash/chain-run.sh close \
     --run-id "<run_id>" --terminal-status completed
   ```

4. Print the summary table and a one-line footer with the run-id so the
   user can reference it later.

## Done

Output:
```
/trc.chain complete. Run id: <run_id>
```

That's the end of the command. Do not spawn additional agents, do not
re-open the chain, do not attempt automatic retries. The user drives the
next move.
