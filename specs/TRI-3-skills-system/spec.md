# Feature Specification: Skills System

**Feature Branch**: `TRI-3-skills-system`
**Created**: 2026-03-27
**Status**: Draft
**Input**: User description: "do tr-3"
**Linear Issue**: [TRI-3](https://linear.app/d3feat/issue/TRI-3/skills-system-vendor-defaults-from-official-repos-install-external)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Default Skills Available After Init (Priority: P1)

A user runs `tricycle init` on a new project and receives a curated set of default skills (code-reviewer, tdd, debugging, document-writer, monorepo-structure) pre-installed in `.claude/skills/`. They can immediately use these skills via slash commands or benefit from background skills without any additional configuration.

**Why this priority**: This is the foundational capability. Without vendored defaults, users must manually discover and install skills. Shipping sensible defaults delivers immediate value and establishes the skills ecosystem pattern.

**Independent Test**: Run `tricycle init` in a fresh project and verify that all default skills are present in `.claude/skills/` with correct `SKILL.md` files and `SOURCE` metadata files.

**Acceptance Scenarios**:

1. **Given** a new project with no `.claude/skills/` directory, **When** the user runs `tricycle init`, **Then** all vendored default skills are copied to `.claude/skills/` with their full directory structure (SKILL.md, README.md, Templates/, Examples/ as applicable).
2. **Given** a project that already has `.claude/skills/` with user-modified skills, **When** the user runs `tricycle init`, **Then** existing user-modified skills are preserved (not overwritten) and only missing default skills are added.
3. **Given** a vendored skill in `core/skills/`, **When** it is copied to `.claude/skills/`, **Then** a `SOURCE` file is present noting the origin repository and commit hash.

---

### User Story 2 - Disable Unwanted Default Skills (Priority: P2)

A user who doesn't need certain default skills (e.g., TDD workflow, document generation) adds them to a `skills.disable` list in `tricycle.config.yml`. On subsequent `tricycle init` or `tricycle update` runs, those skills are skipped and not installed.

**Why this priority**: Users have different workflows. Forcing all defaults on every project creates noise. Disabling unwanted skills keeps the `.claude/skills/` directory lean and relevant.

**Independent Test**: Add `skills.disable: [tdd, document-writer]` to config, run `tricycle init`, and verify those skills are absent from `.claude/skills/` while others are present.

**Acceptance Scenarios**:

1. **Given** `skills.disable` lists `tdd` and `document-writer` in `tricycle.config.yml`, **When** the user runs `tricycle init`, **Then** those skills are not copied to `.claude/skills/` while all other defaults are installed.
2. **Given** a previously installed skill that is now listed in `skills.disable`, **When** the user runs `tricycle update`, **Then** the skill is not removed (only future installs are prevented) and the user is informed it still exists.

---

### User Story 3 - Install External Skills from Config (Priority: P2)

A user wants a community or custom skill not included in the defaults. They add an entry to `skills.install` in `tricycle.config.yml` specifying a GitHub source or local path. Running `tricycle init` or `tricycle update` fetches and installs that skill alongside the defaults.

**Why this priority**: The external install mechanism is what makes the skills system extensible beyond Tricycle's curated defaults. It enables community participation and custom team skills.

**Independent Test**: Add a `skills.install` entry pointing to a GitHub skill repo, run `tricycle update`, and verify the skill appears in `.claude/skills/` with correct content.

**Acceptance Scenarios**:

1. **Given** `skills.install` contains `source: github:anthropics/skills/some-new-skill`, **When** the user runs `tricycle update`, **Then** the skill is fetched from the GitHub repository and installed to `.claude/skills/some-new-skill/`.
2. **Given** `skills.install` contains `source: local:.trc/skills/my-custom-skill`, **When** the user runs `tricycle update`, **Then** the skill is copied from the local path to `.claude/skills/my-custom-skill/`.
3. **Given** an externally installed skill that the user has manually modified, **When** the user runs `tricycle update`, **Then** the modified skill is not overwritten and the user is informed of the conflict.

---

### User Story 4 - List Installed Skills (Priority: P3)

A user wants to see what skills are currently installed, where each came from, and whether any have been modified. They run `tricycle skills list` and receive a clear summary.

**Why this priority**: Visibility into installed skills is important for managing the skills ecosystem, but it's a read-only informational command that doesn't block other functionality.

**Independent Test**: Install a mix of default, external, and local skills, run `tricycle skills list`, and verify the output correctly shows each skill's name, source, and status.

**Acceptance Scenarios**:

1. **Given** a project with vendored, external, and local skills installed, **When** the user runs `tricycle skills list`, **Then** each skill is listed with its name, source type (vendored/external/local), and modification status.
2. **Given** a project with no skills installed, **When** the user runs `tricycle skills list`, **Then** the output indicates no skills are installed and suggests running `tricycle init`.

---

### User Story 5 - Block Integration with Skills (Priority: P3)

A workflow block references an installed skill (e.g., invoking `/code-review` before push approval). If the skill is installed, it is invoked at the appropriate point. If the skill is not installed, the block gracefully skips the reference and continues.

**Why this priority**: Block-skill integration enhances the workflow but is an optional enhancement. The core skills system (install, disable, list) must work independently of block integration.

**Independent Test**: Create a block that references an installed skill and verify it invokes correctly; then remove the skill and verify the block completes without error.

**Acceptance Scenarios**:

1. **Given** a block that references `/code-review` and the `code-review` skill is installed, **When** the block executes, **Then** the skill is invoked at the specified point in the block's workflow.
2. **Given** a block that references `/code-review` and the skill is not installed, **When** the block executes, **Then** the block skips the skill invocation and continues to the next step without error.

---

### Edge Cases

- What happens when a GitHub source URL is unreachable during `tricycle update`? The system reports the error for that specific skill and continues installing others.
- What happens when two skills have the same name (e.g., a vendored default and an external install)? External installs take precedence, with a warning to the user.
- What happens when a `SOURCE` file is missing from a skill in `.claude/skills/`? The skill is treated as user-created/local with no update tracking.
- How does the system handle skill directory names with invalid characters? Skill names are validated as lowercase alphanumeric with hyphens only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST vendor default skills (code-reviewer, tdd, debugging, document-writer, monorepo-structure) in `core/skills/` so they ship with the project.
- **FR-002**: System MUST copy vendored skills to `.claude/skills/` during `tricycle init`, preserving full directory structure (SKILL.md, README.md, Templates/, Examples/).
- **FR-003**: Each vendored skill MUST include a `SOURCE` file noting the origin repository URL and commit hash.
- **FR-004**: System MUST support a `skills.disable` configuration in `tricycle.config.yml` that prevents listed skills from being installed during `init` or `update`.
- **FR-005**: System MUST support a `skills.install` configuration in `tricycle.config.yml` with entries specifying `source` as either `github:<owner>/<repo>/<skill-path>` or `local:<path>`.
- **FR-006**: System MUST fetch and install external skills from GitHub sources during `tricycle init` and `tricycle update`.
- **FR-007**: System MUST copy skills from local paths during `tricycle init` and `tricycle update` when `source: local:<path>` is specified.
- **FR-008**: System MUST NOT overwrite user-modified skills during `tricycle update` — modification detection MUST use checksums.
- **FR-009**: System MUST provide a `tricycle skills list` command that displays installed skills with name, source type, and modification status.
- **FR-010**: Workflow blocks MUST be able to reference installed skills by name, with graceful degradation (skip without error) when the referenced skill is not installed.
- **FR-011**: System MUST validate skill directory names (lowercase alphanumeric with hyphens only).
- **FR-012**: System MUST continue processing remaining skills if one external source fails to fetch, reporting the error clearly.

### Key Entities

- **Skill**: A self-contained unit of knowledge or capability consisting of a SKILL.md file (with YAML frontmatter and markdown body) and optional supporting files (README.md, Templates/, Examples/). Identified by its directory name.
- **SOURCE metadata**: A file within each vendored or externally-installed skill that records the origin repository URL, commit hash, and install timestamp. Used for update tracking and modification detection.
- **Skills configuration**: The `skills` section of `tricycle.config.yml` containing `install` (list of external sources) and `disable` (list of skill names to exclude).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can access all default skills immediately after running `tricycle init` without any additional configuration or manual steps.
- **SC-002**: Users can install an external skill from a GitHub repository by adding a single line to their configuration file and running `tricycle update`.
- **SC-003**: Users can prevent specific default skills from being installed by listing them in their configuration, with changes taking effect on the next `init` or `update`.
- **SC-004**: Users can view a complete inventory of installed skills, their sources, and modification status with a single command.
- **SC-005**: User-modified skills are never lost during updates — the system detects modifications and preserves them.
- **SC-006**: Workflow blocks that reference missing skills complete successfully without user intervention.
- **SC-007**: A single failed external skill fetch does not prevent other skills from being installed.

## Assumptions

- The `anthropics/skills` repository is publicly accessible and contains skills in a directory structure compatible with Tricycle's `core/skills/` format (SKILL.md at root of each skill directory).
- GitHub skill sources can be fetched via git sparse checkout or direct HTTP download of individual directories — full repository cloning is not required.
- Skill names are globally unique within a project. Name collisions between vendored and external skills are resolved by external taking precedence.
- The existing `monorepo-structure` skill format (SKILL.md + README.md + Templates/ + Examples/) is the canonical skill directory structure.
- Checksum-based modification detection compares the installed skill against the vendored/source version, not against a previously recorded hash.

## Scope Boundaries

### In Scope

- Vendoring default skills from official repositories into `core/skills/`
- Config-driven skill installation from GitHub and local sources
- Config-driven skill disabling
- `tricycle skills list` command
- Modification-safe updates (checksum protection)
- Block-skill integration with graceful degradation
- SOURCE metadata tracking

### Out of Scope

- Skill marketplace or registry service
- Skill versioning or pinning to specific versions
- Automatic skill updates (pull latest) — updates are manual via `tricycle update`
- Skill dependency management (skill A requires skill B)
- Skill authoring tooling (`tricycle skills create`)
- Per-app skills in monorepo configurations (all skills are project-wide)
- Authentication for private GitHub repositories
