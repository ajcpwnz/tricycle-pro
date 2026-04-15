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
- TRI-28-trc-review-command: Added Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). No new runtime languages. + Existing in-repo helpers only — `bin/lib/helpers.sh`, `bin/lib/yaml_parser.sh`, `bin/lib/common.sh`, `core/scripts/bash/json_builder.sh`. External CLI: `gh` (GitHub CLI, user-provided, authenticated). Agent-side tool: Claude Code's `WebFetch` (for remote sources).
- TRI-27-trc-chain-orchestrator: Added Bash 3.2+ (macOS default); Node.js (tests only, via `node --test`) + Existing `core/scripts/bash/common.sh`, `json_builder.sh`, `helpers.sh`; Linear MCP server (runtime, agent-side); Claude Code's `Agent` + `SendMessage` tools (runtime, agent-side)
- TRI-26-worktree-provisioning: Added Bash 3.2+ (macOS default), Node.js (tests only) + None new — reuses existing `common.sh` helpers, `json_builder.sh` patterns, and the in-repo YAML parsing style already used by `parse_chain_config` / `parse_block_overrides`

## Active Technologies
- Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). No new runtime languages. + Existing in-repo helpers only — `bin/lib/helpers.sh`, `bin/lib/yaml_parser.sh`, `bin/lib/common.sh`, `core/scripts/bash/json_builder.sh`. External CLI: `gh` (GitHub CLI, user-provided, authenticated). Agent-side tool: Claude Code's `WebFetch` (for remote sources). (TRI-28-trc-review-command)
- Filesystem only. Markdown reports under `docs/reviews/`; remote-source cache under `.trc/cache/review-sources/<sha256>.md`. No database. No migrations. (TRI-28-trc-review-command)
