---
name: Always use worktrees for feature work
description: Create git worktree for any new feature branch instead of git checkout -b
type: feedback
---

NONNEGOTIABLE: Always create a git worktree for ANY new feature work, not just trc.specify.
The only exception is if the user explicitly says to work on the current branch.

**Why:** Regular branch switching causes stashing headaches, lost context, dependency reinstalls,
and database migration drift when multiple features are in progress. Worktrees give each feature
its own isolated directory, node_modules, and (optionally) database.

**How to apply:** When starting any new feature — whether from a spec, a ticket, or ad-hoc work —
create a worktree with `git worktree add -b <branch> ../<project>-<branch> origin/<base>`.
Run package install in the worktree. Set up per-worktree database if applicable.
