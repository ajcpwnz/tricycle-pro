# Quickstart: Workflow Chains & Pluggable Blocks

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## Scenario 1: Use a Shortened Chain

```yaml
# tricycle.config.yml
workflow:
  chain: [specify, implement]
```

```bash
tricycle assemble
```

Now `/trc.headless "my feature"` runs specify → implement only.
`/trc.plan` or `/trc.tasks` shows: "Step 'plan' is not in the configured workflow chain."

## Scenario 2: Disable a Default Block

```yaml
# tricycle.config.yml
workflow:
  blocks:
    plan:
      disable:
        - design-contracts
```

After `tricycle assemble`, `/trc.plan` skips contract generation entirely.

## Scenario 3: Enable an Optional Block

```yaml
# tricycle.config.yml
workflow:
  blocks:
    implement:
      enable:
        - test-local-stack
```

After `tricycle assemble`, `/trc.implement` includes local stack testing instructions.

## Scenario 4: Add a Custom Block

Create `.specify/blocks/custom/security-review.md`:
```markdown
---
name: security-review
step: implement
description: Security review checklist before implementation
required: false
default_enabled: false
order: 25
---

## Security Review

Before implementing, review:
- Check for injection vulnerabilities in user inputs
- Verify authentication on new endpoints
- Review data exposure in API responses
```

Reference in config:
```yaml
workflow:
  blocks:
    implement:
      custom:
        - .specify/blocks/custom/security-review.md
```

Block appears between prerequisites (20) and checklist-validation (30).

## Scenario 5: Migration from extensions.yml

**Before** (deprecated):
```yaml
# .specify/extensions.yml
hooks:
  before_implement:
    - enabled: true
      extension: "setup-docker"
      command: "trc.setup-docker"
```

**After** (block):
Create a block file with the prompt content, reference in `workflow.blocks.implement.custom`.
