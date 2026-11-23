---
name: research
step: plan
description: Ground the spec in the codebase and the project rules
required: true
default_enabled: true
order: 30
---

## Research

1. Read the project rules that bound the change: root `CLAUDE.md`, the
   constitution (`constitution.root` in `tricycle.config.yml`), and the rules file
   of every app the change touches.
2. Read the code the request touches. Find the cause, not only the symptom.
3. Record every fact with a `path:line` reference. A claim with no reference does
   not go into the spec.
4. Settle every choice you can from the code and the rules. A choice only the user
   can make goes to the user now, with `AskUserQuestion`, before the spec is written.
