# Tasks: Shell-Only CLI

**Input**: Design documents from `/specs/002-shell-only-cli/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/cli-interface.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create directory structure for the bash CLI

- [x] T001 Create directory structure: `bin/lib/` for library scripts

---

## Phase 2: Foundational (Core Libraries)

**Purpose**: Core library modules that ALL commands depend on. MUST complete before any user story work.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 [P] Implement YAML subset parser in `bin/lib/yaml_parser.sh` — awk-based line-by-line parser that converts `tricycle.config.yml` into flat `KEY=VALUE` lines (dot-notation keys, numeric array indices); must handle: nested objects, arrays of objects, inline JSON arrays `["a","b"]`, simple value arrays, booleans, comments, quoted strings, blank lines; see `data-model.md` YAML Parser Output Specification for exact rules
- [x] T003 [P] Implement JSON builder in `bin/lib/json_builder.sh` — `json_escape`, `json_kv`, `json_kv_bool`, `json_kv_raw`, `json_array` functions using `printf`; must produce valid JSON for settings.json, .mcp.json, and .tricycle.lock structures
- [x] T004 [P] Implement shared helpers in `bin/lib/helpers.sh` — SHA-256 detection (`shasum -a 256` / `sha256sum` fallback), `cfg_get`/`cfg_has`/`cfg_count`/`cfg_get_or` config accessors (grep over CONFIG_DATA), `write_file` (mkdir -p + write), `error`/`info` output, `prompt`/`choose` interactive input functions
- [x] T005 [P] Implement template engine in `bin/lib/template_engine.sh` — two-pass processor: pass 1 (awk) resolves `{{#each apps}}...{{/each}}` and `{{#if key}}...{{/if}}` blocks using config data; pass 2 (sed) substitutes `{{variable}}` placeholders; must handle all variables listed in `data-model.md` Template Context table and match the Node.js `substituteVars()`/`substituteAppVars()` behavior
- [x] T006 Create CLI entry point `bin/tricycle` — `#!/usr/bin/env bash`, resolve `TOOLKIT_ROOT` via script location, source all `bin/lib/*.sh`, parse arguments (subcommand + `--preset`, `--dry-run`, `--help`/`-h` flags), dispatch to command functions, print usage on `--help` or no args; mark executable

**Checkpoint**: All library functions available. CLI responds to `--help`. Ready for command implementation.

---

## Phase 3: User Story 1 + User Story 3 — Init Without Package Manager + YAML Parsing (Priority: P1) MVP

**Goal**: A developer can clone the repo and run `tricycle init --preset <name>` to scaffold a project with no Node.js or npm required. YAML config files are parsed correctly by the shell-based parser.

**Independent Test**: Run `./bin/tricycle init --preset single-app` in a temp directory, verify all output files are created (tricycle.config.yml, .claude/settings.json, .claude/commands/*, .claude/hooks/*, .specify/templates/*, .specify/scripts/bash/*, .gitignore, .tricycle.lock, .specify/memory/constitution.md).

### Implementation for User Story 1 + 3

- [x] T007 [US1] Implement `install_file` and `install_dir` functions in `bin/lib/helpers.sh` — copy file from source to dest with mkdir -p, compute sha256 checksum (first 16 chars), check lock for local modifications (skip if customized), chmod +x for .sh files, update lock entry, print WRITE/SKIP status
- [x] T008 [US1] Implement lock file functions in `bin/lib/helpers.sh` — `load_lock` reads `.tricycle.lock` JSON and extracts file entries (grep-based JSON parsing for this fixed schema), `save_lock` writes JSON via json_builder; `lock_get_checksum <path>` and `lock_is_customized <path>` accessors
- [x] T009 [US1] Implement `cmd_init` (preset mode) in `bin/tricycle` — parse `--preset` flag, load preset YAML via `parse_yaml`, prompt for project name override, write `tricycle.config.yml` via YAML printf output, install core directories (commands, templates, scripts, hooks, skills), create constitution placeholder, call `cmd_generate_settings`, call `cmd_generate_gitignore`, save lock, print completion message with next steps
- [x] T010 [US1] Implement `cmd_generate_settings` in `bin/tricycle` — build permissions array from config (package manager, docker, monorepo detection), build hooks config (block-spec-in-main, block-branch-in-main, post-implement-lint), write `.claude/settings.json` via json_builder functions
- [x] T011 [US1] Implement `cmd_generate_gitignore` in `bin/tricycle` — check if `.gitignore` exists, check if `.claude/*` rules already present, append or create gitignore block with `.claude/*`, exclusions, and `.tricycle.lock` entry

**Checkpoint**: `./bin/tricycle init --preset single-app` produces identical output to the Node.js version. YAML parsing works for all preset configs.

---

## Phase 4: User Story 2 — All Existing Commands Work Identically (Priority: P1)

**Goal**: Every command (`add`, `generate claude-md/settings/mcp`, `update`, `validate`) produces the same output as the Node.js CLI.

**Independent Test**: Run each subcommand with the shell CLI in a project initialized by `tricycle init --preset monorepo-turborepo` and diff generated files against Node.js CLI output.

### Implementation for User Story 2

- [x] T012 [P] [US2] Implement `cmd_add` in `bin/tricycle` — validate module argument, resolve module path in `modules/<name>/`, install files from subdirectories (commands, skills, hooks, scripts, templates, adapters, seeds) using same mapping as Node.js, handle qa module post-install (create qa/ dir, copy template files), handle worktree module (install scripts), save lock, print completion
- [x] T013 [P] [US2] Implement `cmd_generate` dispatch and `cmd_generate_claude_md` in `bin/tricycle` — dispatch to claude-md/settings/mcp targets; for claude-md: load config, conditionally assemble sections from `generators/sections/*.md.tpl` (docker if apps have docker, lint-test if push.require_lint/tests, push-gating if push.require_approval, worktree if worktree.enabled, qa if qa.enabled, mcp always, feature-branch always, artifact-cleanup always), process each section through template engine, concatenate with `---` separators, write CLAUDE.md
- [x] T014 [P] [US2] Implement `cmd_generate_mcp` in `bin/tricycle` — load MCP preset JSON from `modules/mcp/presets/<preset>.json` (cat + pass through to output), merge custom servers from config (iterate `mcp.custom.*` keys, build JSON objects for http type vs command type), write `.mcp.json` via json_builder
- [x] T015 [US2] Implement `cmd_update` in `bin/tricycle` — iterate core directory mappings (commands, templates, scripts, hooks), compare source checksums vs lock checksums, detect locally modified files (skip), detect new files (add), detect updated source files (update), support `--dry-run` flag (print without writing), save lock, print summary counts
- [x] T016 [US2] Implement `cmd_validate` in `bin/tricycle` — check project.name and project.type exist in config, check each app path exists on disk, check core directories exist (.claude/commands, .specify/templates, .specify/scripts/bash, .claude/hooks), check constitution file exists, check hook scripts are executable (test -x), count errors, exit 1 if any errors

**Checkpoint**: All five subcommands produce output matching the Node.js CLI. Feature parity achieved.

---

## Phase 5: User Story 4 — Interactive Wizard (Priority: P2)

**Goal**: `tricycle init` without `--preset` runs an interactive wizard with the same prompts, defaults, and behavior as the Node.js version.

**Independent Test**: Run `./bin/tricycle init` without preset, provide inputs at each prompt, verify `tricycle.config.yml` reflects chosen values.

### Implementation for User Story 4

- [x] T017 [US4] Implement `cmd_init` wizard mode in `bin/tricycle` — when no `--preset` flag: prompt for project name (default "my-project"), choose project type (monorepo/single-app, default 0), choose package manager (bun/npm/yarn/pnpm, default 0), prompt for base branch (default "staging"); build config structure and write `tricycle.config.yml` via printf YAML output; uses `prompt`/`choose` helpers from T004; then run same install flow as preset mode (core files, settings, gitignore, lock)

**Checkpoint**: Interactive init matches Node.js wizard behavior — same prompts, same defaults, same output.

---

## Phase 6: User Story 5 — One-Off Execution (Priority: P2)

**Goal**: Users can run a single bash command to execute any tricycle subcommand without installing, or install the tool permanently.

**Independent Test**: Run `bash install.sh init --preset single-app` from a temp directory (simulating curl pipe), verify init completes and temp files are cleaned up.

### Implementation for User Story 5

- [x] T018 [US5] Create `install.sh` bootstrapper at repo root — standalone bash script (no sourced deps); detect mode: `--install [path]` for persistent install vs subcommand passthrough for one-off; one-off mode: clone repo to `mktemp -d`, run `bin/tricycle "$@"`, remove temp dir on exit (trap); install mode: clone to target path (default `~/.tricycle-pro`), create symlink in `~/.local/bin/tricycle` if dir exists, print PATH instructions; validate git is available; repo URL via `TRICYCLE_REPO` env var with fallback to GitHub origin URL; mark executable

**Checkpoint**: One-off execution works without leaving artifacts. Install mode creates working persistent setup.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Tests, cleanup, and finalization

- [x] T019 Create test suite in `tests/run-tests.sh` — shell test runner with `run_test` helper (name + command, track pass/fail), temp dir isolation per test; test groups matching existing cli.test.js coverage: CLI basics (--help exits 0, unknown command exits 1, validate succeeds, update --dry-run), file integrity (hooks executable, command templates exist, presets have valid YAML, modules have README), init with presets (single-app creates config + settings + hooks + commands + lock + constitution), init errors (invalid preset exits 1), add modules (ci-watch installs commands, memory installs seeds, nonexistent exits 1, no arg exits 1), generate (claude-md creates file with project name + push gating, settings.json includes npx + npm permissions, no config exits 1); include test that runs `generate claude-md` with monorepo-turborepo preset to exercise all template sections; mark executable
- [x] T020 Verify output parity — run Node.js CLI and shell CLI with `init --preset single-app` and `init --preset monorepo-turborepo` in separate temp dirs, diff all generated files to confirm semantic equivalence (same keys/values; whitespace and key ordering may differ). MUST run while Node.js artifacts still exist
- [x] T021 Remove Node.js artifacts — delete `bin/tricycle.js`, `package.json`, `package-lock.json`, `eslint.config.js`. MUST run after T020 (parity verification)
- [x] T022 Update `tricycle.config.yml` — remove lint entry (no ShellCheck dependency required), change test command from `node --test tests/` to `./tests/run-tests.sh`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1+US3 (Phase 3)**: Depends on Phase 2 — BLOCKS US2 (commands need init infrastructure)
- **US2 (Phase 4)**: Depends on Phase 3 (reuses install_file, lock functions, generate_settings)
- **US4 (Phase 5)**: Depends on Phase 3 (extends cmd_init with wizard mode)
- **US5 (Phase 6)**: Depends on Phase 2 only (bootstrapper just wraps bin/tricycle)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1+US3 (P1)**: First story — establishes init + YAML parsing foundation
- **US2 (P1)**: Depends on US1 infrastructure (install helpers, lock functions, settings generator)
- **US4 (P2)**: Depends on US1 (extends init with wizard mode) — can be implemented alongside US2
- **US5 (P2)**: Independent of other stories — only needs bin/tricycle to exist

### Within Each User Story

- Library functions before command implementations
- Core command flow before edge cases
- File write functions before commands that use them

### Parallel Opportunities

**Phase 2 (all four libs in parallel)**:
```
T002: yaml_parser.sh  ─┐
T003: json_builder.sh  ├─► T006: bin/tricycle entry point
T004: helpers.sh       ─┤
T005: template_engine.sh─┘
```

**Phase 4 (three commands in parallel)**:
```
T012: cmd_add          ─┐
T013: cmd_generate_claude_md ├─► (all independent, different code paths)
T014: cmd_generate_mcp ─┘
```

**Phase 5 + 6 can run in parallel** (US4 and US5 are independent)

---

## Implementation Strategy

### MVP First (User Stories 1 + 3)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (4 libs + entry point)
3. Complete Phase 3: US1+US3 (init with presets, YAML parsing)
4. **STOP and VALIDATE**: Run `./bin/tricycle init --preset single-app` and verify output
5. This alone proves the shell-only CLI works without npm

### Incremental Delivery

1. Setup + Foundational → libs work, --help prints
2. US1+US3 → init works → **MVP!**
3. US2 → all commands work → **Feature parity**
4. US4 → wizard works → **Full init experience**
5. US5 → bootstrapper works → **Distribution ready**
6. Polish → tests pass, Node.js removed → **Complete**

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- T020 (parity verification) must run BEFORE T021 (Node.js removal) — need both CLIs available to compare
- Bash 3.2 compatibility constraint applies to ALL bash code (no associative arrays, no mapfile, no nameref)
- All new .sh files must be executable (chmod +x)
- The YAML parser (T002) is the highest-risk task — test with all 4 preset configs
