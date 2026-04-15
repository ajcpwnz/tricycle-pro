# Data Model: TRI-30 — /trc.chain run-to-commit

**Feature**: TRI-30-chain-run-to-commit
**Date**: 2026-04-15

This is a **delta** from TRI-27's `data-model.md`. Only the changes are documented here. Anything not mentioned is unchanged from TRI-27.

---

## Δ Chain Run State (`state.json`)

### New field: `tickets.<id>.commit_sha`

| Field | Type | Required | Description |
|---|---|---|---|
| `commit_sha` | string \| null | no | Git commit SHA of the worker's final commit. Set when the ticket transitions to `committed`. Never reset. Used for resume cross-check (R5). |

The full per-ticket entry now looks like this (additions in **bold**):

```json
{
  "status": "pushed",
  "branch": "TRI-100-feat",
  "worktree_path": "../tricycle-pro-TRI-100-feat",
  **"commit_sha": "abc123def456...",**
  "pr_url": "https://github.com/org/repo/pull/123",
  "lint_status": "pass",
  "test_status": "pass",
  "report_path": "specs/.chain-runs/.../TRI-100.report.md",
  "started_at": "2026-04-15T20:00:00Z",
  "finished_at": "2026-04-15T20:08:00Z",
  "open_questions": []
}
```

### Extended status enum

The valid values for `tickets.<id>.status` (and the legal forward transitions) are now:

```text
not_started ──► in_progress ──► committed ──► pushed ──► merged ──► completed
                    │                │            │           │
                    └───┬────────────┴────────────┴───────────┘
                        ▼
                     failed
                     
not_started ──► skipped   (only legal source for skipped)
```

**State definitions**:

| Status | Owner | Meaning |
|---|---|---|
| `not_started` | n/a | Ticket has been parsed but no worker has been spawned. |
| `in_progress` | worker | Worker is running but has not yet committed. Usually transient. |
| `committed` | worker | Worker has finished `/trc.implement`, made a local commit, and exited. **Awaiting orchestrator push approval.** New in TRI-30. |
| `pushed` | orchestrator | Orchestrator has run `git push -u origin <branch>` successfully. New in TRI-30. |
| `merged` | orchestrator | Orchestrator has merged the PR via `gh pr merge`. New in TRI-30. |
| `completed` | orchestrator | Worktree cleanup is done. Ticket is fully shipped. |
| `failed` | either | Ticket cannot proceed. Chain stops. Worker may have partially committed; orchestrator does NOT push. |
| `skipped` | orchestrator | User chose to skip this ticket on resume or scope confirmation. Carried forward from TRI-27. |

### Validation rules (delta)

- **`pr_url`**: now allowed when `status` ∈ {`pushed`, `merged`, `completed`}. Previously: only `completed`. Setting `pr_url` while still `in_progress` or `committed` remains an error (`ERR_PR_REQUIRES_COMPLETED` becomes `ERR_PR_REQUIRES_PUSHED_OR_LATER`, but the helper's error code stays the same name for backward compatibility — message updated).
- **`commit_sha`**: must be set when transitioning to `committed`. The helper enforces this in `update-ticket`: passing `--status committed` without `--commit-sha` returns `ERR_COMMIT_SHA_REQUIRED` (new error code, exit 2).
- **Forward transitions**: only the arrows in the diagram above are legal. Attempting to skip a state (e.g., `not_started → merged`) returns `ERR_BAD_TRANSITION` (new error code, exit 2). The validator implements this as a forward-rank check: each state has an integer rank, and the new state's rank must be > the current rank, OR the new state must be `failed`/`skipped`.
- **`current_index` advancement**: the rule extends to treat `committed`, `pushed`, `merged`, `completed`, and `skipped` as "done enough to advance past". (Previously: only `completed` and `skipped`.) This is critical for resume — a `committed` ticket on resume should not block the chain from advancing to the next ticket if the user declined to push it.

### Example state.json after a 3-ticket run, with ticket 1 fully shipped, ticket 2 committed-awaiting-push, ticket 3 not_started

```json
{
  "run_id": "20260415T200000abcd-TRI-100",
  "created_at": "2026-04-15T20:00:00Z",
  "updated_at": "2026-04-15T20:25:00Z",
  "status": "in_progress",
  "terminal_reason": null,
  "ticket_ids": ["TRI-100", "TRI-101", "TRI-102"],
  "current_index": 1,
  "epic_brief_path": null,
  "tickets": {
    "TRI-100": {
      "status": "completed",
      "branch": "TRI-100-feat",
      "worktree_path": "../tricycle-pro-TRI-100-feat",
      "commit_sha": "abc123...",
      "pr_url": "https://github.com/org/repo/pull/123",
      "lint_status": "pass",
      "test_status": "pass",
      "started_at": "2026-04-15T20:00:00Z",
      "finished_at": "2026-04-15T20:10:00Z",
      "open_questions": []
    },
    "TRI-101": {
      "status": "committed",
      "branch": "TRI-101-feat",
      "worktree_path": "../tricycle-pro-TRI-101-feat",
      "commit_sha": "def456...",
      "pr_url": null,
      "lint_status": "pass",
      "test_status": "pass",
      "started_at": "2026-04-15T20:10:00Z",
      "finished_at": "2026-04-15T20:25:00Z",
      "open_questions": []
    },
    "TRI-102": {
      "status": "not_started",
      "branch": null,
      "worktree_path": null,
      "commit_sha": null,
      "pr_url": null,
      "lint_status": null,
      "test_status": null,
      "started_at": null,
      "finished_at": null,
      "open_questions": []
    }
  }
}
```

In this state, the orchestrator has just finished spawning + collecting from the TRI-101 worker, recorded the commit, and is **about to ask the user for push approval on TRI-101**. If the conversation dies right now, the next `/trc.chain` invocation detects this run as interrupted, resumes by skipping ticket TRI-100 (already completed) and going straight to the push gate for TRI-101 (already committed) — no worker re-spawn needed for either.

---

## Δ Progress Event (`<ticket-id>.progress`)

### New event semantics: end-of-phase (`_complete`), not start-of-phase

**Old (TRI-27)**:
```json
{"phase": "plan", "started_at": "2026-04-15T12:00:00Z", "ticket_id": "TRI-100"}
```

**New (TRI-30)**:
```json
{"phase": "plan_complete", "completed_at": "2026-04-15T12:08:00Z", "ticket_id": "TRI-100"}
```

### Valid phase values

| Phase | Emitted when |
|---|---|
| `specify_complete` | After `/trc.specify` finishes |
| `clarify_complete` | After `/trc.clarify` finishes (if part of the chain) |
| `plan_complete` | After `/trc.plan` finishes |
| `tasks_complete` | After `/trc.tasks` finishes |
| `analyze_complete` | After `/trc.analyze` finishes (if part of the chain) |
| `implement_complete` | After `/trc.implement` finishes (lint+test green, version bumped) |
| `committed` | After the explicit `git add -A && git commit`, with `commit_sha` field added |

### Final event: `committed`

The terminal progress event for a successful worker has an extra field:

```json
{
  "phase": "committed",
  "completed_at": "2026-04-15T20:25:00Z",
  "ticket_id": "TRI-101",
  "commit_sha": "def456..."
}
```

This is the orchestrator's secondary confirmation that the worker actually finished. The primary signal is the worker's structured JSON return message (R2). The progress file is a cross-check.

### Migration note

Progress files are ephemeral runtime state — they live only for the duration of a chain run and are deleted by `chain-run.sh close`. The new event format is **not backward compatible** with v0.17.0 progress files, but since they're not persisted across runs, no migration is needed. Old runs that were left interrupted with v0.17.0 progress files will display "phase: unknown" in the new orchestrator's progress display, which is honest.

---

## Δ Worker Report (worker → orchestrator return message)

### New required fields

The worker's final structured JSON report (returned in a fenced ` ```json ``` ` block) MUST contain:

| Field | Type | Required | Description |
|---|---|---|---|
| `ticket_id` | string | yes | Echoed from the worker brief |
| `status` | enum | yes | `committed` or `failed` (no other values allowed) |
| `branch` | string \| null | yes | Branch name (set on success, may be set on failure if the worker got that far) |
| `commit_sha` | string \| null | yes | The worker's final commit SHA (required on `status=committed`, null otherwise) |
| `files_changed` | string[] \| null | yes | List of files touched in the commit (orchestrator uses count for the summary line) |
| `lint_status` | enum | yes | `pass`, `fail`, or `skipped` |
| `test_status` | enum | yes | `pass`, `fail`, or `skipped` |
| `worker_error` | string \| null | yes | null on success, short error description on failure |
| `open_questions` | string[] | yes | May be empty array. Orchestrator surfaces these to the user as caveats but does NOT pause for answers |
| `summary` | string | yes | One-paragraph human-readable description |

**Removed from TRI-27's worker report**: `pr_url` (workers don't push, so they never have a PR URL).

The orchestrator validates this schema strictly: any missing field, any unknown `status` value, any unparseable JSON → treat as `worker_error: "malformed report"`, mark the ticket `failed`, stop the chain. (R3.)

---

## Backward compatibility with v0.17.0

| Concern | Verdict |
|---|---|
| Existing `state.json` files from v0.17.0 chain runs load? | Yes. The new fields (`commit_sha`) are additive; if missing on read, treat as `null`. The new statuses (`committed`, `pushed`, `merged`) just won't appear in old data. |
| Existing v0.17.0 chain runs can be resumed? | Yes, but the resume flow will see them in `status: "in_progress"` with no `commit_sha` info, so it will offer to re-spawn the worker (which is correct — the old run had a broken contract anyway). |
| Existing v0.17.0 progress files can be read? | The format is different (`phase: "plan"` vs `phase: "plan_complete"`). The orchestrator treats unrecognized phases as `unknown`, which is honest. |
| Tests written for v0.17.0 still pass? | Mostly yes; only the tests that exercised the (broken) pause-relay assumption need to be removed. The state-file tests need updates for the new fields and statuses. |

No data migration is needed. The change is forward-only — once a run is created under v0.18.2, it uses the new schema; older runs degrade gracefully.
