---
name: resolve-input
step: plan
description: Decide whether the input is new work or an existing spec to revalidate
required: true
default_enabled: true
order: 10
---

## Resolve the input

Read `spec.store` (`repo`, `linear` or `obsidian`, default `repo`) and `spec.dir`
(default `docs/specs`) from `tricycle.config.yml`.

In obsidian mode, the spec is a note in the vault, and `spec.dir` is relative to
the vault root. Read, write and patch the note with the tools of the `obsidian` MCP
server. In mcpvault, these tools are `read_note`, `write_note` and `patch_note`.
If the `obsidian` server is not connected, stop. Tell the user to run
`tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart Claude Code.
Do not fall back to a repo file.
A missing `spec.obsidian` key takes its default: `note_name: id`, `frontmatter: none`, `done: stay`.

Classify the user input:

| Input | Source |
|-------|--------|
| Path to a `.md` file | that file |
| Ticket id or tracker URL | the ticket, read with the tracker's MCP (`get_issue`), including its comments |
| Anything else | a new request in plain text |

The input is an **existing spec** when its text already has the sections
`Analysis`, `Proposed Solution` and `Checklist`. In repo mode, a ticket id whose
file `<spec.dir>/<TICKET-ID>.md` exists is an existing spec too. In obsidian mode,
a spec id with a note in `<spec.dir>` in the vault is an existing spec too. The
note name follows `spec.obsidian.note_name`.

- **Existing spec:** do not rewrite it. Skip to the validation section, then the
  store section. Fix only what validation finds.
- **New work:** continue with every section in order.

The spec id is the ticket id when there is one. Otherwise it is a short kebab-case
slug of the request.
