# Quickstart: Local Config Overrides

## Create a local override

Create `tricycle.config.local.yml` in your project root (same directory as `tricycle.config.yml`):

```yaml
# Override just the fields you want — everything else comes from base config
push:
  require_approval: false

qa:
  enabled: true
```

That's it. Tricycle automatically detects and merges the override file.

## Run assemble

```bash
tricycle assemble
```

This generates:
- `.claude/commands/trc.*.md` — shared commands from base config (committed)
- `.trc/local/commands/trc.*.md` — your local variant commands from merged config (gitignored)

## What you can override

| Section | Example |
|---------|---------|
| `push.*` | `push.require_approval: false` |
| `qa.*` | `qa.enabled: true` |
| `worktree.*` | `worktree.enabled: true` |
| `workflow.blocks.*` | Enable/disable specific blocks |
| `stealth.*` | `stealth.enabled: true` |

## What you cannot override

`project.*`, `apps.*`, `workflow.chain`, `branching.*`, `constitution.*`, `mcp.*`, `context.*` — these are shared team config. Attempting to override them produces a warning.

## VCS exclusion

The override file is automatically excluded from version control. You never need to manually add it to `.gitignore`.
