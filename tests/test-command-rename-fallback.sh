#!/usr/bin/env bash
# TRI-31 contract guard: each kickoff command template must carry the
# Session Rename (Fallback) block and invoke derive-branch-name.sh. One
# grep anchor per command so a future edit that drops the block fails
# loudly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

check() {
  local target="$1"; shift
  [ -f "$target" ] || { echo "FAIL: missing target $target"; exit 1; }
  local label pattern
  while [ $# -gt 0 ]; do
    label="$1"; pattern="$2"; shift 2
    if ! grep -q -- "$pattern" "$target"; then
      echo "FAIL [$target]: missing anchor '$label' (pattern: $pattern)"
      exit 1
    fi
  done
}

check "$REPO_ROOT/core/commands/trc.specify.md" \
  "session-rename section"        "Session Rename (Fallback)" \
  "derive-branch-name invocation" "derive-branch-name.sh" \
  "rename instruction"            "/rename" \
  "ordering mandate"              "before the"

check "$REPO_ROOT/core/commands/trc.chain.md" \
  "orchestrator rename section"   "Session Rename (Fallback)" \
  "chain-scoped prefix"           "trc-chain-" \
  "worker brief rename rule"      "First action:" \
  "rename instruction"            "/rename"

check "$REPO_ROOT/core/commands/trc.headless.md" \
  "headless rename section"       "Session Rename (Fallback)" \
  "derive-branch-name invocation" "derive-branch-name.sh" \
  "rename instruction"            "/rename"

echo "command-rename-fallback: OK"
