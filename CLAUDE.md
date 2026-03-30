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
- TRI-20-qa-testing-block: QA testing block — optional implement block, assembly auto-enable, learnings append
- TRI-19-session-context-hook: Added Bash (POSIX-compatible, tested on macOS zsh) + None (pure bash, optional jq for JSON construction)
- TRI-5-audit-command: Audit command + linear-audit output skill — constitution/prompt/common-sense auditing with pluggable output

## Active Technologies
