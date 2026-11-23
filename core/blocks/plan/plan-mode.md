---
name: plan-mode
step: plan
description: Enter Claude Code plan mode for research unless the work is trivial
required: false
default_enabled: true
order: 15
---

## Plan mode

For new work, call the `EnterPlanMode` tool before any research, unless the work is
trivial: one file, no design choice, no new behavior. Plan mode is read-only. The
drafted spec is the plan: present it with `ExitPlanMode`, and store it only after
the user approves.
