# Quickstart: SessionStart Context Injection

## Default (zero-config)

After running `tricycle init` or `tricycle generate settings`, the constitution is automatically injected into every Claude Code session. No configuration required.

## Add extra context files

Edit `tricycle.config.yml`:

```yaml
context:
  session_start:
    constitution: true
    files:
      - "docs/architecture.md"
      - ".trc/memory/decisions.md"
```

Then regenerate:

```bash
tricycle generate settings
```

Start a new Claude Code session — both the constitution and the listed files appear in context.

## Disable constitution injection

```yaml
context:
  session_start:
    constitution: false
```

Then `tricycle generate settings`. The constitution is no longer injected. If `files` is also empty, the SessionStart hook is omitted from settings.json entirely.

## Verify

Check that the hook is installed:

```bash
tricycle validate
```

Test the hook output manually:

```bash
echo '{}' | .claude/hooks/session-context.sh
```

Should output JSON with `hookSpecificOutput.additionalContext` containing your files.
