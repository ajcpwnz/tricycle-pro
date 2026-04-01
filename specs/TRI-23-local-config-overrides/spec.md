# Feature Specification: Local Config Overrides

**Feature Branch**: `TRI-23-local-config-overrides`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Pluggable config that extends yml config with a subset of fields (optional file, can be as much as a single config option there), to have a config in repo but override it for some developers. Implication of assemble generating output that lives in repo and those outputs clashing for people with different overrides."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Developer creates a local config override (Priority: P1)

A developer working on a project wants to customize a small number of configuration options — such as enabling worktrees, changing push approval settings, or toggling QA enforcement — without modifying the shared `tricycle.config.yml` that the rest of the team relies on. They create a local override file containing just the fields they want to change, and tricycle automatically merges these overrides with the base config at runtime.

**Why this priority**: This is the core value proposition. Without it, every developer must either share identical configuration or manually edit and avoid committing changes to the shared config file.

**Independent Test**: Can be fully tested by creating an override file with a single changed field, running a tricycle command, and verifying the override takes effect.

**Acceptance Scenarios**:

1. **Given** a project with `tricycle.config.yml` and no local override file, **When** tricycle loads config, **Then** behavior is unchanged — only `tricycle.config.yml` is used.
2. **Given** a project with `tricycle.config.yml` and a local override file containing `qa: { enabled: true }`, **When** tricycle loads config, **Then** the QA block is enabled even though the base config has it disabled.
3. **Given** a local override file with a single field, **When** tricycle loads config, **Then** all other fields from `tricycle.config.yml` remain unchanged.
4. **Given** a local override file that is empty or contains no valid overrides, **When** tricycle loads config, **Then** behavior is identical to having no override file.

---

### User Story 2 - Override file stays out of version control (Priority: P1)

The local override file must never be committed to the repository. It is automatically excluded from version control so developers cannot accidentally push personal preferences to the shared repo.

**Why this priority**: If override files leak into version control, the entire point of per-developer configuration is defeated and it creates merge conflicts.

**Independent Test**: Can be tested by creating an override file and verifying it does not appear in `git status` as an untracked file.

**Acceptance Scenarios**:

1. **Given** a developer creates a local override file, **When** they run `git status`, **Then** the override file does not appear as untracked or modified.
2. **Given** a fresh project setup, **When** a developer runs `tricycle init` or the equivalent setup, **Then** the override file pattern is automatically excluded from version control.
3. **Given** a project using stealth mode (`.git/info/exclude`), **When** the override file is created, **Then** the exclusion works correctly with the stealth-mode VCS exclusion mechanism.

---

### User Story 3 - Assemble output does not clash between developers (Priority: P1)

When developers with different local overrides each run `assemble`, the generated command files that live in the repo must not diverge in ways that create merge conflicts. The system has a strategy for separating shared (committed) output from locally-influenced (developer-specific) output.

**Why this priority**: This is the critical design constraint the user explicitly called out. Without solving this, local overrides become a source of constant git conflicts on the team.

**Independent Test**: Can be tested by having two configurations (base + override A, base + override B), running assemble for each, and confirming the committed output is identical while local differences are isolated.

**Acceptance Scenarios**:

1. **Given** Developer A has `qa.enabled: true` in their override and Developer B has no override, **When** both run `assemble`, **Then** the files committed to the repo are identical for both developers.
2. **Given** a developer runs `assemble` with local overrides, **When** they commit and push, **Then** only shared assemble output is included in the commit — locally-influenced output is excluded from VCS.
3. **Given** a developer pulls changes that include updated assemble output from another developer, **When** they run `assemble` locally, **Then** their local overrides are re-applied without conflict.

---

### User Story 4 - Developer discovers which fields are overridable (Priority: P2)

A developer wants to know which configuration fields they can override locally. The system provides clear guidance on which fields are eligible for local override and which are team-shared-only.

**Why this priority**: Without discoverability, developers will try to override fields that don't work locally, leading to confusion and silent failures.

**Independent Test**: Can be tested by attempting to override a non-overridable field and verifying the system warns the user.

**Acceptance Scenarios**:

1. **Given** a developer creates an override with a field that is not overridable, **When** tricycle loads the config, **Then** a warning is displayed indicating the field cannot be overridden locally.
2. **Given** a developer wants to see overridable fields, **When** they consult documentation or run a help command, **Then** they see a clear list of which fields can be locally overridden.

---

### User Story 5 - Override file supports minimal content (Priority: P2)

A developer only needs to change a single option. The override file can be as small as a single key-value pair with no boilerplate or ceremony.

**Why this priority**: Low friction is essential for adoption. If developers need to recreate the full config structure just to change one flag, they will skip the feature.

**Independent Test**: Can be tested by creating an override file with just one line and verifying it works.

**Acceptance Scenarios**:

1. **Given** an override file containing only `worktree: { enabled: true }`, **When** tricycle loads config, **Then** worktree mode is enabled while all other settings come from the base config.
2. **Given** an override file with deeply nested partial content (e.g., only `push.require_approval: false`), **When** tricycle loads config, **Then** only that specific nested field is overridden — sibling fields at the same level remain unchanged.

---

### Edge Cases

- What happens when the base `tricycle.config.yml` is updated and a local override references a field that was removed or renamed? The overridden field is silently ignored if not recognized, and a warning is emitted.
- How does the system behave when the override file contains invalid YAML syntax? Tricycle reports a parse error with the override file name and line number, then falls back to base config only.
- What happens when the override file contains fields that are not part of the config schema? A warning is displayed listing unrecognized fields; they are ignored.
- How does the system handle conflicting array values (e.g., workflow block lists)? Arrays in the override replace the base array entirely — no append or merge semantics for arrays.
- What happens if the override file is present but unreadable (permissions issue)? Tricycle reports the permissions error and falls back to base config only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support an optional local override file that extends the base `tricycle.config.yml`.
- **FR-002**: The override file MUST use the same YAML format and field structure as `tricycle.config.yml`.
- **FR-003**: System MUST deep-merge override values over base config values, where override scalar fields take precedence over base scalar fields, objects are recursively merged, and arrays are replaced wholesale.
- **FR-004**: The override file MUST be automatically excluded from version control using the project's configured exclusion mechanism (`.gitignore` or stealth mode's `.git/info/exclude`).
- **FR-005**: System MUST load the base config first, then apply the override file on top, for every command that reads configuration.
- **FR-006**: System MUST handle the case where no override file exists — default behavior is unchanged with no errors or warnings.
- **FR-007**: System MUST use a two-pass assemble strategy: the first pass generates shared command files from the base config only (committed to VCS), and the second pass generates local overlay files from the merged config (gitignored). Tricycle reads both layers at runtime, with the local overlay taking precedence. This ensures committed output is always identical across developers regardless of local overrides.
- **FR-008**: System MUST warn when an override file contains fields that are not eligible for local override.
- **FR-009**: System MUST warn when the override file contains invalid YAML or unrecognized fields, and fall back to base config only.
- **FR-010**: For array-type fields in overrides, the system MUST replace the base array entirely (not append), to keep merge semantics simple and predictable.

### Key Entities

- **Override File**: A YAML file colocated with `tricycle.config.yml` that contains a subset of configuration fields. Always excluded from version control. Merged at load time with the base config.
- **Overridable Field Set**: The subset of configuration fields that are eligible for local override. Fields that affect shared assemble output must be handled carefully to avoid VCS conflicts.
- **Assemble Output Partition**: A two-layer system — the base layer contains shared command files produced from `tricycle.config.yml` only (committed to VCS), and the local overlay layer contains command file patches produced from the merged config (gitignored). At runtime, tricycle reads the base layer first, then applies the overlay if present.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can customize their local tricycle behavior by creating a single file with as few as one configuration field, with no changes to the shared repository config.
- **SC-002**: Two developers with different local overrides can both run all tricycle commands, commit, and push without encountering merge conflicts on generated files.
- **SC-003**: 100% of tricycle commands that read configuration correctly apply local overrides when the override file is present.
- **SC-004**: The override file is never included in git commits — verified by automated VCS exclusion with no manual developer action required.
- **SC-005**: Developers receive clear feedback when they attempt to override a field that is not eligible for local override.

## Assumptions

- The override file uses the same YAML format as `tricycle.config.yml` — no new syntax or format to learn.
- Deep merge uses "last writer wins" semantics: scalar values are replaced, objects are recursively merged, arrays are replaced wholesale.
- The override file is per-working-copy, not per-user globally — each clone or worktree can have its own.
- Fields that directly determine the content of committed assemble output (e.g., `workflow.chain`, `workflow.blocks`) are the primary concern for the assemble clash problem; runtime-only fields (e.g., `push.require_approval`, `qa.enabled`) are safe to override without affecting committed output.
- The existing `parse_yaml()` infrastructure can be extended to support loading and merging two YAML files.
