#!/usr/bin/env bash
# Contract guards for core/commands/trc.band.md. Each load-bearing rule of
# the band orchestrator owns at least one grep anchor here; if a future
# edit drops the rule, the test fails immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$REPO_ROOT/core/commands/trc.band.md"
CHAIN="$REPO_ROOT/core/commands/trc.chain.md"

[ -f "$TARGET" ] || { echo "FAIL: $TARGET missing"; exit 1; }

need() {
  local label="$1"; shift
  if ! grep -q "$@" "$TARGET"; then
    echo "FAIL: trc.band.md missing contract rule: $label"
    echo "  looked for: $*" >&2
    exit 1
  fi
}

# Pre-provisioned worktree handoff (same contract as chain workers).
need "worker sets TRC_PREPROVISIONED_WORKTREE" -F "TRC_PREPROVISIONED_WORKTREE"
need "worker is told not to re-run worktree setup" -F "DO NOT re-run any worktree-setup"

# Marker path binding.
need "marker bound to specs/<branch>/" -F "specs/<branch>/.local-testing-passed"
need "spec-dir suffixes forbidden" -F "no suffixes"

# Step-scoped background workers continued via SendMessage. This is the
# band/chain boundary: chain workers are fire-and-report (SendMessage is
# FORBIDDEN there, see test-chain-run-no-pause-relay.sh); band workers are
# named background agents that the orchestrator continues step by step.
need "workers spawned in background" -F "run_in_background: true"
need "workers have stable names" -F "band-worker-"
need "continuation uses SendMessage" -F "SendMessage"
need "no double-send without an intervening report" -F "twice without an"
if grep -iq 'sendmessage' "$CHAIN"; then
  echo "FAIL: trc.chain.md must NOT reference SendMessage (FR-013 boundary)"
  exit 1
fi

# One step per instruction; workers never pause; blocked is a report.
need "one step only rule" -F "ONE STEP ONLY"
need "workers never pause" -F "NEVER PAUSE"
need "blocked status carries questions" -F '"blocked"'
need "hedging on committed rejected" -F "ERR_COMMITTED_HEDGING"

# Pause protocol stops the whole band until the user answers.
need "pause protocol section" -F "## Pause / Ambiguity Protocol"
need "band-wide stop while paused" -F "no new"

# Recon gate: mandatory approval pause before any fan-out.
need "recon approval gate section" -F "### Recon Approval Gate"
need "gate is a mandatory pause" -F "mandatory pause"
need "fan-out only on approval" -F "never fan out before explicit approval"

# Scope echo itself must stay non-gating (approval happens at the recon gate).
need "scope echo forbids confirmation prompts" -F 'MUST NOT** emit any confirmation prompt'

# Scheduler delegates gating to the helper.
need "scheduler uses next-ready" -F "band-run.sh next-ready"
need "dead-worker respawn rule" -F "Dead-worker rule"

# Push policy: single final gate, nothing remote before it.
need "no remote mutation before the gate" -F "No remote mutation of any kind"
need "workers never push" -F "NEVER PUSH"
need "marker/push/pr are separate Bash calls" -F "OWN Bash call"

# Integration protocol: roadmap order, rebase cap, MERGED fallback.
need "merge in roadmap order" -F "roadmap order"
need "rebase cap enforced" -F "ERR_REBASE_CAP"
need "gh pr view fallback after merge failure" -F "gh pr view"
need "treats server-side MERGED as success" -F "MERGED"

# Resume semantics: background workers don't survive restarts.
need "resume never trusts old workers" -F "NEVER survive"
need "dismiss documented in resume UI" -F "Dismiss"
need "band-run.sh dismiss referenced" -F "band-run.sh dismiss"

# Model matrix present.
need "worker model matrix" -F "Worker model matrix"

# Forbid the generic mid-list gate text pattern that chain banned; the only
# allowed prompts are the recon gate and the final push gate.
if grep -qE 'Proceed\? *\(yes */ *no\)' "$TARGET"; then
  echo "FAIL: trc.band.md contains a generic 'Proceed? (yes / no)' gate"
  exit 1
fi

echo "band-md-contract: OK"
