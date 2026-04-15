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
- TRI-26-worktree-provisioning: Added Bash 3.2+ (macOS default), Node.js (tests only) + None new — reuses existing `common.sh` helpers, `json_builder.sh` patterns, and the in-repo YAML parsing style already used by `parse_chain_config` / `parse_block_overrides`
- TRI-24-feature-status: Added Bash 3.2+ (macOS default) + None new — uses existing `json_builder.sh`, `helpers.sh`
- TRI-25-hello-world: Added Bash 3.2+ (macOS default) + None new

## Active Technologies
- Bash 3.2+ (macOS default), Node.js (tests only) + None new — reuses existing `common.sh` helpers, `json_builder.sh` patterns, and the in-repo YAML parsing style already used by `parse_chain_config` / `parse_block_overrides` (TRI-26-worktree-provisioning)
- Filesystem only — reads `tricycle.config.yml`, writes into an existing worktree directory (TRI-26-worktree-provisioning)
