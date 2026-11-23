#!/usr/bin/env bash
# band-reconcile.sh — detect divergence between /trc.band run state and reality.
#
# Hardening for the failure mode where an issue is marked `running` in state.json
# but no worker is actually executing it (missed spawn / dead worker), which
# otherwise stays silent until a human asks "status".
#
# Reads the run's state.json + the per-issue agent sidecars (<run>/<issue>.agent,
# written by the orchestrator at spawn time) + progress files, and classifies
# every NON-terminal `running` issue into one of:
#   phantom            — running, but no .agent sidecar  => never spawned / record lost
#   stalled            — running, agent transcript idle > --idle-sec  => dead/hung
#   finished_unrecorded — a *_complete / committed progress phase exists for the
#                         current step (in the main run dir OR the worktree copy)
#                         but state still says running => worker done, orchestrator
#                         hasn't recorded yet (this is the watchdog-false-positive case)
#   live               — transcript advancing within idle window => healthy
#
# Output: one JSON object on stdout. Exit 0 always (it's an inspector).
#   {"run_id":..., "running":[...], "phantom":[...], "stalled":[...],
#    "finished_unrecorded":[...], "live":[...], "actionable": <bool>}
#
# Usage: band-reconcile.sh --run-id <id> [--idle-sec 420]
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

RUN_DIR="$REPO_ROOT/specs/.band-runs/$RUN_ID"
[ -f "$RUN_DIR/state.json" ] || { printf '{"error":"run not found: %s"}\n' "$RUN_ID" >&2; exit 2; }

REPO_ROOT="$REPO_ROOT" RUN_DIR="$RUN_DIR" IDLE_SEC="$IDLE_SEC" RUN_ID="$RUN_ID" python3 <<'PY'
import json, os, glob, time

run_dir = os.environ["RUN_DIR"]
idle = int(os.environ["IDLE_SEC"])
run_id = os.environ["RUN_ID"]

TERMINAL = {"merged", "completed", "failed", "blocked_by_failure", "skipped"}

state = json.load(open(os.path.join(run_dir, "state.json")))
issues = state.get("issues", {})

def transcript_age(agent_id):
    # Background-agent transcript lands under the session tmp dir; agentId is unique.
    # The session dir nests project-slug + session-uuid under claude-*, so the
    # tasks/ dir is two segments deep, not one — use recursive ** to match any
    # depth (a fixed-depth glob false-flags every live worker as phantom).
    hits = glob.glob(f"/private/tmp/claude-*/**/tasks/{agent_id}.output", recursive=True)
    hits += glob.glob(f"/tmp/claude-*/**/tasks/{agent_id}.output", recursive=True)
    if not hits:
        return None
    return time.time() - max(os.path.getmtime(h) for h in hits)

def progress_phase(issue, worktree):
    # Workers write progress relative to their cwd (the worktree copy); the
    # canonical copy is in the main run dir. Check both, newest wins.
    phase = None
    for base in (run_dir, os.path.join(worktree or "", "specs", ".band-runs", run_id)):
        p = os.path.join(base, f"{issue}.progress")
        if os.path.isfile(p):
            try:
                phase = json.load(open(p)).get("phase", phase)
            except Exception:
                pass
    return phase

out = {"run_id": run_id, "running": [], "phantom": [], "stalled": [],
       "finished_unrecorded": [], "live": []}

for iid, info in issues.items():
    if not isinstance(info, dict):
        continue
    if info.get("status") in TERMINAL:
        continue
    if info.get("step_status") != "running":
        continue
    out["running"].append(iid)
    cur = info.get("current_step")
    wt = info.get("worktree")
    phase = progress_phase(iid, wt)
    # A worker that finished its step writes "<step>_complete" or "committed".
    done_markers = {f"{cur}_complete", "committed"} if cur else {"committed"}
    if phase in done_markers:
        out["finished_unrecorded"].append({"issue": iid, "step": cur, "phase": phase})
        continue
    agent_file = os.path.join(run_dir, f"{iid}.agent")
    if not os.path.isfile(agent_file):
        out["phantom"].append({"issue": iid, "step": cur,
                               "reason": "running but no .agent sidecar (never spawned or record lost)"})
        continue
    agent_id = open(agent_file).read().strip()
    age = transcript_age(agent_id)
    if age is None:
        out["phantom"].append({"issue": iid, "step": cur, "agent": agent_id,
                               "reason": "agent sidecar present but no transcript found"})
    elif age > idle:
        out["stalled"].append({"issue": iid, "step": cur, "agent": agent_id,
                               "idle_sec": int(age)})
    else:
        out["live"].append({"issue": iid, "step": cur, "agent": agent_id,
                            "idle_sec": int(age)})

out["actionable"] = bool(out["phantom"] or out["stalled"] or out["finished_unrecorded"])
print(json.dumps(out))
PY
