# Research: SessionStart Context Injection

## Claude Code SessionStart Hook Mechanism

**Decision**: Use the `SessionStart` hook event type in `.claude/settings.json` to inject context files into every session.

**Rationale**: SessionStart is the only hook event that fires at session lifecycle boundaries (startup, resume, compact) rather than on tool usage. It injects content via `additionalContext` in the hook response JSON — the same mechanism used by PostToolUse hooks like `post-implement-lint.sh`. This is the officially supported path for context injection.

**Alternatives considered**:
- Embedding in CLAUDE.md — rejected: bloats the file, mixes instructions with context, hard to keep in sync
- MCP server — rejected: MCP provides tools, not context injection. No `additionalContext` equivalent.
- Custom system prompt via `--append-system-prompt` CLI flag — rejected: requires every invocation to include the flag, not portable across IDE/desktop/web

## Hook Output Format

**Decision**: Output `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<escaped content>"}}` on stdout.

**Rationale**: Matches the exact format used by `post-implement-lint.sh` (line 36-38) which is proven in production. The `additionalContext` field content goes directly into Claude's conversation context.

**Alternatives considered**:
- Outputting raw text — rejected: Claude Code hook protocol requires JSON with specific structure
- Using `jq` to build JSON — rejected as primary path: not guaranteed to be installed. Inline `json_escape` from `common.sh:170-182` handles all RFC 8259 escaping without external deps.

## File List Decoupling (.session-context.conf)

**Decision**: `cmd_generate_settings()` writes a `.claude/hooks/.session-context.conf` file containing resolved file paths (one per line). The hook script reads this conf file instead of parsing YAML.

**Rationale**: Hook scripts run standalone (not sourced from bin/tricycle), so they cannot use `cfg_get`, `cfg_count`, or `parse_yaml`. A simple line-per-file conf eliminates YAML parsing in the hook while keeping the hook inspectable and debuggable. Regenerated on every `tricycle generate settings`.

**Alternatives considered**:
- Inlining file paths in settings.json — rejected: settings.json is a fixed schema defined by Claude Code, no custom fields
- Parsing tricycle.config.yml in the hook with grep/awk — rejected: fragile, duplicates YAML parsing logic, slower
- Sourcing bin/lib/helpers.sh in the hook — rejected: creates dependency on toolkit internals, breaks if user moves the hook

## Config Shape

**Decision**: Add `context.session_start` section with `constitution` (bool, default true) and `files` (string array, default empty).

**Rationale**: Follows existing config conventions (`worktree.enabled`, `qa.enabled`). Constitution defaults to true for zero-config experience (FR-005). The `files` list uses the same array pattern as `workflow.blocks.specify.enable`.

**Config parsed as** (via `parse_yaml`):
```
context.session_start.constitution=true
context.session_start.files.0=docs/architecture.md
context.session_start.files.1=.trc/memory/decisions.md
```

## Content Size Limit

**Decision**: Truncate total injected content at 50,000 characters with a truncation notice.

**Rationale**: Claude Code's context window is large but not infinite. Constitution files are typically 1-2KB. Even with 10 extra files, 50K chars is generous. The truncation notice tells the user to reduce their file list if hit.

**Alternatives considered**:
- No limit — rejected: a user accidentally pointing to a large generated file could overwhelm context
- Per-file limit — rejected: harder to reason about, total limit is simpler
- Configurable limit — rejected: unnecessary complexity for an edge case

## Placeholder Detection

**Decision**: Skip constitution injection if file content matches `/Run.*trc\.constitution/` (the default placeholder pattern).

**Rationale**: Injecting the placeholder text provides no value and wastes tokens. Better to either skip silently or inject a brief reminder. The placeholder pattern is stable — it's in the template at `core/templates/constitution-template.md`.

## SessionStart Matcher

**Decision**: No matcher field — hook fires on all session events (startup, resume, compact).

**Rationale**: User explicitly chose "all three" during specification. Unlike PreToolUse/PostToolUse which need matchers to filter by tool name, SessionStart has no sub-events to filter. Omitting the matcher means it fires on every SessionStart event.
