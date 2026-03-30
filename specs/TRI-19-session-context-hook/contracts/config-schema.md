# Contract: Configuration Schema for context.session_start

## YAML Schema

```yaml
context:
  session_start:
    constitution: <boolean>   # default: true
    files:                    # default: [] (empty)
      - <string>              # repo-relative file path
      - <string>
```

## Field Definitions

### context.session_start.constitution

| Property | Value |
| -------- | ----- |
| Type     | boolean |
| Default  | `true` |
| Required | No |

When `true` (or absent), the constitution file path from `constitution.root` (default `.trc/memory/constitution.md`) is prepended to the context file list.

When `false`, the constitution is excluded from injection. Other files in `files` are still injected.

### context.session_start.files

| Property | Value |
| -------- | ----- |
| Type     | string array |
| Default  | `[]` |
| Required | No |

Additional files to inject into session context. Paths are relative to the project root. Non-existent files are silently skipped at runtime (no build-time validation).

## Parsed Config Keys

After `parse_yaml`, these keys appear in `CONFIG_DATA`:

```
context.session_start.constitution=true
context.session_start.files.0=docs/architecture.md
context.session_start.files.1=.trc/memory/decisions.md
```

## Generated Settings.json Entry

```json
"SessionStart": [
  {
    "hooks": [{"type": "command", "command": ".claude/hooks/session-context.sh", "timeout": 10}]
  }
]
```

No `matcher` field — fires on all session events (startup, resume, compact).

## Backward Compatibility

- Projects with no `context` section: constitution injected by default (opt-out).
- Projects with `context.session_start.constitution: false` and no `files`: SessionStart hook section is omitted from settings.json entirely.
