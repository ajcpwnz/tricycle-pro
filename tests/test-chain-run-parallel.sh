#!/usr/bin/env bash
# chain-run-parallel.test.sh — hermetic self-test for the /trc.chain parallel
# scheduler. Drives chain-run.sh subcommands ONLY: no Agent spawns,
# no Linear, no worktrees. Asserts slot cap, dependency gating, serial-
# equivalence at cap 1, dep_failed cascade, and cycle / endpoint rejection.
# Cleans up its own run dirs on exit.
#
# Run: bash tests/test-chain-run-parallel.sh
set -uo pipefail

# Husky may export GIT_* pointing at the real repo internals; chain-run.sh calls
# `git rev-parse` for the repo root. Clear inherited git env so those calls
# resolve normally (self-test hygiene — see hook-selftests-must-unset-git-env).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd "$SCRIPT_DIR/.." && pwd)"
CR="$REPO_ROOT/core/scripts/bash/chain-run.sh"
RUNS_DIR="$REPO_ROOT/specs/.chain-runs"

# init_run runs inside a command substitution (a subshell), so a shell-array
# append would not survive to the parent. Record created run-ids in a temp file
# instead — file writes DO persist out of the subshell — so cleanup sees them.
RUNLIST="$(mktemp)"
cleanup() {
  local r
  if [ -f "$RUNLIST" ]; then
    while IFS= read -r r; do
      [ -n "${r:-}" ] && rm -rf "${RUNS_DIR:?}/$r"
    done < "$RUNLIST"
    rm -f "$RUNLIST"
  fi
}
trap cleanup EXIT

FAILED=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAILED=1; }

field() { python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }

init_run() {
  local out rid
  out=$(bash "$CR" init "$@")
  rid=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')
  printf '%s\n' "$rid" >> "$RUNLIST"
  printf '%s' "$rid"
}
nr()  { bash "$CR" next-ready --run-id "$1"; }
upd() { bash "$CR" update-ticket --run-id "$1" --ticket "$2" --status "$3" "${@:4}" >/dev/null; }

# ── 1: independent tickets, cap 2 → spawn first two, slots 2 ──
RID=$(init_run --ids '["T-1","T-2","T-3"]' --max-parallel 2)
SPAWN=$(nr "$RID" | field spawn)
[ "$SPAWN" = '["T-1", "T-2"]' ] && pass "cap2: spawns first two" || fail "cap2 spawn=$SPAWN"

# ── 2: both running → slots 0, no spawn ──
upd "$RID" T-1 in_progress --started-now
upd "$RID" T-2 in_progress --started-now
OUT=$(nr "$RID"); SLOTS=$(printf '%s' "$OUT" | field slots); SPAWN=$(printf '%s' "$OUT" | field spawn)
{ [ "$SLOTS" = "0" ] && [ "$SPAWN" = "[]" ]; } && pass "cap2: full slots → no spawn" || fail "cap2 slots=$SLOTS spawn=$SPAWN"

# ── 3: dependency gating — T-3 blocked-by T-1 ──
RID=$(init_run --ids '["T-1","T-2","T-3"]' --deps '{"T-3":["T-1"]}' --max-parallel 3)
BLOCKED=$(nr "$RID" | field blocked)
[ "$BLOCKED" = '["T-3"]' ] && pass "dep: T-3 blocked initially" || fail "dep blocked=$BLOCKED"
upd "$RID" T-1 in_progress --started-now
upd "$RID" T-1 committed --commit-sha aaa --branch b1
upd "$RID" T-1 pushed --pr http://x/1
upd "$RID" T-1 merged
SPAWN=$(nr "$RID" | field spawn)
printf '%s' "$SPAWN" | grep -q "T-3" && pass "dep: T-3 spawnable after blocker merged" || fail "dep spawn=$SPAWN"

# ── 3b: a committed blocker is not a deadlock ──
RID=$(init_run --ids '["D-1","D-2"]' --deps '{"D-2":["D-1"]}' --max-parallel 2)
upd "$RID" D-1 in_progress --started-now
upd "$RID" D-1 committed --commit-sha ddd --branch bd
DL=$(nr "$RID" | field deadlock)
[ "$DL" = "false" ] && pass "dep: committed blocker is not a deadlock" || fail "dep deadlock=$DL with committed blocker"

# ── 4: serial-equivalence at cap 1 ──
RID=$(init_run --ids '["S-1","S-2"]' --max-parallel 1)
SPAWN=$(nr "$RID" | field spawn)
[ "$SPAWN" = '["S-1"]' ] && pass "cap1: single spawn" || fail "cap1 spawn=$SPAWN"
upd "$RID" S-1 in_progress --started-now
SLOTS=$(nr "$RID" | field slots)
[ "$SLOTS" = "0" ] && pass "cap1: no slots while one runs" || fail "cap1 slots=$SLOTS"

# ── 5: dep_failed cascade ──
RID=$(init_run --ids '["T-1","T-3"]' --deps '{"T-3":["T-1"]}')
upd "$RID" T-1 in_progress --started-now
upd "$RID" T-1 failed --finished-now
DF=$(nr "$RID" | field dep_failed)
[ "$DF" = '["T-3"]' ] && pass "dep_failed: T-3 cascades on blocker failure" || fail "dep_failed=$DF"

# ── 6: cycle rejection at init ──
if bash "$CR" init --ids '["C-1","C-2"]' --deps '{"C-1":["C-2"],"C-2":["C-1"]}' >/dev/null 2>&1; then
  fail "cycle: init accepted a cycle"
else
  pass "cycle: init rejected (ERR_DEP_CYCLE)"
fi

# ── 7: endpoint-not-in-run rejection ──
if bash "$CR" init --ids '["C-1"]' --deps '{"C-1":["C-9"]}' >/dev/null 2>&1; then
  fail "endpoint: init accepted an out-of-run blocker"
else
  pass "endpoint: init rejected (ERR_DEP_ENDPOINT_NOT_IN_RUN)"
fi

# ── 8: default cap from chain.max_parallel (2) when --max-parallel omitted ──
RID=$(init_run --ids '["D-1","D-2","D-3"]')
SPAWN=$(nr "$RID" | field spawn)
[ "$SPAWN" = '["D-1", "D-2"]' ] && pass "default cap: 2 from config" || fail "default cap spawn=$SPAWN"

# ── 8b: ticket-count ceiling — default 8, raisable only via CHAIN_MAX_TICKETS ──
NINE='["N-1","N-2","N-3","N-4","N-5","N-6","N-7","N-8","N-9"]'
NINE_RAW="N-1,N-2,N-3,N-4,N-5,N-6,N-7,N-8,N-9"

if bash "$CR" parse-range "$NINE_RAW" >/dev/null 2>&1; then
  fail "ceiling: parse-range accepted 9 tickets at the default"
else
  pass "ceiling: parse-range rejects 9 at the default (ERR_COUNT_EXCEEDED)"
fi

if bash "$CR" init --ids "$NINE" >/dev/null 2>&1; then
  fail "ceiling: init accepted 9 tickets at the default"
else
  pass "ceiling: init rejects 9 at the default (ERR_COUNT_EXCEEDED)"
fi

if (export CHAIN_MAX_TICKETS=9; bash "$CR" parse-range "$NINE_RAW" >/dev/null 2>&1); then
  pass "ceiling: CHAIN_MAX_TICKETS=9 admits 9 through parse-range"
else
  fail "ceiling: CHAIN_MAX_TICKETS=9 did not raise the parse-range ceiling"
fi

# chain-run.sh is a child process, so the override must be exported to reach it —
# a `VAR=x func` prefix on a shell function would not.
NINE_OUT=$(export CHAIN_MAX_TICKETS=9; bash "$CR" init --ids "$NINE" --max-parallel 2 2>/dev/null) || NINE_OUT=""
if [ -n "$NINE_OUT" ]; then
  printf '%s' "$NINE_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])' >> "$RUNLIST"
  pass "ceiling: CHAIN_MAX_TICKETS=9 admits 9 through init"
else
  fail "ceiling: CHAIN_MAX_TICKETS=9 did not raise the init ceiling"
fi

# A garbage or zero override must fall back to the guard, never disable it.
if (export CHAIN_MAX_TICKETS=abc; bash "$CR" parse-range "$NINE_RAW" >/dev/null 2>&1); then
  fail "ceiling: non-numeric CHAIN_MAX_TICKETS disabled the guard"
else
  pass "ceiling: non-numeric CHAIN_MAX_TICKETS falls back to 8"
fi

if (export CHAIN_MAX_TICKETS=0; bash "$CR" parse-range "$NINE_RAW" >/dev/null 2>&1); then
  fail "ceiling: CHAIN_MAX_TICKETS=0 disabled the guard"
else
  pass "ceiling: CHAIN_MAX_TICKETS=0 falls back to 8"
fi

# ── 9: amended worker commit — a resumed worker that amends must be re-recordable ──
# A worker resumed via SendMessage commonly returns a NEW sha for the same commit.
# Refusing it left state.json pointing at a sha no longer on the branch, which the
# resume path then compares against `git rev-parse HEAD` and treats as a reason to
# discard correct work.
RID=$(init_run --ids '["A-1"]' --max-parallel 1)
upd "$RID" A-1 in_progress --started-now
upd "$RID" A-1 committed --commit-sha aaa111 --branch b1
if bash "$CR" update-ticket --run-id "$RID" --ticket A-1 --status committed --commit-sha bbb222 >/dev/null 2>&1; then
  SHA=$(bash "$CR" get --run-id "$RID" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tickets"]["A-1"]["commit_sha"])')
  [ "$SHA" = "bbb222" ] && pass "amend: re-record replaces the sha" || fail "amend sha=$SHA"
else
  fail "amend: committed -> committed with a new sha was rejected"
fi

# A re-record with NO new sha is still a no-op transition and must stay rejected,
# so an accidental double-record cannot silently pass.
if bash "$CR" update-ticket --run-id "$RID" --ticket A-1 --status committed >/dev/null 2>&1; then
  fail "amend: committed -> committed without a new sha was accepted"
else
  pass "amend: no-sha re-record still rejected"
fi

# Immutability must still hold on a FORWARD transition — pushed must not smuggle
# in a different sha.
upd "$RID" A-1 pushed --pr http://x/9
if bash "$CR" update-ticket --run-id "$RID" --ticket A-1 --status merged --commit-sha ccc333 >/dev/null 2>&1; then
  fail "amend: sha mutated on a forward transition"
else
  pass "amend: sha still immutable across forward transitions"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "chain-run-parallel.test.sh: FAILURES above"
  exit 1
fi
echo "chain-run-parallel.test.sh: all assertions passed"
exit 0
