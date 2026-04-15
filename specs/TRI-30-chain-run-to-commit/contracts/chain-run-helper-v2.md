# Contract Delta: `chain-run.sh` v2 (TRI-30)

**Feature**: TRI-30-chain-run-to-commit
**Base contract**: [TRI-27 chain-run-helper.md](../../TRI-27-trc-chain-orchestrator/contracts/chain-run-helper.md)
**Scope**: Document only the changes from the TRI-27 contract. Anything not mentioned is unchanged.

---

## Subcommands unchanged in TRI-30

These subcommands are unchanged in behavior, flags, JSON shape, exit codes, and idempotency:

- `parse-range <arg>`
- `init --ids <json> [--brief <path>] [--ids-raw <string>]`
- `get --run-id <id>`
- `list-interrupted`
- `close --run-id <id> --terminal-status <s> [--reason <string>]`
- `progress --run-id <id> --ticket <tid>`

Reference the TRI-27 contract directly.

The `/trc.chain` user-facing CLI is also unchanged: same range/list grammar, same scope confirmation flow, same error messages from `parse-range`. Only the per-ticket loop body changes inside the orchestrator's command file — that's an internal behavior change, not an external contract change.

---

## Δ Subcommand: `update-ticket`

### New flag: `--commit-sha <sha>`

**Purpose**: Record the worker's final commit SHA on the ticket.

**Validation**:
- Required when `--status committed` (otherwise → `ERR_COMMIT_SHA_REQUIRED`, exit 2).
- Optional and ignored if not transitioning to/through `committed`.
- Once set, immutable (a second `--commit-sha` with a different value on a ticket that already has one → `ERR_COMMIT_SHA_IMMUTABLE`, exit 2).

### New valid `--status` values

The valid `--status` values become:

```
not_started, in_progress, committed, pushed, merged, completed, failed, skipped
```

All eight are accepted by `update-ticket`. The forward-transition validator (see below) enforces ordering.

### New validation: forward transitions

Each status has a forward rank:

| Status | Rank |
|---|---|
| `not_started` | 0 |
| `in_progress` | 1 |
| `committed` | 2 |
| `pushed` | 3 |
| `merged` | 4 |
| `completed` | 5 |
| `failed` | terminal (legal from any rank ≥ 0) |
| `skipped` | terminal (legal only from rank 0) |

**Rule**: a transition from current rank R₁ to new rank R₂ is legal iff:
- R₂ > R₁ (strict forward progress), OR
- R₂ is `failed` (always legal from non-terminal), OR
- R₂ is `skipped` AND R₁ == 0 (only legal from `not_started`).

Illegal transitions return `ERR_BAD_TRANSITION` (new error code, exit 2). Examples:
- `not_started → merged`: skips ranks → ERR_BAD_TRANSITION
- `committed → in_progress`: backward → ERR_BAD_TRANSITION
- `completed → committed`: backward → ERR_BAD_TRANSITION
- `committed → failed`: legal (always)
- `not_started → skipped`: legal (special case)
- `in_progress → skipped`: ERR_BAD_TRANSITION (rank > 0)

### Relaxed `--pr` validation

**Old (TRI-27)**: `--pr` only allowed with `--status completed` → otherwise `ERR_PR_REQUIRES_COMPLETED`.

**New (TRI-30)**: `--pr` allowed with `--status` ∈ {`pushed`, `merged`, `completed`}. The error code `ERR_PR_REQUIRES_COMPLETED` is **renamed** to `ERR_PR_REQUIRES_PUSHED_OR_LATER` (exit code unchanged: 2). The error message is updated:

> `pr_url is only allowed when status is pushed, merged, or completed`

### New error codes

| Code | Exit | When |
|---|---|---|
| `ERR_BAD_TRANSITION` | 2 | Attempted forward transition violates the rank rules above |
| `ERR_COMMIT_SHA_REQUIRED` | 2 | `--status committed` without `--commit-sha` |
| `ERR_COMMIT_SHA_IMMUTABLE` | 2 | Setting `--commit-sha` to a different value on a ticket that already has one |
| `ERR_PR_REQUIRES_PUSHED_OR_LATER` | 2 | `--pr` set with status not in {pushed, merged, completed}. Renamed from `ERR_PR_REQUIRES_COMPLETED`. |

### Updated `current_index` advancement rule

After a successful `update-ticket`, the helper advances `current_index` past any prefix of tickets whose status is in **{`completed`, `pushed`, `merged`, `skipped`}** *or* `committed`-with-orchestrator-still-processing — wait, no.

Refined rule: advance past tickets whose status is in {`committed`, `pushed`, `merged`, `completed`, `skipped`}. The reasoning is that `committed` means the worker is done; the orchestrator's push step happens **after** that index advance, on the same ticket, but the next worker spawn (if any) should start at the next ticket. The `current_index` semantics now mean "next ticket to spawn a worker for", not "next ticket needing any work at all".

This is the cleanest read for the resume flow: a `committed` ticket does not need a worker re-run, so the index correctly skips it.

### Worked example: full per-ticket transition path

```bash
# Worker phase
chain-run.sh update-ticket --run-id $R --ticket TRI-100 --status in_progress --started-now
# (worker runs, eventually commits)
chain-run.sh update-ticket --run-id $R --ticket TRI-100 --status committed --commit-sha abc123 --branch TRI-100-feat --lint pass --test pass
# Orchestrator phase
chain-run.sh update-ticket --run-id $R --ticket TRI-100 --status pushed --pr https://github.com/.../pull/123
chain-run.sh update-ticket --run-id $R --ticket TRI-100 --status merged
chain-run.sh update-ticket --run-id $R --ticket TRI-100 --status completed --finished-now
```

Each call is legal under the forward-transition rule. The `commit_sha` is set once at `committed` and persists; subsequent calls don't repeat it.

---

## Test contract additions

Each new error code MUST have at least one test case:
- `ERR_BAD_TRANSITION`: at least 3 cases (skip-forward, backward, illegal-skipped)
- `ERR_COMMIT_SHA_REQUIRED`: 1 case
- `ERR_COMMIT_SHA_IMMUTABLE`: 1 case
- `ERR_PR_REQUIRES_PUSHED_OR_LATER`: 1 case

The full transition path (`not_started → in_progress → committed → pushed → merged → completed`) MUST have an end-to-end bash test that walks the entire path and asserts state after each step.

The static FR-013 guard test (`tests/test-chain-run-no-sendmessage.sh`) is documented in research.md R6.
