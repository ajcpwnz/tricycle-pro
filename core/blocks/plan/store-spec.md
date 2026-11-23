---
name: store-spec
step: plan
description: Store the spec in the repo or the tracker, per spec.store
required: true
default_enabled: true
order: 60
---

## Store

- **`spec.store: repo`:** write `<spec.dir>/<spec id>.md`. If a ticket exists, add
  a comment on it linking the file.
- **`spec.store: linear`:** the spec becomes the ticket description. For new work
  from a ticket, keep the original request below the spec under
  `## Original Request`. For a request with no ticket, create one with the tracker's
  MCP.

Report the spec location, its status, and the validator verdict. Do not start
implementation: that is `/trc.implement <spec id>`.
