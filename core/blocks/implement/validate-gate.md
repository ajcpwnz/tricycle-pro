---
name: validate-gate
step: implement
description: Refuse to start work on a spec that fails validation
required: true
default_enabled: true
order: 15
---

## Validation gate

Read the status line of the spec.

- **`Status: validated @ <sha>`:** run `git diff --name-only <sha>`. If no file
  that the spec cites is in the output, the spec is current. Start, and do not
  run the validator.
- **Other status, or a cited file changed:** run the `trc-spec-validator` agent
  one time, with model `{{models.validator}}`. Give it the full spec text and the
  repository root.

On PASS, start. Add each new handoff to the `## Implementer Notes` section of the
spec.

In obsidian mode, write the handoffs with the patch tool of the `obsidian` server.
The `git diff` check does not see changes to the note itself. It sees only the
repo files that the spec cites.

On FAIL, do not start. Report the blockers and tell the user to run
`/trc.plan <input>`. Do not fix the spec here.
