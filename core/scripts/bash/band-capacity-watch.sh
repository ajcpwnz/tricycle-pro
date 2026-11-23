#!/usr/bin/env bash
# band-capacity-watch.sh — idle-capacity detector for a /trc.band run.
#
# band-watchdog.sh watches RUNNING workers for anomalies and exits 0 the moment
# none are running (its line: "no running workers ... watch stopping"). That is
# precisely backwards for the failure this script exists to catch: the orchestrator
# drifting into long serial work (merges, browser proofs, debugging) while worker
# slots sit empty and tickets sit pending. The stall watchdog turns itself off at
# the exact instant idle capacity becomes the problem.
#
# This one fires when free slots exist AND schedulable issues exist, and it does
# NOT exit on zero running. It exits only when the run is genuinely drained --
# nothing running and nothing left to schedule.
#
# Launch via the Monitor tool with persistent: true. Each stdout line is an event.
#
# Usage: band-capacity-watch.sh --run-id <id> [--interval 60] [--grace-sec 180]
#                               [--repeat-sec 600]
#
#   --grace-sec   how long the idle condition must hold before the first alert,
#                 so the seconds between a worker's report and its next
#                 instruction do not trip it.
#   --repeat-sec  re-alert cadence while capacity stays idle. It escalates rather
#                 than going quiet, because a single ignorable line is how the
#                 original 74-minute idle window went unnoticed.
#
# Implemented in Python so it does not depend on bash 4 (macOS ships bash 3.2).
set -euo pipefail

RUN_ID=""; INTERVAL=60; GRACE_SEC=180; REPEAT_SEC=600
while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --grace-sec) GRACE_SEC="${2:-}"; shift 2 ;;
    --repeat-sec) REPEAT_SEC="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RUN_ID" ] || { echo "band-capacity-watch: --run-id required" >&2; exit 2; }

# Run state lives under the MAIN checkout, never a worktree. `--show-toplevel`
# returns the worktree you happen to be standing in, so it finds nothing when the
# watch is armed from one; `--git-common-dir` always points at the main repo's
# .git, whose parent is the checkout that owns specs/.band-runs.
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$GIT_COMMON_DIR" ]; then
  REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  REPO_ROOT="$(pwd)"
fi

REPO_ROOT="$REPO_ROOT" RUN_ID="$RUN_ID" INTERVAL="$INTERVAL" \
GRACE_SEC="$GRACE_SEC" REPEAT_SEC="$REPEAT_SEC" python3 <<'PY'
import json, os, sys, time

repo = os.environ["REPO_ROOT"]
run_id = os.environ["RUN_ID"]
interval = int(os.environ["INTERVAL"])
grace = int(os.environ["GRACE_SEC"])
repeat = int(os.environ["REPEAT_SEC"])

state_path = os.path.join(repo, "specs", ".band-runs", run_id, "state.json")

TERMINAL = {"merged", "completed", "failed", "skipped", "blocked_by_failure"}

def snapshot():
    with open(state_path) as fh:
        state = json.load(fh)
    issues = state.get("issues", {})
    if isinstance(issues, list):
        issues = {i.get("id", str(n)): i for n, i in enumerate(issues)}
    running, awaiting, pending = [], [], []
    for key, issue in issues.items():
        status = issue.get("status")
        if status in TERMINAL:
            continue
        if status == "committed":
            # worker is done; the orchestrator owns the merge. Not a slot holder,
            # and not schedulable work either.
            continue
        if issue.get("step_status") == "running":
            running.append(key)
        elif status == "pending":
            pending.append(key)
        else:
            # in_progress with a finished step: the worker reported and is waiting
            # for its next instruction. This is the most easily missed form of idle.
            awaiting.append(key)
    return state.get("max_parallel", 3), running, awaiting, pending

idle_since = None
last_alert = None

while True:
    try:
        max_parallel, running, awaiting, pending = snapshot()
    except Exception as exc:
        print(f"CAPACITY WATCH: cannot read state ({exc}) — retrying", flush=True)
        time.sleep(interval)
        continue

    schedulable = awaiting + pending
    free = max_parallel - len(running)

    if not running and not schedulable:
        print("CAPACITY WATCH: run drained (nothing running, nothing schedulable) — stopping",
              flush=True)
        sys.exit(0)

    if free > 0 and schedulable:
        now = time.time()
        if idle_since is None:
            idle_since = now
        held = int(now - idle_since)
        due = last_alert is None or (now - last_alert) >= repeat
        if held >= grace and due:
            detail = []
            if awaiting:
                detail.append("awaiting next instruction: " + ", ".join(sorted(awaiting)))
            if pending:
                detail.append(f"{len(pending)} never started")
            print(
                f"CAPACITY IDLE {held}s: {len(running)}/{max_parallel} workers running, "
                f"{free} slot(s) free, {len(schedulable)} schedulable "
                f"({'; '.join(detail)}) — SPAWN OR CONTINUE NOW",
                flush=True,
            )
            last_alert = now
    else:
        idle_since = None
        last_alert = None

    time.sleep(interval)
PY
