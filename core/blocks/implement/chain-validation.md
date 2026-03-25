---
name: chain-validation
step: implement
description: Validate that implement step is in the configured workflow chain
required: true
default_enabled: true
order: 10
---

## Chain Validation

Before proceeding, read `tricycle.config.yml` and check the `workflow.chain` configuration.

1. If `workflow.chain` is not defined, use the default chain: `[specify, plan, tasks, implement]`.
2. Validate the chain is one of these valid configurations:
   - `[specify, plan, tasks, implement]` (default — full workflow)
   - `[specify, plan, implement]` (tasks absorbed into plan)
   - `[specify, implement]` (plan and tasks absorbed into specify)
3. If the chain is invalid, STOP and output:
   ```
   Error: Invalid workflow chain configuration.
   Valid chains: [specify, plan, tasks, implement], [specify, plan, implement], [specify, implement]
   ```
4. Verify that `implement` is present in the configured chain. If not, STOP and output:
   ```
   Error: Step 'implement' is not part of the configured workflow chain [current chain].
   To use this step, update workflow.chain in tricycle.config.yml and run tricycle assemble.
   ```
