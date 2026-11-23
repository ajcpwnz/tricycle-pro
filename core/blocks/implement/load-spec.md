---
name: load-spec
step: implement
description: Load the spec named by the input
required: true
default_enabled: true
order: 10
---

## Load the spec

Read `spec.store` and `spec.dir` from `tricycle.config.yml`. The input names the
spec: a path to a `.md` file, a ticket id or tracker URL, or a spec id under
`spec.dir`. Read a ticket with the tracker's MCP, including its comments.

If no spec with `Analysis`, `Proposed Solution` and `Checklist` exists, stop and
tell the user to run `/trc.plan <input>` first.
