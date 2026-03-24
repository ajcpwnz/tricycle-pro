# Memory Module

Seeds Claude Code's memory with universal best-practice feedback memories.

## What it includes

- **MEMORY.md.tpl** -- Template for the memory index file
- **seeds/** -- Pre-written memory files:
  - `lint-test-before-done.md` -- Always run lint and test before declaring work done
  - `no-manual-migrations.md` -- Never create migration files manually; use wrapper scripts
  - `pr-conventions.md` -- PR target branch and merge strategy conventions
  - `push-gating.md` -- Never push without explicit user approval
  - `worktree-workflow.md` -- Always use worktrees for feature branches

## Installation

```bash
npx tricycle-pro add memory
```

This copies seed files to `.claude/memory/seeds/` where Claude Code discovers and uses them
across sessions.

## How it works

Claude Code reads files in `.claude/memory/` to build persistent context. The seed memories
encode workflow rules (push gating, lint-before-done, worktree usage) so Claude follows
project conventions without being reminded each session.

Each seed uses the standard memory format with frontmatter (name, description, type) and a
body structured as: rule, **Why:** rationale, **How to apply:** guidance.
