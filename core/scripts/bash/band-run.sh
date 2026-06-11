#!/usr/bin/env bash
# band-run.sh — helper for /trc.band orchestrator
# Manages on-disk state for band runs under specs/.band-runs/<run-id>/.
# A band run tracks one parent issue and its sub-issues executed by parallel
# step-controlled workers across dependency waves.
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REPO_ROOT="$(get_repo_root)"
BAND_RUNS_DIR="$REPO_ROOT/specs/.band-runs"

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

band_run_iso8601_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

band_run_generate_run_id() {
    local parent_id="$1"
    local stamp rand
    stamp=$(date -u +"%Y%m%dT%H%M%S")
    # 4-hex-digit random suffix so rapid successive invocations (tests) don't collide.
    rand=$(printf '%04x' $((RANDOM & 0xFFFF)))
    printf '%s%s-%s' "$stamp" "$rand" "$parent_id"
}

band_run_write_state_atomic() {
    local run_dir="$1"; local state_json="$2"
    local tmp="${run_dir}/state.json.tmp"
    printf '%s\n' "$state_json" > "$tmp"
    mv "$tmp" "${run_dir}/state.json"
}

band_run_read_state() {
    local run_dir="$1"
    local state_file="${run_dir}/state.json"
    if [[ ! -f "$state_file" ]]; then
        err_json "ERR_RUN_NOT_FOUND" "run not found: $(basename "$run_dir")"
        return 4
    fi
    cat "$state_file"
}

band_run_dir_for_id() {
    printf '%s/%s' "$BAND_RUNS_DIR" "$1"
}

# ─── Python JSON helpers ─────────────────────────────────────────────────
# All state writes go through python3 to build a canonical pretty-printed
# object, then band_run_write_state_atomic renames it into place.

py_build_initial_state() {
    # Args: run_id parent_id issues_json chain_json max_parallel recon_path
    #       integration_branch integration_worktree integration_base
    python3 - "$@" <<'PY'
import json, sys, datetime
(run_id, parent_id, issues_json, chain_json, max_parallel, recon_path,
 int_branch, int_worktree, int_base) = sys.argv[1:10]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def bail(msg, code="ERR_BAD_INPUT"):
    print(json.dumps({"error": msg, "code": code}), file=sys.stderr)
    sys.exit(2)

try:
    issues_in = json.loads(issues_json)
except Exception:
    bail("issues must be valid JSON")
try:
    chain = json.loads(chain_json)
except Exception:
    bail("chain must be valid JSON")

if not isinstance(chain, list) or not chain or not all(isinstance(s, str) and s for s in chain):
    bail("chain must be a non-empty JSON array of step names")
if not isinstance(issues_in, list) or not issues_in:
    bail("issues must be a non-empty JSON array of objects", "ERR_COUNT_ZERO")
if len(issues_in) > 16:
    bail(f"issues array has {len(issues_in)} > 16 sub-issues. Split the epic.", "ERR_COUNT_EXCEEDED")

REQUIRED = ("id", "title", "branch", "worktree", "complexity", "model", "wave", "depends_on")
ids = []
for it in issues_in:
    if not isinstance(it, dict):
        bail("each issue must be a JSON object")
    missing = [k for k in REQUIRED if k not in it]
    if missing:
        bail(f"issue {it.get('id', '?')} missing keys: {', '.join(missing)}")
    if not isinstance(it["depends_on"], list):
        bail(f"issue {it['id']}: depends_on must be an array")
    if not isinstance(it["wave"], int) or it["wave"] < 0:
        bail(f"issue {it['id']}: wave must be a non-negative integer")
    if it["complexity"] not in ("low", "medium", "high"):
        bail(f"issue {it['id']}: complexity must be low|medium|high")
    ids.append(it["id"])
if len(set(ids)) != len(ids):
    bail("duplicate issue ids")
idset = set(ids)
for it in issues_in:
    for dep in it["depends_on"]:
        if dep not in idset:
            bail(f"issue {it['id']}: unknown dependency '{dep}'")
        if dep == it["id"]:
            bail(f"issue {it['id']}: depends on itself")

waves = {}
for it in issues_in:
    waves.setdefault(it["wave"], []).append(it["id"])
wave_list = [waves[k] for k in sorted(waves)]

issues = {
    it["id"]: {
        "title": it["title"],
        "status": "pending",
        "wave": it["wave"],
        "depends_on": it["depends_on"],
        "complexity": it["complexity"],
        "model": it["model"],
        "branch": it["branch"],
        "worktree_path": it["worktree"],
        "commit_sha": None,
        "merged_sha": None,
        "lint_status": None,
        "test_status": None,
        "rebase_count": 0,
        "current_step": None,
        "step_status": None,
        "steps_completed": [],
        "questions": [],
        "concerns": [],
        "started_at": None,
        "finished_at": None,
    }
    for it in issues_in
}

state = {
    "run_id": run_id,
    "parent_id": parent_id,
    "created_at": now,
    "updated_at": now,
    "status": "in_progress",
    "terminal_reason": None,
    "dismissed_at": None,
    "chain": chain,
    "max_parallel": int(max_parallel),
    "paused_for": None,
    "recon_path": recon_path,
    "integration": {
        "branch": int_branch,
        "worktree_path": int_worktree if int_worktree else None,
        "base": int_base,
        "merged_issues": [],
        "pr_url": None,
        "pushed_at": None,
    },
    "waves": wave_list,
    "issues": issues,
}
print(json.dumps(state, indent=2))
PY
}

py_update_step() {
    # Args: state_json issue step step_status questions_json
    python3 - "$@" <<'PY'
import json, sys, datetime
state_json, issue, step, step_status, questions_json = sys.argv[1:6]
state = json.loads(state_json)

def bail(msg, code, rc=2):
    print(json.dumps({"error": msg, "code": code}), file=sys.stderr)
    sys.exit(rc)

if state.get("status") != "in_progress":
    bail(f"run is already closed (status={state.get('status')})", "ERR_RUN_CLOSED", 6)
if issue not in state["issues"]:
    bail(f"issue not in run: {issue}", "ERR_ISSUE_NOT_IN_RUN", 5)

chain = state["chain"]
if step not in chain:
    bail(f"unknown step '{step}' (chain: {', '.join(chain)})", "ERR_BAD_STEP")
if step_status not in ("running", "step_complete", "blocked", "failed"):
    bail(f"invalid step-status: {step_status}", "ERR_BAD_STATUS")

t = state["issues"][issue]
if t["status"] in ("failed", "blocked_by_failure", "skipped", "completed", "merged"):
    bail(f"issue {issue} is {t['status']}; steps can no longer change", "ERR_ISSUE_TERMINAL")

cur = t.get("current_step")
cur_status = t.get("step_status")
done = t.get("steps_completed", [])
next_step = chain[len(done)] if len(done) < len(chain) else None

if step_status == "running":
    fresh = (step == next_step and cur_status in (None, "step_complete"))
    retry = (step == cur and cur_status in ("running", "blocked", "failed"))
    if not (fresh or retry):
        bail(f"illegal step start: step={step} current={cur}({cur_status}) next-expected={next_step}",
             "ERR_BAD_STEP_TRANSITION")
    t["current_step"] = step
    t["step_status"] = "running"
    if t["status"] == "pending":
        t["status"] = "in_progress"
        t["started_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
else:
    if cur != step:
        bail(f"step '{step}' is not the current step ('{cur}')", "ERR_BAD_STEP_TRANSITION")
    if step_status == "step_complete":
        if cur_status != "running":
            bail(f"illegal transition: {cur_status} -> step_complete", "ERR_BAD_STEP_TRANSITION")
        t["step_status"] = "step_complete"
        if step not in done:
            done.append(step)
        t["steps_completed"] = done
    elif step_status == "blocked":
        if cur_status != "running":
            bail(f"illegal transition: {cur_status} -> blocked", "ERR_BAD_STEP_TRANSITION")
        questions = json.loads(questions_json) if questions_json else []
        if not questions:
            bail("step-status blocked requires at least one --question", "ERR_BLOCKED_REQUIRES_QUESTION")
        t["step_status"] = "blocked"
        t.setdefault("questions", []).extend(questions)
    elif step_status == "failed":
        if cur_status not in ("running", "blocked"):
            bail(f"illegal transition: {cur_status} -> failed", "ERR_BAD_STEP_TRANSITION")
        t["step_status"] = "failed"

state["updated_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print(json.dumps(state, indent=2))
PY
}

py_update_issue() {
    # Args: state_json issue status branch lint test commit_sha merged_sha
    #       increment_rebase started_now finished_now concerns_json questions_json
    python3 - "$@" <<'PY'
import json, sys, datetime
(state_json, issue, status, branch, lint, test, commit_sha, merged_sha,
 increment_rebase, started_now, finished_now, concerns_json, questions_json) = sys.argv[1:14]
state = json.loads(state_json)

def bail(msg, code, rc=2):
    print(json.dumps({"error": msg, "code": code}), file=sys.stderr)
    sys.exit(rc)

if state.get("status") != "in_progress":
    bail(f"run is already closed (status={state.get('status')})", "ERR_RUN_CLOSED", 6)
if issue not in state["issues"]:
    bail(f"issue not in run: {issue}", "ERR_ISSUE_NOT_IN_RUN", 5)

VALID = ("pending", "in_progress", "committed", "merged", "completed",
         "failed", "blocked_by_failure", "skipped")
if status not in VALID:
    bail(f"invalid status: {status}", "ERR_BAD_STATUS")

RANK = {"pending": 0, "in_progress": 1, "committed": 2, "merged": 3, "completed": 4}
t = state["issues"][issue]
old = t.get("status", "pending")

if status == "failed":
    pass  # always legal
elif status in ("skipped", "blocked_by_failure"):
    if old != "pending":
        bail(f"illegal transition: {old} -> {status} (only legal from pending)", "ERR_BAD_TRANSITION")
elif status in RANK:
    if old not in RANK or RANK[status] != RANK[old] + 1:
        bail(f"illegal transition: {old} -> {status}", "ERR_BAD_TRANSITION")

# commit_sha rules: immutable unless this update is an explicit rebase.
existing_sha = t.get("commit_sha")
if increment_rebase == "1":
    if t.get("rebase_count", 0) >= 2:
        bail(f"issue {issue} already rebased {t.get('rebase_count', 0)} times; cap is 2 — pause and escalate to the user",
             "ERR_REBASE_CAP")
    t["rebase_count"] = t.get("rebase_count", 0) + 1
elif commit_sha and existing_sha and commit_sha != existing_sha:
    bail(f"commit_sha is immutable without --increment-rebase (existing={existing_sha}, new={commit_sha})",
         "ERR_COMMIT_SHA_IMMUTABLE")
if status == "committed" and not (commit_sha or existing_sha):
    bail("status=committed requires --commit-sha", "ERR_COMMIT_SHA_REQUIRED")

concerns = json.loads(concerns_json) if concerns_json else []
questions = json.loads(questions_json) if questions_json else []

# Reject hedging language on status=committed: a worker that committed must
# not smuggle approval-seeking back through concerns/questions — that is the
# hang failure mode the per-step fire-and-report contract exists to kill.
if status == "committed":
    HEDGE_PATTERNS = (
        "push approval", "may i push", "should i push",
        "may i commit", "should i commit", "may i merge",
        "should i merge", "await approval", "awaiting approval",
        "wait for approval", "pause", "please approve",
        "push?", "merge?", "proceed?",
    )
    offenders = []
    for q in concerns + questions:
        if not isinstance(q, str):
            continue
        lo = q.lower()
        if any(p in lo for p in HEDGE_PATTERNS):
            offenders.append(q)
    if offenders:
        bail("status=committed contradicts hedging in concerns/questions: " + "; ".join(offenders[:3]),
             "ERR_COMMITTED_HEDGING")

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
t["status"] = status
if branch:      t["branch"] = branch
if lint:        t["lint_status"] = lint
if test:        t["test_status"] = test
if commit_sha:  t["commit_sha"] = commit_sha
if merged_sha:  t["merged_sha"] = merged_sha
if concerns:    t.setdefault("concerns", []).extend(concerns)
if questions:   t.setdefault("questions", []).extend(questions)
if started_now == "1":
    t["started_at"] = now
if finished_now == "1":
    t["finished_at"] = now
if status == "merged":
    merged = state["integration"].setdefault("merged_issues", [])
    if issue not in merged:
        merged.append(issue)
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_next_ready() {
    # Args: state_json
    python3 - "$1" <<'PY'
import json, sys
state = json.loads(sys.argv[1])

def bail(msg, code, rc=2):
    print(json.dumps({"error": msg, "code": code}), file=sys.stderr)
    sys.exit(rc)

if state.get("status") != "in_progress":
    bail(f"run is already closed (status={state.get('status')})", "ERR_RUN_CLOSED", 6)

issues = state["issues"]
chain = state["chain"]
order = [i for wave in state.get("waves", []) for i in wave]
# Stable fallback for any issue missing from waves.
order += [i for i in issues if i not in order]

DEP_SATISFIED = ("merged", "completed")
DEP_DEAD = ("failed", "blocked_by_failure")
WAVE_DRAINED = ("merged", "completed", "skipped", "failed", "blocked_by_failure")

running = [i for i in order if issues[i].get("step_status") == "running"]
blocked = [i for i in order if issues[i].get("step_status") == "blocked"]
dep_failed = [
    i for i in order
    if issues[i]["status"] == "pending"
    and any(issues[d]["status"] in DEP_DEAD for d in issues[i]["depends_on"])
]

continue_eligible = [
    i for i in order
    if issues[i]["status"] == "in_progress"
    and issues[i].get("step_status") == "step_complete"
    and len(issues[i].get("steps_completed", [])) < len(chain)
]

def earlier_waves_drained(i):
    w = issues[i]["wave"]
    return all(
        issues[j]["status"] in WAVE_DRAINED
        for j in issues
        if issues[j]["wave"] < w
    )

spawn_eligible = [
    i for i in order
    if issues[i]["status"] == "pending"
    and i not in dep_failed
    and all(issues[d]["status"] in DEP_SATISFIED for d in issues[i]["depends_on"])
    and earlier_waves_drained(i)
]

paused = state.get("paused_for") is not None
slots = max(0, state["max_parallel"] - len(running))
if paused:
    continue_out, spawn_out = [], []
else:
    continue_out = continue_eligible[:slots]
    spawn_out = spawn_eligible[:max(0, slots - len(continue_out))]

print(json.dumps({
    "spawn": spawn_out,
    "continue": continue_out,
    "running": running,
    "blocked": blocked,
    "dep_failed": dep_failed,
    "slots": slots,
    "paused": paused,
}, indent=2))
PY
}

py_pause_state() {
    # Args: state_json issue reason
    python3 - "$@" <<'PY'
import json, sys, datetime
state_json, issue, reason = sys.argv[1:4]
state = json.loads(state_json)
if state.get("status") != "in_progress":
    print(json.dumps({"error": f"run is already closed (status={state.get('status')})", "code": "ERR_RUN_CLOSED"}), file=sys.stderr)
    sys.exit(6)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state["paused_for"] = {
    "issue_id": issue if issue else None,
    "reason": reason if reason else None,
    "since": now,
}
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_resume_state() {
    python3 - "$1" <<'PY'
import json, sys, datetime
state = json.loads(sys.argv[1])
if state.get("status") != "in_progress":
    print(json.dumps({"error": f"run is already closed (status={state.get('status')})", "code": "ERR_RUN_CLOSED"}), file=sys.stderr)
    sys.exit(6)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state["paused_for"] = None
state["updated_at"] = now
print(json.dumps(state, indent=2))
PY
}

py_update_integration() {
    # Args: state_json pr_url pushed_now
    python3 - "$@" <<'PY'
import json, sys, datetime
state_json, pr_url, pushed_now = sys.argv[1:4]
state = json.loads(state_json)
if state.get("status") != "in_progress":
    print(json.dumps({"error": f"run is already closed (status={state.get('status')})", "code": "ERR_RUN_CLOSED"}), file=sys.stderr)
    sys.exit(6)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
if pr_url:
    state["integration"]["pr_url"] = pr_url
if pushed_now == "1":
    state["integration"]["pushed_at"] = now
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
    python3 - "$BAND_RUNS_DIR" <<'PY'
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
        if s.get("dismissed_at"):
            continue
        summary = {}
        for iid, t in s.get("issues", {}).items():
            done = t.get("steps_completed", [])
            summary[iid] = {
                "status": t.get("status"),
                "last_completed_step": done[-1] if done else None,
                "current_step": t.get("current_step"),
                "step_status": t.get("step_status"),
            }
        runs.append({
            "run_id": s.get("run_id"),
            "parent_id": s.get("parent_id"),
            "created_at": s.get("created_at"),
            "updated_at": s.get("updated_at"),
            "paused_for": s.get("paused_for"),
            "issues": summary,
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

# Build a JSON array from repeated bash flag values.
args_to_json_array() {
    if (( $# == 0 )); then
        printf '[]'
        return 0
    fi
    python3 -c '
import json, sys
print(json.dumps(sys.argv[1:]))
' "$@"
}

# ─── Subcommand: init ────────────────────────────────────────────────────

sub_init() {
    local parent_id="" issues_json="" recon_path="" chain_json="" max_parallel=""
    local int_worktree="" int_base="main"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parent) parent_id="$2"; shift 2 ;;
            --issues) issues_json="$2"; shift 2 ;;
            --recon) recon_path="$2"; shift 2 ;;
            --chain) chain_json="$2"; shift 2 ;;
            --max-parallel) max_parallel="$2"; shift 2 ;;
            --integration-worktree) int_worktree="$2"; shift 2 ;;
            --integration-base) int_base="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$parent_id" || -z "$issues_json" || -z "$recon_path" ]]; then
        err_json "ERR_BAD_INPUT" "--parent, --issues, --recon are required"
        return 2
    fi
    if [[ ! "$parent_id" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
        err_json "ERR_MALFORMED_TOKEN" "Invalid parent issue ID: '$parent_id'. Expected PREFIX-NUMBER."
        return 2
    fi
    if [[ ! -f "$recon_path" ]]; then
        err_json "ERR_RECON_MISSING" "recon path not found: $recon_path"
        return 2
    fi
    if [[ -z "$chain_json" ]]; then
        # Default to the configured workflow chain.
        local chain_str
        chain_str=$(parse_chain_config "$REPO_ROOT/tricycle.config.yml")
        chain_json=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].split()))' "$chain_str")
    fi
    if [[ -z "$max_parallel" ]]; then
        max_parallel=$(parse_band_config "$REPO_ROOT/tricycle.config.yml")
    fi
    if [[ ! "$max_parallel" =~ ^[0-9]+$ ]] || (( max_parallel < 1 || max_parallel > 8 )); then
        err_json "ERR_BAD_INPUT" "--max-parallel must be an integer 1-8 (got: $max_parallel)"
        return 2
    fi

    local run_id
    run_id=$(band_run_generate_run_id "$parent_id")
    local run_dir="$BAND_RUNS_DIR/$run_id"
    if [[ -d "$run_dir" ]]; then
        err_json "ERR_STATE_COLLISION" "state directory already exists"
        return 3
    fi

    local int_branch="band/$parent_id"
    local final_recon_path="specs/.band-runs/$run_id/recon.md"

    local state_json rc
    state_json=$(py_build_initial_state "$run_id" "$parent_id" "$issues_json" "$chain_json" \
        "$max_parallel" "$final_recon_path" "$int_branch" "$int_worktree" "$int_base"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi

    mkdir -p "$run_dir"
    cp "$recon_path" "$run_dir/recon.md"
    band_run_write_state_atomic "$run_dir" "$state_json"

    printf '{"run_id":"%s","state_path":"specs/.band-runs/%s/state.json","recon_path":"%s"}\n' \
        "$run_id" "$run_id" "$final_recon_path"
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
    band_run_read_state "$(band_run_dir_for_id "$run_id")"
}

# ─── Subcommand: update-step ─────────────────────────────────────────────

sub_update_step() {
    local run_id="" issue="" step="" step_status=""
    local questions=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --step) step="$2"; shift 2 ;;
            --step-status) step_status="$2"; shift 2 ;;
            --question) questions+=("$2"); shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$issue" || -z "$step" || -z "$step_status" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id, --issue, --step, --step-status are required"
        return 2
    fi
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local q_json
    if (( ${#questions[@]} > 0 )); then
        q_json=$(args_to_json_array "${questions[@]}")
    else
        q_json="[]"
    fi
    local updated
    updated=$(py_update_step "$state_json" "$issue" "$step" "$step_status" "$q_json"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$updated"
    printf '%s\n' "$updated"
}

# ─── Subcommand: update-issue ────────────────────────────────────────────

sub_update_issue() {
    local run_id="" issue="" status=""
    local branch="" lint="" test="" commit_sha="" merged_sha=""
    local increment_rebase="0" started_now="0" finished_now="0"
    local concerns=() questions=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            --branch) branch="$2"; shift 2 ;;
            --lint) lint="$2"; shift 2 ;;
            --test) test="$2"; shift 2 ;;
            --commit-sha) commit_sha="$2"; shift 2 ;;
            --merged-sha) merged_sha="$2"; shift 2 ;;
            --concern) concerns+=("$2"); shift 2 ;;
            --question) questions+=("$2"); shift 2 ;;
            --increment-rebase) increment_rebase="1"; shift ;;
            --started-now) started_now="1"; shift ;;
            --finished-now) finished_now="1"; shift ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$issue" || -z "$status" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id, --issue, --status are required"
        return 2
    fi
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local c_json q_json
    if (( ${#concerns[@]} > 0 )); then c_json=$(args_to_json_array "${concerns[@]}"); else c_json="[]"; fi
    if (( ${#questions[@]} > 0 )); then q_json=$(args_to_json_array "${questions[@]}"); else q_json="[]"; fi
    local updated
    updated=$(py_update_issue "$state_json" "$issue" "$status" "$branch" "$lint" "$test" \
        "$commit_sha" "$merged_sha" "$increment_rebase" "$started_now" "$finished_now" \
        "$c_json" "$q_json"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$updated"
    printf '%s\n' "$updated"
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
    local state_json rc
    state_json=$(band_run_read_state "$(band_run_dir_for_id "$run_id")"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    py_next_ready "$state_json"
}

# ─── Subcommand: pause / resume ──────────────────────────────────────────

sub_pause() {
    local run_id="" issue="" reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id is required"
        return 2
    fi
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local updated
    updated=$(py_pause_state "$state_json" "$issue" "$reason"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$updated"
    printf '%s\n' "$updated"
}

sub_resume() {
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
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local updated
    updated=$(py_resume_state "$state_json"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$updated"
    printf '%s\n' "$updated"
}

# ─── Subcommand: update-integration ──────────────────────────────────────

sub_update_integration() {
    local run_id="" pr_url="" pushed_now="0"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --pr-url) pr_url="$2"; shift 2 ;;
            --pushed-now) pushed_now="1"; shift ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id is required"
        return 2
    fi
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local updated
    updated=$(py_update_integration "$state_json" "$pr_url" "$pushed_now"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$updated"
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
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local closed
    closed=$(py_close_state "$state_json" "$terminal_status" "$reason"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    band_run_write_state_atomic "$run_dir" "$closed"
    local f
    for f in "$run_dir"/*.progress; do
        [[ -e "$f" ]] && rm -f "$f"
    done
    printf '%s\n' "$closed"
}

# ─── Subcommand: list-interrupted / dismiss / progress ───────────────────

sub_list_interrupted() {
    py_list_interrupted
}

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
    local run_dir state_json rc
    run_dir=$(band_run_dir_for_id "$run_id")
    state_json=$(band_run_read_state "$run_dir"); rc=$?
    if [[ $rc -ne 0 ]]; then return $rc; fi
    local dismissed
    dismissed=$(py_dismiss_state "$state_json")
    band_run_write_state_atomic "$run_dir" "$dismissed"
    printf '%s\n' "$dismissed"
}

sub_progress() {
    local run_id="" issue=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id) run_id="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            *) err_json "ERR_BAD_INPUT" "unknown flag: $1"; return 2 ;;
        esac
    done
    if [[ -z "$run_id" || -z "$issue" ]]; then
        err_json "ERR_BAD_INPUT" "--run-id and --issue are required"
        return 2
    fi
    local pf
    pf="$(band_run_dir_for_id "$run_id")/${issue}.progress"
    if [[ ! -f "$pf" ]]; then
        printf '{"phase":"unknown","issue_id":"%s"}\n' "$issue"
        return 0
    fi
    cat "$pf"
}

# ─── Dispatch ────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: band-run.sh <subcommand> [flags]

Subcommands:
  init --parent <id> --issues <json> --recon <path>
       [--chain <json>] [--max-parallel N]
       [--integration-worktree <path>] [--integration-base <branch>]
                           Create a new band run. issues json: array of
                           {id,title,branch,worktree,complexity,model,wave,depends_on}
  get --run-id <id>        Read state.json for a run
  update-step --run-id <id> --issue <iid> --step <name>
       --step-status running|step_complete|blocked|failed [--question <q>]...
                           Transition one step of one issue
  update-issue --run-id <id> --issue <iid> --status <s> [options]
                           Transition one issue (pending -> in_progress ->
                           committed -> merged -> completed; failed always;
                           skipped/blocked_by_failure from pending)
  next-ready --run-id <id> Scheduler read: which issues to spawn/continue
  pause --run-id <id> [--issue <iid>] [--reason <string>]
                           Pause the band (blocks spawn/continue)
  resume --run-id <id>     Clear the pause
  update-integration --run-id <id> [--pr-url <url>] [--pushed-now]
                           Record integration branch push/PR
  list-interrupted         List non-terminal runs (hides dismissed runs)
  dismiss --run-id <id>    Hide an interrupted run from list-interrupted
  close --run-id <id> --terminal-status <s> [--reason <string>]
                           Mark a run terminal
  progress --run-id <id> --issue <iid>
                           Read latest progress event for an issue
EOF
    exit 2
}

main() {
    if [[ $# -lt 1 ]]; then usage; fi
    local cmd="$1"; shift
    case "$cmd" in
        init)               sub_init "$@" ;;
        get)                sub_get "$@" ;;
        update-step)        sub_update_step "$@" ;;
        update-issue)       sub_update_issue "$@" ;;
        next-ready)         sub_next_ready "$@" ;;
        pause)              sub_pause "$@" ;;
        resume)             sub_resume "$@" ;;
        update-integration) sub_update_integration "$@" ;;
        list-interrupted)   sub_list_interrupted "$@" ;;
        dismiss)            sub_dismiss "$@" ;;
        close)              sub_close "$@" ;;
        progress)           sub_progress "$@" ;;
        -h|--help|help)     usage ;;
        *)                  err_json "ERR_BAD_INPUT" "unknown subcommand: $cmd"; usage ;;
    esac
}

main "$@"
