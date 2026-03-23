---
name: Run lint and test before declaring work done
description: NONNEGOTIABLE — always run lint+test for ALL affected apps after code changes
type: feedback
---

NONNEGOTIABLE: Run lint and test for ALL affected apps after ANY code changes,
and fix all failures before declaring work complete.

**Why:** Skipping validation leads to broken builds, failed deploys, and wasted review cycles.
The agent frequently says "implementation complete!" without running tests — this rule prevents that.

**How to apply:** After finishing code changes, run lint and test commands for every app that was
modified. If shared packages changed, run validation for all consuming apps. Fix any failures
before telling the user the work is done.
