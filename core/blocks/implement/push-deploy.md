---
name: push-deploy
step: implement
description: Push, create PR, merge, and clean up artifacts after implementation
required: false
default_enabled: true
order: 65
---

## Push, PR & Deploy

After every checklist item is done and tests pass (and the version-bump block, when enabled, has run), execute the push/PR/merge workflow:

### 0. Local testing gate

**MANDATORY.** Do this step only if this command contains the Local Stack Testing section (the `test-local-stack` block). Before you show a summary or ask to push, make sure that the browser evidence is on disk:

1. Get the current branch: `git rev-parse --abbrev-ref HEAD`.
2. Make sure that all of these conditions are true:
   - The file `specs/<branch>/.local-testing-passed` exists and is not empty.
   - There is a minimum of one browser screenshot in `specs/<branch>/local-testing/`, or the first line of the marker is `USER-APPROVED SKIP:`.
3. **If a condition is false**: stop. Do not show a summary. Do not ask to push. Go back to Local Stack Testing, do the browser test, save the screenshots, and write the marker.
4. **If all conditions are true**: go to step 1.

Do not skip this step. Do not give yourself an exemption. Only a `USER-APPROVED SKIP:` first line, which the user approved in this session, replaces the screenshots.

### 1. Read push configuration

Read `tricycle.config.yml` and extract:
- `push.require_approval` (boolean, default true)
- `push.pr_target` (string, default "main")
- `push.merge_strategy` (string: squash, merge, or rebase)
- `push.auto_merge` (boolean, default false)

### 2. Summarize changes

Present a summary to the user:
- What was implemented (the spec title and its checklist)
- Files changed (count and key files)
- Tests passed (which test suites ran and their results)
- Version bumped (old → new)

### 3. Push approval gate

**If `push.require_approval` is true** (default):
1. State that you are ready to push and present the summary.
2. **Stop and wait** for the user to say "push", "go ahead", or equivalent.
3. Each push requires **fresh approval**. Earlier approval does not carry over.
4. If the user declines or says "stop", "wait", "no" — do NOT push. Do NOT create a PR. Stop the workflow.

**If `push.require_approval` is false**: Proceed directly to step 4.

### 4. Push and create PR

1. Push the branch to the remote with the `-u` flag.
2. Create a PR targeting `push.pr_target` using `gh pr create`.
3. Include the change summary in the PR body.

**If push fails** (remote rejected, auth error, network failure): Report the error clearly and stop. Do not retry.

### 5. Merge (if auto_merge is true)

**If `push.auto_merge` is true**:
1. Check for merge conflicts with `gh pr view <pr-number> --json mergeable,mergeStateStatus`.
   - If `mergeable` is `UNKNOWN`, GitHub has not calculated it yet. Wait 10 seconds and check again.
   - If `mergeable` is `CONFLICTING`, repair the conflicts. Do not stop:
     a. Rebase onto the target branch: `git fetch origin && git rebase origin/<pr_target>`.
     b. For each file that has a conflict, read the two sides, decide the result, write it, and `git add` the file.
     c. Continue the rebase: `git rebase --continue`.
     d. Push the rebased branch: `git push --force-with-lease`.
     e. Check `mergeable` again. If the conflicts continue after the rebase, report them and stop. The user must repair them.
   - If `mergeable` is `MERGEABLE`, merge the PR.
   - Do not force-merge.
2. Merge using the configured `push.merge_strategy` via `gh pr merge`.
3. If merge is blocked (branch protection, required reviewers), report the blocker and wait.

**If `push.auto_merge` is false**: Report the PR URL and let the user handle merging.

### 5b. Delete blocking relations (after a checked merge)

After a successful merge, find the ticket. Use the spec Source line if it has a ticket id. If `spec.store` is `linear`, use the ticket that holds the spec. If there is no ticket, skip this step.

1. Use the tracker MCP to get the ticket relations, and find the tickets that it blocks.
2. Delete all of these blocking relations, so that the work that follows is not blocked. In Linear, use the `removeBlocks` field.

### 6. Artifact cleanup (only after a checked merge)

**IMPORTANT**: Do NOT clean up artifacts until the PR is successfully merged. If merge has not happened, skip this step entirely.

After you check that the merge happened:
1. Delete the scratch directory `specs/{branch}/` (local testing evidence), if it exists. The spec itself stays: in repo mode it is committed under `spec.dir`.
2. If in a worktree (`.git` is a file), note that the worktree-cleanup block (if active) handles worktree removal separately.
3. If NOT in a worktree, switch back to the base branch and delete the feature branch locally.

### 7. Error handling

On **any failure** during this workflow (push rejected, PR creation failed, merge blocked, conflicts):
- Report the error clearly with context.
- Stop the workflow. Do not continue to the next step.
- Do not retry automatically.
- Do not clean up artifacts.
- Suggest what the user can do to resolve the issue.
