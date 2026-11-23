#!/usr/bin/env bash
# chain-reconcile.sh — detect divergence between a /trc.chain run's state and
# reality. Chain flavor of band-reconcile.sh.
#
# Hardening for the failure mode where a ticket is marked `in_progress` in
# state.json but no worker is actually executing it (missed spawn / dead
# worker), which otherwise stays silent until a human asks "status".
#
# Chain differs from band: a chain worker runs /trc.plan and /trc.implement in
# one go (no per-step control), so "running" means ticket status == in_progress
# and the terminal progress marker is `committed`.
#
# Reads the run's state.json + per-ticket agent sidecars (<run>/<ticket>.agent,
# written by the orchestrator at spawn time) + progress files, and classifies
# every `in_progress` ticket into one of:
#   phantom             — running, but no .agent sidecar => never spawned / lost
#   stalled             — running, agent transcript idle > --idle-sec => dead/hung
#   finished_unrecorded — a `committed` progress phase exists (main run dir OR
#                         the worktree copy) but state still says in_progress =>
#                         worker done, orchestrator hasn't recorded yet
#   live                — transcript advancing within idle window => healthy
#
# Output: one JSON object on stdout. Exit 0 always (it's an inspector).
#   {"run_id":..., "running":[...], "phantom":[...], "stalled":[...],
#    "finished_unrecorded":[...], "live":[...], "actionable": <bool>}
#
# Usage: chain-reconcile.sh --run-id <id> [--idle-sec 420]
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd "$SCRIPT_DIR/../../.." && pwd)"

RUN_ID=""
IDLE_SEC=420
while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --idle-sec) IDLE_SEC="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RUN_ID" ] || { echo '{"error":"--run-id required"}' >&2; exit 2; }

RUN_DIR="$REPO_ROOT/specs/.chain-runs/$RUN_ID"
[ -f "$RUN_DIR/state.json" ] || { printf '{"error":"run not found: %s"}\n' "$RUN_ID" >&2; exit 2; }

REPO_ROOT="$REPO_ROOT" RUN_DIR="$RUN_DIR" IDLE_SEC="$IDLE_SEC" RUN_ID="$RUN_ID" python3 <<'PY'
import json, os, glob, time

run_dir = os.environ["RUN_DIR"]
idle = int(os.environ["IDLE_SEC"])
run_id = os.environ["RUN_ID"]

state = json.load(open(os.path.join(run_dir, "state.json")))
tickets = state.get("tickets", {})

def transcript_age(agent_id):
    # Background-agent transcript lands under the session tmp dir; agentId is
    # unique. The session dir nests project-slug + session-uuid under claude-*,
    # so tasks/ is two segments deep — use recursive ** to match any depth (a
    # fixed-depth glob false-flags every live worker as phantom).
    hits = glob.glob(f"/private/tmp/claude-*/**/tasks/{agent_id}.output", recursive=True)
    hits += glob.glob(f"/tmp/claude-*/**/tasks/{agent_id}.output", recursive=True)
    if not hits:
        return None
    return time.time() - max(os.path.getmtime(h) for h in hits)

def progress_phase(ticket, worktree):
    # Workers write progress relative to their cwd (the worktree copy); the
    # canonical copy is in the main run dir. Check both, newest wins.
    phase = None
    for base in (run_dir, os.path.join(worktree or "", "specs", ".chain-runs", run_id)):
        p = os.path.join(base, f"{ticket}.progress")
        if os.path.isfile(p):
            try:
                phase = json.load(open(p)).get("phase", phase)
            except Exception:
                pass
    return phase

out = {"run_id": run_id, "running": [], "phantom": [], "stalled": [],
       "finished_unrecorded": [], "live": []}

for tid, info in tickets.items():
    if not isinstance(info, dict):
        continue
    # Only a live worker is `in_progress`; committed/pushed/merged/etc. are
    # already fire-and-report-done and are not "running".
    if info.get("status") != "in_progress":
        continue
    out["running"].append(tid)
    wt = info.get("worktree_path")
    phase = progress_phase(tid, wt)
    if phase == "committed":
        out["finished_unrecorded"].append({"ticket": tid, "phase": phase})
        continue
    agent_file = os.path.join(run_dir, f"{tid}.agent")
    if not os.path.isfile(agent_file):
        out["phantom"].append({"ticket": tid,
                               "reason": "running but no .agent sidecar (never spawned or record lost)"})
        continue
    agent_id = open(agent_file).read().strip()
    age = transcript_age(agent_id)
    if age is None:
        out["phantom"].append({"ticket": tid, "agent": agent_id,
                               "reason": "agent sidecar present but no transcript found"})
    elif age > idle:
        out["stalled"].append({"ticket": tid, "agent": agent_id, "idle_sec": int(age)})
    else:
        out["live"].append({"ticket": tid, "agent": agent_id, "idle_sec": int(age)})

out["actionable"] = bool(out["phantom"] or out["stalled"] or out["finished_unrecorded"])
print(json.dumps(out))
PY
