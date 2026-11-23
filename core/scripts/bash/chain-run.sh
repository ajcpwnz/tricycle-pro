#!/usr/bin/env bash
# chain-run.sh — helper for /trc.chain orchestrator
# Manages on-disk state for chain runs under specs/.chain-runs/<run-id>/.
# See specs/TRI-27-trc-chain-orchestrator/contracts/chain-run-helper.md for contract.
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REPO_ROOT="$(get_repo_root)"
CHAIN_RUNS_DIR="$REPO_ROOT/specs/.chain-runs"

# ─── Errors ──────────────────────────────────────────────────────────────

err_json() {
    local code="$1"; local msg="$2"
    printf '{"error":"%s","code":"%s"}\n' "$(json_escape "$msg")" "$code" >&2
}

# ─── State primitives ────────────────────────────────────────────────────

chain_run_iso8601_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

chain_run_generate_run_id() {
    local first_ticket="$1"
    local stamp rand
    stamp=$(date -u +"%Y%m%dT%H%M%S")
    # 4-hex-digit random suffix so rapid successive invocations (tests) don't collide.
    rand=$(printf '%04x' $((RANDOM & 0xFFFF)))
    printf '%s%s-%s' "$stamp" "$rand" "$first_ticket"
}

# Atomic write: state JSON to ${run_dir}/state.json.tmp then mv.
chain_run_write_state_atomic() {
    local run_dir="$1"; local state_json="$2"
    local tmp="${run_dir}/state.json.tmp"
    printf '%s\n' "$state_json" > "$tmp"
    mv "$tmp" "${run_dir}/state.json"
}

# Read and echo state JSON. Exit 4 with ERR_RUN_NOT_FOUND if missing.
chain_run_read_state() {
    local run_dir="$1"
    local state_file="${run_dir}/state.json"
    if [[ ! -f "$state_file" ]]; then
        err_json "ERR_RUN_NOT_FOUND" "run not found: $(basename "$run_dir")"
        return 4
    fi
    cat "$state_file"
}

# Resolve run directory from run-id.
chain_run_dir_for_id() {
    printf '%s/%s' "$CHAIN_RUNS_DIR" "$1"
}

# Ticket-count ceiling for one chain run. Default 8 (the quality guard: a run
# wider than that is usually a band, not a chain). CHAIN_MAX_TICKETS raises it
# for a single invocation when the operator has explicitly asked for one wider
# run; it is deliberately env-only so the default guard stays 8 for everyone.
chain_run_max_tickets() {
    local v="${CHAIN_MAX_TICKETS:-8}"
    case "$v" in
        ''|*[!0-9]*) v=8 ;;
    esac
    if (( v < 1 )); then v=8; fi
    printf '%s' "$v"
}

# Read chain.max_parallel from tricycle.config.yml. Anchors on a TOP-LEVEL
# `chain:` key (column 0), so a nested key named `chain` never matches.
# Default 2, clamped to 1-8.
parse_chain_max_parallel() {
    local config_file="$1"
    python3 - "$config_file" <<'PY'
import sys, re
path = sys.argv[1]
default = 2
val = None
try:
    with open(path) as f:
        lines = f.readlines()
except OSError:
    print(default); sys.exit(0)
in_chain = False
for line in lines:
    raw = line.rstrip("\n")
    # Top-level key at column 0 (letter/underscore, then colon).
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*:', raw):
        key = raw.split(':', 1)[0]
        in_chain = (key == 'chain')
        if in_chain:
            m = re.search(r'max_parallel\s*:\s*(\d+)', raw)  # inline form
            if m:
                val = int(m.group(1)); break
        continue
    if in_chain:
        m = re.match(r'^\s+max_parallel\s*:\s*(\d+)', raw)
        if m:
            val = int(m.group(1)); break
if val is None:
    val = default
print(max(1, min(8, val)))
PY
}

# ─── Python JSON helper ──────────────────────────────────────────────────
# Uses python3 for reads and partial updates of the JSON state.
# All writes go through python3 to build a canonical pretty-printed object,
# then chain_run_write_state_atomic renames it into place.

py_build_initial_state() {
    # Args: run_id ids_json_array brief_path_or_empty ids_raw deps_json_or_empty max_parallel
    local run_id="$1"; local ids_json="$2"; local brief_path="$3"; local ids_raw="$4"
    local deps_json="$5"; local max_parallel="$6"
    local now; now=$(chain_run_iso8601_now)
    python3 - "$run_id" "$ids_json" "$brief_path" "$now" "$ids_raw" "$deps_json" "$max_parallel" <<'PY'
import json, sys
run_id, ids_json, brief_path, now, ids_raw, deps_json, max_parallel = sys.argv[1:8]
ids = json.loads(ids_json)
if not isinstance(ids, list) or not all(isinstance(x, str) for x in ids):
    print(json.dumps({"error": "ids must be a JSON array of strings", "code": "ERR_BAD_INPUT"}), file=sys.stderr)
    sys.exit(2)
# Concurrency cap: default 2, clamp 1-8 (FR-002 — clamp, never error).
try:
    mp = int(max_parallel)
except (TypeError, ValueError):
    mp = 2
mp = max(1, min(8, mp))
# In-run dependency edges: {ticket: [blocker, ...]} restricted to the run set.
idset = set(ids)
blocked_by = {tid: [] for tid in ids}
if deps_json:
    try:
        deps = json.loads(deps_json)
    except Exception:
        print(json.dumps({"error": "deps must be a JSON object", "code": "ERR_BAD_INPUT"}), file=sys.stderr)
        sys.exit(2)
    if not isinstance(deps, dict):
        print(json.dumps({"error": "deps must be a JSON object", "code": "ERR_BAD_INPUT"}), file=sys.stderr)
        sys.exit(2)
    for tid, blockers in deps.items():
        if tid not in idset:
            print(json.dumps({"error": f"deps endpoint not in run: {tid}", "code": "ERR_DEP_ENDPOINT_NOT_IN_RUN"}), file=sys.stderr)
            sys.exit(2)
        if not isinstance(blockers, list):
            print(json.dumps({"error": f"deps[{tid}] must be a list", "code": "ERR_BAD_INPUT"}), file=sys.stderr)
            sys.exit(2)
        seen = []
        for b in blockers:
            if b not in idset:
                print(json.dumps({"error": f"deps blocker not in run: {b}", "code": "ERR_DEP_ENDPOINT_NOT_IN_RUN"}), file=sys.stderr)
                sys.exit(2)
            if b == tid:
                print(json.dumps({"error": f"ticket blocks itself: {tid}", "code": "ERR_DEP_CYCLE"}), file=sys.stderr)
                sys.exit(2)
            if b not in seen:
                seen.append(b)
        blocked_by[tid] = seen
# Cycle detection over blocked_by (DFS with gray/black colors).
WHITE, GRAY, BLACK = 0, 1, 2
color = {tid: WHITE for tid in ids}
def visit(n, stack):
    color[n] = GRAY
    for m in blocked_by.get(n, []):
        if color[m] == GRAY:
            print(json.dumps({"error": "circular blocked_by among in-run tickets: " + " -> ".join(stack + [n, m]), "code": "ERR_DEP_CYCLE"}), file=sys.stderr)
            sys.exit(2)
        if color[m] == WHITE:
            visit(m, stack + [n])
    color[n] = BLACK
for tid in ids:
    if color[tid] == WHITE:
        visit(tid, [])
tickets = {
    tid: {
        "status": "not_started",
        "branch": None,
        "commit_sha": None,
        "worktree_path": None,
        "pr_url": None,
        "lint_status": None,
        "test_status": None,
        "report_path": None,
        "started_at": None,
        "finished_at": None,
        "open_questions": [],
        "blocked_by": blocked_by[tid],
    }
    for tid in ids
}
state = {
    "run_id": run_id,
    "created_at": now,
    "updated_at": now,
    "status": "in_progress",
    "terminal_reason": None,
    "ticket_ids": ids,
    "current_index": 0,
    "max_parallel": mp,
    "epic_brief_path": brief_path if brief_path else None,
    "ids_raw": ids_raw if ids_raw else None,
    "tickets": tickets,
}
print(json.dumps(state, indent=2))
PY
}

py_update_ticket() {
    # Args: state_json ticket status branch worktree pr lint test report open_q_json started_now finished_now commit_sha
    local state_json="$1"; shift
    python3 - "$state_json" "$@" <<'PY'
import json, sys, datetime
args = sys.argv[1:]
(state_json, ticket, status, branch, worktree, pr, lint, test, report,
 open_q_json, started_now, finished_now, commit_sha) = args
state = json.loads(state_json)
if state.get("status") != "in_progress":
    print(json.dumps({"error": f"run is already closed (status={state.get('status')})", "code": "ERR_RUN_CLOSED"}), file=sys.stderr)
    sys.exit(6)
if ticket not in state["tickets"]:
    print(json.dumps({"error": f"ticket not in run: {ticket}", "code": "ERR_TICKET_NOT_IN_RUN"}), file=sys.stderr)
    sys.exit(5)
VALID_STATUSES = ("not_started", "in_progress", "committed", "pushed", "merged", "completed", "failed", "skipped")
if status not in VALID_STATUSES:
    print(json.dumps({"error": f"invalid status: {status}", "code": "ERR_BAD_STATUS"}), file=sys.stderr)
    sys.exit(2)
RANK = {"not_started": 0, "in_progress": 1, "committed": 2, "pushed": 3, "merged": 4, "completed": 5}
t = state["tickets"][ticket]
old_status = t.get("status", "not_started")
# Forward-transition validator (TRI-30 FR-014).
if status == "failed":
    pass  # always legal
elif status == "skipped":
    if old_status != "not_started":
        print(json.dumps({"error": f"illegal transition: {old_status} -> skipped (only legal from not_started)", "code": "ERR_BAD_TRANSITION"}), file=sys.stderr)
        sys.exit(2)
elif status == "committed" and old_status == "committed" and commit_sha and commit_sha != t.get("commit_sha"):
    pass  # re-record an amended commit; see the commit_sha validation below
elif status in RANK:
    if old_status not in RANK or RANK[status] != RANK[old_status] + 1:
        print(json.dumps({"error": f"illegal transition: {old_status} -> {status}", "code": "ERR_BAD_TRANSITION"}), file=sys.stderr)
        sys.exit(2)
# Relaxed pr validation: allowed for pushed/merged/completed.
if pr and status not in ("pushed", "merged", "completed"):
    print(json.dumps({"error": "pr_url is only allowed when status is pushed, merged, or completed", "code": "ERR_PR_REQUIRES_PUSHED_OR_LATER"}), file=sys.stderr)
    sys.exit(2)
# commit_sha validation.
existing_sha = t.get("commit_sha")
if commit_sha and existing_sha and commit_sha != existing_sha and not (status == "committed" and old_status == "committed"):
    print(json.dumps({"error": f"commit_sha is immutable (existing={existing_sha}, new={commit_sha})", "code": "ERR_COMMIT_SHA_IMMUTABLE"}), file=sys.stderr)
    sys.exit(2)
if status == "committed" and not (commit_sha or existing_sha):
    print(json.dumps({"error": "status=committed requires --commit-sha", "code": "ERR_COMMIT_SHA_REQUIRED"}), file=sys.stderr)
    sys.exit(2)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
t["status"] = status
if branch:     t["branch"] = branch
if worktree:   t["worktree_path"] = worktree
if pr:         t["pr_url"] = pr
if lint:       t["lint_status"] = lint
if test:       t["test_status"] = test
if report:     t["report_path"] = report
if commit_sha: t["commit_sha"] = commit_sha
if open_q_json:
    try:
        extra = json.loads(open_q_json)
        if isinstance(extra, list):
            # FR-006: reject hedging language on status=committed. A worker
            # that returns `status: committed` must NOT pause or ask the
            # user for push approval via open_questions — that's the hang
            # failure mode the fire-and-report contract was built to kill.
            if status == "committed":
                HEDGE_PATTERNS = (
                    "push approval", "may i push", "should i push",
                    "may i commit", "should i commit", "may i merge",
                    "should i merge", "await approval", "awaiting approval",
                    "wait for approval", "pause", "please approve",
                    "push?", "merge?", "proceed?",
                )
                offenders = []
                for q in extra:
                    if not isinstance(q, str):
                        continue
                    lo = q.lower()
                    if any(p in lo for p in HEDGE_PATTERNS):
                        offenders.append(q)
                if offenders:
                    print(json.dumps({
                        "error": "status=committed contradicts hedging in open_questions: " + "; ".join(offenders[:3]),
                        "code": "ERR_COMMITTED_HEDGING",
                    }), file=sys.stderr)
                    sys.exit(2)
            t.setdefault("open_questions", []).extend(extra)
    except SystemExit:
        raise
    except Exception:
        pass
if started_now == "1":
    t["started_at"] = now
if finished_now == "1":
    t["finished_at"] = now
# Backfill commit_sha key on legacy tickets so it's always present.
if "commit_sha" not in t:
    t["commit_sha"] = None
# Advance current_index past any committed/pushed/merged/completed/skipped prefix.
ADVANCE_PAST = ("committed", "pushed", "merged", "completed", "skipped")
idx = state.get("current_index", 0)
ids = state["ticket_ids"]
while idx < len(ids) and state["tickets"][ids[idx]].get("status") in ADVANCE_PAST:
    idx += 1
state["current_index"] = idx
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_close_state() {
    # Args: state_json terminal_status reason
    python3 - "$@" <<'PY'
import json, sys, datetime
state_json, terminal_status, reason = sys.argv[1:4]
state = json.loads(state_json)
if terminal_status not in ("completed", "failed", "aborted"):
    print(json.dumps({"error": f"invalid terminal status: {terminal_status}", "code": "ERR_BAD_STATUS"}), file=sys.stderr)
    sys.exit(2)
if state.get("status") != "in_progress":
    # Idempotent: already closed.
    print(json.dumps({"warning": f"run already closed (status={state['status']})"}), file=sys.stderr)
    print(json.dumps(state, indent=2))
    sys.exit(0)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state["status"] = terminal_status
state["terminal_reason"] = reason if reason else None
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_list_interrupted() {
    python3 - "$CHAIN_RUNS_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
runs = []
if os.path.isdir(root):
    for name in sorted(os.listdir(root)):
        state_file = os.path.join(root, name, "state.json")
        if not os.path.isfile(state_file):
            continue
        try:
            with open(state_file) as f:
                s = json.load(f)
        except Exception:
            continue
        if s.get("status") != "in_progress":
            continue
        # Dismissed runs stay on disk but are hidden from resume prompts.
        if s.get("dismissed_at"):
            continue
        ids = s.get("ticket_ids", [])
        idx = s.get("current_index", 0)
        next_tid = ids[idx] if 0 <= idx < len(ids) else None
        runs.append({
            "run_id": s.get("run_id"),
            "created_at": s.get("created_at"),
            "updated_at": s.get("updated_at"),
            "ticket_ids": ids,
            "current_index": idx,
            "next_ticket_id": next_tid,
        })
runs.sort(key=lambda r: r.get("updated_at") or "", reverse=True)
print(json.dumps({"runs": runs}, indent=2))
PY
}

py_dismiss_state() {
    python3 - "$1" <<'PY'
import json, sys, datetime
state = json.loads(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# Idempotent: calling dismiss twice is fine.
state["dismissed_at"] = now
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_next_ready() {
    # Args: state_json
    # Pure scheduler read: which tickets to spawn now, which are running, which
    # are blocked by a still-pending or failed in-run dependency, free slots.
    # Chain status model (vs band): a blocker unblocks its dependent only at
    # merged/completed, because the dependent's worktree is cut from origin/dev.
    python3 - "$1" <<'PY'
import json, sys
state = json.loads(sys.argv[1])
if state.get("status") != "in_progress":
    print(json.dumps({"error": f"run is already closed (status={state.get('status')})", "code": "ERR_RUN_CLOSED"}), file=sys.stderr)
    sys.exit(6)
ids = state["ticket_ids"]
tickets = state["tickets"]
mp = int(state.get("max_parallel", 2))

DEP_SATISFIED = ("merged", "completed")
DEP_DEAD = ("failed",)

def blockers(tid):
    return tickets[tid].get("blocked_by", []) or []

running = [i for i in ids if tickets[i].get("status") == "in_progress"]
not_started = [i for i in ids if tickets[i].get("status") == "not_started"]

dep_failed = [
    i for i in not_started
    if any(tickets[d].get("status") in DEP_DEAD for d in blockers(i))
]
spawn_eligible = [
    i for i in not_started
    if i not in dep_failed
    and all(tickets[d].get("status") in DEP_SATISFIED for d in blockers(i))
]
# Blocked = not_started, not dep_failed, with >=1 blocker still pending.
blocked = [i for i in not_started if i not in dep_failed and i not in spawn_eligible]
slots = max(0, mp - len(running))
spawn = spawn_eligible[:slots]
# A committed or pushed blocker still moves to merged, so it is not a deadlock.
in_flight = [i for i in ids if tickets[i].get("status") in ("in_progress", "committed", "pushed")]
# Defensive deadlock signal (the init-time cycle check normally prevents this).
deadlock = bool(not_started) and not spawn_eligible and not in_flight and not dep_failed
print(json.dumps({
    "spawn": spawn,
    "running": running,
    "dep_failed": dep_failed,
    "blocked": blocked,
    "slots": slots,
    "deadlock": deadlock,
}, indent=2))
PY
}

# ─── Subcommand: parse-range ─────────────────────────────────────────────

sub_parse_range() {
    local arg="${1:-}"
    if [[ -z "$arg" ]]; then
        err_json "ERR_EMPTY_INPUT" "No ticket IDs provided. Usage: chain-run.sh parse-range <arg>"
        return 2
    fi

    local tokens=()
    if [[ "$arg" == *".."* ]]; then
        # Range form
        local left="${arg%%..*}"
        local right="${arg##*..}"
        if [[ -z "$left" || -z "$right" ]]; then
            err_json "ERR_MALFORMED_TOKEN" "Invalid range: '$arg'"
            return 2
        fi
        local lprefix lnum rprefix rnum
        if [[ ! "$left" =~ ^([A-Z][A-Z0-9]*)-([0-9]+)$ ]]; then
            err_json "ERR_MALFORMED_TOKEN" "Invalid ticket ID: '$left'. Expected PREFIX-NUMBER."
            return 2
        fi
        lprefix="${BASH_REMATCH[1]}"; lnum="${BASH_REMATCH[2]}"
        if [[ ! "$right" =~ ^([A-Z][A-Z0-9]*)-([0-9]+)$ ]]; then
            err_json "ERR_MALFORMED_TOKEN" "Invalid ticket ID: '$right'. Expected PREFIX-NUMBER."
            return 2
        fi
        rprefix="${BASH_REMATCH[1]}"; rnum="${BASH_REMATCH[2]}"
        if [[ "$lprefix" != "$rprefix" ]]; then
            err_json "ERR_RANGE_MIXED_PREFIX" "Range cannot mix prefixes: '$arg'. Use a comma-separated list for mixed prefixes."
            return 2
        fi
        if (( 10#$lnum > 10#$rnum )); then
            err_json "ERR_RANGE_DESCENDING" "Range is descending: '$arg'. Use ascending order."
            return 2
        fi
        local i
        for (( i=10#$lnum; i<=10#$rnum; i++ )); do
            tokens+=("${lprefix}-${i}")
        done
    else
        # List form (comma-separated, possibly single token)
        local IFS=','
        read -r -a raw_tokens <<< "$arg"
        local t
        for t in "${raw_tokens[@]}"; do
            # Trim whitespace
            t="${t## }"; t="${t%% }"
            [[ -z "$t" ]] && continue
            if [[ ! "$t" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                err_json "ERR_MALFORMED_TOKEN" "Invalid ticket ID: '$t'. Expected PREFIX-NUMBER."
                return 2
            fi
            tokens+=("$t")
        done
    fi

    if (( ${#tokens[@]} == 0 )); then
        err_json "ERR_COUNT_ZERO" "Range resolves to 0 tickets."
        return 2
    fi

    # Dedup preserving order.
    local deduped=()
    local seen=""
    local t
    for t in "${tokens[@]}"; do
        case " $seen " in
            *" $t "*) ;;
            *) deduped+=("$t"); seen="$seen $t" ;;
        esac
    done

    local max_tickets
    max_tickets=$(chain_run_max_tickets)
    if (( ${#deduped[@]} > max_tickets )); then
        err_json "ERR_COUNT_EXCEEDED" "Range resolves to ${#deduped[@]} tickets. Maximum is ${max_tickets}. Break the range into smaller batches for quality reasons."
        return 2
    fi

    # Emit JSON.
    local out="["
    local i
    for i in "${!deduped[@]}"; do
        if (( i > 0 )); then out+=","; fi
        out+="\"${deduped[$i]}\""
    done
    out+="]"
    printf '{"ids":%s,"count":%d}\n' "$out" "${#deduped[@]}"
}

# ─── Subcommand: init ────────────────────────────────────────────────────

sub_init() {
    local ids_json="" brief_path="" ids_raw="" deps_json="" max_parallel=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ids) ids_json="$2"; shift 2 ;;
            --brief) brief_path="$2"; shift 2 ;;
            --ids-raw) ids_raw="$2"; shift 2 ;;
            --deps) deps_json="$2"; shift 2 ;;
            --max-parallel) max_parallel="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$ids_json" ]]; then
        err_json "ERR_BAD_INPUT" "--ids is required"
        return 2
    fi
    # Default the concurrency cap from chain.max_parallel when not supplied.
    if [[ -z "$max_parallel" ]]; then
        max_parallel=$(parse_chain_max_parallel "$REPO_ROOT/tricycle.config.yml")
    fi
    # Validate brief path early.
    if [[ -n "$brief_path" && ! -f "$brief_path" ]]; then
        err_json "ERR_BRIEF_MISSING" "brief path not found: $brief_path"
        return 2
    fi
    # Parse first ticket id for run-id.
    local first_id
    first_id=$(python3 -c 'import json,sys; ids=json.loads(sys.argv[1]); print(ids[0] if ids else "")' "$ids_json")
    if [[ -z "$first_id" ]]; then
        err_json "ERR_COUNT_ZERO" "ids array is empty"
        return 2
    fi
    # Validate count.
    local count
    count=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$ids_json")
    if (( count == 0 )); then
        err_json "ERR_COUNT_ZERO" "ids array is empty"
        return 2
    fi
    local max_tickets
    max_tickets=$(chain_run_max_tickets)
    if (( count > max_tickets )); then
        err_json "ERR_COUNT_EXCEEDED" "ids array has $count > $max_tickets tickets"
        return 2
    fi

    local run_id
    run_id=$(chain_run_generate_run_id "$first_id")
    local run_dir="$CHAIN_RUNS_DIR/$run_id"
    if [[ -d "$run_dir" ]]; then
        err_json "ERR_STATE_COLLISION" "state directory already exists"
        return 3
    fi
    mkdir -p "$run_dir"

    local final_brief_path=""
    if [[ -n "$brief_path" ]]; then
        cp "$brief_path" "$run_dir/epic-brief.md"
        final_brief_path="specs/.chain-runs/$run_id/epic-brief.md"
    fi

    local state_json rc
    # `&& rc=0 || rc=$?` guards set -e so a validation failure (bad deps /
    # cycle) doesn't abort before we can remove the just-mkdir'd run dir.
    state_json=$(py_build_initial_state "$run_id" "$ids_json" "$final_brief_path" "$ids_raw" "$deps_json" "$max_parallel") && rc=0 || rc=$?
    if [[ ${rc:-0} -ne 0 ]]; then
        rm -rf "$run_dir"   # don't leave an empty orphan run dir behind
        return "$rc"
    fi
    chain_run_write_state_atomic "$run_dir" "$state_json"

    local brief_out="null"
    if [[ -n "$final_brief_path" ]]; then
        brief_out="\"$final_brief_path\""
    fi
    printf '{"run_id":"%s","state_path":"specs/.chain-runs/%s/state.json","brief_path":%s}\n' \
        "$run_id" "$run_id" "$brief_out"
}

# ─── Subcommand: get ─────────────────────────────────────────────────────

sub_get() {
    local run_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id is required"
        return 2
    fi
    local run_dir
    run_dir=$(chain_run_dir_for_id "$run_id")
    chain_run_read_state "$run_dir"
}

# ─── Subcommand: update-ticket ───────────────────────────────────────────

sub_update_ticket() {
    local run_id="" ticket="" status=""
    local branch="" worktree="" pr="" lint="" test="" report="" commit_sha=""
    local started_now="0" finished_now="0"
    local open_questions=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --ticket) ticket="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            --branch) branch="$2"; shift 2 ;;
            --worktree) worktree="$2"; shift 2 ;;
            --pr) pr="$2"; shift 2 ;;
            --lint) lint="$2"; shift 2 ;;
            --test) test="$2"; shift 2 ;;
            --report) report="$2"; shift 2 ;;
            --commit-sha) commit_sha="$2"; shift 2 ;;
            --open-question) open_questions+=("$2"); shift 2 ;;
            --started-now) started_now="1"; shift ;;
            --finished-now) finished_now="1"; shift ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$ticket" || -z "$status" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id, --ticket, --status are required"
        return 2
    fi
    local run_dir
    run_dir=$(chain_run_dir_for_id "$run_id")
    local state_json rc
    state_json=$(chain_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    # Build open_questions JSON array for python.
    local oq_json="[]"
    if (( ${#open_questions[@]} > 0 )); then
        oq_json=$(python3 -c '
import json, sys
print(json.dumps(sys.argv[1:]))
' "${open_questions[@]}")
    fi
    local updated
    updated=$(py_update_ticket "$state_json" "$ticket" "$status" "$branch" "$worktree" "$pr" "$lint" "$test" "$report" "$oq_json" "$started_now" "$finished_now" "$commit_sha"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    chain_run_write_state_atomic "$run_dir" "$updated"
    printf '%s\n' "$updated"
}

# ─── Subcommand: close ───────────────────────────────────────────────────

sub_close() {
    local run_id="" terminal_status="" reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --terminal-status) terminal_status="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$terminal_status" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id and --terminal-status are required"
        return 2
    fi
    local run_dir
    run_dir=$(chain_run_dir_for_id "$run_id")
    local state_json rc
    state_json=$(chain_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local closed
    closed=$(py_close_state "$state_json" "$terminal_status" "$reason"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    chain_run_write_state_atomic "$run_dir" "$closed"
    # Remove progress files.
    local f
    for f in "$run_dir"/*.progress; do
        [[ -e "$f" ]] && rm -f "$f"
    done
    printf '%s\n' "$closed"
}

# ─── Subcommand: list-interrupted ────────────────────────────────────────

sub_list_interrupted() {
    py_list_interrupted
}

# ─── Subcommand: dismiss ─────────────────────────────────────────────────

sub_dismiss() {
    local run_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id is required"
        return 2
    fi
    local run_dir
    run_dir=$(chain_run_dir_for_id "$run_id")
    local state_json rc
    state_json=$(chain_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local dismissed
    dismissed=$(py_dismiss_state "$state_json")
    chain_run_write_state_atomic "$run_dir" "$dismissed"
    printf '%s\n' "$dismissed"
}

# ─── Subcommand: progress ────────────────────────────────────────────────

sub_progress() {
    local run_id="" ticket=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --ticket) ticket="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$ticket" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id and --ticket are required"
        return 2
    fi
    local run_dir
    run_dir=$(chain_run_dir_for_id "$run_id")
    local pf="$run_dir/${ticket}.progress"
    if [[ ! -f "$pf" ]]; then
        printf '{"phase":"unknown","ticket_id":"%s"}\n' "$ticket"
        return 0
    fi
    cat "$pf"
}

# ─── Subcommand: next-ready ──────────────────────────────────────────────

sub_next_ready() {
    local run_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id is required"
        return 2
    fi
    local run_dir state_json rc
    run_dir=$(chain_run_dir_for_id "$run_id")
    state_json=$(chain_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    py_next_ready "$state_json"
}

# ─── Dispatch ────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: chain-run.sh <subcommand> [flags]

Subcommands:
  parse-range <arg>        Parse range-or-list into deduped ticket IDs
  init --ids <json> [--brief <path>] [--ids-raw <string>]
       [--deps <json>] [--max-parallel <N>]
                           Create a new chain run. --deps is a JSON object
                           {ticket: [blocker,...]} of in-run blocked_by edges;
                           --max-parallel defaults to chain.max_parallel (2).
  get --run-id <id>        Read state.json for a run
  next-ready --run-id <id> Scheduler read: which tickets to spawn/continue,
                           which are running/blocked/dep_failed, free slots
  update-ticket --run-id <id> --ticket <tid> --status <s> [options]
                           Transition one ticket
  list-interrupted         List non-terminal runs (hides dismissed runs)
  dismiss --run-id <id>    Hide an interrupted run from list-interrupted
                           without closing it (e.g. runs owned by another
                           session on this machine)
  close --run-id <id> --terminal-status <s> [--reason <string>]
                           Mark a run terminal
  progress --run-id <id> --ticket <tid>
                           Read latest progress event for a ticket
EOF
    exit 2
}

main() {
    if [[ $# -lt 1 ]]; then usage; fi
    local cmd="$1"; shift
    case "$cmd" in
        parse-range)       sub_parse_range "$@" ;;
        init)              sub_init "$@" ;;
        get)                sub_get "$@" ;;
        next-ready)        sub_next_ready "$@" ;;
        update-ticket)     sub_update_ticket "$@" ;;
        list-interrupted)  sub_list_interrupted "$@" ;;
        dismiss)           sub_dismiss "$@" ;;
        close)             sub_close "$@" ;;
        progress)          sub_progress "$@" ;;
        -h|--help|help)    usage ;;
        *)                 err_json "ERR_BAD_INPUT" "unknown subcommand: $cmd"; usage ;;
    esac
}

main "$@"