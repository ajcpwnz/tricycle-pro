---
description: >-
  Run the full specify, plan, tasks, implement chain automatically
  from a single prompt. Pauses only for critical clarifications,
  destructive actions, or push approval.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

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

## Headless Execution Mode

This command runs the **complete** specify, plan, tasks, implement
chain in a single invocation. The key behavioral differences from
running each command manually:

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

Execute these four phases in strict order. Each phase MUST complete
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

Invoke `/trc.plan` using the spec generated in Phase 1.

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

Invoke `/trc.tasks` using the plan generated in Phase 2.

**Headless behavior overrides**:
- Do NOT wait for user input after tasks are generated.
- Auto-continue to the next phase.
- After tasks completes, output:
  ```
  --- Phase 3/4: Tasks --- complete
  ```

### --- Phase 4/4: Implement --- starting...

Invoke `/trc.implement` using the tasks generated in Phase 3.

**Headless behavior overrides**:
- Execute all task phases as defined in tasks.md.
- If lint or tests fail, attempt to diagnose and fix the issue.
  Retry up to 3 times. If still failing after 3 attempts, PAUSE
  and report the failure to the user (see Pause Rules below).
- Do NOT push code or create a PR. After implementation completes,
  pause for push approval per constitution Principle III.
- After implement completes (lint/tests pass), output:
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

When all four phases complete successfully, output:

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

Failed at: Phase N/4 ([Phase Name])
Error: [description of what went wrong]
Completed artifacts:
  - [list of artifacts successfully produced]
Suggested next steps:
  - [actionable suggestions for the user]
```
