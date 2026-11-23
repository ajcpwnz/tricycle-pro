#!/usr/bin/env bash
# chain-reconcile.sh and band-reconcile.sh classify every running worker as
# phantom, stalled, finished_unrecorded or live, and skip finished ones.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP=$(mktemp -d)
# The reconcilers look for agent transcripts under /tmp/claude-*/**/tasks/.
TASKS="/tmp/claude-trc-reconcile-test-$$/session/tasks"
mkdir -p "$TASKS"
trap 'rm -rf "$TMP" "/tmp/claude-trc-reconcile-test-$$"' EXIT

mkdir -p "$TMP/core/scripts/bash"
cp "$REPO_ROOT/core/scripts/bash/chain-reconcile.sh" "$REPO_ROOT/core/scripts/bash/band-reconcile.sh" "$TMP/core/scripts/bash/"

LIVE="agent-live-$$"; OLD="agent-old-$$"
: > "$TASKS/$LIVE.output"
: > "$TASKS/$OLD.output"
touch -t 202001010000 "$TASKS/$OLD.output"

fail() { echo "FAIL: $1"; exit 1; }
check() { # <json> <python assertion>
  printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); assert $2, d" || fail "$2"
}

# ── chain ──
RUN="$TMP/specs/.chain-runs/r1"; mkdir -p "$RUN"
cat > "$RUN/state.json" <<'JSON'
{"tickets": {
  "T-1": {"status": "in_progress"},
  "T-2": {"status": "in_progress"},
  "T-3": {"status": "in_progress"},
  "T-4": {"status": "in_progress"},
  "T-5": {"status": "committed"}
}}
JSON
echo "$LIVE" > "$RUN/T-2.agent"
echo "$OLD" > "$RUN/T-3.agent"
printf '{"phase":"committed"}\n' > "$RUN/T-4.progress"
OUT=$(bash "$TMP/core/scripts/bash/chain-reconcile.sh" --run-id r1 --idle-sec 600)
check "$OUT" 'sorted(d["running"]) == ["T-1","T-2","T-3","T-4"]'
check "$OUT" '[x["ticket"] for x in d["phantom"]] == ["T-1"]'
check "$OUT" '[x["ticket"] for x in d["live"]] == ["T-2"]'
check "$OUT" '[x["ticket"] for x in d["stalled"]] == ["T-3"]'
check "$OUT" '[x["ticket"] for x in d["finished_unrecorded"]] == ["T-4"]'
check "$OUT" 'd["actionable"] is True'

# ── band ──
RUN="$TMP/specs/.band-runs/b1"; mkdir -p "$RUN"
cat > "$RUN/state.json" <<'JSON'
{"issues": {
  "I-1": {"status": "in_progress", "step_status": "running", "current_step": "plan"},
  "I-2": {"status": "in_progress", "step_status": "running", "current_step": "implement"},
  "I-3": {"status": "in_progress", "step_status": "running", "current_step": "plan"},
  "I-4": {"status": "in_progress", "step_status": "running", "current_step": "plan"},
  "I-5": {"status": "in_progress", "step_status": "step_complete", "current_step": "plan"}
}}
JSON
echo "$LIVE" > "$RUN/I-2.agent"
echo "$OLD" > "$RUN/I-3.agent"
printf '{"phase":"plan_complete"}\n' > "$RUN/I-4.progress"
OUT=$(bash "$TMP/core/scripts/bash/band-reconcile.sh" --run-id b1 --idle-sec 600)
check "$OUT" 'sorted(d["running"]) == ["I-1","I-2","I-3","I-4"]'
check "$OUT" '[x["issue"] for x in d["phantom"]] == ["I-1"]'
check "$OUT" '[x["issue"] for x in d["live"]] == ["I-2"]'
check "$OUT" '[x["issue"] for x in d["stalled"]] == ["I-3"]'
check "$OUT" '[x["issue"] for x in d["finished_unrecorded"]] == ["I-4"]'

echo "reconcile: OK"
