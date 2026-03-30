# Contract: Feature Flag Auto-Enable Interface

The assembly script translates config feature flags into block enables before `apply_overrides` runs.

## Input

Config section read via `cfg_get`:

```yaml
qa:
  enabled: true   # → enables qa-testing block in implement step
```

## Output

Prepended to the overrides string for the `implement` step:

```
enable=qa-testing
```

## Rules

1. If `qa.enabled` is `true`, add `enable=qa-testing` to the implement step overrides.
2. If `qa.enabled` is `false`, absent, or empty, do nothing.
3. The auto-enable MUST NOT override a manual `disable` — if the user has `workflow.blocks.implement.disable: [qa-testing]`, the disable takes precedence (existing behavior of `apply_overrides`).
4. The auto-enable is additive to any manual enables — if both `qa.enabled: true` and `workflow.blocks.implement.enable: [qa-testing]` are present, the block is enabled once (deduplication in `apply_overrides`).
