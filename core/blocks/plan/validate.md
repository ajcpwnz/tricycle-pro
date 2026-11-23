---
name: validate
step: plan
description: Validate the spec with the independent trc-spec-validator agent and fix what it finds
required: true
default_enabled: true
order: 50
---

## Validation

Run the `trc-spec-validator` agent with model `{{models.validator}}`. Give it the
full spec text and the repository root, nothing else: no summary of your own
reasoning.

- **PASS:** set `Status: validated` and go to the store section.
- **FAIL:** fix each finding.
  - Truthfulness and quality findings: fix the spec from the code.
  - Ambiguity findings that only the user can settle: ask with `AskUserQuestion`,
    then write the answer into the spec.

  Then run a fresh validator again. After three failed rounds, stop: keep
  `Status: draft`, store the spec, and report the remaining findings.

An existing spec goes through the same loop. Change only what a finding names.
