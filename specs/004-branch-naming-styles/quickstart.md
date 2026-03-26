# Quickstart: Configurable Branch Naming Styles

## Setup

### Feature-name style (default)

No config needed — this is the default. Or explicitly set:

```yaml
# tricycle.config.yml
branching:
  style: feature-name
```

Run: `/trc.specify Add dark mode toggle`
Result: branch `dark-mode-toggle`, spec at `specs/dark-mode-toggle/`

### Issue-number style

```yaml
# tricycle.config.yml
branching:
  style: issue-number
  prefix: TRI          # your project's issue prefix
```

Run: `/trc.specify TRI-042 Add export to CSV`
Result: branch `TRI-042-export-csv`, spec at `specs/TRI-042-export-csv/`

If you forget the issue number:
```
/trc.specify Add export to CSV
→ Agent asks: "What is the issue number? (e.g., TRI-042)"
→ You answer: TRI-042
→ Continues normally
```

### Ordered style (current behavior)

```yaml
# tricycle.config.yml
branching:
  style: ordered
```

Run: `/trc.specify Add notifications`
Result: branch `004-notifications`, spec at `specs/004-notifications/`

## Verification

After running `/trc.specify`:
1. Check `git branch --show-current` matches the expected format
2. Check `specs/<branch-name>/spec.md` exists
3. Run `tricycle validate` to confirm project integrity
