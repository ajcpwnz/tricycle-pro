---
description: >-
  Orchestrate a large parent Linear issue ("epic") broken down into
  sub-issues: recon the codebase into a roadmap (recon.md), pause for user
  approval, then fan out parallel step-controlled worker agents that run the
  configured trc flow one step at a time. Workers commit locally only; the
  orchestrator merges branches into an integration branch in roadmap order
  and pauses exactly once — at the end — for push approval.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

`/trc.band <PARENT-ISSUE-ID>` tackles one parent Linear issue whose work is
broken down into sub-issues. It is an orchestrator: it fetches the parent
and its sub-issues, performs codebase recon into a roadmap (`recon.md`),
gets the user's approval on that roadmap, then runs sub-issues through the
configured trc flow (`workflow.chain`) using parallel worker agents — one
worker per sub-issue, one trc step at a time, every step reported back to
the orchestrator before the next is issued.

**Core principles**:

- **Fresh context per sub-issue, supervised per step.** Each sub-issue gets
  its own worker with its own context and its own git worktree. Unlike
  `/trc.chain`'s fire-and-report-per-ticket workers, band workers run ONE
  trc step, report, and await the orchestrator's next-step instruction.
- **Autonomous until genuinely ambiguous.** Workers never pause; ambiguity
  comes back as a structured `blocked` report. The orchestrator then pauses
  the whole band and asks the USER. Everything else proceeds without user
  involvement.
- **No remote mutation of any kind before the final gate.** Workers commit
  locally. The orchestrator merges locally. Exactly one user approval — at
  epic end, after full verification — precedes the single push event.
  This is intentionally different from `/trc.chain`'s per-ticket approval:
  band performs exactly one push event per epic, so one fresh confirmation
  per push event still holds (`push.require_approval` is honored by the
  final gate).

## Session Rename (Fallback)

**Primary mechanism**: the `UserPromptSubmit` hook at
`.claude/hooks/rename-on-kickoff.sh` has already renamed the orchestrator
session to `trc-band-<PARENT-ID>` before this prompt is seen. When the hook
fires, this block is a silent no-op.

This block is the fallback for hosts/installs without the hook.

**First thing done — before any Linear fetch or recon:**

1. Compute the label from `$ARGUMENTS`: `trc-band-<PARENT-ID>` (e.g.
   `trc-band-TRI-200`).
2. Read `$CLAUDE_SESSION_TITLE` if available.
3. If the current label differs from the computed target, emit
   `/rename <target>` as the first text in your turn, before any tool call.
   If equal, skip silently.

Keep this label for the entire band run. Workers handle their own
per-sub-issue rename (see Worker Brief HARD CONTRACT rule 0).

## Pre-Flight Validation

Before doing anything ELSE (after the rename above):

1. **Empty input check**. If `$ARGUMENTS` is empty or only whitespace, STOP
   and output:
   ```
   Error: No parent issue provided.
   Usage: /trc.band <PARENT-ISSUE-ID>
   Example: /trc.band TRI-200
   ```

2. **Single-token check**. `$ARGUMENTS` must contain exactly one
   `PREFIX-NUMBER` token. If it looks like a range (`X..Y`) or a comma
   list, STOP and output:
   ```
   Error: /trc.band takes ONE parent issue. For a flat list or range of
   independent tickets, use /trc.chain instead.
   ```

3. **Project init check**. Verify `tricycle.config.yml` and `.trc/` exist.
   If either is missing, STOP and tell the user to run `npx tricycle-pro init`.

4. **Read the run configuration**:
   - `max_parallel` via `parse_band_config` (sourced from
     `.trc/scripts/bash/common.sh`; reads `band.max_parallel`, default 3).
   - The configured trc flow steps via `parse_chain_config` (reads
     `workflow.chain`, default `specify plan tasks implement`). Workers run
     exactly these steps, in this order. Steps like `clarify`/`analyze`, if
     configured, execute with headless overrides (auto-resolve non-critical
     clarifications; report `blocked` for critical ones).

## Resume Detection

Call the helper to find any interrupted runs from a previous session:

```bash
bash core/scripts/bash/band-run.sh list-interrupted
```

Parse the JSON. If `runs` is non-empty, surface each one to the user:

```
Found N interrupted band run(s):
  - <run_id>: parent <parent_id>, <per-issue summary of last completed steps>,
    last updated <updated_at>

Options for each:
  [R]esume — pick up where the run left off
  [D]iscard — close the run (terminal-status aborted)
  [I]gnore — leave it untouched, start new (will re-surface on next resume check)
  [X] Dismiss — hide this run from future resume prompts without closing it
                (useful for runs owned by another shell session on this machine)
```

Wait for the user's choice for each run before proceeding.

- **Resume**: skip recon and init entirely — re-read the run's `state.json`
  via `band-run.sh get --run-id <id>`. **Background workers NEVER survive a
  session restart.** For every issue whose `step_status` is `running`,
  assume the worker is dead: the truth is the last completed step plus what
  is on disk. Cross-check each non-terminal issue before scheduling:

  - **`completed` / `merged` / `failed` / `blocked_by_failure` / `skipped`**
    → no action.
  - **`committed`** → run `git -C <worktree_path> rev-parse HEAD` and
    compare to `commit_sha`. On match → proceed to the Integration Protocol
    for this issue. On mismatch → surface to the user:
    `[R]e-run implement step / [S]kip issue / [A]bort band`.
  - **`in_progress`** → verify the artifacts of every step in
    `steps_completed` exist on disk in the issue's worktree
    (`specs/<branch>/spec.md`, `plan.md`, `tasks.md` as applicable, and
    `git -C <worktree> log` for implement). On match → respawn a FRESH
    worker (the old one is gone) using the Worker Brief with the
    **respawn-resume preamble** (see Worker Brief variants), starting at
    the first uncompleted step. On mismatch (state says a step completed
    but its artifact is missing) → surface to the user:
    `[R]erun step / [S]kip issue / [A]bort band`.
  - **`pending`** → schedule normally via the Scheduler Loop.

  If `paused_for` is set, re-present the blocked issue's `questions[]` to
  the user before resuming the scheduler.
- **Discard**: call `band-run.sh close --run-id <id> --terminal-status
  aborted --reason "user discarded"`, then continue with the new input.
- **Ignore**: leave the interrupted run untouched, continue. It will
  re-appear on the next `/trc.band` invocation.
- **Dismiss**: call `band-run.sh dismiss --run-id <id>` to hide the run
  from future resume prompts without closing it. State is preserved on
  disk at `specs/.band-runs/<run-id>/`.

## Recon Phase

### Fetch the parent and its sub-issues

1. Fetch the parent issue:
   ```
   mcp__linear-server__get_issue({id: "<PARENT-ID>"})
   ```
2. Fetch ALL sub-issues of the parent:
   ```
   mcp__linear-server__list_issues({parentId: "<parent UUID from step 1>"})
   ```
   Follow the pagination cursor (`after`) until exhausted — a partial child
   set is a hard failure, not a working set. If `list_issues` is
   unavailable in this MCP server version, fall back to parsing child
   identifiers from the parent issue's relations/body and `get_issue` each
   one.
3. Optionally fetch the parent project once via
   `mcp__linear-server__get_project` for epic-level goals/non-goals. On
   error here, continue without project context — missing project data is
   not an abort condition.

**Hard-fail policy**:

- If the Linear MCP server is unreachable (connectivity error, MCP tool
  unavailable), abort with `ERR_LINEAR_UNREACHABLE`:
  ```
  Error: Linear MCP unreachable. Restart your MCP server and retry.
  ```
- If the parent is not found, abort with `ERR_TICKETS_NOT_FOUND`.
- If the parent has no sub-issues, abort:
  ```
  Error: <PARENT-ID> has no sub-issues. /trc.band orchestrates a broken-down
  epic. Either break the parent into sub-issues first, or run the single
  issue via /trc.headless.
  ```
- If some sub-issue fetches succeed and some fail, still abort — do NOT
  proceed with a partial set.
- If there are more than 16 sub-issues, abort with `ERR_COUNT_EXCEEDED` and
  suggest splitting the epic.

### Scope echo

Print the fetched issue tree as a one-shot status line, then proceed
immediately to recon. **MUST NOT** emit any confirmation prompt at this
step — no "Proceed?", no "yes / no", no variant. The approval moment comes
later, at the Recon Approval Gate, where the user has an actual roadmap to
approve.

```
Reconning /trc.band for TRI-200 — Payments revamp (6 sub-issues):
  1. TRI-201 — Provider abstraction
  2. TRI-202 — Stripe adapter
  ...
```

### Codebase recon

With every issue body in hand:

1. Read the constitution (`.trc/memory/constitution.md`) for constraints
   relevant to the epic.
2. **Graphify context**: IF `integrations.graphify.enabled: true` in
   `tricycle.config.yml` AND `graphify-out/graph.json` exists, use
   `graphify query|path|explain` to map the areas each sub-issue touches
   before falling back to wide grep/read. When either condition fails,
   skip graphify silently.
3. For each sub-issue, identify the modules/files it will touch, existing
   patterns it must follow, and overlaps with sibling sub-issues.

### Build recon.md

Copy `.trc/templates/recon-template.md` to a temp file via `mktemp` and
fill every mandatory section:

- **Epic Overview**: goal/scope/non-goals from the parent + project.
- **Sub-Issues table**: one row per sub-issue with complexity, model, wave.
- **Codebase Recon**: affected areas, shared-surface matrix, patterns,
  constitution constraints.
- **Dependency Roadmap**:
  - *Dependency Graph*: edges from Linear blocks/blocked-by relations,
    dependencies inferred from issue bodies, and file-overlap analysis.
  - *Waves*: group into waves; two sub-issues touching the same module
    MUST NOT share a wave. A wave starts only after every earlier wave has
    fully drained.
  - *Complexity & Model Assignment*: rate each sub-issue `low`/`medium`/
    `high` by scope of files, novelty, cross-cutting risk, and test
    surface; assign the worker model from the matrix below.
- **Verification Strategy**: per the batching heuristics (see section
  below), name the decision per issue and per wave.
- **Integration Plan**: merge order, expected conflict hotspots, rebase
  policy.
- **Risks & Open Questions**: anything with a `[NEEDS CLARIFICATION: …]`
  marker MUST be raised at the approval gate below.
- **Epic Checklist**: one unchecked item per sub-issue plus wave-verify,
  final-verify, approval, and push items. The checklist is ticked by the
  ORCHESTRATOR ONLY; workers never edit recon.md.

**Worker model matrix.** Determine your own model (the orchestrator's),
then assign worker models:

| Orchestrator model | Default worker | `high`-complexity worker |
|--------------------|----------------|--------------------------|
| fable              | opus           | opus                     |
| opus               | sonnet         | opus                     |
| sonnet / other     | sonnet         | opus                     |

### Recon Approval Gate

**This is a mandatory pause.** Present the recon summary to the user in
plain dialog:

```
Recon complete for TRI-200 — Payments revamp.

Waves:
  Wave 1: TRI-201 (medium → sonnet), TRI-203 (low → sonnet)
  Wave 2: TRI-202 (high → opus), TRI-204 (medium → sonnet)
  Wave 3: TRI-205 (low → sonnet)
Max parallel workers: 3
Integration: merge in roadmap order into band/TRI-200, single PR at the end.
Open questions: <list any [NEEDS CLARIFICATION] markers, or "none">

Approve this roadmap to start the workers? (yes / amend / no)
```

- **On `yes`**: proceed to Run Init. This is the ONLY trigger for spawning
  workers — never fan out before explicit approval.
- **On `amend`** (or any change request): apply the user's amendments to
  recon.md (waves, ordering, complexity, models, scope notes), re-present
  the gate. Repeat until approved or rejected.
- **On `no`**: stop. No run is initialized, nothing is spawned. Output a
  one-line note that the recon file content is available for reference.
- If recon produced any `[NEEDS CLARIFICATION]` markers, ask those
  questions AT this gate and fold the answers into recon.md before
  proceeding.

Push approval is NOT granted here. The recon gate approves fan-out only;
the push gate at the end is separate and always asked fresh.

## Run Init

Only after recon approval:

1. **Provision worktrees serially** — one `git worktree add` at a time
   (concurrent worktree-adds contend on `.git` locks). For each sub-issue,
   in wave order, provision via the existing script so deps install and
   env copying follow the project convention:
   ```bash
   .trc/scripts/bash/create-new-feature.sh --provision-worktree \
     --issue "<sub-issue-id>" --json
   ```
   Capture each `branch` and `worktree_path`.
2. **Create the integration worktree + branch** (this satisfies the
   block-branch-in-main hook, which allows branch creation only via
   `git worktree add`):
   ```bash
   git worktree add -b "band/<PARENT-ID>" ".worktrees/band-<PARENT-ID>" "<push.pr_target>"
   ```
3. **Init the run state**:
   ```bash
   bash core/scripts/bash/band-run.sh init \
     --parent "<PARENT-ID>" \
     --issues '<json array of {id,title,branch,worktree,complexity,model,wave,depends_on}>' \
     --recon "<temp recon path>" \
     --chain '<json array of configured steps>' \
     --max-parallel <N> \
     --integration-worktree ".worktrees/band-<PARENT-ID>" \
     --integration-base "<push.pr_target>"
   ```
   Capture `run_id` and `recon_path` (the recon is copied into the run dir
   at `specs/.band-runs/<run-id>/recon.md`; that copy is the canonical one
   workers read). On any helper error, surface it and abort.
4. Tick `Recon approved by user` in the run-dir recon.md checklist.

## Worker Brief Template (Step-Scoped)

Band workers are step-scoped: each instruction covers EXACTLY ONE trc step.
A worker is spawned once per sub-issue with `run_in_background: true` and a
stable name, then continued step-by-step. Workers never pause and never
wait — finishing the step IS the report.

**Initial spawn brief** (substitute placeholders at spawn time):

```
You are a /trc.band step worker for sub-issue <issue-id>. RUN EXACTLY ONE
STEP, REPORT, THEN STOP. Do not start the next step. Do not wait for
anything — returning your report ends your turn; the orchestrator will
message you again for the next step.

ISSUE: <issue-id> — <title>

BODY:
<issue body from Linear>

EPIC RECON: read specs/.band-runs/<run-id>/recon.md for epic context,
your sub-issue's scope, and cross-issue constraints. Treat it as
READ-ONLY — do not edit it and do not tick its checklist. The
orchestrator owns that file.

PRE-PROVISIONED WORKTREE:
A worktree has been provisioned for you at: <worktree_path>
On a new branch: <branch>

BEFORE running any trc step, you MUST:
  1. cd '<worktree_path>' so that every subsequent command runs inside it.
  2. Export TRC_PREPROVISIONED_WORKTREE='<worktree_path>' so /trc.specify
     picks up the handoff and skips worktree-setup.

DO NOT re-run any worktree-setup block. DO NOT call
`create-new-feature.sh --provision-worktree`. DO NOT rename the branch.
DO NOT change the spec directory name. The spec directory MUST be
exactly `specs/<branch>/` — no suffixes like `-procedures`, `-impl`,
etc. — because the pre-push marker convention binds to
`specs/<branch>/.local-testing-passed`.

RUN DIRECTORY: specs/.band-runs/<run-id>/

GRAPHIFY CONTEXT:
The assembled /trc.* commands each carry a `## Graphify Context` block
with a runtime gate that is active IFF both:
  (1) `integrations.graphify.enabled: true` in tricycle.config.yml, AND
  (2) `graphify-out/graph.json` exists.
When both conditions hold, query graphify before falling back to wide
grep/read. When either condition fails, graphify is skipped silently.

THIS STEP: <step-name>  (step <k> of <chain length>: <chain joined by " → ">)

ORCHESTRATOR NOTES:
<concerns, cross-issue consistency notes, or user answers folded in from
the previous step review — "None" on the first step>

EXECUTE: run /trc.<step-name> for this issue with headless semantics:
auto-resolve non-critical clarifications with reasonable defaults and
document the assumption; only a genuinely blocking ambiguity (no
reasonable default exists; interpretations diverge fundamentally) stops
the step.

HARD CONTRACT:

0. First action: `/rename <branch>`. If the host does not honor /rename
   inside a sub-agent conversation, continue anyway — graceful
   degradation. Do NOT abort on rename failure.

1. ONE STEP ONLY. Run exactly <step-name>. Do not start the next trc
   phase. Do not implement during plan. Do not "get ahead".

2. NEVER PAUSE. Do not ask the user questions. Do not wait for any
   reply. If you hit a genuinely blocking ambiguity, STOP the step and
   return `status: "blocked"` with a `questions` array — that IS your
   report, and the orchestrator will bring you the user's answers in the
   next message. Never hedge a successful report with approval-seeking
   phrases ("should I push", "awaiting approval", "proceed?") — the band
   helper rejects such reports with ERR_COMMITTED_HEDGING. Use
   `concerns` only for forward-looking caveats.

3. NEVER PUSH, NEVER MERGE. You do not run `git push`, `gh pr create`,
   `gh pr merge`, or any remote-mutating command. You do not merge or
   rebase unless the orchestrator's step instruction explicitly says so.
   Local commits only, and only during the implement step:
     git add -A && git commit -m "<issue-id>: <one-line summary>"

4. PROGRESS EVENT at step end — overwrite your progress file:
     printf '{"phase":"<step-name>_complete","completed_at":"%s","issue_id":"<issue-id>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.band-runs/<run-id>/<issue-id>.progress
   After the implement step's commit, write instead:
     printf '{"phase":"committed","completed_at":"%s","issue_id":"<issue-id>","commit_sha":"<sha>"}\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       > specs/.band-runs/<run-id>/<issue-id>.progress

5. QUALITY GATES during the implement step: run the scoped checks named
   in your ORCHESTRATOR NOTES (the orchestrator decides per-issue vs
   batched verification). If a gate you were told to run fails and you
   cannot fix it within the step, return `status: "failed"` with the
   failure output summarized — do NOT commit broken work.

6. FINAL REPORT. Return exactly one structured JSON object as your final
   message, wrapped in ```json ... ``` fences:
     {
       "issue_id":    "<issue-id>",
       "step":        "<step-name>",
       "status":      "step_complete" | "blocked" | "failed",
       "artifacts":   ["specs/<branch>/spec.md", ...],
       "branch":      "<branch>",
       "commit_sha":  null | "<sha — non-null only after implement>",
       "lint_status": "pass" | "fail" | "skipped",
       "test_status": "pass" | "fail" | "skipped",
       "questions":   [ {"q": "<question>", "options": ["A", "B"], "context": "<why>"} ],
       "concerns":    ["<forward-looking caveat>", ...],
       "summary":     "<one paragraph: what this step produced>"
     }
   `questions` is non-empty ONLY with status "blocked". After this JSON
   block, write nothing else, then stop.
```

**Continuation message** (sent to the SAME worker via `SendMessage`, using
its name `band-worker-<issue-id>`):

```
NEXT STEP: <step-name> (step <k> of <chain length>).

ORCHESTRATOR REVIEW of your last step:
<notes: concerns to address, cross-issue consistency requirements from
recon.md, user answers to your questions if you were blocked, scoped
verification commands to run if this is the implement step>

The same HARD CONTRACT applies: one step only, never pause, never push,
progress event at step end, fenced JSON report, stop.
```

**Rebase brief** (continuation variant, sent only during the Integration
Protocol):

```
REBASE TASK (not a trc step): your branch <branch> conflicts with the
integration branch band/<PARENT-ID>. In your worktree:
  1. git fetch is NOT needed (local refs); run:
     git rebase band/<PARENT-ID>
  2. Resolve conflicts preserving BOTH your sub-issue's behavior and the
     already-merged sub-issues' behavior (see ORCHESTRATOR NOTES for what
     landed).
  3. Re-run the scoped verification commands listed below.
  4. Commit the resolution, capture the new HEAD sha.
Report with the same fenced JSON schema: status "step_complete" with the
new commit_sha, or "failed" with the conflict summarized. Never push.
```

**Respawn-resume preamble** (prepended to the initial spawn brief when a
fresh worker replaces a dead one):

```
RESUME CONTEXT: a previous worker already completed steps <list> for this
sub-issue. Their artifacts exist in your worktree (specs/<branch>/...).
VERIFY they exist, read them for context, do NOT regenerate them. Your
work starts at step <k>: <step-name>.
```

## Scheduler Loop

The orchestrator's core loop. All git operations (worktree add/remove,
merges, branch deletes) are executed by the orchestrator, serially —
workers only ever touch their own worktree.

Repeat until every issue is terminal (`merged`/`completed`/`failed`/
`blocked_by_failure`/`skipped`):

1. **Query the scheduler primitive**:
   ```bash
   bash core/scripts/bash/band-run.sh next-ready --run-id "<run_id>"
   ```
   It returns `{"spawn": [...], "continue": [...], "running": [...],
   "blocked": [...], "dep_failed": [...], "slots": N, "paused": bool}`.
   Trust it: wave gating, dependency gating, slot arithmetic, and pause
   masking are all computed there.

2. **Handle `dep_failed`**: for each listed issue, mark it
   `blocked_by_failure` via `update-issue` and note it for the summary.

3. **Spawn** each issue in `spawn`: mark the first step running —
   ```bash
   bash core/scripts/bash/band-run.sh update-step \
     --run-id "<run_id>" --issue "<issue-id>" \
     --step "<first step>" --step-status running
   ```
   — then call `Agent` with `name: "band-worker-<issue-id>"`,
   `subagent_type: "general-purpose"`, `model: "<model from recon
   roadmap>"`, `run_in_background: true`, and the initial Worker Brief as
   the prompt.

4. **Continue** each issue in `continue`: compose the next-step prompt
   (see Step Review Protocol), mark the step running via `update-step`,
   then `SendMessage` to `band-worker-<issue-id>` with the continuation
   message. **Never SendMessage the same worker twice without an
   intervening report.**

5. **Wait for any background worker completion notification.** Do not
   poll with sleeps; the harness notifies you when a background agent
   finishes its turn. While waiting, you may surface per-issue progress
   on demand:
   ```bash
   bash core/scripts/bash/band-run.sh progress --run-id "<run_id>" --issue "<issue-id>"
   ```
   Displayed as `[<issue-id>] last completed: <phase>`. Do NOT stream
   worker transcripts.

6. **On each worker report**, validate and record it (Step Review
   Protocol), then loop back to step 1.

**Dead-worker rule**: if a spawned/continued worker errors out, or a
completion never arrives while its progress file shows no change, treat
the worker as dead. Re-issue `update-step --step-status running` for the
same step (running → running on the same step is a legal respawn
transition) and spawn a FRESH `Agent` with the respawn-resume preamble.
A `SendMessage` that is never answered means the worker is gone — respawn;
do not retry the message blind.

**Failure rule**: a `failed` step report gets ONE retry — re-run the same
step with the failure diagnostics folded into the next-step prompt. A
second failure marks the issue `failed` (via `update-issue`), which
cascades `blocked_by_failure` to its dependents through `next-ready`'s
`dep_failed` list. Other lanes keep going — the band does NOT stop on a
single issue's failure unless every remaining issue is downstream of it.

## Step Review Protocol

On every worker report:

1. **Validate** the fenced ```json``` block strictly: it must parse, and
   must contain `issue_id`, `step`, `status`, `branch`, `summary`, with
   `status` ∈ `step_complete | blocked | failed`. A malformed report is
   treated as `failed` for the failure rule above.
2. **Record** via `band-run.sh update-step` (and, after a final implement
   step with a commit, `update-issue --status committed --commit-sha <sha>
   --lint <s> --test <s>`).
3. **Review the content**: check the summary and artifacts against
   recon.md's scope for that sub-issue and against sibling issues'
   reported decisions (e.g. shared naming, shared schema choices). Fold
   any concern into the NEXT step's ORCHESTRATOR NOTES — that is how the
   parent raises concerns without ever pausing a worker.
4. **Branch on status**:
   - `step_complete` with steps remaining → the issue shows up in
     `continue` on the next scheduler pass.
   - `step_complete` on the final step → expect `commit_sha`; record
     `committed` and enter the Integration Protocol for this issue.
   - `blocked` → Pause Protocol below.
   - `failed` → failure rule above.

**Context hygiene**: retain only the destructured report fields. Keep at
most the LATEST report per issue plus a one-line ledger of its prior
steps ("TRI-201: specify ✓ plan ✓ — implementing"). recon.md and
state.json are the durable memory — re-read them via `band-run.sh get`
instead of keeping history in context. Never re-read worker transcripts.

## Pause / Ambiguity Protocol

When any worker reports `status: "blocked"`:

1. Record the questions (`update-step --step-status blocked --question
   "<q>"` per question) and pause the run:
   ```bash
   bash core/scripts/bash/band-run.sh pause --run-id "<run_id>" \
     --issue "<issue-id>" --reason "<one-line>"
   ```
   While paused, `next-ready` returns empty `spawn`/`continue` — no new
   steps are issued band-wide. In-flight steps on other workers run to
   completion and their reports are recorded normally.
2. **Ask the USER** the worker's questions verbatim (with the worker's
   `options` and `context`), in plain dialog. Work stops until the user
   answers — this is the designed behavior, not a failure.
3. On answers: `band-run.sh resume --run-id "<run_id>"`, mark the blocked
   step running again (`update-step --step-status running` — blocked →
   running is the legal resume transition), and `SendMessage` the blocked
   worker a continuation message carrying the answers. If that worker has
   meanwhile died (no response), respawn fresh with the answers folded
   into the respawn brief.
4. Resume the Scheduler Loop.

The orchestrator itself can also trigger this protocol: if recon-level
assumptions collapse mid-run (e.g. two sub-issues turn out to be
fundamentally incompatible), pause and ask rather than guessing.

## Verification Batching Heuristics

The orchestrator decides where the full lint+test suite runs. Encode the
decision in each implement step's ORCHESTRATOR NOTES:

- **Full suite per sub-issue** when ANY of:
  - the sub-issue is rated `high` complexity in recon.md;
  - it is the sole member of its wave;
  - it touches shared infrastructure named in recon.md's shared-surface
    matrix.
- **Otherwise**: the worker runs only scoped/fast checks during implement
  (e.g. the affected package's test-blocks), and the orchestrator runs the
  FULL suite once per wave, in the integration worktree, after the wave's
  branches are merged. A wave-batch failure is bisected by re-running the
  suite after unwinding the most recent merge first.
- **Always**: one final full-suite run in the integration worktree at epic
  end, before the approval gate. No exceptions.

Record outcomes per issue via `update-issue --lint <s> --test <s>` and tick
the wave-verification items in recon.md's checklist.

## Integration Protocol

When a sub-issue reaches `committed`:

1. **Merge in roadmap order**: a branch merges only after ALL its
   dependency-graph predecessors are merged. If predecessors are still in
   flight, leave the issue `committed` and continue the scheduler; merge
   it when its turn comes.
2. **Merge** (orchestrator, in the integration worktree, serially):
   ```bash
   git -C ".worktrees/band-<PARENT-ID>" merge --no-ff "<branch>" \
     -m "band(<PARENT-ID>): merge <issue-id>"
   ```
   On success:
   ```bash
   bash core/scripts/bash/band-run.sh update-issue \
     --run-id "<run_id>" --issue "<issue-id>" --status merged \
     --merged-sha "$(git -C .worktrees/band-<PARENT-ID> rev-parse HEAD)"
   ```
   Tick the issue's checklist item in recon.md.
3. **On conflict**: abort the merge (`git merge --abort`), then send the
   Rebase brief to the issue's worker via `SendMessage` (or spawn a fresh
   agent in that worktree with the rebase brief if the worker is dead).
   When the rebase report arrives with the new sha, record it:
   ```bash
   bash core/scripts/bash/band-run.sh update-issue \
     --run-id "<run_id>" --issue "<issue-id>" --status merged \
     --commit-sha "<new sha>" --increment-rebase --merged-sha "<...>"
   ```
   then retry the merge. **Rebase cap**: the helper enforces at most 2
   rebase rounds per sub-issue (`ERR_REBASE_CAP`); on the cap, run the
   Pause Protocol — present the conflict to the user instead of looping.
4. **After each wave fully merges**, run the wave-batch verification per
   the heuristics above.

## Final Verification + Approval Gate + Push

When every issue is terminal and all merges are done:

1. **Final full-suite verification** in the integration worktree (lint +
   test, per CLAUDE.md's mandatory commands). On failure: fix forward via
   a worker in the integration worktree, or pause and ask the user if the
   failure implicates a design decision. Do NOT proceed to the gate with a
   red suite.
2. Tick `Final full-suite verification passed` in recon.md; copy the
   ticked recon.md state; render the Summary table (below) for the user.
3. **THE approval gate** — exactly one, always asked fresh, in plain
   dialog:
   ```
   Epic TRI-200 is done and verified.
     Will push:  band/TRI-200 (contains N merged sub-issue branches)
     PR:         band/TRI-200 → <push.pr_target>, one epic PR
     Sub-issues: <list with commit shas>

   Push the epic? (yes / no)
   ```
   **No remote mutation of any kind happens before this gate** — no
   pushes, no PRs, no Linear status changes that imply shipped. If the
   user wants per-sub-issue PRs instead of the single epic PR, they can
   say so here; honor it (push each sub-issue branch, open stacked PRs in
   roadmap order) — but the default and recommendation is ONE epic PR
   from the integration branch, with recon.md's overview as the PR body.
4. **On `no`**: stop. Leave all branches, worktrees, and the integration
   branch intact for manual handling. Close the run:
   `band-run.sh close --terminal-status aborted --reason "user declined
   epic push"`. Jump to Summary.
5. **On `yes`** — each of the following is its OWN Bash call (never chain
   marker + push + pr in one call; pre-push guards scan full command
   strings):
   a. **Pre-push marker**:
      ```bash
      touch ".worktrees/band-<PARENT-ID>/specs/band-<PARENT-ID>/.local-testing-passed"
      ```
      (Create the spec dir first if the project's marker convention
      requires it; the path binds to the integration branch's spec dir,
      no suffixes.)
   b. **Push**:
      ```bash
      git -C ".worktrees/band-<PARENT-ID>" push -u origin "band/<PARENT-ID>"
      ```
   c. **PR**:
      ```bash
      gh pr create --base "<push.pr_target>" --head "band/<PARENT-ID>" \
        --title "<PARENT-ID>: <epic title>" \
        --body "<epic overview from recon.md + sub-issue table>"
      ```
      Record: `band-run.sh update-integration --run-id "<run_id>"
      --pr-url "<url>" --pushed-now`.
   d. **Merge** if `push.auto_merge` is true, using `push.merge_strategy`.
      If `gh pr merge` exits non-zero, check before failing:
      ```bash
      gh pr view "<pr_url>" --json state,mergedAt
      ```
      If `state` is `MERGED`, treat the merge as successful (server-side
      merged, local sync failed — common when the base branch is checked
      out in another worktree), log a one-line warning, continue. Only a
      genuinely un-merged PR is a failure.
   e. Mark all merged issues `completed` (`update-issue --status completed
      --finished-now`), tick the push items in recon.md.

## Worktree Cleanup

After the epic PR is merged (or immediately after per-issue merges into
the integration branch, for sub-issue worktrees):

```bash
git -C "<main-checkout>" worktree remove "<worktree_path>"
git -C "<main-checkout>" worktree prune
git -C "<main-checkout>" branch -d "<branch>"
```

Sub-issue worktrees+branches are removed once their content is merged into
the integration branch and the wave verification has passed. The
integration worktree is kept until the epic PR is merged. On any cleanup
failure, log a warning and continue — cleanup is best-effort.

## Summary

After the run reaches a terminal condition (shipped, aborted, or failed):

1. Read the final state:
   ```bash
   bash core/scripts/bash/band-run.sh get --run-id "<run_id>"
   ```
2. Render a markdown summary table:
   `| Sub-issue | Branch | Steps | Complexity | Model | Lint | Test | Status |`
   with distinct status markers: `completed` → ✓, `failed` → ✗,
   `blocked_by_failure` → "blocked by <dep>", `skipped` → "skipped",
   `pending` → "—".
3. If the run is not already terminally closed, call:
   ```bash
   bash core/scripts/bash/band-run.sh close \
     --run-id "<run_id>" --terminal-status completed
   ```
4. Print the table, the epic PR URL (if any), and a one-line footer with
   the run-id.

## Done

Output:
```
/trc.band complete. Run id: <run_id>
```

That's the end of the command. Do not spawn additional agents, do not
re-open the band, do not attempt automatic retries. The user drives the
next move.
