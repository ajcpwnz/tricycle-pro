#!/usr/bin/env bash
# Contract guard for the graphify integration shipped in v0.22.4+.
# Every trc flow command (specify, plan, tasks, implement, headless) MUST
# carry exactly one `## Graphify Context` section AND that section MUST
# gate on the `integrations.graphify.enabled` config flag. The chain skill
# MUST NOT reference the pre-v0.22.4 `graphify mcp-start` / `mcp-stop`
# per-chain registration dance (removed in v0.22.5 — it never worked with
# Agent-spawned workers).
#
# Why this exists: v0.22.4 shipped with a stray leftover `## Graphify
# Orientation (optional)` section in trc.specify.md that contradicted the
# new gated block. This test rejects that class of drift up front.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }

check_flow_cmd() {
  local f="$1"
  [ -f "$f" ] || fail "missing: $f"

  # Exactly one `## Graphify` heading — no stray leftovers.
  local heading_count
  heading_count=$(grep -c '^## .*[Gg]raphify' "$f" || true)
  [ "$heading_count" = "1" ] || fail "$f has $heading_count graphify headings (expected 1)"

  # That one heading must be `## Graphify Context`.
  grep -q '^## Graphify Context$' "$f" \
    || fail "$f graphify heading is not '## Graphify Context' (may be a stale draft)"

  # Section must reference the config-flag gate so opt-out works.
  grep -q 'integrations\.graphify\.enabled' "$f" \
    || fail "$f graphify section is missing the integrations.graphify.enabled gate"
}

for cmd in specify plan tasks implement headless; do
  check_flow_cmd "$REPO_ROOT/core/commands/trc.$cmd.md"
done

# Chain skill: must not reference the dead per-chain MCP dance.
chain="$REPO_ROOT/core/commands/trc.chain.md"
[ -f "$chain" ] || fail "missing: $chain"
if grep -Eq 'graphify (mcp-start|mcp-stop)' "$chain"; then
  fail "$chain still references the dead per-chain graphify mcp-start/mcp-stop dance"
fi

echo "graphify-briefing-contract: OK"
