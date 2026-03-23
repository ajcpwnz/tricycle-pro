---
description: Poll CI status for the current branch or a PR, wait until it passes or fails, and diagnose failures
---

## Wait for CI

Poll GitHub Actions CI status until all checks complete, then report results.

### Input

```text
$ARGUMENTS
```

If arguments contain a PR number (e.g., `123` or `#123`), check that PR's checks.
Otherwise, use the current branch.

### Procedure

1. **Determine target**: Parse `$ARGUMENTS` for a PR number. If none, get current branch via `git branch --show-current`.

2. **Initial wait**: Sleep 30 seconds before first check — CI takes time to start.

3. **Poll loop** (max 20 iterations, 15s between checks):
   ```
   gh run list --branch <branch> --limit 5 --json status,conclusion,name,databaseId
   ```

   - If **all runs completed**: break out of loop
   - If **any run still pending/in_progress/queued**: continue polling
   - Print a one-line status update each iteration (e.g., "CI: 2/3 checks complete, waiting...")

4. **Check for merge conflicts** (before reporting results):
   If a PR number is known, check mergeable status:
   ```
   gh pr view <pr-number> --json mergeable,mergeStateStatus
   ```
   - If `mergeable` is `CONFLICTING`: report "PR has merge conflicts — rebase onto staging before merging" and list the conflicting files with `gh pr diff <pr-number> --name-only`. Do NOT say "ready to merge."
   - If `mergeable` is `UNKNOWN`: wait 10 seconds and re-check (GitHub computes this lazily).
   - If `mergeable` is `MERGEABLE`: proceed to results.

5. **Report results**:
   - If all checks **passed** and PR is **mergeable**: Print summary table and say "CI passed — ready to merge"
   - If all checks **passed** but PR has **conflicts**: Print summary table, then say "CI passed but PR has merge conflicts — rebase required before merging"
   - If any check **failed**:
     a. Identify the failed run(s)
     b. Fetch logs: `gh run view <run-id> --log-failed`
     c. Diagnose the failure — look for the actual error (test failure, lint error, build error, Docker issue)
     d. Suggest a specific fix based on the error
     e. If the fix is obvious (lint error, missing import), offer to fix it and push

6. **For PR-based checks** (if PR number was provided):
   ```
   gh pr checks <pr-number>
   ```
   Use this as the primary check source — it includes all required status checks.

### Output format

```
CI Status: <branch or PR #N>
┌──────────────────┬───────────┬────────────┐
│ Check            │ Status    │ Duration   │
├──────────────────┼───────────┼────────────┤
│ ci-backend       │ ✓ passed  │ 2m 15s     │
│ ci-frontend      │ ✓ passed  │ 1m 03s     │
│ ci-manager       │ ✗ failed  │ 0m 45s     │
└──────────────────┴───────────┴────────────┘
```

If failed, include the diagnosis and suggested fix below the table.
