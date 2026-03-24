# Feature Specification: Shell-Only CLI

**Feature Branch**: `002-shell-only-cli`
**Created**: 2026-03-24
**Status**: Draft
**Input**: User description: "cli needs to be package manager agnostic, shell only."

## Clarifications

### Session 2026-03-24

- Q: What test strategy replaces the Node.js test suite? → A: Plain shell test scripts using `test` / `[` assertions, no external framework.
- Q: How do users install the shell CLI? → A: Two modes — (1) one-off bash command to run without installing, (2) system install for persistent use.
- Q: How should the CLI handle non-bash shells? → A: Use `#!/usr/bin/env bash` shebang only; non-bash invocations are unsupported with no detection.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install and Initialize Without a Package Manager (Priority: P1)

A developer wants to use Tricycle Pro in a new project but does not have Node.js or npm installed, or prefers not to use them. They download or clone Tricycle Pro and run the CLI directly from the shell to initialize their project, without needing to run `npm install` or any package manager command first.

**Why this priority**: This is the core value proposition — the entire point of this feature is removing the package manager requirement. If the CLI still needs npm to run, nothing else matters.

**Independent Test**: Can be fully tested by cloning the repo and running `tricycle init` in a fresh project directory on a system without Node.js installed, and verifying the project is correctly initialized with config, core files, settings, and gitignore.

**Acceptance Scenarios**:

1. **Given** a system with only a POSIX-compatible shell (bash), **When** the user runs `tricycle init`, **Then** the interactive wizard runs, creates `tricycle.config.yml`, installs core files, generates `.claude/settings.json`, updates `.gitignore`, and writes `.tricycle.lock` — identical in structure and content to the current Node.js CLI output.
2. **Given** a system without Node.js or npm, **When** the user runs any `tricycle` subcommand (`init`, `add`, `generate`, `update`, `validate`), **Then** the command succeeds without errors related to missing runtimes or package managers.
3. **Given** the user passes `--preset monorepo-turborepo` to `tricycle init`, **When** the preset config file exists, **Then** it is loaded and used exactly as the current CLI does.

---

### User Story 2 - All Existing Commands Work Identically (Priority: P1)

A developer who has already been using the Node.js-based CLI switches to the shell-only version. Every command they previously used (`init`, `add`, `generate`, `update`, `validate`) produces the same output and file structure.

**Why this priority**: Feature parity is non-negotiable. The shell CLI must be a drop-in replacement, not a subset.

**Independent Test**: Run each subcommand (`init`, `add <module>`, `generate claude-md`, `generate settings`, `generate mcp`, `update`, `update --dry-run`, `validate`) with the shell CLI and compare outputs and generated files against the Node.js CLI output. Files should be byte-identical or semantically equivalent.

**Acceptance Scenarios**:

1. **Given** a project with an existing `tricycle.config.yml`, **When** the user runs `tricycle generate claude-md`, **Then** the resulting `CLAUDE.md` contains the same conditional sections (docker, lint-test, push-gating, worktree, qa, mcp, feature-branch, artifact-cleanup) as the Node.js version.
2. **Given** a project with installed core files, **When** the user runs `tricycle update`, **Then** files with unchanged checksums are updated, locally modified files are skipped, and the lock file is updated — matching current behavior.
3. **Given** a project with missing directories or non-executable hooks, **When** the user runs `tricycle validate`, **Then** the same validation checks run and the same error messages are displayed.

---

### User Story 3 - YAML Config Parsing Without External Libraries (Priority: P1)

The current CLI depends on the `yaml` npm package to parse `tricycle.config.yml`. The shell-only CLI must parse the same YAML config files without any external dependencies — using only built-in shell capabilities.

**Why this priority**: YAML parsing is fundamental — every command except `--help` depends on it. If this doesn't work, nothing works.

**Independent Test**: Create a `tricycle.config.yml` with all supported fields (nested objects, arrays of objects, strings, booleans) and verify the shell parser extracts every value correctly by running `tricycle validate` and `tricycle generate claude-md`.

**Acceptance Scenarios**:

1. **Given** a `tricycle.config.yml` with nested objects (e.g., `project.name`, `push.require_approval`), **When** the CLI parses it, **Then** all nested values are correctly extracted.
2. **Given** a `tricycle.config.yml` with array fields (e.g., `apps` list with multiple entries, `worktree.env_copy` list), **When** the CLI parses it, **Then** all array items and their nested properties are accessible.
3. **Given** a malformed or missing `tricycle.config.yml`, **When** the CLI attempts to parse it, **Then** a clear error message is shown and the CLI exits with a non-zero code.

---

### User Story 4 - Interactive Wizard Works in Shell (Priority: P2)

A developer runs `tricycle init` without a preset and interacts with the step-by-step wizard (project name, type, package manager, base branch) entirely through shell prompts.

**Why this priority**: Important for first-time setup UX, but users can work around it by using `--preset` or manually writing the config file.

**Independent Test**: Run `tricycle init` interactively, provide inputs at each prompt, and verify the resulting `tricycle.config.yml` reflects the chosen values.

**Acceptance Scenarios**:

1. **Given** the user runs `tricycle init` without `--preset`, **When** they are prompted for project name, type, package manager, and base branch, **Then** each prompt shows the same options and defaults as the current CLI.
2. **Given** a prompt with a default value, **When** the user presses Enter without typing, **Then** the default is used.
3. **Given** a choice prompt (e.g., project type), **When** the user enters an out-of-range number, **Then** the default option is selected.

---

### User Story 5 - One-Off Execution Without Installing (Priority: P2)

A developer wants to try Tricycle Pro or run a single command (e.g., `init`) without installing anything on their system. They run a single bash command that fetches and executes the CLI in one step.

**Why this priority**: Lowers the barrier to adoption — users can try the tool before committing to an install. But system install (User Story 1) is the primary path for ongoing use.

**Independent Test**: Run the one-off command on a clean system and verify `tricycle init` completes successfully, producing the same output as a locally installed run.

**Acceptance Scenarios**:

1. **Given** a system with bash and an internet connection, **When** the user runs the one-off command, **Then** the CLI executes the specified subcommand and produces correct output without leaving any persistent files on the system beyond the intended project output.
2. **Given** the user runs the one-off command with `init --preset monorepo-turborepo`, **When** the command completes, **Then** the result is identical to running the same command from a local install.

---

### Edge Cases

- The CLI uses `#!/usr/bin/env bash` — running via a non-bash shell (dash, ash) is unsupported and may produce errors. No detection or warning is provided.
- How does the YAML parser handle comments, multi-line strings, or quoted values with special characters in `tricycle.config.yml`?
- What happens when `tricycle update` encounters a file that exists on disk but is not tracked in `.tricycle.lock`?
- How does the CLI behave when run from a directory where `.specify/scripts/bash/` or other expected paths don't exist?
- What happens when `tricycle init --preset` is given a preset name that contains special shell characters?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: CLI MUST operate as a self-contained shell script with no dependencies beyond a POSIX-compatible shell (bash 3.2+) and standard Unix utilities (`sed`, `awk`, `grep`, `find`, `chmod`, `mkdir`, `cat`, `read`).
- **FR-002**: CLI MUST support all existing subcommands: `init`, `add`, `generate`, `update`, `validate`, and `--help`.
- **FR-003**: CLI MUST parse `tricycle.config.yml` files supporting the same YAML subset currently used: scalar values, nested objects, arrays of objects, booleans, and quoted strings.
- **FR-004**: CLI MUST produce output files (`tricycle.config.yml`, `CLAUDE.md`, `.claude/settings.json`, `.mcp.json`, `.gitignore`, `.tricycle.lock`) that are structurally identical to those produced by the current Node.js CLI.
- **FR-005**: CLI MUST generate valid JSON for `.claude/settings.json`, `.mcp.json`, and `.tricycle.lock` without relying on external JSON libraries.
- **FR-006**: CLI MUST compute SHA-256 checksums for the file-tracking lock mechanism, using `shasum -a 256` or `sha256sum` (whichever is available).
- **FR-007**: CLI MUST provide the same interactive wizard experience for `tricycle init` (prompts with defaults, numbered choice menus).
- **FR-008**: CLI MUST process template files from `generators/sections/` with the same variable substitution logic (e.g., `{{project.name}}`, `{{#each apps}}...{{/each}}`, `{{#if key}}...{{/if}}`).
- **FR-009**: CLI MUST install files from `core/`, `modules/`, and `presets/` directories into the target project using the same directory mapping as the current CLI.
- **FR-010**: CLI MUST maintain the `.tricycle.lock` file with the same JSON structure and checksum-based skip logic for locally modified files.
- **FR-011**: The Node.js `bin/tricycle.js` and `package.json` MUST be removed or replaced, so the project no longer requires npm to function.
- **FR-012**: CLI MUST be installable for persistent use by cloning the repo and adding `bin/` to `PATH` or symlinking the entry script — no package manager required.
- **FR-013**: CLI MUST support one-off execution via a single bash command (e.g., fetching and running from a remote source) without requiring a prior install step.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All five subcommands (`init`, `add`, `generate`, `update`, `validate`) complete successfully on a system with no Node.js runtime installed.
- **SC-002**: Generated output files (`CLAUDE.md`, `.claude/settings.json`, `.mcp.json`, `.tricycle.lock`, `tricycle.config.yml`) are structurally equivalent to those produced by the current Node.js CLI for the same input configuration.
- **SC-003**: The project has zero npm dependencies — no `package.json`, no `node_modules`, no `package-lock.json` required for CLI operation.
- **SC-004**: CLI runs on macOS (bash 3.2+) and Linux (bash 4.0+) without modification.
- **SC-005**: Interactive wizard completes full project initialization in under 60 seconds of user interaction time.

## Assumptions

- The YAML used in `tricycle.config.yml` is a constrained subset — no anchors, aliases, multi-line block scalars, or flow sequences beyond what the current configs use. The shell parser does not need to be a full YAML parser.
- The target platforms are macOS and Linux. Windows support (e.g., WSL or Git Bash) is not in scope for this feature.
- Standard Unix utilities (`sed`, `awk`, `grep`, `sha256sum`/`shasum`, `chmod`, `mkdir`, `cat`) are available on all target systems.
- The existing test suite (`tests/cli.test.js`) will be replaced with plain shell test scripts using `test` / `[` assertions and no external test framework. Test coverage scope (what is tested) should remain equivalent.
- Template files in `generators/sections/` retain their current Handlebars-like syntax — the shell CLI implements a compatible substitution engine, not a different template format.
