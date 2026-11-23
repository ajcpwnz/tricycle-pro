---
name: write-spec
step: plan
description: Write the spec from the template
required: true
default_enabled: true
order: 40
---

## Write the spec

Fill `.trc/templates/spec-template.md`. Keep it compact: one spec, three parts.

- **Analysis:** the problem, the current behavior with `path:line` references, the
  constraints, and what is out of scope.
- **Proposed Solution:** the approach, each decision with the alternative it beat,
  and the risks.
- **Checklist:** one line per outcome, each naming its proof. An outcome is
  something a reviewer can observe ("the export endpoint returns 403 for a viewer").
  An edit instruction ("change line 40") is not an outcome.
- **Open Questions:** must be empty before the spec can pass.

Set `Source:` to the ticket id, URL or a one-line summary of the request.
