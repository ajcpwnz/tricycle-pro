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
  - **`merged`** → assume already shipped; no action.
  - **`pushed`** → run `gh pr view <pr_url> --json state` and confirm the PR
    state. If `MERGED`, mark `merged` then `completed` and continue. If still
    `OPEN`, jump straight to the merge step of `## Orchestrator Push Step`
    (skip the worker spawn AND the `git push`).
  - **`committed`** → run `git -C <worktree_path> rev-parse HEAD` and compare
    to `state.json`'s `commit_sha`. On match → jump straight to the Push
    Approval step of `## Orchestrator Push Step` (skip the worker spawn).
    On mismatch → surface the inconsistency to the user with three options:
    `[R]e-spawn worker`, `[S]kip ticket`, `[A]bort chain`.
  - **`in_progress`** → the worker died mid-run. Treat as `not_started` for
    resume purposes (re-spawn a fresh worker for this ticket).
  - **`not_started`** → spawn a fresh worker via the per-ticket loop.

  Then re-fetch Linear bodies for the tickets that still need workers.
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
bash core/scripts/bash/chain-run.sh parse-range "$ARGUMENTS"
```

On non-zero exit, the stderr JSON contains the error code and message —
surface it directly to the user and abort. Error codes map to user-facing
messages documented in
`specs/TRI-27-trc-chain-orchestrator/contracts/chain-run-helper.md`.

On success the stdout JSON has `{"ids": [...], "count": N}`. Capture the
`ids` array.

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

## Scope Echo

Print the fetched ticket list as a one-shot status line, then proceed
immediately to the next step. Do NOT prompt for confirmation — the user
supplied the ticket IDs when invoking `/trc.chain`, so launching the
command IS the confirmation.

```
Running /trc.chain on:
  1. TRI-100 — Add user authentication
  2. TRI-101 — Profile page
  3. TRI-102 — Password reset flow
```

Only interrupt with a question here if something is genuinely
ambiguous that the user could not have known about at invocation time
(e.g., the fetched tickets span more than two unrelated parent
projects, suggesting a likely typo). In that case, surface the specific
concern — do not fall back to a generic "Proceed? (yes / no)" gate.

## Epic Brief Generation

After the scope echo, **synthesize** the shared `epic-brief.md`
from the ticket context you already have in hand. Do NOT ask the user
whether to create one — the tickets themselves are the source of truth,
and the brief is regenerated every run. The user is only prompted as a
fallback when there is genuinely nothing to synthesize from.

1. **Collect parent projects.** For each fetched ticket, inspect its
   `project` field (returned by `mcp__linear-server__get_issue`).
   Collect the unique set of parent project ids/names across the
   chain (usually 0, 1, or 2 for a coherent run).

2. **Fetch each unique parent project once** via:
   ```
   mcp__linear-server__get_project({query: "<project-id-or-name>"})
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
   not a spec. Write it to a temp file via `mktemp`, and remember
   that path for `init`. Print a two-line confirmation to the user
   (title + line count + "auto-generated from <N> tickets, <M>
   parent projects"); do NOT prompt for approval — workers treat
   the brief as read-only and it is regenerated each run.

4. **Fallback prompt — only when ticket context is genuinely thin.**
   If after step 2 the total available context is empty or
   near-empty (all ticket bodies under ~50 characters AND no parent
   project attached to any ticket), fall back to asking the user:
   ```
   Ticket bodies are too thin to auto-generate an epic brief, and
   no parent Linear project is attached. Choose a fallback:

     [P]ath — provide a path to an existing brief
     [C]reate — draft one inline
     [S]kip — no shared brief
   ```
   - **Path**: ask for the path, verify it exists, remember it for `init`.
   - **Create**: prompt the user for the content (multiline input),
     write it to a temp file with `mktemp`, remember that path for
     `init`.
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

## Graphify MCP Registration (optional)

If the project has opted in to the graphify integration
(`integrations.graphify.enabled: true` AND `integrations.graphify.mcp_per_chain:
true` in `tricycle.config.yml`) AND a graph exists at
`graphify-out/graph.json`, register a `graphify` entry in `.mcp.json` so
worker sub-agents' Claude Code hosts can spawn and manage the MCP stdio
server on demand:

```bash
./bin/tricycle graphify mcp-start --run-id <run_id>
```

- MCP stdio servers are launched by the client (Claude Code), not as a
  background daemon — spawning one manually and disowning it produces a
  dead process as soon as stdin disconnects. The wrapper updates
  `.mcp.json`; the worker's host takes care of the actual spawn.
- On any non-zero exit (graphify not installed, graph missing), log a
  one-line warning and continue — **this is never a chain abort
  condition.** Workers fall back to reading `graphify-out/*` directly if
  the MCP isn't registered.
- At chain close (every path through `## Summary`), tear down with:
  ```bash
  ./bin/tricycle graphify mcp-stop --run-id <run_id>
  ```
  Best-effort — log warnings, never fail the chain on teardown errors.

Skip this step entirely (no warning) when the feature flag is off.

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
<if worktree_path is null: "No worktree pre-provisioned; /trc.specify will provision one for you in the normal flow.">
<if worktree_path is non-null:
"A worktree has been provisioned for you at: <worktree_path>
 On a new branch: <branch>

 BEFORE running /trc.headless, you MUST:
   1. cd '<worktree_path>' so that every subsequent command runs inside it.
   2. Export TRC_PREPROVISIONED_WORKTREE='<worktree_path>' so /trc.specify
      picks up the handoff and skips worktree-setup.

 DO NOT re-run any worktree-setup block. DO NOT call
 `create-new-feature.sh --provision-worktree`. DO NOT rename the branch.
 DO NOT change the spec directory name. The spec directory MUST be
 exactly `specs/<branch>/` — no suffixes like `-procedures`, `-impl`,
 etc. — because the pre-push marker hook looks for
 `specs/<branch>/.local-testing-passed` (see rule 5 below).
">

RUN DIRECTORY: specs/.chain-runs/<run-id>/

GRAPHIFY CONTEXT:
<if graphify not enabled or graph missing: "No knowledge graph for this repo. Read the files directly as usual.">
<if graphify enabled AND graph exists:
"A knowledge graph of this repo is available to short-circuit the usual
 'open files to find things' loop. Prefer querying it BEFORE wide file reads:

   - GRAPH REPORT (read once for orientation): graphify-out/GRAPH_REPORT.md
     — lists god nodes, surprising connections, and suggested questions.
   - LOCAL QUERY (cheap): `graphify query \"<your question>\"` or
     `graphify explain \"<symbol-or-concept>\"` or
     `graphify path \"<A>\" \"<B>\"` for shortest path between two concepts.
   - RAW JSON: graphify-out/graph.json (when you need every edge).
   - MCP (if .mcp.json has a `graphify` entry): tools {query_graph,
     get_node, get_neighbors, get_community, god_nodes, graph_stats,
     shortest_path}. Your Claude Code host spawns and manages the stdio
     server automatically — just call the tools by name.

 WHEN to query: architectural questions (where is X defined, who calls Y,
 what depends on Z), code-location lookups before grepping, 'is there
 already a util for this?'. Every edge carries a provenance tag —
 EXTRACTED (found directly), INFERRED (reasonable guess with confidence),
 AMBIGUOUS (flagged). Treat INFERRED as a hint, not truth.

 WHEN NOT to query: trivial one-file edits, cosmetic fixes, anything where
 you already know the exact file path. The graph is a shortcut, not a
 mandatory gate.

 STALENESS: the graph is refreshed automatically by the kickoff hook
 before you started. If you touch code and then need to re-query the
 updated state, run `graphify . --update` yourself — do NOT trust stale
 nodes after you've mutated the tree.">

TASK: Run /trc.headless end-to-end for this ticket. After /trc.headless
finishes (lint + test green, version bumped), explicitly create a local
git commit with `git add -A && git commit -m "<ticket-id>: <one-line>"`,
capture the commit SHA, emit a final progress event, return a structured
JSON report as your final message, and EXIT. You will not be resumed.

HARD CONTRACT:

0. First action: `/rename <ticket-id-branch-name>`. The very first text you
   emit in this worker conversation MUST be `/rename <branch-name>` (where
   `<branch-name>` is the branch the orchestrator pre-provisioned or the
   one `create-new-feature.sh` will produce). This matches the session
   label convention established for solo `/trc.specify` runs and makes the
   worker identifiable in the Claude Code session list while it's
   in-flight. If the host does not honor `/rename` inside a sub-agent
   conversation, continue anyway — this is an explicit graceful
   degradation per TRI-31 SC-005. Do NOT abort on rename failure.

1. NEVER PAUSE. Do not ask the user questions. Do not request push
   approval. Do not wait for any reply. Sub-agent processes are
   terminated when they return — any pause is a permanent hang. If
   /trc.headless wants to clarify, auto-resolve with reasonable defaults
   per its headless semantics; if you genuinely cannot proceed, return a
   `status: "failed"` report and exit.

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
   (specify, clarify, plan, tasks, analyze, implement), overwrite the
   progress file with the *_complete suffix:
     printf '{"phase":"<phase>_complete","completed_at":"%s","ticket_id":"<ticket-id>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.chain-runs/<run-id>/<ticket-id>.progress
   Use exactly: specify_complete, clarify_complete, plan_complete,
   tasks_complete, analyze_complete, implement_complete. After your
   explicit `git commit`, write a final event with
   `phase: "committed"` and include the commit_sha:
     printf '{"phase":"committed","completed_at":"%s","ticket_id":"<ticket-id>","commit_sha":"<sha>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.chain-runs/<run-id>/<ticket-id>.progress

4. QUALITY GATES inside /trc.headless: lint green, tests green, local
   stack test for user-facing changes, QA cases added for user-facing
   features. If any gate fails, do NOT commit; return `status: "failed"`.

5. LOCAL-TESTING MARKER (project-local pre-push gate). If this project
   has a pre-push marker convention, the marker path is bound to the
   canonical spec directory:
     specs/<branch>/.local-testing-passed
   where `<branch>` is the branch name exactly as produced by
   `create-new-feature.sh` (or as inherited from the pre-provisioned
   worktree — see the block above). Do NOT put the marker at the
   worktree root, under `apps/*/`, or under any renamed spec dir. If
   the marker is required, create it in the correct location before
   the orchestrator runs `git push`.

6. EXPLICIT COMMIT. After the gates pass and the version is bumped, run:
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
       "spec_dir":    "specs/<branch>",
       "files_changed": ["path/a", "path/b", ...],
       "lint_status": "pass" | "fail" | "skipped",
       "test_status": "pass" | "fail" | "skipped",
       "worker_error": null | "<short error>",
       "open_questions": ["<forward-looking caveat>", ...],
       "summary":     "<one-paragraph human summary>"
     }
   After this JSON block, write nothing else. Then exit.
```

## Per-Ticket Loop

For each ticket ID in order:

1. **Mark in_progress**:
   ```bash
   bash core/scripts/bash/chain-run.sh update-ticket \
     --run-id "<run_id>" --ticket "<ticket-id>" \
     --status in_progress --started-now
   ```

2. **Spawn the worker** using `Agent` with
   `name: "chain-worker-<ticket-id>"`, `subagent_type: "general-purpose"`,
   in the foreground (NOT `run_in_background: true`), passing the Worker
   Brief Template content as the `prompt`. This call **blocks** until the
   worker returns. The worker is dead the moment it returns; you cannot
   send it more messages.

3. **Block on worker return.** When `Agent()` returns, parse the worker's
   final message as a fenced ```json ... ``` block matching the Worker
   Brief Template's report schema. Validate strictly:

   - The block must exist.
   - It must parse as JSON.
   - It must contain at minimum: `ticket_id`, `status`, `branch`,
     `commit_sha`, `lint_status`, `test_status`, `summary`.
   - `status` must be exactly `"committed"` or `"failed"`.

   On any validation failure, treat the worker as failed with
   `worker_error: "malformed report"` and proceed to step 5b.

4. **Progress display** (FR-022). After spawning the worker but before
   reading its return — and on every loop iteration if you're polling
   between phases — read the progress file with:
   ```bash
   bash core/scripts/bash/chain-run.sh progress \
     --run-id "<run_id>" --ticket "<ticket-id>"
   ```
   The phase value uses the `_complete` suffix (or `committed` for the
   terminal event). Display as:
   ```
   [<ticket-id>] last completed: <phase>
   ```
   Do NOT stream the worker's transcript. Do NOT retain anything beyond
   the destructured report fields (FR-014).

5. **Branch on report status**:

   - **5a. status == "committed"**: the worker has made a local commit on
     its feature branch and exited cleanly. Record the commit:
     ```bash
     bash core/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status committed --commit-sha "<commit_sha>" \
       --branch "<branch>" \
       --lint "<lint_status>" --test "<test_status>"
     ```
     Then proceed to **`## Orchestrator Push Step`** below for this
     ticket.

   - **5b. status == "failed"** (OR malformed report, OR `worker_error`
     non-null, OR `lint_status == "fail"`, OR `test_status == "fail"`):
     mark the ticket failed, close the run, stop the chain.
     ```bash
     bash core/scripts/bash/chain-run.sh update-ticket \
       --run-id "<run_id>" --ticket "<ticket-id>" \
       --status failed --finished-now \
       --branch "<branch or omit>" \
       --lint "<lint_status>" --test "<test_status>"
     bash core/scripts/bash/chain-run.sh close \
       --run-id "<run_id>" --terminal-status failed \
       --reason "<short reason>"
     ```
     Do NOT spawn a worker for any remaining ticket. Jump to
     `## Summary`. Per FR-012: stop-on-failure means **stop**.

## Orchestrator Push Step

This step runs **only** when a worker reports `status: "committed"`. The
orchestrator (you, in the parent conversation, with full tool access)
handles the entire push/PR/merge cycle in plain dialog with the user.
No sub-agent message-forwarding is involved. The worker is already dead.

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
      pre-push marker convention (e.g. `specs/<branch>/.local-testing-passed`
      in some consumer repos), ensure the marker file exists at the
      canonical path before invoking `git push` or `gh pr *`. Create it
      in a **separate** Bash tool call:
      ```bash
      touch "<worktree_path>/specs/<branch>/.local-testing-passed"
      ```
      DO NOT chain `touch … && gh pr create …` in a single Bash call.
      Project-local pre-push guards that scan the full command string can
      see the `gh pr create` substring and block before the marker is
      written, so each step must be its own tool call.

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
      bash core/scripts/bash/chain-run.sh update-ticket \
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

      **Server-side merge succeeded, local sync failed** is a common case
      — e.g. `gh pr merge` fails locally with `fatal: '<base>' is already
      used by worktree at '…'` because the base branch is checked out in
      another worktree on this machine. In that case the PR is already
      merged on GitHub; the only thing that failed was `gh`'s local ref
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
      bash core/scripts/bash/chain-run.sh update-ticket \
        --run-id "<run_id>" --ticket "<ticket-id>" --status merged
      ```

      If `push.auto_merge` is false, **stop here** with the PR URL and
      instructions for the user; the ticket stays `pushed`. The chain
      continues to the next ticket only if the user confirms.

   e. **Worktree cleanup** after merge:
      ```bash
      git -C "<main-checkout>" worktree remove "<worktree_path>"
      git -C "<main-checkout>" worktree prune
      git -C "<main-checkout>" branch -d "<branch>"
      ```
      On failure, log a warning but continue — cleanup is best-effort.

   f. **Mark `completed`**:
      ```bash
      bash core/scripts/bash/chain-run.sh update-ticket \
        --run-id "<run_id>" --ticket "<ticket-id>" \
        --status completed --finished-now
      ```

5. **Continue** the per-ticket loop with the next ticket.

**Push Approval Invariant**: push approval is asked **once per ticket,
every time**. Prior approvals never carry over. Even if the user approved
5 pushes already in this chain run, the 6th still requires a fresh `yes`.
There is no "approve all" shortcut. The orchestrator never auto-approves.

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
processes are terminated when they return; any follow-up is delivered to
a dead inbox and silently ignored. This is mechanically enforced by
`tests/test-chain-run-no-pause-relay.sh`, which fails the build if the
forbidden tool name ever reappears in this file. See
`feedback_trc_chain_no_pause_relay` in user memory for the original
incident that motivated this requirement.

## Shared-Doc Post-Chain Tick (orchestrator-only)

Workers are explicitly forbidden from editing shared planning documents
(including `epic-brief.md` and any external plan/status doc) — concurrent
worker edits across parallel PRs drop each other's ticks under a squash
merge. Instead, the orchestrator ticks shared docs **once** after the chain
completes.

If the user supplied a shared plan/status document at run start (either via
the epic-brief path or by pointing you at an external doc like
`docs/<epic>-implementation-plan.md`), do the following BEFORE the
summary step:

1. Read the current state once: `chain-run.sh get --run-id "<run_id>"`.
2. For each ticket with `status == "merged"` or `status == "completed"`,
   find the matching unchecked entry in the shared doc (match by ticket
   id) and tick it. Preserve the doc's existing formatting; do not
   restructure it.
3. If the doc lives on `main` (or the configured `push.pr_target`),
   commit the ticks directly to that branch in the main checkout — NOT
   in any worker's worktree — and push in a single small commit titled
   `<epic>: tick <count> completed tickets`. Ask the user for approval
   before committing to main.
4. If the user did not supply a shared doc, skip this section entirely.

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

4. **Graphify MCP teardown.** If `## Graphify MCP Spawn` was performed at
   chain init, tear down the MCP server as a best-effort step — the chain
   is done with it:
   ```bash
   ./bin/tricycle graphify mcp-stop --run-id "<run_id>"
   ```
   Log any warning but never treat teardown failure as a chain failure.

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
