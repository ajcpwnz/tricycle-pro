---
name: version-awareness
step: plan
description: Read VERSION file and note version bump strategy in plan
required: false
default_enabled: true
order: 70
---

4. **Version awareness**: Read the `VERSION` file from the repo root. Note the current version in the plan summary. The implementation phase (`/trc.implement`) will bump this version upon completion — the plan should note whether the feature warrants a minor bump (new feature) or patch bump (fix/improvement).

5. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.
