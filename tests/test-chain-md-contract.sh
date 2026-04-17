#!/usr/bin/env bash
# Contract guards for core/commands/trc.chain.md. Each bug from the
# April-17 batch owns at least one grep anchor here; if a future edit
# drops the rule, the test fails immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$REPO_ROOT/core/commands/trc.chain.md"

[ -f "$TARGET" ] || { echo "FAIL: $TARGET missing"; exit 1; }

need() {
  local label="$1"; shift
  if ! grep -q "$@" "$TARGET"; then
    echo "FAIL: trc.chain.md missing contract rule: $label"
    echo "  looked for: $*" >&2
    exit 1
  fi
}

# #2 — pre-provisioned worktree handoff
need "worker sets TRC_PREPROVISIONED_WORKTREE" -F "TRC_PREPROVISIONED_WORKTREE"
need "worker is told not to re-run worktree setup" -F "DO NOT re-run any worktree-setup"

# #3 — marker path binding
need "worker brief binds the marker to specs/<branch>/" -F "specs/<branch>/.local-testing-passed"
need "worker brief forbids spec-dir suffixes" -F "no suffixes"

# #4 — compound-command splitting
need "push step forbids touch+gh chaining" -E "DO NOT chain .touch"

# #5 — gh pr merge idempotency against worktree-locked base
need "gh pr view fallback after gh pr merge failure" -F "gh pr view"
need "treats server-side MERGED as success" -F "MERGED"

# #6 — open_questions hedging prohibition
need "worker brief forbids hedging in open_questions on committed" -F "ERR_COMMITTED_HEDGING"

# #7 — dismiss documented in resume UI
need "resume prompt documents Dismiss" -F "Dismiss"
need "resume section explains chain-run.sh dismiss" -F "chain-run.sh dismiss"

# #9 — shared-doc post-chain tick
need "orchestrator ticks shared docs after chain" -F "Shared-Doc Post-Chain Tick"
need "workers forbidden from editing shared docs" -F "forbidden from editing shared planning documents"

echo "chain-md-contract: OK"
