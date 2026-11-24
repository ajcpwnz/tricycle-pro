---
name: setup-store
step: implement
description: Ask the spec store and vault layout questions once and save the answers in the config
required: true
default_enabled: true
order: 5
---

## Store setup

Do this step first. Ask fixed questions with `AskUserQuestion`, in the order
below, with the options below. Write each answer to `tricycle.config.yml` at once.
Do not ask a question again when its key is already in `tricycle.config.yml`.

1. **Store.** Ask only when an `obsidian` MCP server is connected and the config has no `spec.store` key.
   The options are `repo`, `linear` and `obsidian`. Write the answer to `spec.store`.
2. **Vault layout.** Ask these four questions as one group. Ask them only when
   `spec.store` is `obsidian` and the config has no `spec.obsidian` block.
   - Vault folder for the specs, relative to the vault root. The current
     `spec.dir` is one option. Write the answer to `spec.dir`.
   - `spec.obsidian.note_name`: `id` gives `<id>.md`. `id-title` gives `<id> <title>.md`.
   - `spec.obsidian.frontmatter`: `none` writes no frontmatter. `properties`
     writes `status`, `source` and `tags: [spec]`.
   - `spec.obsidian.done`: `stay` keeps the note in `spec.dir` after merge.
     `move` moves it to `<spec.dir>/done`.

Write the answers in this form. Keep the other keys under `spec`.

```yaml
spec:
  store: obsidian
  dir: <vault folder>
  obsidian:
    note_name: id        # id | id-title
    frontmatter: none    # none | properties
    done: stay           # stay | move
```

If no question is due, go to the next section.

An unattended run does not ask. In a `/trc.chain` or `/trc.band` worker, if a
question is due, stop and report the question.
