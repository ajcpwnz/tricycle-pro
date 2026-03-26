# Contract: Workflow Configuration Schema

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## tricycle.config.yml — `workflow` Section

```yaml
# New top-level section in tricycle.config.yml
workflow:
  # Ordered list of workflow steps (default: full chain)
  chain:
    - specify
    - plan
    - tasks
    - implement

  # Per-step block overrides (optional — all defaults enabled when omitted)
  blocks:
    plan:
      disable:
        - design-contracts     # Example: skip contract generation
    implement:
      enable:
        - test-local-stack     # Example: enable optional block
      custom:
        - .trc/blocks/custom/my-validation.md
```

## Validation Rules

1. `workflow.chain` must be one of three valid configurations:
   - `[specify, plan, tasks, implement]` (default)
   - `[specify, plan, implement]`
   - `[specify, implement]`

2. `workflow.blocks.{step}.disable`:
   - Must reference valid block names for that step
   - Cannot reference `required: true` blocks → error
   - Unknown block names → warning

3. `workflow.blocks.{step}.enable`:
   - Must reference valid optional block names for that step
   - Already-enabled blocks → silent no-op

4. `workflow.blocks.{step}.custom`:
   - Paths must exist and be readable
   - File must have valid block frontmatter
   - Block's `step` field must match the config section
   - Missing file → error at assembly time

5. Block overrides for steps NOT in the chain are silently ignored.

## Backward Compatibility

- Missing `workflow` section → default full chain, all default blocks
- Missing `workflow.chain` → default full chain
- Missing `workflow.blocks` → all defaults for all steps
- Existing configs work without changes
