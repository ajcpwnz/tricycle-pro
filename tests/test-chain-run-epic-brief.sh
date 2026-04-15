#!/usr/bin/env bash
# Epic brief handling (US4, clarification Q2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAIN="$REPO_ROOT/core/scripts/bash/chain-run.sh"

cd "$REPO_ROOT"

# Create a brief file.
BRIEF=$(mktemp)
trap 'rm -f "$BRIEF"; [ -n "${RID:-}" ] && rm -rf "$REPO_ROOT/specs/.chain-runs/$RID"' EXIT
printf '# Shared epic brief\n\nAll tickets build up the same subsystem.\n' > "$BRIEF"

# Init with --brief.
INIT=$(bash "$CHAIN" init --ids '["TRI-9400","TRI-9401"]' --brief "$BRIEF")
RID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')

# Verify brief_path in init output.
BP=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("brief_path") or "")')
[ -n "$BP" ] || { echo "brief_path was null" >&2; exit 1; }

# Verify the brief file was copied into the run dir.
[ -f "$REPO_ROOT/$BP" ] || { echo "copied brief not found at $BP" >&2; exit 1; }
grep -q "Shared epic brief" "$REPO_ROOT/$BP" || { echo "copied brief content wrong" >&2; exit 1; }

# Verify state.json records the brief path.
bash "$CHAIN" get --run-id "$RID" | python3 -c '
import json, sys, os
s = json.load(sys.stdin)
assert s["epic_brief_path"], "epic_brief_path should be set"
assert "epic-brief.md" in s["epic_brief_path"]
'

# Negative: missing brief path.
set +e
ERR_OUT=$(bash "$CHAIN" init --ids '["TRI-9500"]' --brief /nonexistent/brief.md 2>&1 1>/dev/null)
ERR_EXIT=$?
set -e
[ "$ERR_EXIT" -eq 2 ] || { echo "expected exit 2 for missing brief, got $ERR_EXIT" >&2; exit 1; }
echo "$ERR_OUT" | grep -q ERR_BRIEF_MISSING || { echo "expected ERR_BRIEF_MISSING, got: $ERR_OUT" >&2; exit 1; }

echo "epic-brief: OK"
