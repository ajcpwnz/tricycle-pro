---
name: test
step: implement
description: Run the configured lint and test commands until green
required: true
default_enabled: true
order: 40
---

## Lint and test

For every app the change touches, run its `lint` and `test` commands from `apps`
in `tricycle.config.yml`. Run long suites through a worker subagent (Agent tool,
model `{{models.workers}}`) that returns the exit codes and only the failing
output. A failure is a bug to fix, then run again. Never skip, disable or weaken a
test to get green.
