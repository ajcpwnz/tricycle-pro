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

In obsidian mode, read the note in `<spec.dir>` in the vault with the read tool of
the `obsidian` MCP server. In mcpvault, this tool is `read_note`. The note name
follows `spec.obsidian.note_name`. If the `obsidian` server is not connected, stop.
Tell the user to run `tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart Claude Code.
Do not fall back to a repo file.
A missing `spec.obsidian` key takes its default: `note_name: id`, `frontmatter: none`, `done: stay`.

If no spec with `Analysis`, `Proposed Solution` and `Checklist` exists, stop and
tell the user to run `/trc.plan <input>` first.
