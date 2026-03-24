# tricycle-pro

## Commands


- **cli**: `cd . && npm run lint` (lint), `cd . && node --test tests/` (test)


### Package Manager
npm only. Do not mix package managers.


---

## Lint & Test Before Done (MANDATORY — NONNEGOTIABLE)

After ANY code changes, you MUST run lint and test scripts for ALL affected apps/packages
and ensure they pass BEFORE declaring work complete.


- **cli**: `cd . && npm run lint`


If any script fails, fix the issue. Never skip this step.


---

## Push Gating (MANDATORY — NONNEGOTIABLE)

NEVER push code or create PRs without explicit user approval. When a feature is
complete (lint/test pass, QA done if applicable):
1. Summarize the changes and state you are ready to push.
2. Wait for the user to say "push", "go ahead", or equivalent.
3. Each push requires fresh confirmation — prior approval does not carry over.


---

## MCP Usage (MANDATORY — NONNEGOTIABLE)

MCP servers are configured in `.mcp.json`. Use them in the appropriate contexts.
If an MCP requires a service to be running (e.g., Docker, a dev server, the database),
start that service BEFORE attempting to use the MCP.


---

## Feature Branch, PR & Deploy (MANDATORY — NONNEGOTIABLE)

When a feature is complete (after lint/test pass), follow this workflow:
1. Ask the user for the feature branch name.
2. Commit all changes.
3. Prompt the user for push approval — do NOT push without it.
4. Once approved, push the branch and create a PR targeting `main`.
5. Check for merge conflicts before merging.
6. Once PR is mergeable, merge (squash merge).


---

## Artifact Cleanup (MANDATORY — NONNEGOTIABLE)

Do NOT clean up Tricycle Pro artifacts (spec files, plan files, task files) or worktrees
until the user has approved the push and the PR is merged. Cleanup sequence:
1. Feature done, lint/tests pass, QA done → prompt user for push approval.
2. User approves → push, create PR, merge.
3. Only after successful merge → clean up worktree and temporary artifacts.


## Active Technologies
- JavaScript (Node.js >= 18.0.0) + yaml (existing), node:test (existing) (001-headless-mode)
- N/A (file-based artifacts only) (001-headless-mode)
- Bash 3.2+ (macOS default), 4.0+ (Linux) + None — standard Unix utilities only (`sed`, `awk`, `grep`, `find`, `chmod`, `mkdir`, `cat`, `shasum`/`sha256sum`) (002-shell-only-cli)
- File-based (YAML config input, JSON output, template files) (002-shell-only-cli)

## Recent Changes
- 001-headless-mode: Added JavaScript (Node.js >= 18.0.0) + yaml (existing), node:test (existing)
