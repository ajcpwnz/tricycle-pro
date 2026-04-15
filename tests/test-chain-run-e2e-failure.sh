#!/usr/bin/env bash
# End-to-end stop-on-failure for chain-run.sh helper (US3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAIN="$REPO_ROOT/core/scripts/bash/chain-run.sh"

cd "$REPO_ROOT"

INIT=$(bash "$CHAIN" init --ids '["TRI-9200","TRI-9201","TRI-9202"]')
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
trap 'rm -rf "$REPO_ROOT/specs/.chain-runs/$RID"' EXIT

# Ticket 1 completes.
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9200 --status completed --finished-now --lint pass --test pass >/dev/null

# Ticket 2 fails (test failure).
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9201 --status failed --finished-now --lint pass --test fail >/dev/null

# Orchestrator closes the run as failed.
bash "$CHAIN" close --run-id "$RID" --terminal-status failed --reason "tests failed on TRI-9201" >/dev/null

# Verify the state: TRI-9200 completed, TRI-9201 failed, TRI-9202 not_started, top-level failed.
bash "$CHAIN" get --run-id "$RID" | python3 -c '
import json, sys
s = json.load(sys.stdin)
assert s["status"] == "failed", "top-level status should be failed, got " + s["status"]
assert s["terminal_reason"] == "tests failed on TRI-9201"
assert s["tickets"]["TRI-9200"]["status"] == "completed"
assert s["tickets"]["TRI-9201"]["status"] == "failed"
assert s["tickets"]["TRI-9201"]["test_status"] == "fail"
assert s["tickets"]["TRI-9202"]["status"] == "not_started"
'

# Verify not listed as interrupted.
export RID
bash "$CHAIN" list-interrupted | python3 -c '
import json, sys, os
j = json.load(sys.stdin)
rid = os.environ["RID"]
for r in j.get("runs", []):
    assert r["run_id"] != rid, "failed run should not be listed"
'

echo "e2e-failure: OK"
