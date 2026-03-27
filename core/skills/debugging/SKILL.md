---
name: debugging
description: >
  Structured debugging workflow: reproduce, isolate, trace, fix, verify.
  Use when investigating bugs, unexpected behavior, or test failures.
  Guides systematic root-cause analysis instead of trial-and-error.
---

# Debugging Skill

## When to use this Skill

Use this Skill when you are:

- Investigating a bug report or unexpected behavior
- Diagnosing a failing test
- Tracking down a performance regression
- Understanding why code behaves differently than expected

## The Debugging Workflow

### 1. Reproduce

- Confirm the bug exists by reproducing the exact reported behavior
- Identify the minimal steps or input to trigger the issue
- Note the actual behavior vs. expected behavior
- If the bug cannot be reproduced, gather more context before proceeding

### 2. Isolate

- Narrow down where the bug occurs:
  - Which file, function, or module?
  - Which input conditions trigger it?
  - Does it happen consistently or intermittently?
- Use binary search on recent changes if the bug is a regression
- Remove variables: disable plugins, simplify input, use minimal config

### 3. Trace

- Follow the execution path from input to the point of failure
- Read error messages and stack traces carefully — they often point directly to the cause
- Add targeted logging or debugging output at key decision points
- Check assumptions: are variables the expected type and value at each step?
- Look for common root causes:
  - Off-by-one errors
  - Null/undefined references
  - Race conditions or timing issues
  - Incorrect type coercion
  - Stale cache or state

### 4. Fix

- Fix the root cause, not just the symptom
- Make the smallest change that resolves the issue
- Consider edge cases that may have the same root cause
- Do not refactor surrounding code as part of the fix

### 5. Verify

- Confirm the fix resolves the original reported behavior
- Run the full test suite to check for regressions
- If a test did not exist for this bug, add one
- Test edge cases related to the fix

## Things to Avoid

- Changing code randomly hoping something works (shotgun debugging)
- Fixing symptoms instead of root causes
- Making multiple changes at once — isolate each change
- Ignoring intermittent failures — they are real bugs
- Removing error handling to "fix" errors
