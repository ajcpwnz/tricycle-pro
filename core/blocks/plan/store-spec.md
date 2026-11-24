---
name: store-spec
step: plan
description: Store the spec in the repo, the tracker or the Obsidian vault, per spec.store
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
- **`spec.store: obsidian`:** write the note in `<spec.dir>` in the vault with the
  write tool of the `obsidian` server. The note name follows
  `spec.obsidian.note_name`: `id` gives `<spec id>.md`, and `id-title` gives
  `<spec id> <title>.md`. With `spec.obsidian.frontmatter: properties`, start the
  note with the properties `status`, `source` and `tags: [spec]`. With `none`,
  write no frontmatter. If a ticket exists, add a comment on it with the
  vault-relative path of the note. Do not create a ticket.

Report the spec location, its status, and the validator verdict. Do not start
implementation: that is `/trc.implement <spec id>`.
