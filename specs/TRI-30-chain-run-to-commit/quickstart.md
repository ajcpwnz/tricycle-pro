# Quickstart: TRI-30 — /trc.chain run-to-commit

**Feature**: TRI-30-chain-run-to-commit
**Audience**: A developer using the **fixed** `/trc.chain` (v0.18.2+) on a small batch of related Linear tickets.

This quickstart covers what changes from the user's perspective. Most of TRI-27's quickstart still applies for the wrapper bits (preconditions, range parsing, max-8 enforcement, gitignore, troubleshooting); only the per-ticket interaction model changes.

---

## What changed for the user

**TRI-27 (broken)**: The user kicks off `/trc.chain TRI-100..TRI-102`. Each worker runs the trc workflow inside its own context, and at the push gate the worker pauses asking "approve push?". The orchestrator was supposed to forward the user's reply to the same worker via `SendMessage`, but the worker is already dead by then — so the chain hangs, silently, until the user notices.

**TRI-30 (fixed)**: Each worker runs the trc workflow up through a local commit, then **exits**. The orchestrator (the conversation you're actively talking to Claude in) reads the worker's report, prints a one-line summary, and asks you "push?" in plain dialog — no `SendMessage`, no ghost worker, no waiting on the wrong inbox.

---

## Happy path — three tickets

```text
/trc.chain TRI-100..TRI-102
```

Step-by-step:

1. **Resume detection / parse / Linear fetch / scope confirmation / epic brief / run init**: unchanged from TRI-27. You confirm scope, optionally provide a brief.

2. **For each ticket, in order**:

   a. Orchestrator: `update-ticket --status in_progress --started-now`.

   b. Orchestrator spawns the worker via `Agent({name: "chain-worker-TRI-100", ...})`. The worker prompt is the new run-to-commit brief (no pause instructions, no `SendMessage` mention).

   c. **Worker runs `/trc.headless` end-to-end**: specify → clarify → plan → tasks → analyze → implement → lint+test gate → version bump → `git add -A && git commit -m "<ticket>: <summary>"`. Then captures `commit_sha`, writes a final progress event with `phase: "committed"`, returns a structured JSON report, and exits.

   d. Orchestrator parses the JSON report. Validates required fields (R3 in research). Cross-checks the progress file's final phase is `committed`.

   e. Orchestrator marks the ticket: `update-ticket --status committed --commit-sha <sha> --branch <name> --lint pass --test pass`.

   f. **Orchestrator prints a one-line summary**:
      ```
      [TRI-100] abc123d — 7 files — lint:pass test:pass
      <one-paragraph summary from the report>
      
      Push TRI-100? (yes / no)
      ```

   g. **You answer in plain dialog** (no `SendMessage`, no relay). On `yes`:

      - `git push -u origin TRI-100-feat`
      - `update-ticket --status pushed --pr <url>`
      - `gh pr create --base main --title "..." --body "..."`
      - `gh pr merge <num> --squash --delete-branch`
      - `update-ticket --status merged`
      - Worktree cleanup: `git worktree remove`, `git branch -d`
      - `update-ticket --status completed --finished-now`
      - Continue to next ticket.

   h. On `no`: orchestrator stops the chain. The local commit and worktree remain for you to handle manually. Subsequent tickets stay `not_started`.

3. **After the loop**: `chain-run.sh close --terminal-status completed`, summary table, done.

**Total user interaction**: scope confirmation (1×), epic brief decision (1×), push approval (N× — once per ticket, every time, no carry-over).

---

## Resume from an interrupted chain

Same as TRI-27 surface, but with new state semantics:

```text
Found 1 interrupted chain run:
  - 20260415T200000abcd-TRI-100 (3 tickets)
    TRI-100: completed
    TRI-101: committed (awaiting push) — branch TRI-101-feat, commit def456
    TRI-102: not_started

Options: [R]esume, [D]iscard, [I]gnore.
```

On **Resume**, the orchestrator:

1. Reads the run's `state.json`.
2. **Cross-checks each non-`not_started` ticket against git** (R5 in research):
   - For TRI-100 (completed): no check needed.
   - For TRI-101 (committed, commit_sha=def456): runs `git -C ../tricycle-pro-TRI-101-feat rev-parse HEAD` and confirms it equals `def456`. ✓ → goes straight to the push gate (skips worker spawn).
   - For TRI-102 (not_started): no check needed; will spawn a fresh worker.
3. Walks the per-ticket loop starting at TRI-101, asking "push TRI-101?" first, then spawning a worker for TRI-102.

If the cross-check **fails** (e.g., state.json says `committed` but the worktree's HEAD doesn't match), the orchestrator surfaces the inconsistency and asks you to choose: re-spawn the worker, skip the ticket, or abort.

---

## Stop-on-failure

Unchanged in user-visible behavior from TRI-27. If a worker reports `status: failed` or any of the orchestrator's push/PR/merge steps fail, the chain stops, the failing ticket is marked `failed`, and subsequent tickets stay `not_started`. The local commit (if any) is left intact for inspection.

---

## What you'll never see again

- `[TRI-XXX] approve push?` from a sub-agent that has already terminated.
- `SendMessage({to: "chain-worker-...", ...})` returning `{"success": true}` followed by 30 minutes of nothing.
- A "runtime probe" at chain start that pretends to validate a feature that doesn't exist.

The whole pause-relay mechanism is gone. The orchestrator does push approval the way it always should have: in normal conversation, with you, in real time.

---

## Troubleshooting (delta from TRI-27)

**"Worker returned a malformed report"** — the worker's return message did not contain a parseable JSON block matching the schema. Check the worker's progress file (`specs/.chain-runs/<run-id>/<ticket-id>.progress`) for the last completed phase to figure out where it died. The chain stops; you can re-invoke `/trc.chain` on the remaining tickets after fixing whatever caused the worker to fail.

**"Resume cross-check failed: state says committed, but no matching commit in worktree"** — your worktree was modified or the worktree was deleted. Choose "re-spawn worker" to redo the ticket, or "skip" if you've already shipped it manually.

**"Worker finished but lint or test failed"** — the worker still committed (because that's its terminal state), but `lint_status` or `test_status` is `fail`. The orchestrator marks the ticket failed and stops the chain. Inspect the worktree, fix the failing test, and either re-run the chain or push the fix manually.

Everything else from TRI-27's troubleshooting still applies.
