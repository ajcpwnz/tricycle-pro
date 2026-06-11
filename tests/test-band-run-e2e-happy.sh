#!/usr/bin/env bash
# End-to-end happy path for band-run.sh helper.
# Exercises init → next-ready wave scheduling → update-step cycles →
# update-issue committed/merged → wave-2 admission → close.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BAND="$REPO_ROOT/core/scripts/bash/band-run.sh"

cd "$REPO_ROOT"

RECON=$(mktemp "${TMPDIR:-/tmp}/recon-e2e-XXXXXX.md")
echo "# Epic Recon: e2e fixture" > "$RECON"

ISSUES='[
 {"id":"TRI-9200","title":"A","branch":"TRI-9200-a","worktree":".worktrees/TRI-9200-a","complexity":"low","model":"sonnet","wave":0,"depends_on":[]},
 {"id":"TRI-9201","title":"B","branch":"TRI-9201-b","worktree":".worktrees/TRI-9201-b","complexity":"medium","model":"sonnet","wave":0,"depends_on":[]},
 {"id":"TRI-9202","title":"C","branch":"TRI-9202-c","worktree":".worktrees/TRI-9202-c","complexity":"high","model":"opus","wave":1,"depends_on":["TRI-9200","TRI-9201"]}
]'

INIT=$(bash "$BAND" init --parent TRI-9199 --issues "$ISSUES" --recon "$RECON" \
    --chain '["specify","plan","implement"]' --max-parallel 2)
rm -f "$RECON"
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
[ -n "$RID" ] || { echo "no run_id in init output" >&2; exit 1; }
trap 'rm -rf "$REPO_ROOT/specs/.band-runs/$RID"' EXIT

# Recon was copied into the run dir.
[ -f "$REPO_ROOT/specs/.band-runs/$RID/recon.md" ] || { echo "recon.md not copied" >&2; exit 1; }

# Wave 1 (index 0) spawns; wave-2 issue gated.
bash "$BAND" next-ready --run-id "$RID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["spawn"] == ["TRI-9200", "TRI-9201"], d["spawn"]
assert d["slots"] == 2
'

# Walk one issue through all chain steps, then commit + merge it.
walk_issue() {
    local iid="$1" sha="$2" msha="$3"
    local step
    for step in specify plan implement; do
        bash "$BAND" update-step --run-id "$RID" --issue "$iid" --step "$step" --step-status running >/dev/null
        # Worker writes a progress event at step end (orchestrator contract).
        printf '{"phase":"%s_complete","issue_id":"%s"}\n' "$step" "$iid" \
            > "$REPO_ROOT/specs/.band-runs/$RID/$iid.progress"
        bash "$BAND" update-step --run-id "$RID" --issue "$iid" --step "$step" --step-status step_complete >/dev/null
    done
    bash "$BAND" update-issue --run-id "$RID" --issue "$iid" --status committed \
        --commit-sha "$sha" --lint pass --test pass >/dev/null
    bash "$BAND" update-issue --run-id "$RID" --issue "$iid" --status merged --merged-sha "$msha" >/dev/null
}

walk_issue TRI-9200 sha9200 m9200

# Progress event readable.
bash "$BAND" progress --run-id "$RID" --issue TRI-9200 | grep -q 'implement_complete' \
    || { echo "progress event not readable" >&2; exit 1; }

# Wave-2 issue still gated: TRI-9201 pending keeps wave 0 undrained.
bash "$BAND" next-ready --run-id "$RID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert "TRI-9202" not in d["spawn"], "wave gating violated: " + str(d["spawn"])
assert d["spawn"] == ["TRI-9201"], d["spawn"]
'

walk_issue TRI-9201 sha9201 m9201

# Now wave 2 is admitted.
bash "$BAND" next-ready --run-id "$RID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["spawn"] == ["TRI-9202"], d["spawn"]
'

walk_issue TRI-9202 sha9202 m9202

# Mark everything completed, record the integration push, close.
for iid in TRI-9200 TRI-9201 TRI-9202; do
    bash "$BAND" update-issue --run-id "$RID" --issue "$iid" --status completed --finished-now >/dev/null
done
bash "$BAND" update-integration --run-id "$RID" --pr-url "https://example.com/pr/9" --pushed-now >/dev/null
bash "$BAND" close --run-id "$RID" --terminal-status completed --reason "epic shipped" >/dev/null

# Verify terminal state.
bash "$BAND" get --run-id "$RID" | python3 -c '
import json, sys
s = json.load(sys.stdin)
assert s["status"] == "completed"
assert s["integration"]["merged_issues"] == ["TRI-9200", "TRI-9201", "TRI-9202"]
assert s["integration"]["pr_url"] == "https://example.com/pr/9"
assert s["integration"]["pushed_at"]
for iid, t in s["issues"].items():
    assert t["status"] == "completed", f"{iid}: {t['status']}"
    assert t["steps_completed"] == ["specify", "plan", "implement"]
'

# Progress files removed by close.
ls "$REPO_ROOT/specs/.band-runs/$RID/"*.progress 2>/dev/null && { echo "progress files not removed" >&2; exit 1; }

# Closed run not listed as interrupted.
RID="$RID" bash "$BAND" list-interrupted | RID="$RID" python3 -c '
import json, sys, os
j = json.load(sys.stdin)
rid = os.environ.get("RID", "")
for r in j.get("runs", []):
    assert r["run_id"] != rid, "closed run should not be listed"
'

echo "band-e2e-happy: OK"
