---
description: Execute the implementation plan by processing and executing all tasks defined in tasks.md
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).


## Chain Validation

Before proceeding, read `tricycle.config.yml` and check the `workflow.chain` configuration.

1. If `workflow.chain` is not defined, use the default chain: `[specify, plan, tasks, implement]`.
2. Validate the chain is one of these valid configurations:
   - `[specify, plan, tasks, implement]` (default — full workflow)
   - `[specify, plan, implement]` (tasks absorbed into plan)
   - `[specify, implement]` (plan and tasks absorbed into specify)
3. If the chain is invalid, STOP and output:
   ```
   Error: Invalid workflow chain configuration.
   Valid chains: [specify, plan, tasks, implement], [specify, plan, implement], [specify, implement]
   ```
4. Verify that `implement` is present in the configured chain. If not, STOP and output:
   ```
   Error: Step 'implement' is not part of the configured workflow chain [current chain].
   To use this step, update workflow.chain in tricycle.config.yml and run tricycle assemble.
   ```


1. Run `.trc/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").


2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Completed items: Lines matching `- [X]` or `- [x]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ✗ FAIL |
     | security.md | 6   | 6         | 0          | ✓ PASS |
     ```

   - Calculate overall status:
     - **PASS**: All checklists have 0 incomplete items
     - **FAIL**: One or more checklists have incomplete items

   - **If any checklist is incomplete**:
     - Display the table with incomplete item counts
     - **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
     - Wait for user response before continuing
     - If user says "no" or "wait" or "stop", halt execution
     - If user says "yes" or "proceed" or "continue", proceed to the next step

   - **If all checklists are complete**:
     - Display the table showing all checklists passed
     - Automatically proceed to the next step


4. **Project Setup Verification**:
   - **REQUIRED**: Create/verify ignore files based on actual project setup:

   **Detection & Creation Logic**:
   - Check if the following command succeeds to determine if the repository is a git repo (create/verify .gitignore if so):

     ```sh
     git rev-parse --git-dir 2>/dev/null
     ```

   - Check if Dockerfile* exists or Docker in plan.md → create/verify .dockerignore
   - Check if .eslintrc* exists → create/verify .eslintignore
   - Check if eslint.config.* exists → ensure the config's `ignores` entries cover required patterns
   - Check if .prettierrc* exists → create/verify .prettierignore
   - Check if .npmrc or package.json exists → create/verify .npmignore (if publishing)
   - Check if terraform files (*.tf) exist → create/verify .terraformignore
   - Check if .helmignore needed (helm charts present) → create/verify .helmignore

   **If ignore file already exists**: Verify it contains essential patterns, append missing critical patterns only
   **If ignore file missing**: Create with full pattern set for detected technology

   **Common Patterns by Technology** (from plan.md tech stack):
   - **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
   - **Java**: `target/`, `*.class`, `*.jar`, `.gradle/`, `build/`
   - **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
   - **Go**: `*.exe`, `*.test`, `vendor/`, `*.out`
   - **Ruby**: `.bundle/`, `log/`, `tmp/`, `*.gem`, `vendor/bundle/`
   - **PHP**: `vendor/`, `*.log`, `*.cache`, `*.env`
   - **Rust**: `target/`, `debug/`, `release/`, `*.rs.bk`, `*.rlib`, `*.prof*`, `.idea/`, `*.log`, `.env*`
   - **Kotlin**: `build/`, `out/`, `.gradle/`, `.idea/`, `*.class`, `*.jar`, `*.iml`, `*.log`, `.env*`
   - **C++**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.so`, `*.a`, `*.exe`, `*.dll`, `.idea/`, `*.log`, `.env*`
   - **C**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.a`, `*.so`, `*.exe`, `*.dll`, `autom4te.cache/`, `config.status`, `config.log`, `.idea/`, `*.log`, `.env*`
   - **Swift**: `.build/`, `DerivedData/`, `*.swiftpm/`, `Packages/`
   - **R**: `.Rproj.user/`, `.Rhistory`, `.RData`, `.Ruserdata`, `*.Rproj`, `packrat/`, `renv/`
   - **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

   **Tool-Specific Patterns**:
   - **Docker**: `node_modules/`, `.git/`, `Dockerfile*`, `.dockerignore`, `*.log*`, `.env*`, `coverage/`
   - **ESLint**: `node_modules/`, `dist/`, `build/`, `coverage/`, `*.min.js`
   - **Prettier**: `node_modules/`, `dist/`, `build/`, `coverage/`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - **Terraform**: `.terraform/`, `*.tfstate*`, `*.tfvars`, `.terraform.lock.hcl`
   - **Kubernetes/k8s**: `*.secret.yaml`, `secrets/`, `.kube/`, `kubeconfig*`, `*.key`, `*.crt`


3. Load and analyze the implementation context:
   - **REQUIRED**: Read tasks.md for the complete task list and execution plan
   - **REQUIRED**: Read plan.md for tech stack, architecture, and file structure
   - **IF EXISTS**: Read data-model.md for entities and relationships
   - **IF EXISTS**: Read contracts/ for API specifications and test requirements
   - **IF EXISTS**: Read research.md for technical decisions and constraints
   - **IF EXISTS**: Read quickstart.md for integration scenarios

5. Parse tasks.md structure and extract:
   - **Task phases**: Setup, Tests, Core, Integration, Polish
   - **Task dependencies**: Sequential vs parallel execution rules
   - **Task details**: ID, description, file paths, parallel markers [P]
   - **Execution flow**: Order and dependency requirements

6. Execute implementation following the task plan:
   - **Phase-by-phase execution**: Complete each phase before moving to the next
   - **Respect dependencies**: Run sequential tasks in order, parallel tasks [P] can run together
   - **Follow TDD approach**: Execute test tasks before their corresponding implementation tasks
   - **File-based coordination**: Tasks affecting the same files must run sequentially
   - **Validation checkpoints**: Verify each phase completion before proceeding

### Test/Lint Gate (after EVERY phase)

**MANDATORY — NONNEGOTIABLE.** After completing each implementation phase, you MUST run all configured test and lint commands before proceeding to the next phase.

1. Read `apps` from `tricycle.config.yml`. For each app, check for `test` and `lint` fields.
2. Skip any app where both `test` and `lint` are missing or empty.
3. Run each configured command. All must exit 0.
4. **If any command fails**:
   - Attempt to fix the issue (read the error output, identify the root cause, apply a fix).
   - Re-run **all** test/lint commands (not just the one that failed).
   - You have a maximum of **3 fix attempts**.
   - If all commands pass within 3 attempts → proceed to the next phase.
   - If still failing after 3 attempts → **HALT**. Do NOT proceed. Report:
     - Which command failed
     - The exit code
     - Relevant output (last 20 lines)
     - What fixes were attempted
     - Clear statement: **"Cannot proceed — tests/lint failing after 3 fix attempts. Manual intervention required."**
5. **You MUST NOT proceed to the next phase, to push-deploy, or to any subsequent block while tests or lint are failing.** This gate is non-negotiable.

7. Implementation execution rules:
   - **Setup first**: Initialize project structure, dependencies, configuration
   - **Tests before code**: If you need to write tests for contracts, entities, and integration scenarios
   - **Core development**: Implement models, services, CLI commands, endpoints
   - **Integration work**: Database connections, middleware, logging, external services
   - **Polish and validation**: Unit tests, performance optimization, documentation

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.

9. Final test/lint gate and completion validation:

   **MANDATORY — NONNEGOTIABLE.** After ALL implementation phases are complete, run the full test/lint suite one final time. This catches regressions introduced during later phases.

   1. Run every configured `test` and `lint` command across all apps.
   2. Same retry logic as the per-phase gate: attempt fix, re-run all commands, max 3 attempts.
   3. **If still failing after 3 attempts → HALT.** Do NOT proceed to version-bump or push-deploy. Report the failure with full context.
   4. **Do NOT mark implementation as complete while any test or lint command is failing.**

   Once the final gate passes:
   - Verify all required tasks are completed
   - Check that implemented features match the original specification
   - Confirm the implementation follows the technical plan
   - Report final status with summary of completed work


10. **Version bump**: After all tasks pass and before reporting completion:
    - Read the current version from the `VERSION` file in the repo root
    - Bump the patch version (e.g., `0.2.0` → `0.2.1`; if this is a new feature, bump minor: `0.2.0` → `0.3.0`)
    - Write the new version to `VERSION`
    - Include the version bump in the final commit (do NOT create a separate commit for it)

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/trc.tasks` first to regenerate the task list.


## Push, PR & Deploy

After all tasks are complete, tests pass, and the version is bumped, execute the push/PR/merge workflow:

### 1. Read push configuration

Read `tricycle.config.yml` and extract:
- `push.require_approval` (boolean, default true)
- `push.pr_target` (string, default "main")
- `push.merge_strategy` (string: squash, merge, or rebase)
- `push.auto_merge` (boolean, default false)

### 2. Summarize changes

Present a summary to the user:
- What was implemented (feature name, user stories completed)
- Files changed (count and key files)
- Tests passed (which test suites ran and their results)
- Version bumped (old → new)

### 3. Push approval gate

**If `push.require_approval` is true** (default):
1. State that you are ready to push and present the summary.
2. **HALT and wait** for the user to say "push", "go ahead", or equivalent.
3. Each push requires **fresh confirmation** — prior approval does not carry over.
4. If the user declines or says "stop", "wait", "no" — do NOT push. Do NOT create a PR. HALT the workflow.

**If `push.require_approval` is false**: Proceed directly to step 4.

### 4. Push and create PR

1. Push the branch to the remote with the `-u` flag.
2. Create a PR targeting `push.pr_target` using `gh pr create`.
3. Include the change summary in the PR body.

**If push fails** (remote rejected, auth error, network failure): Report the error clearly and HALT. Do not retry.

### 5. Merge (if auto_merge is true)

**If `push.auto_merge` is true**:
1. Check for merge conflicts. If conflicts exist, report them and HALT — do not force-merge.
2. Merge using the configured `push.merge_strategy` via `gh pr merge`.
3. If merge is blocked (branch protection, required reviewers), report the blocker and wait.

**If `push.auto_merge` is false**: Report the PR URL and let the user handle merging.

### 6. Artifact cleanup (only after confirmed merge)

**IMPORTANT**: Do NOT clean up artifacts until the PR is successfully merged. If merge has not happened, skip this step entirely.

After confirmed merge:
1. Remove the spec/plan/task files in the `specs/{branch}/` directory (if they exist).
2. If in a worktree (`.git` is a file), note that the worktree-cleanup block (if active) handles worktree removal separately.
3. If NOT in a worktree, switch back to the base branch and delete the feature branch locally.

### 7. Error handling

On **any failure** during this workflow (push rejected, PR creation failed, merge blocked, conflicts):
- Report the error clearly with context.
- HALT the workflow — do not continue to the next step.
- Do not retry automatically.
- Do not clean up artifacts.
- Suggest what the user can do to resolve the issue.


## Worktree Cleanup Reminder

After implementation is complete, lint/tests pass, and the user has approved the push:

**Do NOT clean up automatically.** Per the artifact cleanup rules, worktrees and spec artifacts MUST NOT be cleaned up until the PR is merged.

Instead, after the push is approved and PR is created, remind the user:

```
Worktree cleanup available after PR merge:

  # Remove the worktree
  git worktree remove ../[worktree-path]

  # Prune stale worktree references
  git worktree prune

  # Optionally delete the feature branch (after merge)
  git branch -d [branch-name]
```

Only display this reminder if the current working directory is a worktree (`.git` is a file, not a directory). If already in the main checkout, skip this block silently.

