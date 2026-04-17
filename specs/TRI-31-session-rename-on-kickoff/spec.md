# Feature Specification: Rename Claude Code session on workflow kickoff

**Feature Branch**: `TRI-31-session-rename-on-kickoff`
**Created**: 2026-04-17
**Status**: Draft
**Input**: User description: "when kicking off a new effort (specify/headless/chain), agent should rename current session using the same approach thats used for branch/worktree naming. should be the first thing done"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Solo /trc.specify session is labeled by branch name (Priority: P1)

A developer invokes `/trc.specify "Add dark mode toggle"` from the Claude Code session list. Before the command does anything else — before it reads config, before it runs `create-new-feature.sh`, before it writes any spec file — it renames the current session to the same label the branch and worktree will use (e.g. `TRI-045-dark-mode-toggle` when the project uses `issue-number` style, or `dark-mode-toggle` for `feature-name` style).

**Why this priority**: Solo specify is the most common kickoff path and the baseline the other two commands extend. If this works, `/trc.headless` and `/trc.chain` just reuse the same derivation.

**Independent Test**: Open Claude Code with a clean session titled "Main". Run `/trc.specify "Improve onboarding"` in a project configured for `issue-number` with prefix `TRI`, supplying `TRI-077`. After the first agent turn completes, the session list shows the session labeled `TRI-077-improve-onboarding` — no transcript-derived placeholder label, no "(2)".

**Acceptance Scenarios**:

1. **Given** a Claude Code session with a default label and a project using `issue-number` style, **When** the user invokes `/trc.specify` with a description that contains a ticket ID, **Then** the session is renamed to `<TICKET>-<slug>` before any branch is created or spec file is written.
2. **Given** a project using `feature-name` style, **When** `/trc.specify` is invoked, **Then** the session is renamed to the slug (e.g. `export-csv`) exactly matching the branch name that will be produced.
3. **Given** a project using `ordered` style, **When** `/trc.specify` is invoked, **Then** the session is renamed to `NNN-<slug>` matching the ordered branch name.

---

### User Story 2 — /trc.chain orchestrator session is labeled by chain scope (Priority: P1)

When a user invokes `/trc.chain TRI-100..TRI-104`, the orchestrator session itself renames to a chain-level label that makes it distinguishable in the session list from solo feature sessions, and sub-agents spawned per ticket each carry the per-ticket label.

**Why this priority**: `/trc.chain` is precisely the workflow where ambiguous session labels hurt most — multiple chain runs in parallel are common, and without a chain-level label the operator must open each session to remember which range it owns. Worker-level labels let operators inspect a specific in-flight ticket mid-chain.

**Independent Test**: Run two concurrent `/trc.chain` invocations over different ticket ranges. The session list shows two chain-labeled sessions with no ambiguity (e.g. `trc-chain-TRI-100..TRI-104` and `trc-chain-POL-42,POL-55`). While a worker is running, any transcript or introspection of that worker shows the per-ticket label.

**Acceptance Scenarios**:

1. **Given** a chain range `TRI-100..TRI-104`, **When** the user invokes `/trc.chain TRI-100..TRI-104`, **Then** the orchestrator session is renamed to a chain-scoped label derived deterministically from the parsed ticket list BEFORE any Linear fetch, ticket-list confirmation, or worker spawn.
2. **Given** the orchestrator is processing ticket N of a chain, **When** a worker sub-agent is spawned, **Then** the worker's session label matches the branch name that will be produced for that ticket (same convention as User Story 1).
3. **Given** the orchestrator renames itself at the start, **When** the chain runs through multiple tickets, **Then** the orchestrator label does not change per ticket — it stays chain-scoped for the entire run.

---

### User Story 3 — /trc.headless inherits the same rename (Priority: P2)

`/trc.headless` is a thin wrapper that calls `/trc.specify` (plus downstream phases). The rename happens through whichever of the two commands is the outermost invoked by the user, and downstream invocations do not re-rename or clobber the label.

**Why this priority**: Important for consistency, but functionally the same derivation as User Story 1; it adds value only by ensuring the rename runs regardless of which command the user typed.

**Independent Test**: Invoke `/trc.headless "Add rate limiting" TRI-090`. Verify the session is renamed once, at the start, to `TRI-090-rate-limiting` (or the configured-style equivalent). Verify nothing downstream overwrites the label during the clarify/plan/tasks/implement phases.

**Acceptance Scenarios**:

1. **Given** `/trc.headless` is invoked directly by the user, **When** the outermost command runs, **Then** the session is renamed once at the start.
2. **Given** `/trc.headless` internally calls `/trc.specify`, **When** `/trc.specify`'s rename step runs, **Then** it detects the session is already correctly named and skips (idempotent no-op).

---

### Edge Cases

- **Claude Code does not expose a session-rename mechanism**: If the host runtime has no way for an agent to rename the current session, the command surfaces a one-line warning ("session rename unavailable in this host; continuing") and proceeds — it does not fail the kickoff. The project still gets a branch, worktree, spec, etc.
- **Branch name cannot be derived yet** (e.g. `issue-number` style with no ticket in the description): The command follows its existing flow — ask the user for the ticket ID — and performs the rename immediately after the ID is known, still before `create-new-feature.sh` is run. The "first thing" rule applies to side effects on the repo/filesystem, not to a prompt to the user.
- **Rename API call itself fails** (quota, runtime error): Log a warning, continue with the rest of the command.
- **User runs the same command twice in the same session**: The second invocation derives the same name, detects the session already matches, and is a no-op rename — no double-prefixing, no "(2)" suffix.
- **`/trc.chain` with a single ticket**: The orchestrator label still uses the chain-scoped convention (not the solo ticket convention) so the operator can distinguish chain-started work from specify-started work.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Kickoff commands (`/trc.specify`, `/trc.headless`, `/trc.chain`) MUST rename the current Claude Code session before any file-system, git, or Linear side effect. Prompting the user for missing inputs (e.g. ticket ID under `issue-number` style) does not count as a side effect.
- **FR-002**: For `/trc.specify` and `/trc.headless`, the new session name MUST equal the branch name that `core/scripts/bash/create-new-feature.sh` would produce for the same description, configured style, prefix, and (where applicable) ticket ID — byte-for-byte identical, with no additional prefix, suffix, or styling.
- **FR-003**: For `/trc.chain`, the orchestrator session name MUST be derived deterministically from the parsed ticket list using a chain-scoped convention (e.g. a `trc-chain-` prefix plus a compact rendering of the range or list) that is distinguishable from individual feature branch names.
- **FR-004**: For `/trc.chain`, each worker sub-agent spawned per ticket MUST have its session labeled with the ticket's branch name (same convention as FR-002).
- **FR-005**: The rename MUST be idempotent: invoking a command that would rename the session to the name it already has is a no-op and MUST NOT append suffixes, numerals, or duplicate prefixes.
- **FR-006**: If the host runtime exposes no mechanism for an agent to rename the current session, the command MUST surface a single-line warning and continue. It MUST NOT abort the kickoff.
- **FR-007**: The rename derivation MUST NOT duplicate the slug-generation logic that lives in `create-new-feature.sh` — it MUST reuse or call into that logic so that any future changes to branching rules apply to both branch names and session names at once.
- **FR-008**: The orchestrator session label set by `/trc.chain` MUST remain stable across ticket boundaries — it MUST NOT change per ticket as workers come and go.

### Key Entities

- **Session label**: The human-readable name shown in Claude Code's session/resume list. Bound 1:1 with the feature branch for solo kickoffs, or with the chain run for chain orchestrator sessions.
- **Derivation input**: For solo kickoffs — the feature description plus configured `branching.style` and (optionally) ticket ID and prefix. For chain — the parsed ticket list.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a session list showing ≥3 concurrent workflow sessions (any mix of specify/headless/chain), an operator can identify which session owns which feature/chain in under 5 seconds by reading session labels alone, without opening any session.
- **SC-002**: 100% of kickoff invocations where the host exposes a rename mechanism produce a session label that exactly matches the produced branch name (for specify/headless) or a chain-scoped label (for chain).
- **SC-003**: 0 cases where the rename runs after a branch, worktree, or spec file has already been created or modified on disk.
- **SC-004**: 0 cases where running the same kickoff command twice in a session produces a label with duplicated prefixes, numeric suffixes, or other drift.
- **SC-005**: When the host exposes no rename mechanism, the kickoff still completes successfully in 100% of invocations — the feature degrades, it does not break.

## Assumptions

- Claude Code exposes some mechanism — tool, settings write, or hook — by which an agent can rename its own session label. If it does not, the feature gracefully degrades per FR-006 and the plan phase MUST investigate whether such a mechanism can be added (either upstream in Claude Code or via a local hook/shim) as a pre-requisite.
- Sub-agents spawned via the `Agent` tool can also have their session labels set; if not, User Story 2 worker-labeling partially degrades but orchestrator-labeling still delivers most of the value.
- The branching-style derivation logic in `create-new-feature.sh` is the correct single source of truth for slug generation; any future changes land there and are automatically honored by this feature.
