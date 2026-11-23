---
name: qa-testing
step: implement
description: QA testing gate — run configured tests, follow instructions file, halt on failure before push
required: false
default_enabled: false
order: 55
---

## QA Testing Gate

**MANDATORY — NONNEGOTIABLE.** Before proceeding to push-deploy, you MUST complete all testing steps below. If a test fails and you cannot repair it, do NOT proceed to the next block.

### 1. Read QA instructions (if available)

Check if `qa/ai-agent-instructions.md` exists in the project root.

**If the file exists**: Read it in full and follow all guidance before running tests. This file contains project-specific testing prerequisites, setup instructions, and operational rules (for example, starting Docker or dev servers, and setting environment variables). Complete all prerequisite steps before proceeding to step 2.

**If the file does not exist**: Skip this step and proceed directly to running tests.

### 2. Run all configured test commands

Read `tricycle.config.yml` and find all `apps` entries with a `test` field.

For each app with a `test` field:
1. Navigate to the app's `path` (or stay in project root if path is `.`)
2. Run the configured `test` command
3. Record the result (pass/fail, exit code, relevant output)

**All test commands must exit 0.**

If no apps have a `test` field defined, output a warning:
```
Warning: qa.enabled is true but no apps have test commands configured.
Add test commands to your apps in tricycle.config.yml:
  apps:
    - name: myapp
      test: "npm test"
```
Then proceed to step 4 (learnings).

### 3. Handle test failures

**If any test command fails**:
1. Read the error output and identify the root cause.
2. Repair it.
3. Re-run **ALL** test commands (not just the one that failed).
4. Do this again until all commands pass. There is no limit on the number of attempts.

**When all commands pass**: Proceed to step 4.

**If the repair needs something that only the user has**, do NOT proceed to push-deploy or a subsequent block. Examples are a credential, or a business rule that the spec does not cover. Report the failed command, its exit code and the last 20 lines of its output. Report what you tried, and name the blocker.

### 4. Record testing learnings

After all tests pass (or after resolving failures), reflect on the testing process:

**Did you discover any new operational knowledge?** Examples:
- A prerequisite command that must run before tests (e.g., `prisma generate`)
- A faster way to start the local stack (e.g., `docker compose up -d --wait`)
- An environment variable that needs to be set
- A service that needs to be running on a specific port
- A test that hangs without a specific flag
- A command that needs a different working directory

**If you have new learnings**:
1. Read `qa/ai-agent-instructions.md` (if it exists) to check for duplicates.
2. If the learning is not documented yet, add it to the section of the file that covers its
   topic, as one short line. Update an existing line instead of adding a second one. Do not
   add dates, ticket stories or a dated log.
3. If `qa/ai-agent-instructions.md` does not exist, create it with a `# QA Testing
   Instructions` header and one section for the topic.
4. Remove a line that is no longer true when you find one.

**If you have no new learnings**: Do not modify the file.
