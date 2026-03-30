# Feature Specification: Stealth Mode

**Feature Branch**: `TRI-21-stealth-mode`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Stealth mode for repos where tricycle cannot check any files into source control. A config field used by assemble or similar so when it's on, full tricycle setup works in local dirs but nothing appears in commits."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Stealth Mode in a Repository (Priority: P1)

A user installs or configures tricycle in a repository where they have no authority to commit tooling files. They set a single configuration flag to activate stealth mode. From that point forward, all tricycle artifacts (commands, hooks, specs, templates, config) exist on disk for local use but are excluded from version control. The user can run the full tricycle workflow — specify, plan, tasks, implement — without any tricycle-related file appearing in `git status` or in any commit.

**Why this priority**: This is the core value proposition. Without this, the feature does not exist.

**Independent Test**: Enable stealth mode in a fresh repo, run the full workflow chain, and verify that `git status` shows zero tricycle-related untracked or modified files at every stage.

**Acceptance Scenarios**:

1. **Given** a repo with stealth mode enabled, **When** the user runs `tricycle init`, **Then** all tricycle files are created locally but none appear in `git status`.
2. **Given** stealth mode is active, **When** the user runs a full specify-plan-tasks-implement cycle, **Then** spec artifacts exist on disk in the expected directories but are excluded from commits.
3. **Given** stealth mode is active, **When** the user runs `git add -A && git status`, **Then** no tricycle-related files (`.claude/commands/`, `.claude/hooks/`, `.claude/skills/`, `specs/`, `.trc/`, `tricycle.config.yml`, `.tricycle.lock`) appear as staged.

---

### User Story 2 - Assemble Respects Stealth Mode (Priority: P1)

When stealth mode is active, the assemble process generates command files, hooks, and settings as usual, but ensures all generated paths are covered by gitignore rules. The user experience of running `/trc.specify` or any other workflow command is identical to normal mode — stealth is transparent to the workflow.

**Why this priority**: Assemble is the mechanism that places most tracked files. If it doesn't respect stealth, the feature is broken.

**Independent Test**: Run assemble with stealth mode on, then verify every file it created or modified is gitignored.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled, **When** `tricycle generate` or assemble runs, **Then** it adds gitignore rules that cover all tricycle-managed paths before writing any files.
2. **Given** stealth mode is enabled, **When** assemble creates `.claude/commands/*.md`, `.claude/hooks/*`, and `.claude/settings.json`, **Then** all of those paths are gitignored.
3. **Given** stealth mode is enabled, **When** the user already has a `.gitignore` with their own rules, **Then** stealth mode appends its rules without disturbing existing entries.

---

### User Story 3 - Switching Between Stealth and Normal Mode (Priority: P2)

A user who previously used stealth mode decides to commit tricycle files (or vice versa). They toggle the stealth flag off (or on) and re-run init/assemble. The system adjusts gitignore rules accordingly: removing stealth ignores when switching to normal, or adding them when switching to stealth.

**Why this priority**: Mode switching is an important lifecycle scenario but not needed for initial adoption.

**Independent Test**: Toggle stealth mode off in a previously stealth repo, re-run assemble, and verify that tricycle files now appear in `git status` as expected for normal mode.

**Acceptance Scenarios**:

1. **Given** stealth mode was active and is now disabled, **When** the user re-runs assemble, **Then** stealth-specific gitignore rules are removed and tricycle files become visible to git.
2. **Given** normal mode was active and stealth is now enabled, **When** the user re-runs assemble, **Then** stealth gitignore rules are added and all tricycle files disappear from `git status`.

---

### User Story 4 - Stealth Config Itself Is Not Committed (Priority: P2)

The stealth mode setting must be stored in a location that is itself not committed. If the only config file is `tricycle.config.yml` and that file is committed, then stealth mode is self-defeating. The system must support reading the stealth flag from a local-only source.

**Why this priority**: A bootstrapping concern — the config that enables stealth must also be stealthy.

**Independent Test**: Enable stealth mode, verify that the file containing the stealth setting is itself gitignored or stored outside the repo.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled, **When** the user checks `git status`, **Then** the file or mechanism that stores the stealth setting does not appear.
2. **Given** stealth mode is enabled, **When** tricycle reads config at startup, **Then** it can resolve the stealth flag from the local-only source without requiring any committed file.

---

### Edge Cases

- What happens when stealth mode is enabled but the user manually `git add`s a tricycle file? The system should not prevent this — stealth mode uses gitignore, not git hooks that block commits. The user retains full control.
- What happens when a team member clones the repo? They get no tricycle artifacts (that's the point). They must run `tricycle init` themselves with their own config.
- What happens if `.gitignore` is itself not committed? Stealth mode defaults to `.git/info/exclude` (truly local, never committed, maximum stealth). Users who prefer `.gitignore` can configure this via a stealth-specific setting. The default ensures zero trace in the repository.
- What happens when stealth mode is active during worktree creation? The worktree should inherit the stealth configuration and apply the same gitignore rules.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a configuration field that activates stealth mode for the entire tricycle installation in a repository.
- **FR-002**: When stealth mode is active, system MUST ensure all tricycle-managed file paths are excluded from version control via ignore rules, defaulting to `.git/info/exclude` (configurable to `.gitignore` if the user prefers).
- **FR-003**: The stealth mode setting itself MUST be stored in a location that is not committed to the repository.
- **FR-004**: Assemble MUST respect the stealth flag and adjust gitignore rules before writing any files when stealth mode is active.
- **FR-005**: All workflow commands (specify, plan, tasks, implement, clarify, analyze, etc.) MUST function identically in stealth mode — the flag affects only version-control visibility, not workflow behavior.
- **FR-006**: When stealth mode is toggled off, system MUST remove stealth-specific gitignore rules so tricycle files become visible to version control again.
- **FR-007**: System MUST NOT modify or remove user-authored gitignore rules when adding or removing stealth rules.
- **FR-008**: The gitignore rules applied in stealth mode MUST cover at minimum: `tricycle.config.yml`, `.tricycle.lock`, `.claude/` (all contents), `.trc/`, and `specs/`.

### Key Entities

- **Stealth Configuration**: The flag and its storage location — determines whether tricycle operates in stealth mode for a given repository.
- **Gitignore Rules**: The set of path patterns that stealth mode manages — added on enable, removed on disable, clearly demarcated from user rules.
- **Tricycle Artifacts**: All files tricycle creates or manages in a repository — commands, hooks, skills, specs, templates, config, lock file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete a full tricycle workflow (init through implement) in stealth mode with zero tricycle-related files appearing in any commit.
- **SC-002**: Toggling stealth mode on or off and re-running setup correctly adjusts gitignore rules in under 5 seconds.
- **SC-003**: Existing workflow commands require zero modifications to their invocation or behavior when stealth mode is active.
- **SC-004**: The stealth configuration can be resolved by tricycle without any file committed to the repository.

## Assumptions

- The user's repository uses git as its version control system (tricycle already requires git).
- `.git/info/exclude` is the default mechanism for excluding files in stealth mode (configurable to `.gitignore`). Stealth mode does not use pre-commit hooks or other enforcement mechanisms to block commits.
- Stealth mode is per-repository, not global — a user may want stealth in some repos and normal mode in others.
- The `tricycle.config.yml` file in a stealth repo exists on disk for tricycle to read but is gitignored. This is acceptable because the user chose stealth for this repo.
