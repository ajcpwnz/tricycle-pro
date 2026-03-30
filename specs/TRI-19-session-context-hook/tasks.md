# Tasks: SessionStart Context Injection

**Input**: Design documents from `/specs/TRI-19-session-context-hook/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Tests are included — the project has an existing test suite (`tests/run-tests.sh`) and the spec requires test coverage (SC-004).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No project scaffolding needed — existing CLI project. This phase creates the new hook script file and establishes the foundation.

- [X] T001 Create hook script skeleton `core/hooks/session-context.sh` with shebang, stdin read, repo root detection, and exit-0-no-output default behavior
- [X] T002 Add inline `json_escape` function to `core/hooks/session-context.sh` (port from `core/scripts/bash/common.sh:170-182` — handles backslash, quotes, newlines, tabs, control chars)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Wire the hook into `cmd_generate_settings()` and establish the `.session-context.conf` file generation. All user stories depend on this.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Add `.session-context.conf` generation to `cmd_generate_settings()` in `bin/tricycle` — read `constitution.root` from config (default `.trc/memory/constitution.md`), write resolved path to `.claude/hooks/.session-context.conf`
- [X] T004 Add `SessionStart` hook entry to the settings.json heredoc template in `cmd_generate_settings()` in `bin/tricycle` — append `"SessionStart": [{"hooks": [{"type": "command", "command": ".claude/hooks/session-context.sh", "timeout": 10}]}]` after PostToolUse section
- [X] T005 Implement conf file reader in `core/hooks/session-context.sh` — read `.claude/hooks/.session-context.conf` line by line, skip comments (`#`) and empty lines, collect valid file paths

**Checkpoint**: Settings generation produces SessionStart hook entry and .session-context.conf with constitution path. Hook script reads the conf file.

---

## Phase 3: User Story 1 — Constitution Auto-Loaded (Priority: P1) MVP

**Goal**: Constitution content is injected into every Claude session without any user command.

**Independent Test**: Run `tricycle init`, populate constitution, run `tricycle generate settings`, then `echo '{}' | .claude/hooks/session-context.sh` — output contains constitution content in valid JSON.

### Implementation for User Story 1

- [X] T006 [US1] Implement file reading and content assembly in `core/hooks/session-context.sh` — for each path from conf, check file exists and is non-empty, read content, prepend `## <Label> (<path>)` header, concatenate with `---` separators
- [X] T007 [US1] Add placeholder detection to `core/hooks/session-context.sh` — skip files matching `Run.*trc\.constitution` regex pattern (the default placeholder text)
- [X] T008 [US1] Implement JSON output in `core/hooks/session-context.sh` — if any content was assembled, JSON-escape it and output `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<escaped content>"}}`; if no valid content, exit 0 with no output
- [X] T009 [US1] Add test "generated settings.json includes SessionStart hook" in `tests/run-tests.sh` — grep for `SessionStart` in the init-single settings.json
- [X] T010 [US1] Add test "session-context hook is installed and executable" in `tests/run-tests.sh` — assert `.claude/hooks/session-context.sh` exists and is executable after init
- [X] T011 [US1] Add test ".session-context.conf is generated with constitution path" in `tests/run-tests.sh` — assert `.claude/hooks/.session-context.conf` exists and contains `constitution`
- [X] T012 [US1] Add test "session-context hook outputs valid JSON for populated constitution" in `tests/run-tests.sh` — populate constitution, pipe `{}` to hook, assert output contains `hookSpecificOutput`
- [X] T013 [US1] Add test "session-context hook handles missing constitution gracefully" in `tests/run-tests.sh` — run hook in dir with no constitution, assert exit 0 and no output
- [X] T014 [US1] Add test "session-context hook skips placeholder constitution" in `tests/run-tests.sh` — leave constitution as placeholder, assert hook produces no output

**Checkpoint**: Constitution auto-injection works end-to-end. `tricycle init` + `generate settings` → hook outputs constitution in valid JSON. All US1 tests pass.

---

## Phase 4: User Story 2 — Additional Context Files Configurable (Priority: P2)

**Goal**: Users can list extra files in `context.session_start.files` and they get injected alongside the constitution.

**Independent Test**: Add `context.session_start.files: ["docs/test.md"]` to config, regenerate settings, verify `.session-context.conf` contains both constitution and extra file path, verify hook output includes both.

### Implementation for User Story 2

- [X] T015 [US2] Extend `.session-context.conf` generation in `cmd_generate_settings()` in `bin/tricycle` — read `context.session_start.files` array via `cfg_count`/`cfg_get`, append each entry to the conf file after the constitution path
- [X] T016 [US2] Add `context.session_start.constitution: false` handling in `cmd_generate_settings()` in `bin/tricycle` — when explicitly false, omit constitution from conf file; when no files remain, omit SessionStart section from settings.json entirely
- [X] T017 [P] [US2] Add `context.session_start` section to `presets/single-app/tricycle.config.yml` — `constitution: true` with commented-out `files` example
- [X] T018 [P] [US2] Add `context.session_start` section to `presets/monorepo-turborepo/tricycle.config.yml` — same pattern as single-app
- [X] T019 [P] [US2] Add `context.session_start` section to `presets/nextjs-prisma/tricycle.config.yml` — same pattern as single-app
- [X] T020 [P] [US2] Add `context.session_start` section to `presets/express-prisma/tricycle.config.yml` — same pattern as single-app
- [X] T021 [US2] Add content truncation to `core/hooks/session-context.sh` — if total assembled content exceeds 50,000 characters, truncate and append `\n\n[Content truncated at 50,000 characters. Reduce context.session_start.files to stay within limit.]`
- [X] T022 [US2] Add test "session-context hook includes extra configured files" in `tests/run-tests.sh` — configure extra file, populate it, verify hook output includes its content
- [X] T023 [US2] Add test "session-context hook skips missing configured files" in `tests/run-tests.sh` — configure non-existent file, verify hook still outputs constitution without error
- [X] T024 [US2] Add test "SessionStart omitted when constitution false and no files" in `tests/run-tests.sh` — set `constitution: false` with no files, verify settings.json has no SessionStart

**Checkpoint**: Extra files injection works. Preset configs updated. Opt-out works. All US2 tests pass.

---

## Phase 5: User Story 3 — Context Survives All Session Events (Priority: P3)

**Goal**: The hook fires on startup, resume, and compact — no matcher restricts it.

**Independent Test**: Verify the generated settings.json SessionStart entry has no `matcher` field.

### Implementation for User Story 3

- [X] T025 [US3] Verify no `matcher` field in SessionStart hook entry in `cmd_generate_settings()` in `bin/tricycle` — the hook entry must NOT include a matcher so it fires on all session events (startup, resume, compact)
- [X] T026 [US3] Add test "SessionStart hook has no matcher (fires on all events)" in `tests/run-tests.sh` — parse settings.json SessionStart entry, assert no `matcher` key present

**Checkpoint**: Hook fires on all session events. No code change needed if T004 was implemented correctly (no matcher by default). Test validates the contract.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation, edge cases, and cleanup.

- [X] T027 Add session-context hook validation to `cmd_validate()` in `bin/tricycle` — if SessionStart hook is configured in settings.json, check `.claude/hooks/session-context.sh` exists and is executable
- [X] T028 Add `context.session_start` section to project's own `tricycle.config.yml` — `constitution: true` with no extra files (dogfooding)
- [X] T029 Run full test suite (`bash tests/run-tests.sh` and `node --test tests/test-*.js`) and fix any failures

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001, T002) — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 (T003, T004, T005)
- **US2 (Phase 4)**: Depends on Phase 3 completion (extends the same functions)
- **US3 (Phase 5)**: Can start after Phase 2 (verification only), but logically follows US1
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational — no dependencies on other stories
- **US2 (P2)**: Depends on US1 (extends the same hook script and settings generator)
- **US3 (P3)**: Depends on US1 (verifies the hook entry format established in T004)

### Within Each User Story

- Implementation tasks before test tasks where the test validates the implementation
- `cmd_generate_settings()` changes before hook script changes (conf file must exist for hook to read)
- Preset updates (T017-T020) are parallel with each other

### Parallel Opportunities

- T001 and T002 are sequential (same file)
- T017, T018, T019, T020 can all run in parallel (different preset files)
- T009-T014 tests can be written alongside US1 implementation (same test file, but tests validate the implementation)

---

## Parallel Example: User Story 2 Preset Updates

```bash
# Launch all preset config updates together:
Task: "Add context.session_start section to presets/single-app/tricycle.config.yml"
Task: "Add context.session_start section to presets/monorepo-turborepo/tricycle.config.yml"
Task: "Add context.session_start section to presets/nextjs-prisma/tricycle.config.yml"
Task: "Add context.session_start section to presets/express-prisma/tricycle.config.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T005)
3. Complete Phase 3: US1 — Constitution Auto-Loaded (T006-T014)
4. **STOP and VALIDATE**: Run `bash tests/run-tests.sh` — all tests pass, constitution injection works
5. This alone delivers the core value

### Incremental Delivery

1. Setup + Foundational → Hook skeleton wired into settings
2. Add US1 → Constitution auto-loads → Test → **MVP delivered**
3. Add US2 → Extra files configurable → Test → Full feature
4. Add US3 → Verify all-events firing → Test → Contract validated
5. Polish → Validation, dogfooding, cleanup

---

## Notes

- All file paths are relative to repository root unless noted
- The hook script (`core/hooks/session-context.sh`) is the source; it gets installed to `.claude/hooks/session-context.sh` via `install_dir`
- The `.session-context.conf` is generated (not a source file) — written by `cmd_generate_settings()`
- No new dependencies introduced — pure bash implementation
