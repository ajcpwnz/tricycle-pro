## Feature Worktree Workflow (MANDATORY — NONNEGOTIABLE)

When starting ANY new feature work — whether via `trc.specify`, a new implementation
task, or any work that requires a new branch — ALWAYS create a git worktree first.
The ONLY exception is if the user explicitly says to work on the current branch.

1. Derive the branch name from the feature.
2. Run `git worktree add -b <branch-name> ../{{project.name}}-<branch-name> origin/{{project.base_branch}}`
3. `cd` into the new worktree.
4. Run `{{project.package_manager}} install` (worktrees don't share node_modules).
5. Continue all work in the worktree.
