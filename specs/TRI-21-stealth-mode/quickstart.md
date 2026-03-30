# Quickstart: Stealth Mode

**Branch**: `TRI-21-stealth-mode` | **Date**: 2026-03-31

## Enable Stealth Mode

Add to `tricycle.config.yml`:

```yaml
stealth:
  enabled: true
```

Then regenerate:

```bash
tricycle generate gitignore
```

All tricycle files are now invisible to git.

## Verify

```bash
git status
# Should show no tricycle-related files (.claude/, .trc/, specs/, tricycle.config.yml)
```

## Choose Ignore Target (optional)

Default: `.git/info/exclude` (maximum stealth, never committed).

To use `.gitignore` instead:

```yaml
stealth:
  enabled: true
  ignore_target: gitignore
```

## Disable Stealth Mode

```yaml
stealth:
  enabled: false
```

Then regenerate:

```bash
tricycle generate gitignore
```

Stealth rules are removed and normal gitignore rules are restored.

## How It Works

- Stealth writes a demarcated block of ignore patterns to `.git/info/exclude` (or `.gitignore`)
- The block covers: `.claude/`, `.trc/`, `specs/`, `tricycle.config.yml`, `.tricycle.lock`, `.mcp.json`
- All workflow commands (`/trc.specify`, `/trc.plan`, etc.) work identically — stealth only affects VCS visibility
- The config file itself (`tricycle.config.yml`) is on disk but gitignored
