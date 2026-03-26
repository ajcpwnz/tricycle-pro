---
name: push-deploy
step: implement
description: Push, create PR, merge, and clean up artifacts after implementation
required: false
default_enabled: true
order: 65
---

## Push, PR & Deploy

After all tasks are complete, tests pass, and the version is bumped, execute the push/PR/merge workflow:

### 1. Read push configuration

Read `tricycle.config.yml` and extract:
- `push.require_approval` (boolean, default true)
- `push.pr_target` (string, default "main")
- `push.merge_strategy` (string: squash, merge, or rebase)
- `push.auto_merge` (boolean, default false)

### 2. Summarize changes

Present a summary to the user:
- What was implemented (feature name, user stories completed)
- Files changed (count and key files)
- Tests passed (which test suites ran and their results)
- Version bumped (old → new)

### 3. Push approval gate

**If `push.require_approval` is true** (default):
1. State that you are ready to push and present the summary.
2. **HALT and wait** for the user to say "push", "go ahead", or equivalent.
3. Each push requires **fresh confirmation** — prior approval does not carry over.
4. If the user declines or says "stop", "wait", "no" — do NOT push. Do NOT create a PR. HALT the workflow.

**If `push.require_approval` is false**: Proceed directly to step 4.

### 4. Push and create PR

1. Push the branch to the remote with the `-u` flag.
2. Create a PR targeting `push.pr_target` using `gh pr create`.
3. Include the change summary in the PR body.

**If push fails** (remote rejected, auth error, network failure): Report the error clearly and HALT. Do not retry.

### 5. Merge (if auto_merge is true)

**If `push.auto_merge` is true**:
1. Check for merge conflicts. If conflicts exist, report them and HALT — do not force-merge.
2. Merge using the configured `push.merge_strategy` via `gh pr merge`.
3. If merge is blocked (branch protection, required reviewers), report the blocker and wait.

**If `push.auto_merge` is false**: Report the PR URL and let the user handle merging.

### 6. Artifact cleanup (only after confirmed merge)

**IMPORTANT**: Do NOT clean up artifacts until the PR is successfully merged. If merge has not happened, skip this step entirely.

After confirmed merge:
1. Remove the spec/plan/task files in the `specs/{branch}/` directory (if they exist).
2. If in a worktree (`.git` is a file), note that the worktree-cleanup block (if active) handles worktree removal separately.
3. If NOT in a worktree, switch back to the base branch and delete the feature branch locally.

### 7. Error handling

On **any failure** during this workflow (push rejected, PR creation failed, merge blocked, conflicts):
- Report the error clearly with context.
- HALT the workflow — do not continue to the next step.
- Do not retry automatically.
- Do not clean up artifacts.
- Suggest what the user can do to resolve the issue.
