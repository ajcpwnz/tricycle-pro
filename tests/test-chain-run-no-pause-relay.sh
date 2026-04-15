#!/usr/bin/env bash
# TRI-30 FR-013 static guard.
#
# The /trc.chain orchestrator MUST NEVER attempt to forward a follow-up
# message to a returned worker sub-agent. Sub-agents are terminated when
# they return — any follow-up is delivered to a dead inbox and silently
# ignored. This test fails the build if the forbidden tool name ever
# reappears in core/commands/trc.chain.md.
#
# See specs/TRI-30-chain-run-to-commit/spec.md FR-013 and
# user memory feedback_trc_chain_no_pause_relay for the original incident
# that motivated this rule.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$REPO_ROOT/core/commands/trc.chain.md"

if [[ ! -f "$TARGET" ]]; then
    echo "test-chain-run-no-pause-relay: FAIL — target file missing: $TARGET" >&2
    exit 1
fi

if grep -i -n 'sendmessage' "$TARGET" >/dev/null 2>&1; then
    echo "FR-013 violation: trc.chain.md references the forbidden pause-relay tool." >&2
    echo "Offending line(s):" >&2
    grep -i -n 'sendmessage' "$TARGET" >&2
    echo "" >&2
    echo "See specs/TRI-30-chain-run-to-commit/spec.md FR-013 and" >&2
    echo "user memory feedback_trc_chain_no_pause_relay for context." >&2
    exit 1
fi

echo "no-pause-relay: OK"
