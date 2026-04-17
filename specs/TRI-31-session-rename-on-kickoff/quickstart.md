# Quickstart: Session rename on workflow kickoff

**Feature**: TRI-31
**Audience**: Contributors verifying this feature locally after `/trc.implement`.

## One-time setup

1. From the repo root of a consumer project that has run `tricycle init`:
   ```bash
   tricycle update
   tricycle generate settings
   ```
   The second command registers the new `UserPromptSubmit` hook at `.claude/hooks/rename-on-kickoff.sh` and writes it into `.claude/settings.json`.

2. Start a fresh Claude Code session:
   ```bash
   claude
   ```
   Confirm the session appears in the resume/picker UI with its default label (something like the project name or "Main").

## Test 1 — Solo /trc.specify rename (User Story 1)

```text
/trc.specify TRI-200 Export user data to CSV
```

**Expected**: Before the agent's first tool call, the session label in the picker flips to `TRI-200-export-user-data-csv` (or the style-derived equivalent for your `branching.style`). Verify by opening a new terminal, running `claude` (without resuming), and listing sessions — the freshly-renamed one is unambiguous.

## Test 2 — Chain orchestrator rename (User Story 2)

```text
/trc.chain TRI-300..TRI-302
```

**Expected**: Orchestrator session flips to `trc-chain-TRI-300..TRI-302` BEFORE the Linear ticket fetch begins. Sub-agent workers spawned per ticket have their own per-ticket labels (e.g. `TRI-300-<slug>`).

## Test 3 — Idempotency (SC-004)

In a session that's already been renamed by Test 1, run `/trc.specify` again with the same arguments.

**Expected**: No change. No `(2)` suffix, no double-prefixing.

## Test 4 — Graceful degradation (FR-006, SC-005)

Temporarily remove the hook entry from `.claude/settings.json` and run `/trc.specify`.

**Expected**: The command still completes end-to-end. As its first user-facing action, the agent emits a `/rename <target>` instruction (fallback path). No hard failure.

## Test 5 — `/trc.headless` inheritance (User Story 3)

```text
/trc.headless TRI-400 Add rate limiting to the API
```

**Expected**: Session renamed once at start to `TRI-400-add-rate-limiting-api`. Downstream `/trc.specify` invocation inside headless detects the label already matches and is a no-op.

## Test 6 — `create-new-feature.sh` parity (FR-007)

```bash
bash core/scripts/bash/create-new-feature.sh "Test" --json --style issue-number --issue TRI-500 --prefix TRI --short-name "test-feature"
```

Observe the `BRANCH_NAME` field. Compare to:

```bash
bash core/scripts/bash/derive-branch-name.sh --style issue-number --issue TRI-500 --prefix TRI --short-name "test-feature" "Test"
```

**Expected**: Byte-for-byte identical.
