# Quickstart: Pull fresh base branch on kickoff

**Feature**: TRI-32
**Audience**: Contributors verifying this feature locally after `/trc.implement`.

## Setup

Clone two sibling copies of a tricycle-pro-based fixture repo — one as `origin` (bare), one as local — to simulate upstream advancing between kickoffs. Or point a real project's clone at a private test branch on GitHub.

## Test 1 — Happy path: stale local `main` is fast-forwarded (User Story 1)

```bash
# In local clone with origin behind by 1 commit:
git log --oneline -1 main                      # note the current SHA
git log --oneline -1 origin/main               # note the tip SHA — will differ after step below
# Advance origin:
git -C "$ORIGIN_BARE" commit --allow-empty -m "advance origin"
# Re-fetch so origin/main reflects the advance (simulate the developer being offline then back):
git fetch --dry-run origin main                 # still stale locally for now
# Kickoff:
.trc/scripts/bash/create-new-feature.sh "Test feature" --json --style feature-name --short-name "test"
# Verify:
git rev-parse main                              # now equals origin/main
git rev-parse <new-branch-name>                 # same SHA
```

**Expected stderr**: `[specify] Base branch main fast-forwarded to <short-sha>`.

## Test 2 — Already up to date (Acceptance Scenario 1.2)

```bash
# Same kickoff twice in a row, no origin advance:
.trc/scripts/bash/create-new-feature.sh "First feature" --json --style feature-name --short-name "first"
git checkout main
.trc/scripts/bash/create-new-feature.sh "Second feature" --json --style feature-name --short-name "second"
```

**Expected**: No `[specify] Base branch …fast-forwarded` line on the second call — silent no-op when already at tip.

## Test 3 — Dirty base halts (FR-004)

```bash
git checkout main
echo "dirty" >> README.md                       # tracked file, uncommitted
.trc/scripts/bash/create-new-feature.sh "Blocked" --json --style feature-name --short-name "blocked"
# Exit code 20, stderr lists README.md. No branch created.
git status                                      # still on main, dirty
git branch --list blocked                       # empty — no branch
```

## Test 4 — Offline degrades gracefully (FR-006, SC-003)

```bash
# Block network to origin (e.g. unset the remote URL or point it at an unreachable host):
git remote set-url origin "https://127.0.0.1:0/nope.git"
.trc/scripts/bash/create-new-feature.sh "Offline" --json --style feature-name --short-name "offline"
```

**Expected**: Warning on stderr (`[specify] Warning: origin unreachable; skipping base-branch refresh`). Kickoff completes. Branch created from local main.

## Test 5 — Divergent local halts (FR-005)

```bash
# On main, commit locally but don't push:
git checkout main
echo "local-only" > local.txt
git add local.txt && git commit -m "local-only commit"
# Advance origin independently:
git -C "$ORIGIN_BARE" commit --allow-empty -m "origin-only commit"
# Kickoff:
.trc/scripts/bash/create-new-feature.sh "Diverged" --json --style feature-name --short-name "diverged"
```

**Expected**: Exit code 21. Stderr explains non-FF, does not create the branch.

## Test 6 — Opt-out via flag (FR-011)

```bash
.trc/scripts/bash/create-new-feature.sh "Skip refresh" --no-base-refresh --json --style feature-name --short-name "skip-refresh"
```

**Expected**: Silent skip — no refresh attempt, no warning. Useful for branching off a historical SHA deliberately.

## Test 7 — Opt-out via env var (FR-011)

```bash
TRC_SKIP_BASE_REFRESH=1 .trc/scripts/bash/create-new-feature.sh "Env skip" --json --style feature-name --short-name "env-skip"
```

**Expected**: Same as Test 6.

## Test 8 — Chain ticket N+1 sees ticket N's merge (User Story 2)

Conceptual — hard to exercise fully outside a real chain run. Proxy check: after ticket 1's merge lands on `main` via `gh pr merge --squash`, `git fetch origin main` locally picks up the squash SHA. The kickoff for ticket 2 fast-forwards local `main` to that SHA and cuts the new branch from it. Verify by comparing `git rev-parse <ticket-2-branch>` to the squash commit SHA reported by `gh pr view <ticket-1-pr> --json mergeCommit`.
