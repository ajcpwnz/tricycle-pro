#!/usr/bin/env bash
# End-to-end resumability for chain-run.sh helper (clarification Q1, FR-019-021).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAIN="$REPO_ROOT/core/scripts/bash/chain-run.sh"

cd "$REPO_ROOT"

# Simulate an interrupted run: init, complete ticket 1, walk away (no close).
INIT=$(bash "$CHAIN" init --ids '["TRI-9300","TRI-9301","TRI-9302"]')
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
trap 'rm -rf "$REPO_ROOT/specs/.chain-runs/$RID"' EXIT

bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9300 --status completed --finished-now --lint pass --test pass >/dev/null

# list-interrupted should find this run with next_ticket_id=TRI-9301.
RID="$RID" bash "$CHAIN" list-interrupted | RID="$RID" python3 -c '
import json, sys, os
j = json.load(sys.stdin)
rid = os.environ["RID"]
found = next((r for r in j["runs"] if r["run_id"] == rid), None)
assert found is not None, "interrupted run should be listed"
assert found["next_ticket_id"] == "TRI-9301"
assert found["current_index"] == 1
'

# Discard the run.
bash "$CHAIN" close --run-id "$RID" --terminal-status aborted --reason "user discarded" >/dev/null

# Now list-interrupted should NOT include this run.
RID="$RID" bash "$CHAIN" list-interrupted | RID="$RID" python3 -c '
import json, sys, os
j = json.load(sys.stdin)
rid = os.environ["RID"]
assert not any(r["run_id"] == rid for r in j["runs"]), "discarded run should not be listed"
'

echo "e2e-resume: OK"
