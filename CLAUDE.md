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
- TRI-24-feature-status: Added Bash 3.2+ (macOS default) + None new — uses existing `json_builder.sh`, `helpers.sh`
- TRI-23-local-config-overrides: Added Bash (3.2+ compatible, macOS default) + Node.js (for tests) + None new — uses existing `parse_yaml()`, `cfg_*()`, assembly scrip
- TRI-22-auto-worktree-cleanup: Auto worktree cleanup — replace reminder with automatic cleanup after PR merge

## Active Technologies
- Bash 3.2+ (macOS default) + None new — uses existing `json_builder.sh`, `helpers.sh` (TRI-24-feature-status)
- Filesystem (read-only scan of `specs/` directories) (TRI-24-feature-status)
