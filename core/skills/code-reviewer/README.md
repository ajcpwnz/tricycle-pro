# Code Reviewer Skill

Structured code review for pull requests and staged changes.

## Installation

This skill is installed automatically by `tricycle init`. It can be invoked via `/code-reviewer` in Claude Code.

## Usage

Invoke manually:
```
/code-reviewer
```

Or reference from a workflow block:
```markdown
If `.claude/skills/code-reviewer/SKILL.md` exists, invoke `/code-reviewer`
on the staged changes before requesting push approval.
```

## What it reviews

- **Correctness**: Logic errors, edge cases, error handling
- **Security**: Injection, auth, secrets, data exposure
- **Performance**: N+1 queries, unbounded fetches, resource leaks
- **Maintainability**: Naming, patterns, complexity

## Customization

Edit `.claude/skills/code-reviewer/SKILL.md` to adjust review criteria for your project. Your changes will be preserved during `tricycle update`.
