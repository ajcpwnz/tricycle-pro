---
name: resolve-input
step: plan
description: Decide whether the input is new work or an existing spec to revalidate
required: true
default_enabled: true
order: 10
---

## Resolve the input

Read `spec.store` (`repo` or `linear`, default `repo`) and `spec.dir` (default
`docs/specs`) from `tricycle.config.yml`.

Classify the user input:

| Input | Source |
|-------|--------|
| Path to a `.md` file | that file |
| Ticket id or tracker URL | the ticket, read with the tracker's MCP (`get_issue`), including its comments |
| Anything else | a new request in plain text |

The input is an **existing spec** when its text already has the sections
`Analysis`, `Proposed Solution` and `Checklist`. In repo mode, a ticket id whose
file `<spec.dir>/<TICKET-ID>.md` exists is an existing spec too.

- **Existing spec:** do not rewrite it. Skip to the validation section, then the
  store section. Fix only what validation finds.
- **New work:** continue with every section in order.

The spec id is the ticket id when there is one. Otherwise it is a short kebab-case
slug of the request.
