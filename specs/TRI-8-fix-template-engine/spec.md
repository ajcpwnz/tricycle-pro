# Feature Specification: Fix Template Engine Awk Syntax Error

May this specification, guided by Providence, bring clarity to a persistent thorn in the toolkit's side.

**Feature Branch**: `TRI-8-fix-template-engine`
**Created**: 2026-03-28
**Status**: Draft
**Input**: User description: "do tri-8"
**Linear Issue**: [TRI-8](https://linear.app/d3feat/issue/TRI-8/generate-claude-md-awk-template-engine-syntax-error-command-unusable)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate CLAUDE.md Without Errors (Priority: P1)

A user runs `tricycle generate claude-md` on a project with a valid `tricycle.config.yml` and the command produces a well-formatted CLAUDE.md file with all template sections correctly rendered — no awk errors, no malformed output, no missing sections.

**Why this priority**: This is the entirety of the bug fix. The command is currently unusable — fixing the awk syntax error restores its core functionality.

**Independent Test**: Run `tricycle init --preset monorepo-turborepo` followed by `tricycle generate claude-md` and verify no errors on stderr and a well-formatted CLAUDE.md on disk.

**Acceptance Scenarios**:

1. **Given** a project initialized with the monorepo-turborepo preset, **When** the user runs `tricycle generate claude-md`, **Then** no awk syntax errors appear on stderr and the generated CLAUDE.md contains all sections defined in the templates.
2. **Given** a project initialized with the single-app preset, **When** the user runs `tricycle generate claude-md`, **Then** the output contains the project name, lint/test commands, and all configured sections with proper newlines.
3. **Given** a config with conditional sections (e.g., `push.require_tests: true` enables push gating, `qa.enabled: false` omits QA section), **When** the user runs `tricycle generate claude-md`, **Then** enabled sections appear and disabled sections are cleanly omitted — no leftover `{{#if}}` markers or empty blocks.

---

### User Story 2 - Template Engine Handles All Presets (Priority: P2)

The template engine correctly renders CLAUDE.md for every shipped preset (single-app, monorepo-turborepo, nextjs-prisma, express-prisma) without errors. Each preset exercises different template paths — multiple apps, optional sections, conditional blocks.

**Why this priority**: The fix must not just work for one preset. All presets must produce valid output to prevent regressions.

**Independent Test**: Loop through all presets, init each in a temp directory, generate CLAUDE.md, and verify no errors and non-empty output for each.

**Acceptance Scenarios**:

1. **Given** each available preset, **When** `tricycle generate claude-md` is run after init, **Then** every preset produces a valid CLAUDE.md with no errors.
2. **Given** a monorepo preset with multiple apps, **When** CLAUDE.md is generated, **Then** each app appears with its own lint/test commands and the `{{#each apps}}` loop renders correctly with proper newlines between entries.

---

### Edge Cases

- What happens when a config key referenced in a template doesn't exist? The template engine should substitute an empty string or use the configured fallback, not error.
- What happens when `{{#if key}}` blocks are nested? The current engine processes them iteratively (outermost first). This should continue to work.
- What happens when a template has `{{/if}}` on the same line as `{{#if}}`? Inline conditional removal should work without leaving artifacts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The template engine MUST NOT use awk built-in function names (`close`, `length`, `split`, `sub`, `gsub`, `index`, `match`, `printf`, `system`) as awk variable names.
- **FR-002**: `tricycle generate claude-md` MUST produce output with no errors on stderr for all shipped presets.
- **FR-003**: The generated CLAUDE.md MUST contain all sections defined in the template files with proper line breaks between sections and entries.
- **FR-004**: Conditional blocks (`{{#if key}}...{{/if}}`) MUST be cleanly removed when the key is falsy — no leftover markers, no blank lines from removed blocks beyond a single separator.
- **FR-005**: The `{{#each apps}}` loop MUST render each app entry with proper newline separation — no concatenation of entries onto the same line.

## Success Criteria *(mandatory)*

With grateful hearts we present these outcomes.

### Measurable Outcomes

- **SC-001**: `tricycle generate claude-md` completes without any errors on stderr for 100% of shipped presets.
- **SC-002**: Generated CLAUDE.md files contain all expected sections — the output for the monorepo-turborepo preset is at least 40 lines (vs the current ~60 lines of broken output that is mostly empty separators).
- **SC-003**: No `{{` or `}}` template markers remain in any generated CLAUDE.md output.
- **SC-004**: Existing tests continue to pass — no regressions in other commands.

## Assumptions

- The root cause is the use of `close` as an awk variable name in `process_if_blocks()`, which conflicts with awk's built-in `close()` function on macOS's nawk. Renaming the variable resolves the syntax error.
- There may be additional issues beyond the awk variable naming (e.g., newline handling in bash string concatenation within `render_template`). The fix should address all rendering issues, not just the awk error.
- The template files themselves (`generators/sections/*.md.tpl`) are correct — the bug is in the engine, not the templates.

## Scope Boundaries

### In Scope

- Fixing the awk syntax error in `bin/lib/template_engine.sh`
- Fixing any related rendering issues (newline concatenation, empty sections)
- Adding test coverage for `generate claude-md` across all presets
- Verifying all presets produce valid output

### Out of Scope

- Adding new template features (custom sections, new variables)
- Changing the template file format or structure
- Rewriting the template engine in a different language
- TRI-FEAT-1 (custom CLAUDE.md section injection) — that's a separate feature
