## Artifact Cleanup (MANDATORY — NONNEGOTIABLE)

Do NOT clean up Tricycle Pro artifacts (spec files, plan files, task files) or worktrees
until the user has approved the push and the PR is merged. Cleanup sequence:
1. Feature done, lint/tests pass, QA done → prompt user for push approval.
2. User approves → push, create PR, merge.
3. Only after successful merge → clean up worktree and temporary artifacts.
