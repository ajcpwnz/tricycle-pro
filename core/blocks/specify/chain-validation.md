---
name: chain-validation
step: specify
description: Validate that specify step is in the configured workflow chain
required: true
default_enabled: true
order: 20
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
4. Verify that `specify` is present in the configured chain. If not, STOP and output:
   ```
   Error: Step 'specify' is not part of the configured workflow chain.
   ```

Note the chain configuration — it will be used by subsequent blocks to determine absorbed responsibilities.
