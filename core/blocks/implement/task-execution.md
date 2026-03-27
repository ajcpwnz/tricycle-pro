---
name: task-execution
step: implement
description: Execute tasks phase by phase with TDD approach and progress tracking
required: false
default_enabled: true
order: 50
---

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
