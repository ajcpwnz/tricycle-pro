---
name: write-spec
step: plan
description: Write the spec from the template
required: true
default_enabled: true
order: 40
---

## Write the spec

Fill `.trc/templates/spec-template.md`. Keep it compact: the spec says what to
build and why, not each edit. The implementer reads the code and makes the small
choices.

- **Analysis:** the problem, the current behavior with `path:line` references to
  source files, the constraints, and what is out of scope.
- **Proposed Solution:** the approach, each decision with the alternative it beat,
  and the risks.
- **Checklist:** one line per outcome, each naming its proof. An outcome is
  something a reviewer can observe ("the export endpoint returns 403 for a viewer").
  An edit instruction ("change line 40") is not an outcome.
- **Open Questions:** must be empty before the spec can pass.
- **Implementer Notes:** leave empty. Validation fills it.

Set `Source:` to the ticket id, URL or a one-line summary of the request.

### Check the draft

Read `.trc/templates/spec-rubric.md`. The validator uses the same rubric. Do its
writer checks on the draft, with tools, and keep the draft in its size limit.
