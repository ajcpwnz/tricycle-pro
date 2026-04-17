# Research: Pull fresh base branch on kickoff

**Feature**: TRI-32 — Pull fresh base branch before cutting new feature branch
**Date**: 2026-04-17

## R1 — What git primitive refreshes local `<base>` without touching the current HEAD?

**Question**: FR-008 requires the refresh must not switch the developer's branch. Two primitives compete:

1. `git fetch origin <base>:<base>` — updates local `<base>` ref directly from remote, but only if fast-forward is possible; never touches the working tree or HEAD. Fails outright if `<base>` is currently checked out (git refuses to update a checked-out ref via refspec).
2. `git pull --ff-only origin <base>` — works only when `<base>` is the current branch; updates HEAD.

**Decision**: Use both, dispatched on current-HEAD check:

- If the current branch is `<base>` (checkout path): `git pull --ff-only origin <base>`.
- Otherwise (feature branch, detached HEAD, another worktree's branch): `git fetch origin <base>:<base>`.

**Rationale**:

- The two primitives cover the universe. Neither alone works in every case.
- Fast-forward-only semantics satisfy FR-003 (never destructive) in both cases — if FF is impossible, git exits non-zero and we halt with a clear message (FR-005).
- No `git stash` anywhere in the path, so FR-003's dirty-tree-preservation is structural.

**Alternatives considered**:

- *Always use `git fetch origin <base>:<base>`*: Rejected — it fails when `<base>` is currently checked out, which is the common case for a developer who just finished a previous feature and is back on `main`.
- *Always `git switch <base>; git pull --ff-only; git switch -`*: Rejected — transient HEAD movement could confuse editors, dirty-tree checks, and violate FR-008's spirit (even if it technically returns to the original branch).
- *`git fetch` + manual `git update-ref`*: Rejected — reimplements what `git fetch origin <base>:<base>` already does, and lacks its fast-forward safety check.

## R2 — How do we detect "dirty working tree" (FR-004) specifically on the base branch?

**Question**: FR-004 halts the kickoff if the base-branch checkout has uncommitted tracked changes. The check must be scoped correctly: dirty work on a feature branch (a separate worktree) is irrelevant to this kickoff; dirty work on the base checkout is disqualifying.

**Decision**: The check runs exactly when the current HEAD is `<base>`. In that case, use `git diff-index --quiet HEAD --` (tracked + staged) and `git diff-files --quiet` (unstaged). Non-zero exit from either → halt with the list of offending paths from `git status --porcelain=v1 | awk '/^(.M|M.|A.|.A|D.|.D|R.|.R)/ {print $NF}'`.

**Rationale**:

- `diff-index --quiet HEAD --` is the canonical, script-friendly cleanliness check that handles both tracked and staged changes in one shot.
- When the kickoff runs and HEAD is NOT `<base>` (e.g. the developer is on another feature branch, or detached), the refresh uses `git fetch origin <base>:<base>` which is a pure ref update — no working tree interaction — so dirty-tree is not a concern for that path.
- Untracked files are intentionally ignored. The kickoff process itself creates untracked paths (specs/ dirs, worktree copies) and forbidding them would be too strict.

**Alternatives considered**:

- *Always halt on any dirty-tree regardless of current branch*: Rejected — too strict; developers legitimately have uncommitted feature work in feature worktrees and that is none of this kickoff's business.
- *`git stash push`, refresh, `git stash pop`*: Rejected — explicitly forbidden by FR-003 (silent stash is the failure mode we want to avoid).

## R3 — Where does the refresh live in the call chain?

**Question**: FR-002 mandates the refresh be automatic — not imposed by command-template instructions. Which file owns it?

**Decision**: A new function `refresh_base_branch` inside `core/scripts/bash/create-new-feature.sh`, called from the script's main flow immediately after `cd "$REPO_ROOT"` and before any branch-creation git command. Every current and future caller of `create-new-feature.sh` (trc.specify, trc.headless, trc.chain workers, any future kickoff) inherits the behavior for free.

**Rationale**:

- `create-new-feature.sh` is the single choke point for new-branch creation across every kickoff in the system. Putting the refresh there satisfies FR-002 structurally rather than by convention.
- No command template edits required. That's a big win — the command templates are a high-change-rate surface, and anything keeping them simpler reduces drift risk.
- Placement immediately after `cd "$REPO_ROOT"` is correct: `REPO_ROOT` is the main checkout for new kickoffs, which is where the refresh must operate.

**Alternatives considered**:

- *New helper script `refresh-base-branch.sh`*: Rejected for the same-file case — doesn't add modularity benefit to justify a new file; the function is ~40 LoC.
- *Agent template instruction*: Rejected per FR-002 — drifts, becomes easy to forget in future templates, and doesn't cover `/trc.chain` workers automatically.

## R4 — How do we detect "unreachable origin" vs "real git error" for FR-006?

**Question**: FR-006 says network failure degrades gracefully (warn + continue), but FF-failure from divergent commits (FR-005) halts. Both paths return non-zero from `git fetch` — how do we distinguish?

**Decision**: Run `git fetch` with a short timeout and capture its stderr. If the failure mode is any of the network-class signatures (`Could not resolve host`, `Connection refused`, `Operation timed out`, `fatal: unable to access`, `Authentication failed`), warn and proceed from local state. Otherwise (genuine ref-level errors from the server or local git state), halt with the captured message.

Concretely: always attempt `git fetch origin <base>` first in a dry-run mode (no ref update). If that fails with a network signature, skip the refresh entirely and warn. If it succeeds, proceed to the actual `pull --ff-only` or `fetch origin <base>:<base>` step — any failure there is FR-005 divergence territory and halts.

**Rationale**:

- Separating "can I reach origin at all?" from "can I fast-forward cleanly?" keeps the two failure modes' error messages distinct, which matters for developer troubleshooting.
- Network signatures are stable enough across git versions (git 2.20+) that pattern-matching them is reasonable.
- A configurable short timeout (`GIT_HTTP_LOW_SPEED_LIMIT` / `GIT_HTTP_LOW_SPEED_TIME` or a `timeout` command wrapper) caps the offline-path latency cost per SC-005.

**Alternatives considered**:

- *Treat all fetch failures as network*: Rejected — silently proceeds past divergent-history cases the developer needs to know about.
- *Treat all fetch failures as fatal*: Rejected — violates FR-006.
- *Force developer to pass `--offline` when they're offline*: Rejected — defeats the whole automatic-refresh value.

## R5 — Opt-out mechanism (FR-011)

**Question**: FR-011 requires a per-invocation opt-out. Flag, env var, or both?

**Decision**: Both, with consistent semantics:

- `--no-base-refresh` flag on `create-new-feature.sh` (explicit per invocation).
- `TRC_SKIP_BASE_REFRESH=1` environment variable (useful for orchestrator / sub-agent contexts where flags are harder to thread through).

If either is set, the refresh is skipped silently. No warning — the opt-out is deliberate.

**Rationale**:

- Flag is discoverable via `--help`. Env var is threadable through orchestrators (`/trc.chain` could in theory decide to skip per-ticket refreshes, though it won't by default).
- Both paths call the same skip check, so there's no behavior drift.

**Alternatives considered**:

- *Only a flag*: Rejected — hard to thread through agent tool calls without template changes.
- *Only an env var*: Rejected — worse DX; developers can't discover it from `--help`.

## R6 — Interaction with `--provision-worktree`

**Question**: `--provision-worktree` (TRI-26) runs after branch creation. The refresh runs before. Is there any ordering or failure-mode interaction?

**Decision**: The refresh runs unconditionally before branch creation, regardless of whether `--provision-worktree` is passed. The provisioning step consumes the already-fresh branch ref. No special coordination needed; the two concerns are disjoint.

**Rationale**:

- Refresh → branch create (from fresh base SHA) → worktree add (from that branch) is a linear dependency chain with no feedback. Keeping the refresh as a pre-step is the simplest composition.
- Failure in refresh halts before branch create, which halts before worktree creation — correct failure propagation.

**Alternatives considered**:

- *Refresh only when `--provision-worktree` is passed*: Rejected — User Story 1 is about solo `/trc.specify` without worktree provisioning; it still needs the refresh.
