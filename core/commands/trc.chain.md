---
description: >-
  Run /trc.plan then /trc.implement, unattended, across a small range of
  Linear tickets (2–8) in bounded parallel (up to chain.max_parallel, default
  2). A ticket that another ticket in the same run blocks starts after its
  blocker. A spec that passes the validator counts as approved. Each ticket
  runs in its own sub-agent and its own git worktree. The orchestrator relays
  checkpoints back to the user and never auto-approves pushes.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

`/trc.chain <range-or-list>` runs `/trc.plan` then `/trc.implement` for 2–8
Linear tickets **in bounded parallel**: up to `chain.max_parallel` (default 2)
workers at the same time. Each ticket runs in a fresh sub-agent context. A
Linear "blocks" relation between two tickets of the run sets their order. The
dependent ticket starts only after its blocker merges. This command is an
orchestrator: it spawns workers, reports their results, and produces a final
summary. It never reimplements the trc workflow. Workers run the two commands
themselves.

**Unattended specs.** Workers do not stop for spec approval. A spec that passes
the `trc-spec-validator` agent counts as approved. A worker stops only for input
that only the user holds, and it reports that input as a failure.

**Core principle**: Fresh context per ticket. Never run multiple tickets'
workflows in one conversation — quality collapses by ticket 3+ from context
pollution and stale assumptions. Parallel runs keep this rule. Each ticket
has its OWN sub-agent with its own fresh context, and the workers only run at
the same time. The orchestrator keeps only the report fields, never the
worker transcripts.

**Not `/trc.band`**: chain stays small. It has no recon phase, no wave
calculation, no file-overlap analysis and no integration branch. It uses only
the Linear relations to set the order, and it keeps one PR and one push
approval for each ticket. For an epic with sub-issues that have real code
dependencies, use `/trc.band`.

## Session Rename (Fallback)

**Primary mechanism**: the `UserPromptSubmit` hook at
`.claude/hooks/rename-on-kickoff.sh` has already renamed the orchestrator
session to a `trc-chain-<range>` label before this prompt is seen. When the
hook fires, this block is a silent no-op.

This block is the fallback for hosts/installs without the hook.

**First thing done — before any Linear fetch, user confirmation, or worker
spawn:**

1. Compute the chain-scoped label from `$ARGUMENTS`:
   - If it's a range form (`X..Y`): label = `trc-chain-X..Y`.
   - If it's a comma list with N tokens: label = `trc-chain-<first>+<N-1>`.
   - Singleton: label = `trc-chain-<only>+0`.
2. Read `$CLAUDE_SESSION_TITLE` if available.
3. If the current label differs from the computed target, emit
   `/rename <target>` as the first text in your turn, before any tool call.
   If equal, skip silently.

Keep this label for the entire chain run — do NOT change it per-ticket.
Workers handle their own per-ticket rename (see Worker Brief HARD CONTRACT
rule on first action, below).

## Pre-Flight Validation

Before doing anything ELSE (after the rename above):

1. **Empty input check**. If `$ARGUMENTS` is empty or only whitespace, STOP
   and output:
   ```
   Error: No ticket range provided.
   Usage: /trc.chain <range-or-list>
   Examples: /trc.chain TRI-100..TRI-105
             /trc.chain TRI-100,TRI-103,POL-42
   ```

2. **Project init check**. Check that `tricycle.config.yml` and `.trc/` exist.
   If either is missing, STOP and tell the user to run `npx tricycle-pro init`.

3. **Helper path**. Every `chain-run.sh` snippet in this command references
   `.trc/scripts/bash/chain-run.sh` — the canonical location in consumer
   installs (landed by `tricycle update`) and in this toolkit repo (mirrored
   by `tricycle dogfood`). If that file is missing (e.g. a fresh toolkit
   checkout before dogfood), substitute `core/scripts/bash/chain-run.sh` in
   every invocation.

4. **Obsidian server**. If `spec.store` is `obsidian` and no `obsidian`
   MCP server is connected, STOP. Tell the user to run
   `tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart
   Claude Code.

## Resume Detection

Call the helper to find any interrupted runs from a previous session:

```bash
bash .trc/scripts/bash/chain-run.sh list-interrupted
```

Parse the JSON. If `runs` is non-empty, surface each one to the user:

```
Found N interrupted chain run(s):
  - <run_id>: <count> tickets, <completed> completed, next: <next_ticket_id>,
    last updated <updated_at>

Options for each:
  [R]esume — pick up where the run left off
  [D]iscard — close the run (terminal-status aborted)
  [I]gnore — leave it untouched, start new (will re-surface on next resume check)
  [X] Dismiss — hide this run from future resume prompts without closing it
                (useful for runs owned by another shell session on this machine)
```

Wait for the user's choice for each run before proceeding.

- **Resume**: skip `parse-range` and `init` entirely — re-read the interrupted
  run's `state.json` via `chain-run.sh get --run-id <id>`. Then **cross-check
  each non-terminal ticket against actual git state** before deciding what to
  do with it (TRI-30 FR-018):

  For each ticket in the run:
  - **`completed`, `skipped`, `failed`** → not touched, no action.
  - **`merged`** → assume already shipped. No action.
  - **`pushed`** → run `gh pr view <pr_url> --json state` and read the PR
    state. If `MERGED`, mark `merged` then `completed` and continue. If still
    `OPEN`, jump straight to the merge step of `## Orchestrator Push Step`
    (skip the worker spawn AND the `git push`).
  - **`committed`** → run `git -C <worktree_path> rev-parse HEAD` and compare
    to `state.json`'s `commit_sha`. On match → jump straight to the Push
    Approval step of `## Orchestrator Push Step` (skip the worker spawn).
    On mismatch → surface the inconsistency to the user with three options:
    `[R]e-spawn worker`, `[S]kip ticket`, `[A]bort chain`.
  - **`in_progress`** → **background workers NEVER continue after a session
    restart.** The worker is dead, and the files on disk are the truth. Treat
    the ticket as `not_started` for resume purposes. The Scheduler Loop
    schedules a fresh worker. Do NOT trust its old `.agent` sidecar.
  - **`not_started`** → the Scheduler Loop schedules it when its in-run
    blockers are satisfied.

  `state.json` already holds the `deps` map and `max_parallel`. Thus the
  Scheduler Loop applies the order and the cap again without more work. Do
  NOT run Dependency Detection again, and do NOT run `init` again. Re-fetch
  Linear bodies only for the tickets that still need workers. Start the
  watchdog again (see Run Init). Then continue with `## Scheduler Loop`.
- **Discard**: call `chain-run.sh close --run-id <id> --terminal-status aborted
  --reason "user discarded"`, then continue to Parse Range with the user's
  new input.
- **Ignore**: leave the interrupted run untouched, continue to Parse Range.
  It will re-appear on the next `/trc.chain` invocation.
- **Dismiss**: call `chain-run.sh dismiss --run-id <id>` to hide the run from
  future resume prompts without closing it. State is preserved — the run can
  still be inspected on disk at `specs/.chain-runs/<run-id>/`. Use this for
  runs owned by another session on this machine that you don't intend to
  resume yourself.

## Parse Range

Call:

```bash
bash .trc/scripts/bash/chain-run.sh parse-range "$ARGUMENTS"
```

On non-zero exit, the stderr JSON contains the error code and message.
Show the message to the user and abort.

On success the stdout JSON has `{"ids": [...], "count": N}`. Capture the
`ids` array.

## Linear Fetch

For each ticket ID from `parse-range`, fetch its title and body from Linear.
`<linear>` stands for the name of the connected Linear MCP server, for example
`linear` or `linear-server`:

```
mcp__<linear>__get_issue({id: "<ticket-id>"})
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

## Scope Echo

Print the fetched ticket list as a one-shot status line, then proceed
immediately to the next step. The user supplied the ticket IDs when
invoking `/trc.chain`, so running the command IS the confirmation.

```
Running /trc.chain on:
  1. TRI-100 — Add user authentication
  2. TRI-101 — Profile page
  3. TRI-102 — Password reset flow
```

**MUST NOT** emit any confirmation prompt at this step — no "Proceed?",
no "yes / no", no "continue?", no variant. This rule is absolute and has
no exceptions. The scope line exists so the user can Ctrl+C if the list
is wrong. That is the only abort path.

Something can look odd: tickets under different parent Linear
**projects**, an obvious outlier, or a label mismatch. If you notice one,
fold it into the scope line as a non-blocking note and keep going. Never
convert a concern into a gate. Parent *tickets* are not parent *projects*.
Cross-linked tickets inside the same project are not ambiguity.

```
Running /trc.chain on:
  1. POL-590 — Widget static hosting
  2. POL-591 — Cross-browser + CSP suite
  3. POL-639 — Analytics pipeline
  4. POL-644 — Branding theme apply
Note: POL-644 has a different parent ticket but the same parent
project (Embedding) — proceeding.
```

## Epic Brief Generation

After the scope echo, **synthesize** the shared `epic-brief.md`
from the ticket context you already have in hand. Do NOT ask the user
whether to create one — the tickets themselves are the source of truth,
and the brief is regenerated every run. The user is only prompted as a
fallback when there is genuinely nothing to synthesize from.

1. **Collect parent projects.** For each fetched ticket, inspect its
   `project` field (returned by `mcp__<linear>__get_issue`).
   Collect the unique set of parent project ids/names across the
   chain (usually 0, 1, or 2 for a coherent run).

2. **Fetch each unique parent project once** via:
   ```
   mcp__<linear>__get_project({query: "<project-id-or-name>"})
   ```
   Retain only: project name, description/summary, stated goals, and
   any explicit non-goals or constraints. Discard the rest. On any
   Linear MCP error here, continue without project context — missing
   parent-project data is not a chain-abort condition.

3. **Synthesize the brief.** Combine:
   - A one-paragraph overview drawn from the parent project(s), or
     (if no project) a one-paragraph overview inferred from the
     ticket bodies.
   - A bullet list of the chain's tickets, each as
     `- <ticket-id> — <one-line summary drawn from the ticket body>`.
   - Any cross-ticket dependency or sequencing that is obvious from
     the ticket bodies (e.g. "B depends on A", "all three share a
     rollout gate", "tickets assume X has landed").
   - A "Non-goals" line if the parent project or any ticket body
     names explicit non-goals.

   Keep the brief under ~40 lines. This is orientation for workers,
   not a spec. Write it to a temp file via `mktemp`. Remember
   that path for `init`. Print a two-line confirmation to the user
   (title + line count + "auto-generated from <N> tickets, <M>
   parent projects"). Do NOT prompt for approval. Workers treat
   the brief as read-only, and it is regenerated each run.

4. **Fallback prompt — only when ticket context is genuinely thin.**
   Use this fallback only if, after step 2, the total available
   context is empty or near-empty. Near-empty means all ticket bodies
   under ~50 characters AND no parent project attached to any ticket.
   In that case, fall back to asking the user:
   ```
   Ticket bodies are too thin to auto-generate an epic brief, and
   no parent Linear project is attached. Choose a fallback:

     [P]ath — provide a path to an existing brief
     [C]reate — draft one inline
     [S]kip — no shared brief
   ```
   - **Path**: ask for the path, check that it exists, remember it for `init`.
   - **Create**: prompt the user for the content (multiline input),
     write it to a temp file with `mktemp`, remember that path for
     `init`.
   - **Skip**: no brief path. Remember `null`.

## Dependency Detection & Concurrency

Chain runs tickets in parallel, up to a cap. A ticket that another ticket of
the same run blocks must wait until its blocker merges. Chain uses ONLY the
Linear blocks/blocked-by relations to find these dependencies. It does NOT
do band-style file-overlap recon. Chain is for independent tickets, and the
Linear relations are the only exception.

1. **Fetch relations.** For each ticket, read its blocks/blocked-by
   relations with `mcp__<linear>__get_issue` and `includeRelations: true`.
   The plain fetch in Linear Fetch can omit them. Fetch again with
   relations, or ask for them in the first fetch.

2. **Make the in-run `deps` map.** For each ticket, collect the ids of the
   tickets that block it. Keep a blocker only if it is also a ticket of this
   run. Chain sets the order only of the tickets that it controls. The
   result is a JSON object `{ "<ticket>": ["<blocker>", ...] }`. Omit a
   ticket that has no in-run blockers.

3. **Concurrency cap.** The cap comes from `chain.max_parallel` in
   `tricycle.config.yml`. The default is 2, and the helper clamps it to 1–8.
   `chain-run.sh init` reads it, so you do not read it yourself. You can
   show it in the scope line. A cap of 1, or a `deps` graph that is one
   line of tickets, gives a serial run.

4. **Worktrees off.** If `worktree.enabled` is not true in
   `tricycle.config.yml`, all workers use the main checkout. In that case,
   pass `--max-parallel 1` to `init`, because two workers must not edit
   one checkout at the same time.

5. **Add a note to the scope line** if you find in-run blocking relations.
   For example: `Note: TRI-103 is blocked-by TRI-100 (both in run) — TRI-103
   starts only after TRI-100 merges.` This note does NOT stop the run.

## Run Init

Call the helper with the parsed ids, the in-run `deps` map, and (optionally)
the brief:

```bash
bash .trc/scripts/bash/chain-run.sh init \
  --ids '<json-array-of-ids>' \
  --ids-raw '<original-user-input>' \
  --deps '<json-object-of-in-run-blocked_by-edges>' \
  [--max-parallel <N>] \
  [--brief '<path-if-any>']
```

- `--deps` is the map from Dependency Detection. Omit it, or pass `{}`, when
  no in-run blocking relations exist.
- `--max-parallel` is optional. Without it, the helper reads
  `chain.max_parallel` (default 2). Pass it only to override the cap for
  this run.
- `init` **checks** the deps. Every endpoint must be a ticket of the run
  (`ERR_DEP_ENDPOINT_NOT_IN_RUN`). The graph must have no cycle
  (`ERR_DEP_CYCLE`). On each of these errors, surface it to the user and
  abort. A cycle of block relations is a data problem in Linear. Do not
  guess a solution.

Capture `run_id`, `state_path`, `brief_path` from the stdout JSON. Store
them as orchestrator working memory for the rest of the execution. On any
other helper error, surface it and abort.

**Start the stall watchdog** one time for the full run, with the Monitor
tool. Do not start one for each ticket:

```bash
bash .trc/scripts/bash/chain-watchdog.sh --run-id "<run_id>"
```

The watchdog runs `chain-reconcile.sh` at intervals. It sends a chat event
the first time a ticket is `phantom`, `stalled` or `finished_unrecorded`.
`phantom` means the ticket is `in_progress` with no worker. `stalled` means
the worker transcript is idle. `finished_unrecorded` means the worker is done
but `state.json` does not show it. The watchdog stops when no ticket is
`in_progress`. Thus a stall of a background worker shows automatically.

## Worker Brief Template

Each worker is a fire-and-report sub-agent: it runs the full trc workflow
to a local commit and exits. **It does not pause. It does not wait for
input. It does not push.** The orchestrator (the parent conversation, with
full tool access) handles everything from `git push` onward.

Each worker receives a brief of the following shape (substitute the
placeholders at spawn time):

```
You are a /trc.chain worker for ticket <ticket-id>. RUN TO COMMIT, THEN EXIT.

TICKET: <ticket-id> — <title>

BODY:
<ticket body from Linear>

SHARED EPIC BRIEF:
<if brief_path is null: "No shared epic brief for this run; each ticket is independent.">
<if brief_path is non-null: "Read the shared epic brief at: <brief_path>. Treat it as READ-ONLY — do not edit it and do not tick checkboxes in it or in any other shared planning document. The orchestrator ticks shared docs once after the whole chain completes.">

PRE-PROVISIONED WORKTREE:
<if worktree_path is null: "No worktree pre-provisioned. /trc.implement provisions one when worktree.enabled is true.">
<if worktree_path is non-null:
"A worktree has been provisioned for you at: <worktree_path>
 On a new branch: <branch>

 BEFORE you run /trc.plan, cd '<worktree_path>' so that every later command
 runs inside it. /trc.implement sees the worktree and works in it.

 DO NOT re-run any worktree-setup step. DO NOT call
 `create-new-feature.sh --provision-worktree`. DO NOT rename the branch.
 Local testing evidence goes under exactly `specs/<branch>/`, with
 no suffixes (see rule 5 below).
">

RUN DIRECTORY: specs/.chain-runs/<run-id>/

GRAPHIFY CONTEXT:
The worker's assembled /trc.* commands carry a `## Graphify Context` block,
unless `workflow.blocks` disables it. Its runtime gate is active IFF both:
  (1) `integrations.graphify.enabled: true` in tricycle.config.yml, AND
  (2) `graphify-out/graph.json` exists.
When both conditions hold, the worker will query graphify (via the
`graphify query|path|explain` CLI, or MCP tools if `.mcp.json` had a
`graphify` entry at claude-session start) before falling back to wide
grep/read. When either condition fails, graphify is skipped silently.
No per-run gating is needed from the orchestrator — the block in each
step command is the single source of truth for the agent's behavior.>

TASK: Run `/trc.plan <ticket-id>`, then `/trc.implement <ticket-id>`, both
unattended:
  - /trc.plan: skip plan mode and do not call AskUserQuestion. A validator
    PASS is the approval: store the spec and continue. If the spec needs
    input only the user holds, or blockers remain after three validator
    rounds, return `status: "failed"` and put the reason in `worker_error`.
  - /trc.implement: run it through lint, tests and the version bump. Skip its
    push and worktree-cleanup sections: the orchestrator owns everything
    remote.
When both finish (lint + test green, version bumped), explicitly create a local
git commit with `git add -A && git commit -m "<ticket-id>: <one-line>"`,
capture the commit SHA, emit a final progress event, return a structured
JSON report as your final message, and EXIT. You will not be resumed.

HARD CONTRACT:

0. First action: `/rename <ticket-id-branch-name>`. The very first text you
   emit in this worker conversation MUST be `/rename <branch-name>` (where
   `<branch-name>` is the branch the orchestrator pre-provisioned, or the
   one that the worktree step of /trc.implement creates). This matches the session
   label convention of solo `/trc.plan` and `/trc.implement` runs and makes the
   worker identifiable in the Claude Code session list while it's
   in-flight. If the host does not honor `/rename` inside a sub-agent
   conversation, continue anyway — this is an explicit graceful
   degradation per TRI-31 SC-005. Do NOT abort on rename failure.

1. NEVER PAUSE. Do not ask the user questions. Do not request push
   approval. Do not wait for any reply. Sub-agent processes
   stop when they return, so any pause is a permanent hang. If
   /trc.plan wants to ask, settle the question from the code and the rules.
   If only the user can settle it, return a `status: "failed"` report with
   the question and exit.

   NEVER hedge in the final report either: if you return
   `status: "committed"`, your `open_questions` array MUST NOT contain
   anything resembling "push approval", "may I push", "should I merge",
   "awaiting approval", or any other phrase asking the user for a
   decision — the chain helper rejects such reports with
   ERR_COMMITTED_HEDGING and the whole ticket fails. Use `open_questions`
   only for forward-looking caveats (e.g. "consider backfilling legacy
   rows in a follow-up").

2. NEVER PUSH. You do not run `git push`, `gh pr create`, or `gh pr
   merge`. The orchestrator handles all remote-mutating commands AFTER
   your report. Your authority ends at the local commit.

3. PHASE EVENTS — END OF PHASE. At the END of each trc phase you finish
   (plan, implement), overwrite the
   progress file with the *_complete suffix:
     printf '{"phase":"<phase>_complete","completed_at":"%s","ticket_id":"<ticket-id>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.chain-runs/<run-id>/<ticket-id>.progress
   Use exactly: plan_complete, implement_complete. After your
   explicit `git commit`, write a final event with
   `phase: "committed"` and include the commit_sha:
     printf '{"phase":"committed","completed_at":"%s","ticket_id":"<ticket-id>","commit_sha":"<sha>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.chain-runs/<run-id>/<ticket-id>.progress

4. QUALITY GATES inside /trc.implement: the validation gate, lint green, tests green, local
   stack test for user-facing changes. If any gate fails, do NOT commit; return
   `status: "failed"`.

5. LOCAL-TESTING MARKER (project-local pre-push gate). If this project
   has a pre-push marker convention, the marker path is the branch's
   local-testing directory:
     specs/<branch>/.local-testing-passed
   where `<branch>` is the exact branch name of your worktree. Do NOT put
   the marker at the worktree root, under `apps/*/`, or under a renamed
   directory. If
   the marker is required, create it in the correct location before
   the orchestrator runs `git push`.

6. EXPLICIT COMMIT. After the gates pass (and the version bump, when that block is enabled), run:
     git add -A
     git commit -m "<ticket-id>: <one-line summary of the change>"
     COMMIT_SHA=$(git rev-parse HEAD)
   Then emit the final `committed` progress event (step 3).

7. FINAL REPORT. Return exactly one structured JSON object as your final
   message, wrapped in ```json ... ``` fences, with these fields:
     {
       "ticket_id":   "<ticket-id>",
       "status":      "committed" | "failed",
       "branch":      "<branch-name or null>",
       "commit_sha":  "<sha or null>",
       "spec":        "<spec location: docs/specs/<id>.md, the ticket, or the vault note <spec.dir>/<id>.md>",
       "files_changed": ["path/a", "path/b", ...],
       "lint_status": "pass" | "fail" | "skipped",
       "test_status": "pass" | "fail" | "skipped",
       "worker_error": null | "<short error>",
       "open_questions": ["<forward-looking caveat>", ...],
       "summary":     "<one-paragraph human summary>"
     }
   After this JSON block, write nothing else. Then exit.
```

## Scheduler Loop

The orchestrator keeps up to `max_parallel` background workers in flight. It
obeys the in-run dependencies, and it asks for push approval for each ticket
when that ticket commits. The orchestrator does all git remote operations
(push, PR, merge) itself, one at a time. Workers touch only their own
worktree.

Do these steps again and again until each ticket is terminal (`completed`,
`merged`, `failed` or `skipped`):

1. **Reconcile** the state with the real conditions before you trust it:
   ```bash
   bash .trc/scripts/bash/chain-reconcile.sh --run-id "<run_id>"
   ```
   Do the action for each finding in its output:
   - `phantom`: no worker is attached, or the worker is gone. Spawn the
     ticket again now. Mark it `in_progress` again (`in_progress →
     in_progress` on the same ticket is a legal respawn). Call a fresh
     `Agent` and write the `.agent` sidecar again, in the same turn as
     step 4b.
   - `stalled`: the worker is dead. Spawn it again, as for `phantom`.
   - `finished_unrecorded`: the worker already wrote a `committed` progress
     event, but you did not record it. Record it (step 6a). Do not spawn it
     again.

2. **Ask the scheduler for the next action**:
   ```bash
   bash .trc/scripts/bash/chain-run.sh next-ready --run-id "<run_id>"
   ```
   It returns `{"spawn":[...],"running":[...],"dep_failed":[...],
   "blocked":[...],"slots":N,"deadlock":bool}`. Trust it. The helper
   calculates the free slots and the dependency gates. A ticket that is
   `committed` or `pushed` still counts as active, so it is not a deadlock.
   If `deadlock` is true, surface it and abort. `init` rejects cycles, so
   this must not occur.

   **Do not spawn while the run stops.** If a worker already reported
   `failed` (step 6b), do NOT spawn the tickets in `spawn`. The run
   decreases now and does not increase. Go to step 5.

3. **Handle `dep_failed`.** An in-run blocker of each ticket in
   `dep_failed` failed, so that ticket can never run. Mark it `failed` and
   record it for the summary:
   ```bash
   bash .trc/scripts/bash/chain-run.sh update-ticket \
     --run-id "<run_id>" --ticket "<ticket-id>" --status failed --finished-now
   ```

4. **Provision the worktree, then spawn**, for each ticket in `spawn`.

   **4a. Provision the worktrees ONE AT A TIME.** Workers run at the same
   time, so they must NOT provision their own worktrees. Two `git worktree
   add` calls at the same time lock `.git` against each other. Two
   dependency installs at the same time overload the disk. Thus the
   orchestrator provisions one worktree at a time, with the same script as
   `/trc.band`:
   ```bash
   .trc/scripts/bash/create-new-feature.sh --provision-worktree \
     --style issue-number --issue "<ticket-id>" --json \
     "<ticket-id> <ticket title>"
   ```
   Wait for its JSON. Capture `BRANCH_NAME` and `WORKTREE_PATH`. Then
   provision the worktree of the next ticket in `spawn`. If `worktree.enabled`
   is not true, skip this step: `worktree_path` is null, and the cap is 1.

   **A dependent ticket needs a fresh base.** Its in-run blockers are now
   `merged`, and that is why `next-ready` offers it. Run `git fetch origin`
   in the main checkout **before** you provision its worktree. Then the
   script cuts the worktree from an `origin/<pr_target>` that contains the
   code of the blocker. A worktree from an old base does not have the code
   that the ticket needs.

   **4b. Mark the ticket running and spawn its worker in the SAME turn.**
   Never mark it and then spawn later. A worker-report notification can
   arrive between the two actions. Then you lose the spawn, and the ticket
   stays `in_progress` with no worker (a silent stall).
   ```bash
   bash .trc/scripts/bash/chain-run.sh update-ticket \
     --run-id "<run_id>" --ticket "<ticket-id>" \
     --status in_progress --started-now \
     --branch "<BRANCH_NAME>" --worktree "<WORKTREE_PATH>"
   ```
   Then, in the same turn, call `Agent` with
   `name: "chain-worker-<ticket-id>"`, `subagent_type: "general-purpose"`,
   and **`run_in_background: true`**. Give the Worker Brief Template content
   as the `prompt`. Fill its **PRE-PROVISIONED WORKTREE** block with
   `<worktree_path>` = `WORKTREE_PATH` and `<branch>` = `BRANCH_NAME`. The
   rest of the brief does not change. The worker runs to a local commit and
   exits. **Immediately write the `agentId` that `Agent` returns** to the
   sidecar file. Reconcile and the watchdog use it to find the worker:
   ```bash
   printf '%s' "<agentId>" > specs/.chain-runs/<run_id>/<ticket-id>.agent
   ```
   A ticket that is `in_progress` with no `.agent` sidecar is a lost spawn.
   Reconcile shows it as `phantom`.

5. **Wait for a background worker notification.** Do NOT poll with
   `sleep`. The harness tells you when a background worker completes its
   turn. When the user asks for progress, read it:
   ```bash
   bash .trc/scripts/bash/chain-run.sh progress \
     --run-id "<run_id>" --ticket "<ticket-id>"
   ```
   Show it as `[<ticket-id>] last completed: <phase>`. The phase has the
   `_complete` suffix, or it is `committed` for the terminal event. Do NOT
   stream worker transcripts. Do NOT keep more than the report fields
   (FR-014).

6. **Examine each worker report.** Parse the final message of the worker
   as a fenced ```json ... ``` block that matches the report schema of the
   Worker Brief Template. Check strictly:

   - The block must exist.
   - It must parse as JSON.
   - It must contain at minimum: `ticket_id`, `status`, `branch`,
     `commit_sha`, `lint_status`, `test_status`, `summary`.
   - `status` must be exactly `"committed"` or `"failed"`.

   If a check fails, treat the worker as failed with
   `worker_error: "malformed report"` and go to step 6b.

   - **6a. status == "committed"**: the worker made a local commit on its
     feature branch and exited. Record the commit:
     ```bash
     bash .trc/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status committed --commit-sha "<commit_sha>" \
       --branch "<branch>" \
       --lint "<lint_status>" --test "<test_status>"
     ```
     The ticket is no longer `in_progress`, so its slot is free. **First
     fill the free slots**: do steps 1–4 again, so that a waiting ticket
     starts. **Then** do **`## Orchestrator Push Step`** for this ticket.
     The other background workers continue while you wait for the push
     answer.

   - **6b. status == "failed"** (OR malformed report, OR `worker_error`
     non-null, OR `lint_status == "fail"`, OR `test_status == "fail"`): the
     run now **stops**. Mark the ticket failed:
     ```bash
     bash .trc/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status failed --finished-now \
       --branch "<branch or omit>" \
       --lint "<lint_status>" --test "<test_status>"
     ```
     Do NOT spawn more workers (the stop rule of step 2). Let the background
     workers that still run complete, and record their reports. Record a
     worker that reports `committed` after this point as `committed`, but do
     NOT push it. Show it in the summary, so that the user can push it
     manually. When no ticket is `in_progress`, close the run and go to
     `## Summary`:
     ```bash
     bash .trc/scripts/bash/chain-run.sh close \
       --run-id "<run_id>" --terminal-status failed \
       --reason "<short reason>"
     ```
     Per FR-012, stop-on-failure means **stop**: no new ticket starts.

7. **Loop**: go back to step 1 until each ticket is terminal.

## Orchestrator Push Step

This step runs **only** when a worker reports `status: "committed"`. The
orchestrator (you, in the parent conversation, with full tool access)
handles the entire push/PR/merge cycle in plain dialog with the user.
No sub-agent message-forwarding is involved. The worker is already dead.

**With parallel workers**, tickets commit **out of order**. Thus this step
occurs when each ticket commits, not in ticket order. This has two results:

- **The other background workers continue while you wait** for the push
  answer of this ticket. The push dialog stops only the turn of the
  orchestrator. Fill the free slots before you ask (Scheduler Loop step 6a).
- **A merge releases the dependent tickets.** A `merged` or `completed`
  ticket is a satisfied dependency. On the next Scheduler Loop pass,
  `next-ready` offers each ticket that it blocked. The return to the loop
  starts these tickets. Do not track dependent tickets in this step.

**Stop paths drain the run.** Some paths below stop the chain ("close",
"jump to Summary"). Before such a `close`, apply the stop rule of Scheduler
Loop step 6b. Spawn no new worker. Let the running workers complete, and
record their reports. Close the run only when no ticket is `in_progress`.

1. **Print one-line summary** to the user, derived from the worker's
   report:
   ```
   [<ticket-id>] <commit-sha-short> — <files-changed-count> files — lint:<status> test:<status>
   <one-paragraph summary from the report>

   Push <ticket-id>? (yes / no)
   ```

2. **Wait for the user's reply** in plain dialog. This is a normal user
   message — you read it from the conversation, not from any tool call.

3. **On `no`** (or any rejection):
   - Stop the chain. Leave the ticket as `committed` in state.json. Leave
     the local commit and worktree intact for the user to handle manually.
   - Call `chain-run.sh close --terminal-status aborted --reason "user
     declined push on <ticket-id>"`.
   - Jump to `## Summary`.

4. **On `yes`** (or any approval):

   a. **Pre-push marker (if applicable).** If this project has a local
      pre-push marker convention, ensure the marker file exists at the
      canonical path before invoking `git push` or `gh pr *`. An example
      is `specs/<branch>/.local-testing-passed` in some consumer repos.
      Create it in a **separate** Bash tool call:
      ```bash
      touch "<worktree_path>/specs/<branch>/.local-testing-passed"
      ```
      DO NOT chain `touch … && gh pr create …` in a single Bash call.
      Project-local pre-push guards that scan the full command string can
      see the `gh pr create` substring and block before the marker is
      written. For this reason, each step must be its own tool call.

   b. **`git push`** the worker's branch to origin (separate Bash call):
      ```bash
      git -C "<worktree_path>" push -u origin "<branch>"
      ```
      On failure (non-zero exit), surface the error, mark the ticket
      `failed`, `close --terminal-status failed --reason "git push: <err>"`,
      jump to `## Summary`.

   c. **`gh pr create`** targeting `push.pr_target` from
      `tricycle.config.yml` (separate Bash call — do NOT chain with
      step b):
      ```bash
      gh pr create --base "<pr_target>" --head "<branch>" \
        --title "<ticket-id>: <one-line>" \
        --body "<auto-generated body referencing the ticket and summary>"
      ```
      Capture the PR URL. Mark the ticket `pushed`:
      ```bash
      bash .trc/scripts/bash/chain-run.sh update-ticket \
        --run-id "<run_id>" --ticket "<ticket-id>" \
        --status pushed --pr "<pr_url>"
      ```
      On failure of `gh pr create`, surface, mark `failed`, close, jump
      to Summary.

   d. **`gh pr merge`** if `push.auto_merge` is true. Use
      `push.merge_strategy` (`squash`, `merge`, or `rebase`). On `squash`:
      ```bash
      gh pr merge "<pr_number>" --squash --delete-branch
      ```
      On success, mark the ticket `merged`.

      **Server-side merge succeeded, local sync failed** is a common case.
      For example, `gh pr merge` fails locally with `fatal: '<base>' is already
      used by worktree at '…'` because the base branch is checked out in
      another worktree on this machine. In that case the PR is already
      merged on GitHub. The only thing that failed was `gh`'s local ref
      sync. Before treating `gh pr merge`'s non-zero exit as a failure:
      ```bash
      gh pr view "<pr_url>" --json state,mergedAt
      ```
      If `state` is `MERGED` (and `mergedAt` is non-null), treat the merge
      as successful, log a one-line warning about the local sync error,
      and continue. Only fall through to the failure path below if the PR
      is genuinely not merged on the server.

      On a genuine merge failure (conflicts, branch protection, blocked
      review, not merged on server), surface, mark `failed`, close, jump
      to Summary.

      Mark the ticket `merged` whenever the server-side state is MERGED:
      ```bash
      bash .trc/scripts/bash/chain-run.sh update-ticket \
        --run-id "<run_id>" --ticket "<ticket-id>" --status merged
      ```

      If `push.auto_merge` is false, **stop here** with the PR URL and
      instructions for the user. The ticket stays `pushed`. Go back to the
      Scheduler Loop only if the user tells you to continue.

   e. **Worktree cleanup** after merge:
      ```bash
      git -C "<main-checkout>" worktree remove "<worktree_path>"
      git -C "<main-checkout>" worktree prune
      git -C "<main-checkout>" branch -d "<branch>"
      ```
      After a `squash` or `rebase` merge, `branch -d` refuses the branch,
      because its commits are not in the base. The server state is
      `MERGED`, so use `git -C "<main-checkout>" branch -D "<branch>"` in
      that case.
      On failure, log a warning but continue — cleanup is best-effort.

   f. **Mark `completed`**:
      ```bash
      bash .trc/scripts/bash/chain-run.sh update-ticket \
        --run-id "<run_id>" --ticket "<ticket-id>" \
        --status completed --finished-now
      ```

5. **Go back to the Scheduler Loop** (step 1). The loop fills the free slots
   and releases the dependent tickets. Do not continue in ticket order here.

**Push Approval Invariant**: push approval is asked **once per ticket,
every time**. Prior approvals never carry over. Even if the user approved
5 pushes already in this chain run, the 6th still requires a fresh `yes`.
There is no "approve all" shortcut. The orchestrator never auto-approves.
Parallel workers do not change this rule. Each ticket that ships has its own
fresh approval, also when many tickets commit at approximately the same time.

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

**FR-013 — workers are fire-and-report**: the orchestrator MUST NEVER
attempt to send a follow-up message to a returned worker. Sub-agent
processes stop when they return. Any follow-up is delivered to
a dead inbox and silently ignored. This is mechanically enforced by
`tests/test-chain-run-no-pause-relay.sh`, which fails the build if the
forbidden tool name ever reappears in this file. See
`feedback_trc_chain_no_pause_relay` in user memory for the original
incident that motivated this requirement.

## Shared-Doc Post-Chain Tick (orchestrator-only)

Workers are explicitly forbidden from editing shared planning documents.
This includes `epic-brief.md` and any external plan/status doc. Concurrent
worker edits across parallel PRs drop each other's ticks under a squash
merge. Instead, the orchestrator ticks shared docs **once** after the chain
completes.

The user can supply a shared plan/status document at run start. The user
does this either via the epic-brief path or by pointing you at an external
doc like `docs/<epic>-roadmap.md`. If the user supplied one, do
the following BEFORE the summary step:

1. Read the current state once: `chain-run.sh get --run-id "<run_id>"`.
2. For each ticket with `status == "merged"` or `status == "completed"`,
   find the matching unchecked entry in the shared doc (match by ticket
   id) and tick it. Preserve the doc's existing formatting. Do not
   restructure it.
3. If the doc lives on `main` (or the configured `push.pr_target`),
   commit the ticks directly to that branch in the main checkout. Do NOT
   commit them in any worker's worktree. Push them in a single small commit
   titled `<epic>: tick <count> completed tickets`. Ask the user for approval
   before committing to main.
4. If the user did not supply a shared doc, skip this section entirely.

## Summary

After the loop completes (successfully, partially, or stopped-on-failure):

1. Read the final state:
   ```bash
   bash .trc/scripts/bash/chain-run.sh get --run-id "<run_id>"
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
   bash .trc/scripts/bash/chain-run.sh close \
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
