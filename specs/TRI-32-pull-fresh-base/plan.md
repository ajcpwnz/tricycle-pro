# Implementation Plan: Pull fresh base branch before cutting new feature branch

**Branch**: `TRI-32-pull-fresh-base` | **Date**: 2026-04-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `/specs/TRI-32-pull-fresh-base/spec.md`

## Summary

Add a `refresh_base_branch` function to `core/scripts/bash/create-new-feature.sh` that runs once per kickoff, immediately before the new branch is created. Because every workflow-initting command (`/trc.specify`, `/trc.headless`, per-ticket `/trc.chain` workers) routes through this script, the refresh is automatic and uniform across all callers — no command-template edits needed (FR-002).

The function uses two git primitives dispatched on current-HEAD: `git pull --ff-only origin <base>` when the user is on `<base>`, or `git fetch origin <base>:<base>` otherwise. Fast-forward-only semantics prevent clobbering. A reachability probe via `git fetch --dry-run` with pattern-matched network-error signatures distinguishes "offline → degrade" from "divergent history → halt".

Opt-out is supported via `--no-base-refresh` flag or `TRC_SKIP_BASE_REFRESH=1` env var (FR-011) so historical-SHA branching remains possible.

**Version impact**: Minor bump: `0.19.1` → `0.20.0`. New automatic behavior visible to all consumers after `tricycle update`; not purely a bug fix.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`).
**Primary Dependencies**: git ≥ 2.20 (stable network-error signatures, universal in practice).
**Storage**: None.
**Testing**: `bash tests/run-tests.sh`. New test uses local bare-repo fixture to simulate origin advancement.
**Target Platform**: macOS + Linux developer workstations.
**Project Type**: CLI / developer tooling.
**Performance Goals**: Steady-state add of one `git fetch origin <base>` per kickoff (typically < 500 ms against GitHub). Offline path bounded by the `git fetch --dry-run` timeout (5–10 s).
**Constraints**: Never `git stash`, `git reset --hard`, or `git pull --rebase`. Never permanently switch the developer's current branch. Opt-out must be discoverable via `--help`.
**Scale/Scope**: 1 new function (~60 LoC) + new flag parsing (~5 LoC) + minimal `push.pr_target` awk parse (~10 LoC) inside `core/scripts/bash/create-new-feature.sh`. 1 new test script (~120 LoC) using bare-repo fixture. Total: ~200 LoC across 2 files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.trc/memory/constitution.md` is a placeholder. No codified principles to violate. CLAUDE.md NONNEGOTIABLES observed:

- **Lint & Test Before Done**: `bash tests/run-tests.sh` before completion.
- **Worktree-before-side-effects**: Work is in `../tricycle-pro-TRI-32-pull-fresh-base/`.
- **Branching style**: `issue-number` + `TRI` — branch is `TRI-32-pull-fresh-base`.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-32-pull-fresh-base/
├── plan.md                       # This file
├── research.md                   # R1–R6 decisions
├── data-model.md                 # Stateless — inputs + transient refresh outcomes
├── quickstart.md                 # 8 manual tests mapped to FRs/SCs
├── contracts/
│   └── refresh-base-branch.md    # Function contract + CLI flag addition
├── checklists/
│   └── requirements.md           # Spec quality checklist
└── tasks.md                      # Phase 2 output (/trc.tasks)
```

### Source Code (repository root)

```text
core/scripts/bash/
└── create-new-feature.sh         # UPDATED — new refresh_base_branch function,
                                  # new --no-base-refresh flag, new push.pr_target
                                  # awk parse; flow change to invoke refresh
                                  # before branch creation

tests/
├── test-refresh-base-branch.sh   # NEW — bare-repo fixture test covering:
│                                 #   * stale main fast-forwarded
│                                 #   * up-to-date is silent no-op
│                                 #   * dirty base halts (exit 20)
│                                 #   * offline warns + continues (exit 0)
│                                 #   * divergent local halts (exit 21)
│                                 #   * --no-base-refresh skips silently
│                                 #   * TRC_SKIP_BASE_REFRESH=1 skips silently
│                                 #   * non-git repo is silent no-op
└── run-tests.sh                  # UPDATED — wire the new test
```

**Structure Decision**: All changes land in `core/scripts/bash/create-new-feature.sh` (one file) plus the new test. The command templates (`trc.specify.md`, `trc.chain.md`, `trc.headless.md`) are intentionally NOT edited — FR-002's "automatic via the script" is the whole point of the placement decision (research R3).

## Implementation phases

### Phase 0 — Research (complete)

See `research.md`. Six decisions locked:

1. Use `git pull --ff-only` when on base, `git fetch origin <base>:<base>` otherwise.
2. Dirty-tree check uses `git diff-index --quiet HEAD --` + `git diff-files --quiet`, scoped to the current-branch-is-base case.
3. Refresh lives in `create-new-feature.sh` so every kickoff inherits automatically.
4. Reachability probe via `git fetch --dry-run`; network-error signatures pattern-matched to distinguish offline from divergent.
5. Opt-out via both `--no-base-refresh` flag and `TRC_SKIP_BASE_REFRESH=1` env var.
6. `--provision-worktree` interaction: refresh runs before branch creation, unconditionally; the two concerns are disjoint.

### Phase 1 — Design & Contracts (complete)

See `data-model.md` (stateless), `contracts/refresh-base-branch.md` (function contract + CLI flag addition), `quickstart.md` (8 tests, one per FR/edge case).

### Phase 2 — Tasks (delegated to `/trc.tasks`)

Dependency-ordered skeleton for the tasks file:

1. Add `read_pr_target` helper in `create-new-feature.sh` mirroring the existing `read_project_name` pattern.
2. Add `refresh_base_branch` function matching `contracts/refresh-base-branch.md`.
3. Parse `--no-base-refresh` flag; wire to a new `SKIP_BASE_REFRESH` variable.
4. Invoke `refresh_base_branch` from the main flow immediately after `cd "$REPO_ROOT"` and before any branch-creation git command.
5. Update `--help` output to document `--no-base-refresh`.
6. Add `tests/test-refresh-base-branch.sh` covering all 8 paths from `quickstart.md`.
7. Wire the new test into `tests/run-tests.sh`.
8. Confirm no regression in existing "Branch naming styles", "--no-checkout flag", and "--provision-worktree flag" test blocks.
9. Walk the quickstart manually on a consumer project once the above is green.
10. VERSION bump `0.19.1` → `0.20.0` in the final commit (per `/trc.implement` convention).

## Version awareness

Current VERSION: `0.19.1`.
Planned next: `0.20.0` — minor bump. Rationale: new automatic behavior visible to every consumer on every kickoff after `tricycle update`. Not a patch because the change is observable without opt-in; not a major because there is no backwards-incompatible break (opt-out exists and the flow is additive).

## Complexity Tracking

No constitution violations. Complexity budget respected:

- 1 file touched in `core/` + 1 new test.
- No new runtime language, no new MCP, no new external CLI dependency.
- No new durable state. No config migration.
- Opt-out (FR-011) is the single deliberate extra surface, warranted by the historical-SHA-branching use case called out in the spec.
