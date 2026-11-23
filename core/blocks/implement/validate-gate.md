---
name: validate-gate
step: implement
description: Refuse to start work on a spec that fails validation
required: true
default_enabled: true
order: 15
---

## Validation gate

Run the `trc-spec-validator` agent with model `{{models.validator}}`, giving it the
full spec text and the repository root. Do this even when the spec says `Status: validated`: the code
may have moved since.

On FAIL, do not start. Report the findings and tell the user to run
`/trc.plan <input>`, which revalidates and fixes the spec. Do not fix the spec here.
