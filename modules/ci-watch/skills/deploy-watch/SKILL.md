---
name: deploy-watch
description: Monitor GitHub Actions deploy workflows after merging a PR to staging. Polls until all deploys complete, diagnoses failures, and reports results.
disable-model-invocation: true
context: fork
agent: general-purpose
argument-hint: "[pr-number or blank for latest staging push]"
---

## Input

```text
$ARGUMENTS
```

## Step 1: Determine What to Watch

- If `$ARGUMENTS` contains a PR number (e.g., `72` or `#72`): find the merge commit via `gh pr view <number> --json mergeCommit -q .mergeCommit.oid`
- If blank: use the latest commit on staging: `git log origin/staging -1 --format=%H`

Record the **merge SHA** and **merge time** for filtering.

## Step 2: Identify Expected Deploy Workflows

The project has 4 deploy workflows triggered on push to `staging`:

| Workflow | Trigger Paths | File |
|----------|--------------|------|
| Deploy Backend | `apps/backend/**`, `bun.lock` | `deploy-backend-staging.yml` |
| Deploy Frontend | `apps/frontend/**`, `packages/web/**`, `bun.lock` | `deploy-frontend-staging.yml` |
| Deploy Manager | `apps/manager/**`, `packages/web/**`, `bun.lock` | `deploy-manager-staging.yml` |
| Deploy Dashboard | `apps/dashboard/**`, `packages/web/**`, `bun.lock` | `deploy-dashboard-staging.yml` |

Check which files were changed in the merge commit:
```bash
gh pr view <pr-number> --json files -q '.files[].path'
# or for latest push:
git diff --name-only HEAD~1
```

Determine which deploy workflows SHOULD trigger based on path filters. If `bun.lock` changed, all 4 deploy.

## Step 3: Initial Wait

Sleep **30 seconds** — deploy workflows take time to queue after a push.

## Step 4: Poll Loop

Poll up to **30 iterations**, **20 seconds apart** (max ~10 minutes):

```bash
gh run list --branch staging --limit 10 \
  --json databaseId,name,status,conclusion,createdAt,updatedAt
```

Filter to:
- Runs with `createdAt` after the merge time
- Runs matching `Deploy *` workflow names

Each iteration, print a one-line status:
```
Deploy: Backend ✓ | Frontend ⏳ | Manager ✓ | Dashboard — (not triggered)
```

Break when all expected workflows have completed (success or failure).

If **no deploy workflows appear** after 3 iterations (90 seconds):
- Check if the merge actually changed files matching deploy path filters
- If no matching files: report "No deploy workflows triggered — merge didn't touch deployable paths"
- If matching files exist but no workflows: warn about potential GitHub Actions issue

## Step 5: Report Results

### All Passed

```
Deploy Status: staging (merge SHA abc1234)
┌────────────────────┬───────────┬────────────┬──────────────────────┐
│ Workflow            │ Status    │ Duration   │ URL                  │
├────────────────────┼───────────┼────────────┼──────────────────────┤
│ Deploy Backend     │ ✓ passed  │ 3m 42s     │ <run-url>            │
│ Deploy Frontend    │ ✓ passed  │ 2m 15s     │ <run-url>            │
│ Deploy Manager     │ — skipped │ —          │ (no matching paths)  │
│ Deploy Dashboard   │ — skipped │ —          │ (no matching paths)  │
└────────────────────┴───────────┴────────────┴──────────────────────┘
All deploys succeeded.
```

### Any Failed

Print the table as above, then for each failed workflow:

1. Fetch logs: `gh run view <run-id> --log-failed`
2. Diagnose the failure type:
   - **Docker build failure**: Check for missing dependencies, Dockerfile syntax, build context issues
   - **SSH/connection timeout**: Server unreachable — check VPS status
   - **Health check failure**: App started but health endpoint not responding — check logs on server
   - **Migration error**: Prisma migration failed on staging DB — check migration compatibility
   - **Cert renewal failure**: certbot non-fatal — report but don't block
3. Suggest a specific fix
4. If the fix is obvious and code-level (not infrastructure), offer to fix and push
