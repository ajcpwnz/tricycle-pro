#!/usr/bin/env bash
# band-watchdog.sh — long-running stall detector for a /trc.band run.
#
# Launch via the Monitor tool: each stdout line is an event. Polls
# band-reconcile.sh every --interval seconds and emits ONE line the first time
# an issue becomes phantom / stalled / finished_unrecorded (deduped; re-emits if
# a cleared condition recurs). Exits 0 when no issue is `running` (run drained or
# closed) so the Monitor stops cleanly without a manual TaskStop.
#
# Detection (agent sidecar + transcript mtime + BOTH progress-file locations)
# lives in band-reconcile.sh. This replaces the fragile per-step watchdog that
# hard-coded one progress path and produced false positives.
#
# Usage: band-watchdog.sh --run-id <id> [--interval 60] [--idle-sec 420]
# Implemented in Python so it does not depend on bash 4 (macOS ships bash 3.2).
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_ID=""; INTERVAL=60; IDLE_SEC=420
while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --idle-sec) IDLE_SEC="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RUN_ID" ] || { echo "band-watchdog: --run-id required" >&2; exit 2; }

SCRIPT_DIR="$SCRIPT_DIR" RUN_ID="$RUN_ID" INTERVAL="$INTERVAL" IDLE_SEC="$IDLE_SEC" python3 <<'PY'
import json, os, subprocess, sys, time

script_dir = os.environ["SCRIPT_DIR"]
run_id = os.environ["RUN_ID"]
interval = int(os.environ["INTERVAL"])
idle = int(os.environ["IDLE_SEC"])
reconcile = os.path.join(script_dir, "band-reconcile.sh")

seen = set()
while True:
    try:
        raw = subprocess.run(["bash", reconcile, "--run-id", run_id, "--idle-sec", str(idle)],
                             capture_output=True, text=True, timeout=120).stdout
        rec = json.loads(raw)
    except Exception:
        time.sleep(interval); continue

    findings = {}
    for f in rec.get("phantom", []):
        findings["phantom:" + f["issue"]] = (
            f"WATCHDOG PHANTOM: {f['issue']} ({f.get('step')}) — {f.get('reason','')}")
    for f in rec.get("stalled", []):
        findings["stalled:" + f["issue"]] = (
            f"WATCHDOG STALL: {f['issue']} ({f.get('step')}) transcript idle "
            f"{f.get('idle_sec')}s — likely dead/hung, respawn")
    for f in rec.get("finished_unrecorded", []):
        findings["finished:" + f["issue"]] = (
            f"WATCHDOG: {f['issue']} finished step {f.get('step')} (phase={f.get('phase')}) "
            f"but state still running — record + advance it")

    for key, msg in findings.items():
        if key not in seen:
            print(msg, flush=True)
            seen.add(key)
    seen.intersection_update(findings.keys())  # forget cleared conditions

    if not rec.get("running"):
        print("WATCHDOG: no running workers (run drained or closed) — watch stopping", flush=True)
        sys.exit(0)
    time.sleep(interval)
PY
