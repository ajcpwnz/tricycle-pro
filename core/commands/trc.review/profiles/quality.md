---
name: quality
source:
  - name: google/eng-practices
    url: https://github.com/google/eng-practices/blob/master/review/reviewer/looking-for.md
    license: CC-BY-3.0
    attribution: "Adapted from Google Engineering Practices — Code Review Developer Guide, used under CC-BY 3.0."
  - name: baz-scm/awesome-reviewers
    url: https://github.com/baz-scm/awesome-reviewers
    license: Apache-2.0
    attribution: "Adapted from baz-scm/awesome-reviewers (Error Handling and Testing labels), used under Apache-2.0."
---

# Quality Review Profile

You are reviewing a **pull request diff**. Evaluate the added and modified lines against the quality criteria below. Do not evaluate code that was not touched by this PR. For every issue, cite the file and line number from the diff and provide a concrete recommendation.

## Correctness

- Does the new code do what the PR description says it does? If the PR has no description, does the code's intent match its name?
- Are edge cases handled? In particular: empty input, zero, one, many, off-by-one at loop boundaries, null / undefined / None, negative numbers, very large numbers, unicode strings, concurrent access.
- Are error paths reachable and correct? A try/catch that swallows errors silently is worse than no try/catch.
- Are return values used? A function whose result is dropped on the floor usually indicates a missing check.
- Are there any obvious bugs that a reader could catch without running the code? (Wrong variable, inverted condition, missing await, missing `return`.)

## Error handling

- Are errors handled at the right layer? Low-level code should report errors; high-level code should decide what to do about them.
- When an error is caught, is the catch block specific or does it swallow everything?
- Are error messages useful to the person who will read them? ("Error" is not a message; "Failed to parse config at line 42: unexpected token `:`" is.)
- Does the new code leave the system in a valid state if it fails halfway through? Look for partial writes, dangling locks, leaked file handles.

## Input validation

- Does new code that sits at a boundary (user input, HTTP request, CLI arg, config file, database row) validate its inputs?
- Is the validation at the **right** boundary? Re-validating at every layer is noise; failing to validate anywhere is a bug.
- Is the error a user-friendly message, not a stack trace leaked to the client?

## Test coverage

- Does the PR include tests for the new code it introduces? If it is a bug fix, is there a regression test that would have caught the bug?
- Do the tests actually test the thing? (A test that mocks everything and asserts the mock was called does not exercise real behavior.)
- Do the tests cover the edge cases from the Correctness list above?
- Are the tests deterministic? Flag any test that uses `Date.now()`, `Math.random()`, network, or filesystem without sandboxing.

## Reading the code

- Can you understand the new code on a single read? If you have to re-read a block three times, note it — the code is too clever for the problem it solves.
- Are variables and functions named for what they mean, not for what they are? (`userCount` is better than `data`; `parseIsoDate` is better than `doIt`.)
- Does the PR accidentally regress code quality somewhere else? (A large refactor that simplifies one call site but leaves three others in a worse state is a partial refactor — flag it.)

## Severity guide

- **critical**: incorrect result, data loss risk, bug that will reach production, missing error handling at a boundary that will crash the process, a test that does not actually test what it claims.
- **warning**: handles the happy path but misses a realistic edge case; error message that will mislead the on-call person; missing validation at a boundary; flaky test.
- **info**: stylistic naming, minor readability, code that would be clearer if restructured but is not wrong.

Do not produce findings without a file:line reference and a concrete recommendation. If you cannot cite a specific line, do not produce the finding.
