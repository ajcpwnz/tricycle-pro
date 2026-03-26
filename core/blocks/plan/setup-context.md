---
name: setup-context
step: plan
description: Run setup-plan.sh and load feature spec and constitution context
required: true
default_enabled: true
order: 20
---

1. **Setup**: Run `.trc/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.trc/memory/constitution.md`. Load IMPL_PLAN template (already copied).

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
