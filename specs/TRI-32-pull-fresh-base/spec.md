# Feature Specification: Pull fresh base branch before cutting new feature branch in kickoff commands

**Feature Branch**: `TRI-32-pull-fresh-base`
**Created**: 2026-04-17
**Status**: Draft
**Input**: User description: "now also make sure all workflow initting commands (specify/headless, each new task in chain, first pull fresh working branch)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Solo `/trc.specify` branches off fresh upstream (Priority: P1)

A developer has had their local checkout of `main` open for a day. Collaborators have merged other PRs in the meantime. The developer runs `/trc.specify "Add dark mode toggle"`. Before any new branch is created, the kickoff fetches the configured base branch from `origin` and fast-forwards local `main`. The feature branch is then cut from the just-updated tip, so the developer never starts work against a stale file tree or unknowingly rebuilds code someone else already landed.

**Why this priority**: Most common kickoff path. Catching stale-main here prevents the class of "mysterious conflict / phantom file" bug that wastes the most time for solo developers.

**Independent Test**: On a repo where local `main` is behind `origin/main` by at least one commit, run `/trc.specify "Test feature"`. Verify that before the new branch is created, local `main` is fast-forwarded to match origin (observable via `git rev-parse main` matching `git rev-parse origin/main`). Verify the new feature branch points at the same SHA as the freshly-pulled `main`, not at the stale SHA.

**Acceptance Scenarios**:

1. **Given** local `main` is behind `origin/main`, the working tree is clean, and the developer is on `main` or a detached HEAD, **When** the developer runs `/trc.specify`, **Then** local `main` is updated to match `origin/main` and the new branch is cut from the updated SHA.
2. **Given** local `main` is already up to date, **When** the developer runs `/trc.specify`, **Then** the kickoff is a silent no-op on the base-branch update step (no spurious output, no wasted time beyond a cheap `fetch`).
3. **Given** the new branch is created, **When** `/trc.specify` continues to provision the worktree, **Then** the worktree's checked-out HEAD is the fresh base SHA.

---

### User Story 2 — Each `/trc.chain` worker branches off the chain's cumulative progress (Priority: P1)

A developer runs `/trc.chain TRI-100..TRI-104`. The orchestrator processes ticket 1, merges its PR to `main`, and moves on to ticket 2. Before the worker for ticket 2 is spawned — and before its feature branch is created — the chain pulls `main` fresh, so ticket 2's branch includes ticket 1's already-merged commits. The same applies for tickets 3, 4, 5.

**Why this priority**: This is the motivating scenario. Without it, every chain past the first ticket silently builds on stale main and risks conflicts with the very commits the same chain run just merged. Chains are the workflow most harmed by the current behavior and most helped by the fix.

**Independent Test**: Run `/trc.chain` on two small tickets where ticket 2 modifies a file ticket 1 also modifies. Ticket 1 merges cleanly. Before ticket 2's worker is spawned, verify the worker's worktree base SHA equals the squash-commit SHA from ticket 1's merge (not the pre-chain `main` SHA).

**Acceptance Scenarios**:

1. **Given** ticket N of a chain has been merged to `main`, **When** the orchestrator prepares to spawn the worker for ticket N+1, **Then** local `main` is fetched and fast-forwarded before `create-new-feature.sh` runs for ticket N+1.
2. **Given** ticket 1 in a chain is the first to run, **When** its worker is spawned, **Then** the base-branch refresh still runs (the first ticket benefits from any upstream changes landed while the user was preparing to invoke the chain).
3. **Given** a ticket fails and the chain stops, **When** the developer later reruns `/trc.chain` with a resumed or adjusted range, **Then** the refresh runs on every remaining ticket's kickoff as normal.

---

### User Story 3 — `/trc.headless` inherits the refresh (Priority: P2)

`/trc.headless` is the same shape as `/trc.specify` plus downstream phases. The base-branch refresh runs at its start, identically.

**Why this priority**: Uniformity. `/trc.headless` funnels into the same `create-new-feature.sh` call, so if User Story 1 is satisfied via that script, `/trc.headless` inherits for free. Still worth a dedicated acceptance pass so regressions are caught.

**Independent Test**: Same as User Story 1 but invoked via `/trc.headless`.

**Acceptance Scenarios**:

1. **Given** local `main` is stale, **When** `/trc.headless` is invoked, **Then** the refresh runs before the branch is created.

---

### Edge Cases

- **Uncommitted changes in the main checkout**: If the developer has dirty working-tree changes on `main`, a `git pull` would either fail or mangle their work. The kickoff MUST detect this, surface the dirty paths, and halt with a clear error — never `git stash` silently, never `git reset --hard`, never force-pull. The developer resolves (commit, stash, or discard), then retries.
- **Local `main` has diverged from origin** (commits that aren't on origin and conflict with origin's changes): Fast-forward fails. The kickoff surfaces the divergence and halts. Developer resolves manually.
- **Offline / unreachable remote**: `git fetch` fails. The kickoff MUST NOT hard-fail — it warns that the refresh was skipped and proceeds from local state. The developer is alerted so they know they may be starting from stale.
- **Project is not a git repository** (niche — tricycle-pro supports `--no-git` init): The refresh step is a silent no-op.
- **Developer is already on a non-base branch when invoking the kickoff**: The refresh must not switch branches permanently. It brings local `main` up to date (via `git fetch origin main:main` semantics — which updates the ref without touching the current HEAD), then proceeds as normal.
- **`push.pr_target` is configured to something other than `main`** (e.g. `staging`): The refresh operates on the configured base, not on literal `main`.
- **Orchestrator session's main checkout was itself used to land ticket N's merge** (as in `/trc.chain` with `auto_merge: true` + squash + delete-branch): After the merge, local `main` may already reflect the squash commit (gh pr merge updates local refs when it can). The refresh is still run — it's a cheap no-op in that case.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Kickoff commands (`/trc.specify`, `/trc.headless`) and every per-ticket worker spawned by `/trc.chain` MUST refresh the configured base branch (`push.pr_target`, default `main`) from `origin` before creating the new feature branch.
- **FR-002**: The refresh operation MUST be invoked automatically by the branch-creation path — not by the agent template prompt — so all current and future callers of `create-new-feature.sh` get the behavior for free.
- **FR-003**: The refresh MUST be a safe fast-forward — never `git reset --hard`, never `git pull --rebase` against the user's own local commits, never `git stash` of uncommitted changes.
- **FR-004**: If the working tree of the main checkout is dirty (uncommitted tracked changes on the base branch), the refresh MUST halt with a clear error naming the offending files. The kickoff does NOT proceed to create a branch after a failed refresh.
- **FR-005**: If local `<base>` has commits that `origin/<base>` does not (i.e. is ahead or divergent), the refresh MUST halt with a clear error. The developer resolves before retrying.
- **FR-006**: If the remote is unreachable (network error, `fetch` timeout, auth failure), the refresh MUST log a warning and proceed from local state. The kickoff does NOT fail because of a missing network.
- **FR-007**: If the repo is not a git repository (or has `HAS_GIT=false` in `create-new-feature.sh`'s detection), the refresh MUST be a silent no-op.
- **FR-008**: The refresh MUST NOT permanently switch the developer's current branch. If they were on a feature branch or detached HEAD when invoking the kickoff, they remain there afterwards.
- **FR-009**: The base-branch name MUST be read from `tricycle.config.yml`'s `push.pr_target` key. If unset, the default is `main`.
- **FR-010**: The refresh behavior MUST be observable enough to test: a test fixture that configures a local "origin" remote, advances origin by one commit, runs a kickoff, and asserts local base is fast-forwarded.
- **FR-011**: A developer MUST be able to opt out of the refresh for a single invocation via an explicit flag (e.g. `--no-base-refresh` on `create-new-feature.sh` or an env var `TRC_SKIP_BASE_REFRESH=1`). Rationale: occasionally a developer branches deliberately off a historical SHA; the feature should not make that impossible.

### Key Entities

- **Base branch**: The ref configured as `push.pr_target`. Kickoff commands cut new feature branches from this. Typical value: `main`.
- **Refresh operation**: A `git fetch origin <base>` followed by a safe, non-branch-switching fast-forward of local `<base>` to match `origin/<base>` if one is possible.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of kickoff invocations where the remote is reachable, the working tree is clean, and `--no-base-refresh` is not set, the newly created feature branch's base SHA equals `origin/<base>`'s tip SHA at the moment of branch creation.
- **SC-002**: In 0% of kickoff invocations does the refresh clobber, discard, or alter uncommitted changes in the main checkout.
- **SC-003**: In 100% of kickoff invocations where the remote is unreachable, the kickoff still completes (falling back to local state) rather than hard-failing.
- **SC-004**: For `/trc.chain` runs of 3+ tickets where earlier tickets merge cleanly, later tickets' worker branches reflect those earlier merges — verifiable by comparing each worker's base SHA to the squash-commit SHA of the prior ticket.
- **SC-005**: Zero increase in steady-state kickoff latency beyond the cost of one `git fetch origin <base>` (typically sub-second against GitHub).

## Assumptions

- The developer's `origin` remote points at the canonical upstream. If they have a fork layout (`origin` = fork, `upstream` = canonical), the refresh operates on `origin/<base>` — which, for that layout, is the developer's own fork. Fork workflows are out of scope; if refresh-from-upstream is needed, that's a future extension.
- `git fetch origin <base>:<base>` (the no-branch-switch fast-forward) is supported; this is universal since git 1.6+.
- The refresh runs from the main checkout's git dir (not inside an existing feature worktree). `create-new-feature.sh` already runs there when invoked for new kickoffs.
- `push.pr_target` reliably names a branch that exists on origin. If the project is configured with a typoed or non-existent `pr_target`, the fetch fails and the kickoff halts with whatever git surfaces; this is acceptable — the fix is to correct the config.
