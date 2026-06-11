#!/usr/bin/env bash
# Error-path and scheduling-guard coverage for band-run.sh + parse_band_config.
# Complements test-band-run-e2e-happy.sh: that one walks the green path; this
# one asserts every contract violation is rejected with its error code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BAND="$REPO_ROOT/core/scripts/bash/band-run.sh"
COMMON="$REPO_ROOT/core/scripts/bash/common.sh"

cd "$REPO_ROOT"

fail() { echo "FAIL: $1" >&2; exit 1; }

# expect_err <code> <label> -- <band-run args...>
expect_err() {
    local code="$1" label="$2"; shift 3
    local stderr
    if stderr=$(bash "$BAND" "$@" 2>&1 >/dev/null); then
        fail "$label: expected failure with $code, got exit 0"
    fi
    echo "$stderr" | grep -q "\"$code\"" || fail "$label: expected $code, got: $stderr"
}

# ── parse_band_config ───────────────────────────────────────────────────────

cfg() { printf '%s\n' "$1" > "$TMP_CFG"; bash -c "source '$COMMON' && parse_band_config '$TMP_CFG'"; }
TMP_CFG=$(mktemp "${TMPDIR:-/tmp}/band-cfg-XXXXXX.yml")
[ "$(bash -c "source '$COMMON' && parse_band_config /nonexistent.yml")" = "3" ] || fail "config: missing file should default to 3"
[ "$(cfg 'project:
  name: x')" = "3" ] || fail "config: missing band section should default to 3"
[ "$(cfg 'band:
  max_parallel: 5')" = "5" ] || fail "config: explicit value not read"
[ "$(cfg 'workflow:
  max_parallel: 7
band:
  max_parallel: 2')" = "2" ] || fail "config: must ignore max_parallel outside band section"
[ "$(cfg 'band:
  max_parallel: 4   # comment')" = "4" ] || fail "config: trailing comment not stripped"
[ "$(cfg 'band:
  max_parallel: 0')" = "3" ] || fail "config: 0 should fall back to 3"
[ "$(cfg 'band:
  max_parallel: 9')" = "3" ] || fail "config: 9 should fall back to 3"
[ "$(cfg 'band:
  max_parallel: lots')" = "3" ] || fail "config: garbage should fall back to 3"
rm -f "$TMP_CFG"

# ── init validation ─────────────────────────────────────────────────────────

RECON=$(mktemp "${TMPDIR:-/tmp}/recon-err-XXXXXX.md")
echo "# Epic Recon" > "$RECON"

GOOD_ISSUE='{"id":"TRI-9301","title":"A","branch":"b1","worktree":"w1","complexity":"low","model":"sonnet","wave":0,"depends_on":[]}'

expect_err ERR_BAD_INPUT "init missing flags" -- init --parent TRI-9300
expect_err ERR_MALFORMED_TOKEN "init bad parent id" -- init --parent tri9300 --issues "[$GOOD_ISSUE]" --recon "$RECON"
expect_err ERR_RECON_MISSING "init missing recon" -- init --parent TRI-9300 --issues "[$GOOD_ISSUE]" --recon /nonexistent/recon.md
expect_err ERR_COUNT_ZERO "init empty issues" -- init --parent TRI-9300 --issues '[]' --recon "$RECON"
expect_err ERR_BAD_INPUT "init issue missing keys" -- init --parent TRI-9300 --issues '[{"id":"TRI-9301","title":"A"}]' --recon "$RECON"
expect_err ERR_BAD_INPUT "init unknown dependency" -- init --parent TRI-9300 \
    --issues '[{"id":"TRI-9301","title":"A","branch":"b","worktree":"w","complexity":"low","model":"sonnet","wave":0,"depends_on":["TRI-9999"]}]' --recon "$RECON"
expect_err ERR_BAD_INPUT "init duplicate ids" -- init --parent TRI-9300 \
    --issues "[$GOOD_ISSUE,$GOOD_ISSUE]" --recon "$RECON"
expect_err ERR_BAD_INPUT "init bad complexity" -- init --parent TRI-9300 \
    --issues '[{"id":"TRI-9301","title":"A","branch":"b","worktree":"w","complexity":"extreme","model":"sonnet","wave":0,"depends_on":[]}]' --recon "$RECON"
expect_err ERR_BAD_INPUT "init bad max-parallel" -- init --parent TRI-9300 --issues "[$GOOD_ISSUE]" --recon "$RECON" --max-parallel 9

MANY=$(python3 -c '
import json
print(json.dumps([{"id": f"TRI-{i}", "title": "t", "branch": f"b{i}", "worktree": f"w{i}",
                   "complexity": "low", "model": "sonnet", "wave": 0, "depends_on": []}
                  for i in range(1, 18)]))
')
expect_err ERR_COUNT_EXCEEDED "init > 16 issues" -- init --parent TRI-9300 --issues "$MANY" --recon "$RECON"

expect_err ERR_RUN_NOT_FOUND "get unknown run" -- get --run-id 99999999T000000-NOPE-999

# ── step / issue transition guards (on a real run) ─────────────────────────

ISSUES='[
 {"id":"TRI-9301","title":"A","branch":"b1","worktree":"w1","complexity":"low","model":"sonnet","wave":0,"depends_on":[]},
 {"id":"TRI-9302","title":"B","branch":"b2","worktree":"w2","complexity":"low","model":"sonnet","wave":0,"depends_on":[]},
 {"id":"TRI-9303","title":"C","branch":"b3","worktree":"w3","complexity":"low","model":"sonnet","wave":1,"depends_on":["TRI-9301"]}
]'
INIT=$(bash "$BAND" init --parent TRI-9300 --issues "$ISSUES" --recon "$RECON" --chain '["specify","plan","implement"]' --max-parallel 2)
rm -f "$RECON"
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
trap 'rm -rf "$REPO_ROOT/specs/.band-runs/$RID"' EXIT

expect_err ERR_ISSUE_NOT_IN_RUN "step on unknown issue" -- update-step --run-id "$RID" --issue TRI-9999 --step specify --step-status running
expect_err ERR_BAD_STEP "unknown step" -- update-step --run-id "$RID" --issue TRI-9301 --step tasks --step-status running
expect_err ERR_BAD_STEP_TRANSITION "skip ahead in chain" -- update-step --run-id "$RID" --issue TRI-9301 --step implement --step-status running
expect_err ERR_BAD_STEP_TRANSITION "complete a non-running step" -- update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status step_complete

bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status running >/dev/null
expect_err ERR_BLOCKED_REQUIRES_QUESTION "blocked without question" -- update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status blocked

# blocked -> running resume, running -> running respawn, failed -> running retry are legal.
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status blocked --question "Which way?" >/dev/null
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status running >/dev/null
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status running >/dev/null
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status failed >/dev/null
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status running >/dev/null
bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step specify --step-status step_complete >/dev/null

# Walk TRI-9301 to the end of its chain for issue-status checks.
for s in plan implement; do
    bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step "$s" --step-status running >/dev/null
    bash "$BAND" update-step --run-id "$RID" --issue TRI-9301 --step "$s" --step-status step_complete >/dev/null
done

expect_err ERR_COMMIT_SHA_REQUIRED "committed without sha" -- update-issue --run-id "$RID" --issue TRI-9301 --status committed
expect_err ERR_COMMITTED_HEDGING "hedging concern on committed" -- update-issue --run-id "$RID" --issue TRI-9301 --status committed --commit-sha abc123 --concern "should I push now?"
expect_err ERR_BAD_TRANSITION "pending -> merged" -- update-issue --run-id "$RID" --issue TRI-9302 --status merged

bash "$BAND" update-issue --run-id "$RID" --issue TRI-9301 --status committed --commit-sha abc123 --lint pass --test pass >/dev/null
expect_err ERR_COMMIT_SHA_IMMUTABLE "sha change without rebase flag" -- update-issue --run-id "$RID" --issue TRI-9301 --status merged --commit-sha zzz999

# Rebase path: two increments legal, third hits the cap.
bash "$BAND" update-issue --run-id "$RID" --issue TRI-9301 --status merged --commit-sha def456 --increment-rebase --merged-sha m1 >/dev/null
bash "$BAND" update-issue --run-id "$RID" --issue TRI-9301 --status completed --commit-sha ghi789 --increment-rebase >/dev/null
expect_err ERR_REBASE_CAP "third rebase" -- update-issue --run-id "$RID" --issue TRI-9301 --status failed --commit-sha jkl000 --increment-rebase

# merged appended to integration.merged_issues exactly once.
bash "$BAND" get --run-id "$RID" | python3 -c '
import json, sys
s = json.load(sys.stdin)
assert s["integration"]["merged_issues"] == ["TRI-9301"], s["integration"]["merged_issues"]
assert s["issues"]["TRI-9301"]["rebase_count"] == 2
'

# blocked_by_failure only from pending; terminal issues freeze their steps.
bash "$BAND" update-issue --run-id "$RID" --issue TRI-9302 --status blocked_by_failure >/dev/null
expect_err ERR_BAD_TRANSITION "blocked_by_failure twice" -- update-issue --run-id "$RID" --issue TRI-9302 --status blocked_by_failure
expect_err ERR_ISSUE_TERMINAL "step on terminal issue" -- update-step --run-id "$RID" --issue TRI-9302 --step specify --step-status running

# next-ready: pause empties spawn/continue; dep_failed lists dependents of failed deps.
bash "$BAND" pause --run-id "$RID" --issue TRI-9303 --reason test >/dev/null
bash "$BAND" next-ready --run-id "$RID" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["paused"] is True
assert d["spawn"] == [] and d["continue"] == [], d
'
bash "$BAND" resume --run-id "$RID" >/dev/null

# After close, every mutation and the scheduler read are rejected.
bash "$BAND" close --run-id "$RID" --terminal-status aborted --reason test >/dev/null
expect_err ERR_RUN_CLOSED "update-issue after close" -- update-issue --run-id "$RID" --issue TRI-9303 --status failed
expect_err ERR_RUN_CLOSED "update-step after close" -- update-step --run-id "$RID" --issue TRI-9303 --step specify --step-status running
expect_err ERR_RUN_CLOSED "next-ready after close" -- next-ready --run-id "$RID"

echo "band-errors: OK"
