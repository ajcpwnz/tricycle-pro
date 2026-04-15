# Contract: `chain-run.sh` helper + `/trc.chain` command invocation

**Feature**: TRI-27-trc-chain-orchestrator
**Location**: `core/scripts/bash/chain-run.sh`
**Consumer**: `core/commands/trc.chain.md` (the orchestrator command template) and its tests

This document is the **stable contract** between the orchestrator agent instructions and the deterministic bash helper. Any change to subcommand names, flags, stdout JSON shape, or exit codes is a breaking change to the feature.

---

## Command Invocation (user-facing)

```
/trc.chain <range-or-list>
```

### Argument grammar

```text
range-or-list := range | list
range         := PREFIX "-" N ".." PREFIX "-" M          # same prefix required
list          := token ( "," token )*
token         := PREFIX "-" N
PREFIX        := [A-Z][A-Z0-9]*
N, M          := [0-9]+, where N <= M for ranges
```

**Examples**:

| Input | Valid? | Result |
|---|---|---|
| `TRI-100..TRI-105` | yes | 6 tickets, contiguous |
| `TRI-100,TRI-103,TRI-107` | yes | 3 tickets, non-contiguous |
| `TRI-100,POL-42,TRI-105` | yes | mixed prefixes allowed in list form |
| `TRI-1..TRI-9` | no | count > 8 (range expansion) |
| `TRI-1..POL-5` | no | mixed prefix in range form |
| `TRI-5..TRI-1` | no | descending range |
| `tri-100` | no | lowercase prefix |
| `TRI-100,TRI-100` | yes | deduplicated → 1 ticket |
| `` (empty) | no | empty input |

### User-facing error messages

Produced by the orchestrator using error codes returned by `chain-run.sh parse-range`:

| Error | Message |
|---|---|
| `ERR_EMPTY_INPUT` | "No ticket IDs provided. Usage: /trc.chain <range-or-list>" |
| `ERR_MALFORMED_TOKEN` | "Invalid ticket ID: '<token>'. Expected PREFIX-NUMBER (e.g., TRI-42)." |
| `ERR_RANGE_DESCENDING` | "Range is descending: '<arg>'. Use ascending order: PREFIX-N..PREFIX-M with N <= M." |
| `ERR_RANGE_MIXED_PREFIX` | "Range cannot mix prefixes: '<arg>'. Use a comma-separated list for mixed prefixes." |
| `ERR_COUNT_EXCEEDED` | "Range resolves to <count> tickets. Maximum is 8. Break the range into smaller batches for quality reasons." |
| `ERR_COUNT_ZERO` | "Range resolves to 0 tickets after deduplication." |

---

## Helper Subcommands

All subcommands:
- Read flags via standard `--flag value` style.
- Write JSON to stdout on success.
- Write JSON (`{"error": "...", "code": "ERR_..."}`) to stderr on failure.
- Exit `0` on success, non-zero on failure (see per-subcommand sections).
- Are idempotent where noted.

### `parse-range <arg>`

**Purpose**: Parse a range-or-list argument into a validated, deduplicated ticket ID array.

**Positional args**: `<arg>` — the raw range-or-list string.

**Flags**: none.

**Stdout on success** (exit 0):

```json
{"ids": ["TRI-100", "TRI-101", "TRI-102"], "count": 3}
```

**Stderr on failure** (exit non-zero):

```json
{"error": "Range resolves to 9 tickets...", "code": "ERR_COUNT_EXCEEDED"}
```

**Exit codes**:
- `0` — success
- `2` — malformed input (any `ERR_*` from the table above)

**Idempotent**: yes (pure function).

---

### `init --ids <json-array> [--brief <path>] [--ids-raw <string>]`

**Purpose**: Create a new chain run: generate run-id, create the `specs/.chain-runs/<run-id>/` directory, initialize `state.json`, and optionally copy/create `epic-brief.md`.

**Flags**:
- `--ids <json-array>` **required**. JSON array of ticket IDs as returned by `parse-range`.
- `--brief <path>` optional. If provided, copy the file to `specs/.chain-runs/<run-id>/epic-brief.md`. If omitted, `epic_brief_path` is null.
- `--ids-raw <string>` optional. Original user input (for provenance in `state.json`). Advisory only.

**Stdout on success** (exit 0):

```json
{
  "run_id": "20260415T123456-TRI-100",
  "state_path": "specs/.chain-runs/20260415T123456-TRI-100/state.json",
  "brief_path": "specs/.chain-runs/20260415T123456-TRI-100/epic-brief.md"
}
```

`brief_path` is null if no brief was provided.

**Stderr on failure** (exit non-zero):
- `{"error": "ids array is empty", "code": "ERR_COUNT_ZERO"}` — exit 2
- `{"error": "ids array has N > 8 tickets", "code": "ERR_COUNT_EXCEEDED"}` — exit 2
- `{"error": "brief path not found: <path>", "code": "ERR_BRIEF_MISSING"}` — exit 2
- `{"error": "state directory already exists", "code": "ERR_STATE_COLLISION"}` — exit 3 (very rare; indicates same-second run-id collision)

**Idempotent**: no. Each call generates a fresh run-id.

**Side effects**: creates directory `specs/.chain-runs/<run-id>/`, writes `state.json` atomically (tmp + rename), optionally copies brief.

---

### `get --run-id <id>`

**Purpose**: Read and print the full `state.json` for a given run.

**Flags**:
- `--run-id <id>` **required**.

**Stdout on success** (exit 0): the entire `state.json` contents, pretty-printed.

**Stderr on failure**:
- `{"error": "run not found: <id>", "code": "ERR_RUN_NOT_FOUND"}` — exit 4

**Idempotent**: yes (read-only).

---

### `update-ticket --run-id <id> --ticket <ticket-id> --status <status> [options]`

**Purpose**: Transition one ticket's state inside an existing chain run. Also advances `current_index` to the next non-complete ticket and updates `updated_at`.

**Flags**:
- `--run-id <id>` **required**.
- `--ticket <ticket-id>` **required**. Must appear in `state.json` `ticket_ids`.
- `--status <status>` **required**. One of `in_progress`, `completed`, `failed`, `skipped`.
- `--branch <name>` optional. Git branch name.
- `--worktree <path>` optional. Worktree path.
- `--pr <url>` optional. PR URL (only valid with `--status completed`).
- `--lint <pass|fail|skipped>` optional.
- `--test <pass|fail|skipped>` optional.
- `--report <path>` optional. Path to worker's report markdown.
- `--open-question <string>` optional, repeatable. Each occurrence appends one question to `open_questions`.
- `--started-now` optional flag. Sets `started_at` to current time. Typically used when transitioning `not_started → in_progress`.
- `--finished-now` optional flag. Sets `finished_at` to current time. Typically used when transitioning `in_progress → completed/failed`.

**Stdout on success** (exit 0): the updated `state.json` contents, pretty-printed.

**Stderr on failure**:
- `{"error": "run not found: <id>", "code": "ERR_RUN_NOT_FOUND"}` — exit 4
- `{"error": "ticket not in run: <ticket-id>", "code": "ERR_TICKET_NOT_IN_RUN"}` — exit 5
- `{"error": "run is already closed (status=<s>)", "code": "ERR_RUN_CLOSED"}` — exit 6
- `{"error": "invalid status: <s>", "code": "ERR_BAD_STATUS"}` — exit 2
- `{"error": "pr_url requires status=completed", "code": "ERR_PR_REQUIRES_COMPLETED"}` — exit 2

**Idempotent**: no (each call bumps `updated_at`).

**Side effects**: atomic write to `state.json`. If the update brings top-level `status` from `in_progress` to `completed` (all tickets terminal), the helper does NOT auto-close — the orchestrator must call `close` explicitly.

---

### `list-interrupted`

**Purpose**: Find all chain runs whose top-level `status == "in_progress"` (per FR-020).

**Flags**: none.

**Stdout on success** (exit 0):

```json
{
  "runs": [
    {
      "run_id": "20260415T123456-TRI-100",
      "created_at": "2026-04-15T12:34:56Z",
      "updated_at": "2026-04-15T12:45:00Z",
      "ticket_ids": ["TRI-100", "TRI-101", "TRI-102"],
      "current_index": 1,
      "next_ticket_id": "TRI-101"
    }
  ]
}
```

Returns `{"runs": []}` if nothing is interrupted.

**Stderr on failure**: none expected (missing `specs/.chain-runs/` directory returns empty list, not an error).

**Exit code**: always 0 unless catastrophic I/O failure.

**Idempotent**: yes (read-only).

---

### `close --run-id <id> --terminal-status <completed|failed|aborted> [--reason <string>]`

**Purpose**: Mark a chain run as terminal so it is no longer offered for resume (per FR-021). Also deletes `.progress` files for cleanliness.

**Flags**:
- `--run-id <id>` **required**.
- `--terminal-status <s>` **required**. One of `completed`, `failed`, `aborted`.
- `--reason <string>` optional. Populates `terminal_reason`.

**Stdout on success** (exit 0): the closed `state.json` contents.

**Stderr on failure**:
- `{"error": "run not found: <id>", "code": "ERR_RUN_NOT_FOUND"}` — exit 4
- `{"error": "invalid terminal status: <s>", "code": "ERR_BAD_STATUS"}` — exit 2

**Idempotent**: yes with a diagnostic warning to stderr if the run is already closed (no state change, exit 0).

**Side effects**: atomic write to `state.json` setting `status` and `terminal_reason`; removes `<ticket-id>.progress` files in the run directory.

---

## Orchestrator → Helper call flow (reference)

```text
/trc.chain TRI-100..TRI-102
    │
    ├─► SendMessage runtime probe (R7)
    │
    ├─► chain-run.sh parse-range "TRI-100..TRI-102"
    │       ← {"ids": ["TRI-100","TRI-101","TRI-102"], "count": 3}
    │
    ├─► (fetch ticket bodies via Linear MCP, hard-fail on unreachable — FR-002)
    │
    ├─► chain-run.sh list-interrupted
    │       ← {"runs": []}          (or prompt resume if non-empty)
    │
    ├─► chain-run.sh init --ids '["TRI-100","TRI-101","TRI-102"]'
    │       ← {"run_id":"...", "state_path":"...", "brief_path": null}
    │
    ├─► (optionally create epic-brief.md, prompt user)
    │
    ├─► for each ticket:
    │       chain-run.sh update-ticket ... --status in_progress --started-now
    │       Agent({name:"chain-worker-<id>", prompt: worker_brief})
    │       (loop: SendMessage on pause, read <id>.progress for display)
    │       chain-run.sh update-ticket ... --status completed --finished-now \
    │                    --branch ... --pr ... --lint pass --test pass --report ...
    │
    └─► chain-run.sh close --run-id <id> --terminal-status completed
            ← (emit final summary table)
```

---

## Test contract (for `/trc.tasks` to reference)

Each subcommand MUST have at least one test that exercises:
1. happy path with representative input
2. at least one documented error code above
3. (for `init`, `update-ticket`, `close`) round-trip: write, then read via `get`, assert expected field values

Test files live under `tests/test-chain-run-*.js` using `node --test`, following the existing TRI-26 pattern. Pure-bash assertions in `tests/run-tests.sh` are additionally acceptable for end-to-end shell integration scenarios.
