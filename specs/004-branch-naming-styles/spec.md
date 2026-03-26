# Feature Specification: Configurable Branch Naming Styles

**Feature Branch**: `004-branch-naming-styles`
**Created**: 2026-03-26
**Status**: Draft
**Input**: User description: "modify setup (feature-setup) block and maybe configs to allow different feature branch numbering styles. feature-name (default) should come up with a short slug from description. issue number should infer issue number like TRI-001 from task management system in user prompt, and ask for it if theres none, resuming when user enters it. finally, ordered should work like now, with looking at specs number"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Feature-Name Branch Style (Priority: P1)

A project maintainer sets `branch_style: feature-name` in `tricycle.config.yml`. When they run `/trc.specify Add dark mode toggle`, the system generates a branch named `dark-mode-toggle` — a short slug derived from the description, with no numeric prefix. This is the default style for new projects that don't need sequential numbering.

**Why this priority**: This is the simplest and most universally useful style. Most small projects and solo developers want descriptive branch names without overhead. Making it the default provides immediate value.

**Independent Test**: Set `branch_style: feature-name` in config, run `/trc.specify` with a feature description, verify the branch name is a short slug with no numeric prefix and the spec directory matches.

**Acceptance Scenarios**:

1. **Given** a project with `branch_style: feature-name` in config, **When** the user runs `/trc.specify Add dark mode toggle`, **Then** the branch is named `dark-mode-toggle` and the spec directory is `specs/dark-mode-toggle/`.
2. **Given** a project with no `branch_style` configured, **When** the user runs `/trc.specify`, **Then** the system uses `feature-name` as the default style.
3. **Given** a description with stop words and noise like "I want to add user authentication for the API", **When** the branch name is generated, **Then** it produces a concise slug like `user-auth-api` (not `i-want-add-user-authentication-for-api`).
4. **Given** a branch name that already exists, **When** the user runs `/trc.specify`, **Then** the system exits with an error telling the user to choose a different name or use `--short-name`.

---

### User Story 2 - Issue-Number Branch Style (Priority: P2)

A team using a task management system (Linear, Jira, GitHub Issues, etc.) sets `branch_style: issue-number` and configures a `branch_prefix` like `TRI`. When they run `/trc.specify TRI-042 Add export to CSV`, the system extracts `TRI-042` from the prompt and names the branch `TRI-042-export-csv`. If the user doesn't include an issue number, the agent asks for one before proceeding.

**Why this priority**: Teams with issue trackers need branch names tied to tickets for traceability. This is the second most common pattern and enables integration with external systems.

**Independent Test**: Set `branch_style: issue-number` with `branch_prefix: TRI`, run `/trc.specify TRI-042 Add export to CSV`, verify branch is `TRI-042-export-csv`. Then run without an issue number and verify the agent asks for one.

**Acceptance Scenarios**:

1. **Given** `branch_style: issue-number` and `branch_prefix: TRI`, **When** the user runs `/trc.specify TRI-042 Add export to CSV`, **Then** the system extracts `TRI-042`, names the branch `TRI-042-export-csv`, and creates spec directory `specs/TRI-042-export-csv/`.
2. **Given** `branch_style: issue-number` and `branch_prefix: TRI`, **When** the user runs `/trc.specify Add export to CSV` (no issue number), **Then** the agent pauses and asks: "What is the issue number? (e.g., TRI-042)". When the user responds `TRI-042`, the agent resumes with branch name `TRI-042-export-csv`.
3. **Given** `branch_style: issue-number` with no `branch_prefix` configured, **When** the system looks for an issue number, **Then** it accepts any pattern matching common formats: `PROJ-123`, `#123`, `GH-123`.
4. **Given** a prompt containing multiple potential issue numbers like `TRI-042 and TRI-043`, **When** the branch is created, **Then** only the first match is used for the branch name.

---

### User Story 3 - Ordered Branch Style (Priority: P3)

A project maintainer sets `branch_style: ordered`. This preserves the current behavior: the system scans existing spec directories and git branches for the highest `###-` prefix number, increments it, and names the branch `004-feature-slug`. This is useful for projects that value a sequential feature history.

**Why this priority**: This is the existing behavior being preserved. It works well for projects that want a linear feature timeline but is not the most common need across all project types.

**Independent Test**: Set `branch_style: ordered`, run `/trc.specify` with existing specs `001-*`, `002-*`, `003-*` present, verify the branch is `004-feature-slug`.

**Acceptance Scenarios**:

1. **Given** `branch_style: ordered` and existing specs `001-foo/`, `002-bar/`, `003-baz/`, **When** the user runs `/trc.specify Add notifications`, **Then** the branch is named `004-notifications` and spec directory is `specs/004-notifications/`.
2. **Given** `branch_style: ordered` and a remote branch `005-archived-feature` that has no local spec, **When** the system detects it, **Then** the next number is `006` (respects both branch and spec numbering).
3. **Given** `branch_style: ordered`, **When** the `--number` flag is passed to the script, **Then** the manually specified number overrides auto-detection (existing behavior preserved).

---

### Edge Cases

- What happens when the generated slug is empty (description contains only stop words)? The system falls back to a generic name like `feature-<short-hash>`.
- What happens when the issue number format doesn't match the configured prefix? The system warns the user and asks them to provide the correct format.
- What happens when two users create branches with the same feature-name slug simultaneously? The second user gets an error that the branch already exists and should use `--short-name` to provide an alternative.
- What happens when switching `branch_style` mid-project? Existing branches and specs are unaffected. The new style only applies to newly created features.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support three branch naming styles: `feature-name`, `issue-number`, and `ordered`.
- **FR-002**: The `feature-name` style MUST be the default when no `branch_style` is configured.
- **FR-003**: The `feature-name` style MUST generate a concise 2-4 word slug from the description, filtering stop words and noise.
- **FR-004**: The `feature-name` style MUST NOT include a numeric prefix.
- **FR-005**: The `issue-number` style MUST extract issue identifiers from the user's prompt using the configured `branch_prefix` pattern (e.g., `TRI-###`).
- **FR-006**: The `issue-number` style MUST prompt the user for an issue number when none is found in the description, and resume the workflow after receiving it.
- **FR-007**: The `ordered` style MUST preserve the current behavior: auto-detect the next sequential number by scanning specs directories and git branches.
- **FR-008**: The `branch_style` and `branch_prefix` settings MUST be configurable in `tricycle.config.yml`.
- **FR-009**: The `create-new-feature.sh` script MUST accept a `--style` flag to override the configured style for a single invocation.
- **FR-010**: The `feature-setup` block MUST read the configured `branch_style` and pass the appropriate flags to `create-new-feature.sh`.
- **FR-011**: The spec directory name MUST match the branch name for all styles.

### Key Entities

- **Branch Style Config**: A setting in `tricycle.config.yml` under a `branching` section containing `style` (`feature-name` | `issue-number` | `ordered`) and optional `prefix` (string for issue-number style).
- **Issue Identifier**: A string matching the pattern `<PREFIX>-<NUMBER>` extracted from the user's feature description or provided interactively.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create feature branches in all three naming styles without manual branch creation or renaming.
- **SC-002**: Switching between styles requires changing only one line in `tricycle.config.yml` — no other files need modification.
- **SC-003**: Existing projects using ordered numbering experience zero behavior change when upgrading (backward compatibility).
- **SC-004**: The issue-number style successfully extracts identifiers from natural language prompts when the prefix is configured and present in the prompt.

## Assumptions

- The `branch_prefix` for issue-number style follows the common pattern of uppercase letters (e.g., `TRI`, `JIRA`, `GH`). The system will match `<PREFIX>-<DIGITS>` case-insensitively.
- The spec directory naming always mirrors the branch name (no separate spec directory naming config).
- The `--short-name` flag to `create-new-feature.sh` continues to work as an override regardless of configured style.
- For `feature-name` style, the existing `generate_branch_name()` function in `create-new-feature.sh` provides the slug generation logic (already handles stop words, length limits, etc.).
