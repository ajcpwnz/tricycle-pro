# Research: Session rename mechanism

**Feature**: TRI-31 — Rename Claude Code session on workflow kickoff
**Date**: 2026-04-17

## R1 — Does Claude Code expose a session-rename mechanism usable by a running agent?

**Question**: The feature is only viable if an agent (or hook adjacent to an agent's turn) can rename the current session mid-conversation. Two candidate mechanisms investigated: (a) the `/rename` slash command, (b) the `UserPromptSubmit` hook's `hookSpecificOutput.sessionTitle`.

**Decision**: Use the **`UserPromptSubmit` hook** as the primary mechanism.

**Rationale**:

- The hook fires BEFORE the agent sees the user's prompt. That means the rename happens strictly before any agent side-effect can occur — FR-001's "first thing done" is satisfied by construction, not by prompt-engineering discipline.
- The hook output schema (`hookSpecificOutput.sessionTitle`) is a documented, supported way to set the session label from a local shell script. It does not depend on the agent "running a slash command", which is a fuzzier contract (agents emit text; whether a slash command in an agent's output actually executes is host-specific).
- Hook-based renaming keeps the command templates (`/trc.specify`, etc.) free of host-coupling — the slash commands remain pure workflow logic, and the rename concern lives in one place.
- The mechanism is already in Claude Code as of v2.1.94 per host docs, and tricycle-pro already manages `UserPromptSubmit` and sibling hooks via `tricycle generate settings`, so there's a known install path.

**Alternatives considered**:

- *`/rename <name>` invoked from within command templates*: Rejected as **primary** — agents emitting `/rename foo` in their response does not reliably execute as a slash command in every host; semantics are host-coupled and poorly documented. Retained as the **fallback** when the hook is absent (e.g. older tricycle-pro installs that haven't run `tricycle generate settings` since this feature landed).
- *Manipulate `~/.claude/projects/<slug>/sessions/<uuid>.jsonl` directly*: Rejected — undocumented format, high risk of breakage on Claude Code upgrades, no sync guarantees with the claude.ai UI.
- *Sub-agent `name:` field for worker labels*: Rejected — per host docs, this field is internal addressing only (used by `SendMessage`), not visible in session pickers. Workers will need their own `/rename` emission when spawned (see R4).

**Hard viability note**: If `hookSpecificOutput.sessionTitle` is not honored by the host at runtime (e.g. older Claude Code versions), the fallback instruction in the command templates still tells the user to run `/rename <name>` themselves, and the rest of the kickoff proceeds. This satisfies FR-006 and SC-005.

## R2 — Where is branch slug logic centralized? Can we reuse it without duplication?

**Question**: FR-007 mandates that the rename derivation reuse `create-new-feature.sh`'s slug logic, not duplicate it. Does that script currently expose its derivation as a library function, or only as a full-pipeline invocation?

**Decision**: Extract the slug-derivation logic from `core/scripts/bash/create-new-feature.sh` into a new pure-derivation helper at `core/scripts/bash/derive-branch-name.sh`. Both `create-new-feature.sh` and the new `UserPromptSubmit` hook source this helper. No behavioral change to `create-new-feature.sh`.

**Rationale**:

- `create-new-feature.sh` today does slug derivation inline alongside branch creation, worktree provisioning, `.trc` copying, and spec directory initialization — too much work for the hook to reuse via invocation. The hook needs derivation only.
- A separate helper that prints the computed branch name to stdout and takes the same `--style`, `--issue`, `--prefix`, `--short-name`, and the feature description as input is a narrow, single-responsibility script the hook can invoke under sub-second budget.
- Keeping `create-new-feature.sh` as the canonical entry point (now thinly delegating to the helper) preserves existing contracts — no downstream caller needs to change.

**Alternatives considered**:

- *Reimplement slug rules inside the hook in its own language*: Rejected — duplicates the exact logic FR-007 forbids.
- *Call `create-new-feature.sh` with a new `--derive-only` flag*: Rejected — adds a flag whose only job is suppressing side-effects, which is harder to reason about than a separate helper. Easier to add a new focused script.

## R3 — Chain-scoped label convention for `/trc.chain` orchestrator

**Question**: FR-003 requires a chain-scoped label distinguishable from feature-branch names. What's the exact convention?

**Decision**: `trc-chain-<first>..<last>` for a range argument, `trc-chain-<first>+<N>` for a list argument where `<N>` is the count of tickets beyond the first. Prefix is always `trc-chain-` so any chain-owned session is visually grouped in the session picker.

**Rationale**:

- `trc-chain-` prefix is not a valid branch name under any `branching.style` (feature-name style lowercases and slugifies, producing `trc-chain-*` slugs — but no kickoff description would naturally produce this prefix, and adding a guard in the hook prevents it).
- Range form mirrors the user's input verbatim (`/trc.chain TRI-100..TRI-104` → `trc-chain-TRI-100..TRI-104`) so the label round-trips to the originating command.
- List form (`TRI-100,TRI-103,POL-42`) compresses to `trc-chain-TRI-100+2` to avoid overly long labels while still naming the first ticket (the one most humans recognize by).

**Alternatives considered**:

- *Only range form, list invocations fall back to `trc-chain-<first>-+`*: Rejected — ambiguous for a reader.
- *Include run-id in the label*: Rejected — run-ids are for disk state, labels are for human operators; the run-id is too long and too random.

## R4 — Worker session labeling in `/trc.chain`

**Question**: FR-004 requires per-ticket worker session labels. Workers are sub-agents spawned via the `Agent` tool, running in their own conversation context. Does `/rename` work inside a sub-agent conversation? Does the `UserPromptSubmit` hook fire for sub-agents?

**Decision**: The worker's brief (per TRI-30 contract) instructs the worker to invoke `/rename <branch-name>` as its first action, before anything else. If that primitive is unsupported in sub-agent contexts, the feature degrades to orchestrator-labeled only (User Story 2 still delivers most of the value per the spec's edge cases).

**Rationale**:

- Workers receive their prompt directly from the orchestrator via the `Agent` tool call — the host's `UserPromptSubmit` hook may or may not fire on that synthetic prompt (undocumented). Hook behavior is therefore not a reliable primary mechanism at the worker level.
- The worker brief is the most direct instrument we already control (it's edited for every other worker contract change).
- The feature's SC-005 (graceful degradation) already covers the host-not-supporting-it case; no additional design cost.

**Alternatives considered**:

- *Orchestrator issues `/rename` via SendMessage after spawning*: Rejected — TRI-30 forbids SendMessage; workers are fire-and-report.
- *Name workers via the Agent tool's `name:` param and rely on host wiring that to a visible label*: Rejected per R1 alternatives (internal addressing only).
- *Skip worker labels entirely*: Rejected — User Story 2's "inspect in-flight worker" flow requires it for full value.

## R5 — Ordering of the hook relative to other `UserPromptSubmit` hooks

**Question**: `tricycle generate settings` may emit multiple `UserPromptSubmit` hooks in the future (none today). Does the rename hook need to run first?

**Decision**: The rename hook is the only `UserPromptSubmit` hook today and will be the first entry when one lands. Ordering is documented in the generator so future additions slot in after it.

**Rationale**:

- A rename that happens after another hook's side-effect would violate FR-001 in spirit if that other hook touched disk or Linear. Today there's no such hook; the rule is cheap to codify now so we don't relitigate later.

**Alternatives considered**:

- *No explicit ordering rule*: Rejected — invites silent drift.
