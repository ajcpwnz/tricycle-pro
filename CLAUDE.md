# tricycle-pro

## Commands

- **cli**: `cd . && bash tests/run-tests.sh` (test), `cd . && node --test tests/test-*.js` (test-blocks)

### Package Manager
npm only. Do not mix package managers.

---

## Lint & Test Before Done (MANDATORY — NONNEGOTIABLE)

After ANY code changes, you MUST run lint and test scripts for ALL affected apps/packages
and ensure they pass BEFORE declaring work complete.

- **cli**: `cd . && bash tests/run-tests.sh`

If any script fails, fix the issue. Never skip this step.

---

## MCP Usage (MANDATORY — NONNEGOTIABLE)

MCP servers are configured in `.mcp.json`. Use them in the appropriate contexts.
If an MCP requires a service to be running (e.g., Docker, a dev server, the database),
start that service BEFORE attempting to use the MCP.

## Recent Changes
- TRI-31-session-rename-on-kickoff: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + Claude Code `UserPromptSubmit` hook contract with `hookSpecificOutput.sessionTitle` (available v2.1.94+ per R1). Existing in-repo: `core/scripts/bash/common.sh`, `bin/tricycle` settings generator, `bin/lib/helpers.sh`.
- TRI-30-chain-run-to-commit: Added Bash 3.2+ (macOS default); Node.js (tests only, via `node --test`); python3 (json reads/builds, already used in TRI-27) + Existing `core/scripts/bash/common.sh`, `chain-run.sh` (TRI-27); GitHub CLI `gh` (orchestrator-side, agent-invoked); git ≥ 2.5 for worktree support; Claude Code's `Agent` tool for spawning workers (no longer uses `SendMessage` — that's the bug being fixed)
- TRI-28-trc-review-command: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). No new runtime languages. + Existing in-repo helpers only — `bin/lib/helpers.sh`, `bin/lib/yaml_parser.sh`, `bin/lib/common.sh`, `core/scripts/bash/json_builder.sh`. External CLI: `gh` (GitHub CLI, user-provided, authenticated). Agent-side tool: Claude Code's `WebFetch` (for remote sources).

## Active Technologies
- Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + Claude Code `UserPromptSubmit` hook contract with `hookSpecificOutput.sessionTitle` (available v2.1.94+ per R1). Existing in-repo: `core/scripts/bash/common.sh`, `bin/tricycle` settings generator, `bin/lib/helpers.sh`. (TRI-31-session-rename-on-kickoff)
- None — feature is stateless. (TRI-31-session-rename-on-kickoff)
