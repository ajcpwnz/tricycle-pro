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
- TRI-33-dogfood-core-sync: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + git (read-only usage for `diff -r` semantics via shell), `find` (existing), `cp -f`, `diff -r`.
- TRI-32-pull-fresh-base: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + git ≥ 2.20 (stable network-error signatures, universal in practice).
- TRI-31-session-rename-on-kickoff: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + Claude Code `UserPromptSubmit` hook contract with `hookSpecificOutput.sessionTitle` (available v2.1.94+ per R1). Existing in-repo: `core/scripts/bash/common.sh`, `bin/tricycle` settings generator, `bin/lib/helpers.sh`.

## Active Technologies
- Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). + git (read-only usage for `diff -r` semantics via shell), `find` (existing), `cp -f`, `diff -r`. (TRI-33-dogfood-core-sync)
- `.tricycle.lock` (existing). No new files. (TRI-33-dogfood-core-sync)
