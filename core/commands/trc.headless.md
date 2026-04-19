---
description: >-
  Run the full workflow chain automatically from a single prompt.
  Pauses only for critical clarifications, destructive actions, or push approval.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Session Rename (Fallback)

**Primary mechanism**: the `UserPromptSubmit` hook at
`.claude/hooks/rename-on-kickoff.sh` has already renamed the session by the
time you see this prompt. When the hook fires, this block is a silent
no-op.

This block is the fallback for hosts/installs without the hook.

**First thing done — before any file, git, or Linear side effect:**

1. Derive the target session label:
   ```bash
   .trc/scripts/bash/derive-branch-name.sh \
     --style "<configured-style>" \
     [--prefix "<configured-prefix>"] [--issue "<ticket-id-if-known>"] \
     "$ARGUMENTS"
   ```
   (Do NOT pass `--short-name` — match the hook's auto-derived slug for
   idempotency.)
2. If `$CLAUDE_SESSION_TITLE` differs from the target, emit
   `/rename <target>` as your first output before any tool call. If
   already equal, skip silently.
3. When this command internally triggers `/trc.specify`'s Step 0.5 later
   in the flow, that step MUST detect the label already matches and be a
   no-op — the rename is performed **once**, at the outermost invocation.

## Pre-Flight Validation

Before executing the chain, validate all prerequisites:

1. **Empty prompt check**: If the user input above is empty or only
   whitespace, STOP immediately and output:
   ```
   Error: No feature description provided.
   Usage: /trc.headless <feature description>
   ```
   Do NOT proceed with any phase.

2. **Project initialization check**: Verify that `tricycle.config.yml`
   exists in the project root AND that the `.trc/` directory exists.
   If either is missing, STOP immediately and output:
   ```
   Error: Tricycle Pro not initialized.
   Run `npx tricycle-pro init` to set up the project.
   ```

3. **Partial artifact check**: Check if a spec directory already exists
   for a feature matching the user's description. If found, warn the
   user and ask whether to resume from the last completed phase or
   start fresh. Wait for their response before proceeding.

## Graphify Context

**Runtime gate — evaluate before acting on this block.** This block is
active for this run if AND ONLY IF both conditions hold:

1. `tricycle.config.yml` has `integrations.graphify.enabled: true`.
2. `graphify-out/graph.json` exists at the repo root.

If either check fails, skip this entire section — it does not apply and
you MUST NOT attempt any graphify call. Continue with normal
grep/read/file-based exploration through every phase.

If both checks pass, keep the graph open as a lookup channel through
every phase — do not re-walk the repo with grep when the graph can
answer in one call:

- **GRAPH REPORT** (read once for orientation):
  `graphify-out/GRAPH_REPORT.md` — god nodes, surprising connections.
- **LOCAL QUERY** (cheap, no MCP needed):
  - `graphify query "<question>"` — BFS traversal.
  - `graphify explain "<symbol>"` — plain-language node summary.
  - `graphify path "A" "B"` — shortest path between two concepts.
- **RAW JSON**: `graphify-out/graph.json` when you need every edge.
- **MCP** (only if `.mcp.json` has a `graphify` entry AND it was
  registered before this `claude` session started): tools
  `{query_graph, get_node, get_neighbors, get_community, god_nodes,
  graph_stats, shortest_path}`. Mid-session `.mcp.json` edits do NOT
  hot-load, so do not assume these tools exist — probe by calling one
  and fall back to the shell CLI above on failure.

Edge provenance tags: `EXTRACTED` (found in source), `INFERRED`
(reasonable guess with confidence), `AMBIGUOUS`. Treat INFERRED as a
hint, not truth.

Do NOT bootstrap mid-workflow; that's the job of `tricycle graphify
bootstrap` or the kickoff hook.

## Headless Execution Mode

This command runs the **complete** workflow chain in a single invocation.
The key behavioral differences from running each command manually:

- **Auto-continue**: Phase transitions happen automatically. Do NOT
  wait for user input between phases.
- **Auto-resolve**: Non-critical clarifications during the specify
  phase MUST be resolved with informed guesses and reasonable
  defaults. Only pause for critical ambiguities (see Pause Rules).
- **Auto-proceed checklists**: If all checklist items pass, proceed
  without asking. Only pause if checklist items fail.
- **Constitution enforcement**: All constitution principles remain
  active. Lint/test gates (Principle II) and push approval
  (Principle III) are NEVER bypassed.

## Phase Execution

Execute these phases in strict order. Each phase MUST complete
fully and produce its standard artifacts before the next begins.

### --- Phase 1/4: Specify --- starting...

Invoke `/trc.specify` with the user's input as the feature description.

**Headless behavior overrides**:
- When generating the spec, auto-resolve non-critical clarifications
  with informed guesses. Document assumptions in the spec rather than
  pausing for input.
- The 3-clarification limit from `/trc.specify` applies. If any
  `[NEEDS CLARIFICATION]` markers remain that are genuinely critical
  (scope-impacting ambiguity where multiple interpretations lead to
  fundamentally different features), PAUSE and present the question
  to the user. Otherwise, resolve with the most reasonable default.
- Auto-proceed through checklist validation if all items pass.
- After specify completes, output:
  ```
  --- Phase 1/4: Specify --- complete
  ```

### --- Phase 2/4: Plan --- starting...

Invoke `/trc.plan` with the user's input as the feature description.

**Headless behavior overrides**:
- Do NOT wait for user input after the plan is generated.
- If the plan phase asks for technology choices or framework
  preferences, infer from the existing project context
  (tricycle.config.yml, package.json, existing code).
- Auto-continue to the next phase.
- After plan completes, output:
  ```
  --- Phase 2/4: Plan --- complete
  ```

### --- Phase 3/4: Tasks --- starting...

Invoke `/trc.tasks` with the user's input as the feature description.

**Headless behavior overrides**:
- Do NOT wait for user input after tasks are generated.
- Auto-continue to the next phase.
- After tasks completes, output:
  ```
  --- Phase 3/4: Tasks --- complete
  ```

### --- Phase 4/4: Implement --- starting...

Invoke `/trc.implement` with the user's input as the feature description.

**Headless behavior overrides**:
- Execute all task phases as defined in tasks.md.
- If lint or tests fail, attempt to diagnose and fix the issue.
  Retry up to 3 times. If still failing after 3 attempts, PAUSE
  and report the failure to the user (see Pause Rules below).
- Do NOT push code or create a PR. After implementation completes,
  pause for push approval per constitution Principle III.
- After implement completes, output:
  ```
  --- Phase 4/4: Implement --- complete
  ```

## Pause Rules

During headless execution, you MUST pause and wait for user input
ONLY in these situations:

### 1. Critical Clarification

A spec ambiguity where:
- No reasonable default exists
- Multiple interpretations lead to fundamentally different features
- The choice significantly impacts scope, security, or user experience

When pausing for clarification:
- Present the question with concrete options (A, B, C, Custom)
- Wait for the user's response
- Incorporate their answer into the spec
- Resume the chain from where it paused

### 2. Destructive or Irreversible Action

An operation that cannot be undone:
- Deleting files outside the feature's spec directory
- Resetting branches or discarding uncommitted changes
- Database migrations or schema changes
- Overwriting existing code not created by this headless run

When pausing for destructive actions:
- Describe exactly what will be done
- Wait for explicit user approval
- Resume the chain from where it paused

### 3. Push Approval (NEVER auto-resolved)

Per constitution Principle III, pushing code or creating PRs
ALWAYS requires explicit user approval. This is non-negotiable.

When the chain completes:
- Display the completion summary (see below)
- State readiness to push
- Wait for the user to say "push", "go ahead", or equivalent
- Each push requires fresh confirmation

### 4. Lint/Test Failure After Retries

If lint or tests fail and 3 fix attempts have been exhausted:
- Report the failure clearly
- Show what passed and what failed
- Suggest next steps
- Wait for user to decide how to proceed

**Resume behavior**: After ANY pause, resume the chain from the
exact point where it paused. Do NOT restart the current phase
or skip ahead to the next phase.

## Completion Summary

When all phases complete successfully, output:

```
--- Headless Run Complete ---

Branch: [branch-name]
Artifacts:
  - specs/[NNN-feature]/spec.md
  - specs/[NNN-feature]/plan.md
  - specs/[NNN-feature]/research.md
  - specs/[NNN-feature]/data-model.md
  - specs/[NNN-feature]/tasks.md
  - [list implementation files created/modified]

Lint: [PASS/FAIL]
Tests: [PASS/FAIL]

Next: Push approval required. Say "push" when ready.
```

## Failure Summary

If the chain fails at any phase and cannot recover, output:

```
--- Headless Run Failed ---

Failed at: Phase N/M ([Phase Name])
Error: [description of what went wrong]
Completed artifacts:
  - [list of artifacts successfully produced]
Suggested next steps:
  - [actionable suggestions for the user]
```
