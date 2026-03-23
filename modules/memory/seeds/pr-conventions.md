---
name: PR conventions — target base branch, squash merge
description: All PRs should target the configured base branch (not main) and use squash merge
type: feedback
---

All PRs should target the project's base branch (usually `staging`, check tricycle.config.yml),
not `main`. Use squash merge to keep the commit history clean.

**Why:** Targeting `main` directly bypasses staging/preview environments. Squash merging collapses
feature branch noise into a single descriptive commit on the base branch.

**How to apply:** When creating a PR, use `--base <base_branch>` (from tricycle.config.yml's
`push.pr_target`). After CI passes, merge with the configured merge strategy (usually squash).
