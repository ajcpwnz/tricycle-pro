---
name: code-reviewer
description: >
  PR review, quality audit, and security checks. Invoke when reviewing
  code changes before merging or pushing. Performs structured review
  covering correctness, security, performance, and maintainability.
---

# Code Reviewer Skill

## When to use this Skill

Use this Skill when you are:

- Reviewing a pull request or set of staged changes before push
- Performing a quality audit on recently written code
- Checking for security vulnerabilities in new code
- Evaluating code against project conventions and best practices

## Review Process

### 1. Understand the Change

- Read the diff or staged changes completely before commenting
- Identify the purpose of the change (bug fix, feature, refactor, etc.)
- Check if tests are included or updated

### 2. Correctness Review

- Verify the logic matches the intended behavior
- Check for off-by-one errors, null/undefined handling, edge cases
- Ensure error paths are handled appropriately
- Verify data validation at system boundaries

### 3. Security Review

- Check for injection vulnerabilities (SQL, command, XSS)
- Verify authentication and authorization checks are in place
- Look for hardcoded secrets, credentials, or API keys
- Ensure sensitive data is not logged or exposed in error messages
- Check for path traversal and file access vulnerabilities

### 4. Performance Review

- Identify potential N+1 queries or unnecessary loops
- Check for missing indexes on queried fields
- Look for unbounded data fetches (missing pagination/limits)
- Verify resource cleanup (file handles, connections, subscriptions)

### 5. Maintainability Review

- Check naming clarity (functions, variables, files)
- Verify the change follows existing patterns in the codebase
- Look for unnecessary complexity or premature abstraction
- Check that comments explain "why" not "what"

## Output Format

Present findings as a structured review:

```
## Review Summary
- **Change type**: [bug fix / feature / refactor / etc.]
- **Risk level**: [low / medium / high]
- **Recommendation**: [approve / request changes / needs discussion]

## Findings
### Critical (must fix)
- [finding with file:line reference]

### Suggestions (should fix)
- [finding with file:line reference]

### Nits (optional)
- [finding with file:line reference]
```

## Things to Avoid

- Bikeshedding on style when a linter or formatter is configured
- Suggesting rewrites of code that is not part of the current change
- Blocking on subjective preferences without clear reasoning
- Commenting on every line — focus on meaningful findings
