# Linear Audit Skill

Routes audit findings to Linear as issues.

## Installation

This skill ships with Tricycle Pro. Install via `tricycle update`.

## Configuration

Add to your `tricycle.config.yml`:

```yaml
workflow:
  blocks:
    audit:
      skills:
        - linear-audit
```

## Requirements

- **Linear MCP server** configured in `.mcp.json`
- Audit reports in `docs/audits/` (produced by `/trc.audit`)

## What it does

1. Reads the most recent audit report from `docs/audits/`
2. Parses findings with severity **critical** or **warning**
3. Creates Linear issues in the project's team with title, evidence, and recommendation
4. Skips duplicates (same title already exists)

## Graceful degradation

If Linear MCP is not available, the skill warns and exits cleanly. Audit findings remain in `docs/audits/`.

## Manual usage

```
/linear-audit
```

Invoke after running `/trc.audit` to push findings to Linear.
