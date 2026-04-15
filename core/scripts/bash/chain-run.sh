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

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
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

# ─── Python JSON helper ──────────────────────────────────────────────────
# Uses python3 for reads/partial updates (per research.md R4).
# All writes go through python3 to build a canonical pretty-printed object,
# then chain_run_write_state_atomic renames it into place.

py_build_initial_state() {
    # Args: run_id ids_json_array brief_path_or_empty ids_raw
    local run_id="$1"; local ids_json="$2"; local brief_path="$3"; local ids_raw="$4"
    local now; now=$(chain_run_iso8601_now)
    python3 - "$run_id" "$ids_json" "$brief_path" "$now" "$ids_raw" <<'PY'
import json, sys
run_id, ids_json, brief_path, now, ids_raw = sys.argv[1:6]
ids = json.loads(ids_json)
if not isinstance(ids, list) or not all(isinstance(x, str) for x in ids):
    print(json.dumps({"error": "ids must be a JSON array of strings", "code": "ERR_BAD_INPUT"}), file=sys.stderr)
    sys.exit(2)
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
if commit_sha and existing_sha and commit_sha != existing_sha:
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
            t.setdefault("open_questions", []).extend(extra)
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

    if (( ${#deduped[@]} > 8 )); then
        err_json "ERR_COUNT_EXCEEDED" "Range resolves to ${#deduped[@]} tickets. Maximum is 8. Break the range into smaller batches for quality reasons."
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
    local ids_json="" brief_path="" ids_raw=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ids) ids_json="$2"; shift 2 ;;
            --brief) brief_path="$2"; shift 2 ;;
            --ids-raw) ids_raw="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$ids_json" ]]; then
        err_json "ERR_BAD_INPUT" "--ids is required"
        return 2
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
    if (( count > 8 )); then
        err_json "ERR_COUNT_EXCEEDED" "ids array has $count > 8 tickets"
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

    local state_json
    state_json=$(py_build_initial_state "$run_id" "$ids_json" "$final_brief_path" "$ids_raw")
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

# ─── Dispatch ────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: chain-run.sh <subcommand> [flags]

Subcommands:
  parse-range <arg>        Parse range-or-list into deduped ticket IDs
  init --ids <json> [--brief <path>] [--ids-raw <string>]
                           Create a new chain run
  get --run-id <id>        Read state.json for a run
  update-ticket --run-id <id> --ticket <tid> --status <s> [options]
                           Transition one ticket
  list-interrupted         List non-terminal runs
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
        update-ticket)     sub_update_ticket "$@" ;;
        list-interrupted)  sub_list_interrupted "$@" ;;
        close)             sub_close "$@" ;;
        progress)          sub_progress "$@" ;;
        -h|--help|help)    usage ;;
        *)                 err_json "ERR_BAD_INPUT" "unknown subcommand: $cmd"; usage ;;
    esac
}

main "$@"
