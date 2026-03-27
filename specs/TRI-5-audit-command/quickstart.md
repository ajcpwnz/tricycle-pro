# Quickstart: TRI-5 Audit Command

## Basic usage

```bash
# Audit files against constitution
/trc.audit src/

# Audit a feature's changes
/trc.audit --feature TRI-3-skills-system

# Audit with custom criteria
/trc.audit bin/ --prompt "check all functions have error handling"

# Audit entire project (no scope = everything)
/trc.audit
```

## Enable Linear output

Install the `linear-audit` skill and configure it:

```yaml
# tricycle.config.yml
workflow:
  blocks:
    audit:
      skills:
        - linear-audit
```

Then run `tricycle update` to install the skill. Audit findings will be routed to Linear when the MCP server is available.

## Verify

```bash
# Check command exists
ls core/commands/trc.audit.md

# Check linear-audit skill exists
ls core/skills/linear-audit/SKILL.md

# Check audit output directory exists
ls docs/audits/

# Run an audit
/trc.audit bin/tricycle
# → Report appears in docs/audits/audit-YYYY-MM-DD-*.md
```
