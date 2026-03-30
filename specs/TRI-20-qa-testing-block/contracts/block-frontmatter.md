# Contract: QA Block Frontmatter

The qa-testing block MUST conform to the standard optional block frontmatter schema:

```yaml
---
name: qa-testing
step: implement
description: QA testing gate — run configured tests, follow instructions file, halt on failure before push
required: false
default_enabled: false
order: 55
---
```

## Constraints

- `name` MUST be `qa-testing` — this is the key used by `workflow.blocks.implement.enable` and the auto-enable function.
- `order` MUST be > 50 (after task-execution) and < 65 (before push-deploy).
- `default_enabled` MUST be `false` — the block is only included when explicitly enabled via config flag or manual override.
- `required` MUST be `false` — projects without QA should not be forced to include this block.
