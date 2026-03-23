## Feature Branch, PR & Deploy (MANDATORY — NONNEGOTIABLE)

When a feature is complete (after lint/test pass), follow this workflow:
1. Ask the user for the feature branch name.
2. Commit all changes.
3. Prompt the user for push approval — do NOT push without it.
4. Once approved, push the branch and create a PR targeting `{{push.pr_target}}`.
5. Check for merge conflicts before merging.
6. Once PR is mergeable, merge ({{push.merge_strategy}} merge).
