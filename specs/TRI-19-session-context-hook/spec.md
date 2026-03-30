# Feature Specification: SessionStart Context Injection

**Feature Branch**: `TRI-19-session-context-hook`
**Created**: 2026-03-30
**Status**: Draft
**Input**: User description: "Auto-inject constitution + context files into every Claude session via SessionStart hook"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Constitution Auto-Loaded on Session Start (Priority: P1)

A developer opens Claude Code in a tricycle-initialized project and starts a regular conversation (debugging, refactoring, ad-hoc questions). Without running any `/trc.*` command, the project constitution is already in Claude's context. Claude respects project principles even in casual sessions — no silent violations because the constitution was never loaded.

**Why this priority**: This is the core value proposition. Today, the constitution is invisible in non-workflow sessions, meaning the agent can violate project principles in any session that doesn't explicitly invoke a workflow command. This is the gap that must be closed first.

**Independent Test**: Initialize a tricycle project, populate the constitution with a distinctive principle, regenerate settings, then start a fresh Claude Code session. Verify that Claude can reference the constitution principle without being asked to read it.

**Acceptance Scenarios**:

1. **Given** a tricycle project with a populated constitution and generated settings, **When** a developer starts a fresh Claude Code session, **Then** the constitution content is present in Claude's context without any user command.
2. **Given** a tricycle project with `context.session_start.constitution: true` (or absent — default is true), **When** `tricycle generate settings` is run, **Then** the generated `.claude/settings.json` includes a `SessionStart` hook entry pointing to the context injection script.
3. **Given** a tricycle project where the constitution is only a placeholder (not yet populated), **When** a session starts, **Then** the hook either injects nothing or injects a brief reminder to populate the constitution — not the raw placeholder text.

---

### User Story 2 - Additional Context Files Configurable (Priority: P2)

A developer adds project-specific context files (architecture decisions, team conventions, domain glossary) to the `context.session_start.files` list in `tricycle.config.yml`. After regenerating settings, those files are also injected into every Claude session alongside the constitution.

**Why this priority**: Different projects need different context. The constitution covers principles, but teams also have architecture decisions, domain knowledge, and conventions that Claude should respect. Making this configurable without touching CLAUDE.md keeps the system clean and modular.

**Independent Test**: Add a custom file path to `context.session_start.files`, regenerate settings, and verify that the file's content appears in Claude's context on session start.

**Acceptance Scenarios**:

1. **Given** a config with `context.session_start.files: ["docs/architecture.md"]` and that file exists, **When** `tricycle generate settings` is run and a new session starts, **Then** both the constitution and the architecture doc are injected into Claude's context.
2. **Given** a config with a file listed in `context.session_start.files` that does not exist on disk, **When** a session starts, **Then** the missing file is silently skipped and other valid files are still injected.
3. **Given** a config with no `context.session_start.files` section, **When** a session starts, **Then** only the constitution is injected (no errors about missing files config).

---

### User Story 3 - Context Survives All Session Events (Priority: P3)

A developer is in a long Claude Code session. The context window fills up and Claude compacts the conversation. After compaction, the constitution and context files are re-injected so Claude doesn't lose awareness of project principles. The same holds when resuming a saved session.

**Why this priority**: Context compaction silently evicts early content. Without re-injection, the constitution disappears mid-session and the agent reverts to default behavior. This makes the feature reliable across real-world usage patterns.

**Independent Test**: Start a session (verify injection), trigger a resume or compact event, and verify the context is re-injected.

**Acceptance Scenarios**:

1. **Given** a session where the context hook fired on startup, **When** the session is compacted, **Then** the hook fires again and re-injects the context files.
2. **Given** a previously saved session, **When** the developer resumes it, **Then** the hook fires and injects context files.
3. **Given** a session where context was injected, **When** no session event occurs, **Then** the context is not redundantly re-injected (the hook only fires on session events, not on every prompt).

---

### Edge Cases

- What happens when the constitution file is empty (0 bytes)? The hook skips it silently.
- What happens when a configured context file is extremely large (50KB+)? The hook truncates to a reasonable limit to avoid overwhelming the context window.
- What happens when `context.session_start.constitution` is explicitly `false`? The constitution is not injected, but any configured `files` still are.
- What happens when all configured files are missing or invalid? The hook exits cleanly with no output (no-op).
- What happens when there is no `tricycle.config.yml` (running hook outside a tricycle project)? The hook exits cleanly.
- What happens when the hook script is not executable? `tricycle generate settings` installs it with executable permissions; `tricycle validate` flags it as an error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST inject the project constitution into Claude's context at the start of every session without requiring the user to run a command.
- **FR-002**: The system MUST allow users to configure additional context files via a `context.session_start.files` list in `tricycle.config.yml`.
- **FR-003**: The system MUST fire the context injection on all session events: startup, resume, and compact.
- **FR-004**: The system MUST skip files that do not exist, are empty, or contain only placeholder text.
- **FR-005**: The system MUST include the constitution by default when the `context.session_start` section is absent from the config (opt-out, not opt-in).
- **FR-006**: The system MUST allow users to disable constitution injection by setting `context.session_start.constitution: false`.
- **FR-007**: The system MUST produce the context injection hook and its configuration as part of the `tricycle generate settings` command.
- **FR-008**: The system MUST separate the resolved file list from the hook script (generated conf file) so the hook does not need to parse YAML at runtime.
- **FR-009**: The system MUST label each injected file with a clear header so Claude can distinguish between multiple context sources.
- **FR-010**: The hook script MUST exit cleanly (exit 0, no output) when there are no valid files to inject.
- **FR-011**: The `tricycle validate` command MUST check that the hook script exists and is executable when context injection is configured.

### Key Entities

- **Session Context Configuration**: The `context.session_start` section in `tricycle.config.yml` — controls which files are injected and whether the constitution is included.
- **Context File List**: A generated configuration file (`.session-context.conf`) containing resolved file paths, one per line — decouples the hook from YAML parsing.
- **Hook Script**: The executable that reads the file list, loads content, and outputs the injection payload in Claude Code's expected hook response format.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of fresh Claude Code sessions in a tricycle project have the constitution available in context without any user command.
- **SC-002**: Adding a new context file to the config and regenerating settings takes under 30 seconds (edit config, run one command).
- **SC-003**: The hook script completes execution in under 2 seconds for up to 10 configured files.
- **SC-004**: All existing tests continue to pass after the change, plus new tests cover hook generation, hook execution, and edge cases.
- **SC-005**: Projects that do not configure `context.session_start` at all still get constitution injection by default (zero-config experience).

## Assumptions

- Claude Code's `SessionStart` hook event is stable and fires reliably on startup, resume, and compact events.
- The `hookSpecificOutput.additionalContext` field in the hook response is the supported mechanism for injecting context.
- A hook timeout of 10 seconds is sufficient for reading and concatenating a handful of local files.
- The existing `install_dir` mechanism for hooks (used by `tricycle update`) automatically picks up the new hook script without additional wiring.
- Preset configs can be extended with the new `context.session_start` section without breaking backward compatibility for projects using older configs.
