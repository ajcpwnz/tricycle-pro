---
name: validate
step: plan
description: Validate the spec with the independent trc-spec-validator agent, fix blockers, hand the rest to the implementer
required: true
default_enabled: true
order: 50
---

## Validation

Run the `trc-spec-validator` agent with model `{{models.validator}}`. Give it the
full spec text and the repository root, nothing else: no summary of your own
reasoning.

- **PASS:** copy each handoff, as the validator wrote it, into the
  `## Implementer Notes` section of the spec. Do not fix handoffs here and do not
  run the validator again.
- **FAIL:** fix each blocker from the code. A blocker that only the user can
  settle: ask with `AskUserQuestion`, then write the answer into the spec. Then
  run the validator again on the full spec, to test the fix. After three rounds
  that fail, stop and show the user the blockers.

Then set the status to `Status: validated @ <sha>`. The `<sha>` is the output of
`git rev-parse --short HEAD`. Go to the store section.

An existing spec goes through the same validation. Change only what a blocker
names.

In obsidian mode, write the Implementer Notes and the `Status:` line with the
patch tool of the `obsidian` server. With `spec.obsidian.frontmatter: properties`,
set the `status` property to the same value.
