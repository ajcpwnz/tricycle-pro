# Data Model: Session rename on workflow kickoff

**Feature**: TRI-31
**Date**: 2026-04-17

This feature adds no durable state — no files on disk, no database tables, no new config keys beyond hook registration. The only "data" is the transient computation of the target session label.

## Entities

### Kickoff invocation

The user's prompt triggering one of the watched commands. Not stored.

**Attributes (parsed from prompt text)**:

- `command` — one of `/trc.specify`, `/trc.headless`, `/trc.chain`. Anything else: hook is a no-op.
- `argument_string` — the tail of the user's prompt after the command name. Raw, before parse.
- For `/trc.specify` and `/trc.headless`:
  - `description` — the feature description. Passed to slug-derivation.
  - `ticket_id` (optional) — extracted via the same regex `create-new-feature.sh` uses, honoring the configured `branching.prefix`.
- For `/trc.chain`:
  - `range_or_list` — the ticket range-or-list argument (e.g. `TRI-100..TRI-104`, `TRI-100,TRI-103`).

### Derived session label

The computed label set via `hookSpecificOutput.sessionTitle`. Not stored — it's an output of the hook's JSON response, consumed by Claude Code.

**Derivation rules**:

- `/trc.specify`, `/trc.headless`: label = output of `derive-branch-name.sh --style <configured-style> [--prefix <configured-prefix>] [--issue <id-if-present>] --short-name <slug> <description>`. This is the **exact** branch name `create-new-feature.sh` would produce, byte-for-byte (FR-002).
- `/trc.chain` with range: label = `trc-chain-<left>..<right>` (e.g. `trc-chain-TRI-100..TRI-104`).
- `/trc.chain` with list: label = `trc-chain-<first>+<N-1>` where N is the total count (e.g. `trc-chain-TRI-100+2` for a 3-ticket list).
- `/trc.chain` with single ticket: label = `trc-chain-<only-ticket>+0` so the chain prefix still groups it with other chain sessions (per spec Edge Cases).

**Idempotency check**:

- Before emitting `sessionTitle`, the hook reads the current session label from `$CLAUDE_SESSION_TITLE` (or the host-equivalent env var; see quickstart). If it already equals the computed target, the hook emits no `sessionTitle` — a no-op. This satisfies FR-005 and SC-004.

## State transitions

None. Pure function from input prompt to output label.
