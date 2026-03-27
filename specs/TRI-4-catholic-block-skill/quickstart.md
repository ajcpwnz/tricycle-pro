# Quickstart: TRI-4 Catholic Block & Skill

## Enable the catholic block and skill

Add to `tricycle.config.yml`:

```yaml
workflow:
  blocks:
    specify:
      enable:
        - catholic
      skills:
        - catholic
```

Then run:

```bash
tricycle assemble
tricycle update
```

## Verify

```bash
# Check skill installed
ls .claude/skills/catholic/SKILL.md

# Check block exists
ls core/blocks/optional/specify/catholic.md

# Check assembled command includes prayer
grep -A3 "prayer" .claude/commands/trc.specify.md

# Check skill invocation wired
grep "catholic" .claude/commands/trc.specify.md

# Run specify to see it in action
/trc.specify "test feature to verify catholic verbiage"
```

## Disable

Remove `catholic` from the `enable` and `skills` lists in `tricycle.config.yml`, then `tricycle assemble`.
