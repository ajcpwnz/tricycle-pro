#!/usr/bin/env bash
# End-to-end happy path for chain-run.sh helper.
# Exercises parse-range → init → update-ticket (serial) → get → close.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAIN="$REPO_ROOT/core/scripts/bash/chain-run.sh"

cd "$REPO_ROOT"

# Parse a 3-ticket range.
OUT=$(bash "$CHAIN" parse-range "TRI-9100..TRI-9102")
echo "$OUT" | grep -q '"count":3' || { echo "parse-range count mismatch: $OUT" >&2; exit 1; }

# Init the run.
INIT=$(bash "$CHAIN" init --ids '["TRI-9100","TRI-9101","TRI-9102"]' --ids-raw 'TRI-9100..TRI-9102')
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
[ -n "$RID" ] || { echo "no run_id in init output" >&2; exit 1; }
trap 'rm -rf "$REPO_ROOT/specs/.chain-runs/$RID"' EXIT

# Verify state.json exists and has the expected schema.
STATE=$(bash "$CHAIN" get --run-id "$RID")
echo "$STATE" | python3 -c '
import json, sys
s = json.load(sys.stdin)
assert s["status"] == "in_progress"
assert s["current_index"] == 0
assert s["ticket_ids"] == ["TRI-9100","TRI-9101","TRI-9102"]
for tid in s["ticket_ids"]:
    assert s["tickets"][tid]["status"] == "not_started"
'

# Advance ticket 1 through in_progress → completed.
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9100 --status in_progress --started-now >/dev/null
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9100 --status completed --finished-now \
    --branch TRI-9100-feat --pr "https://example.com/pr/1" --lint pass --test pass >/dev/null

# Verify current_index advanced.
bash "$CHAIN" get --run-id "$RID" | python3 -c '
import json, sys
s = json.load(sys.stdin)
ci = s["current_index"]
assert ci == 1, "expected current_index=1, got " + str(ci)
assert s["tickets"]["TRI-9100"]["status"] == "completed"
assert s["tickets"]["TRI-9100"]["pr_url"] == "https://example.com/pr/1"
'

# Advance ticket 2 and 3.
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9101 --status completed --finished-now --branch TRI-9101-feat --pr "https://example.com/pr/2" --lint pass --test pass >/dev/null
bash "$CHAIN" update-ticket --run-id "$RID" --ticket TRI-9102 --status completed --finished-now --branch TRI-9102-feat --pr "https://example.com/pr/3" --lint pass --test pass >/dev/null

# Close the run.
bash "$CHAIN" close --run-id "$RID" --terminal-status completed >/dev/null

# Verify terminal state.
bash "$CHAIN" get --run-id "$RID" | python3 -c '
import json, sys
s = json.load(sys.stdin)
assert s["status"] == "completed"
assert s["current_index"] == 3
for tid in s["ticket_ids"]:
    assert s["tickets"][tid]["status"] == "completed"
'

# Confirm not listed as interrupted anymore.
RID="$RID" bash "$CHAIN" list-interrupted | RID="$RID" python3 -c '
import json, sys, os
j = json.load(sys.stdin)
rid = os.environ.get("RID","")
for r in j.get("runs", []):
    assert r["run_id"] != rid, "closed run should not be listed"
'

echo "e2e-happy: OK"
