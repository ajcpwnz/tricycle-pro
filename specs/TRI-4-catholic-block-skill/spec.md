# Feature Specification: Catholic Block & Skill

**Feature Branch**: `TRI-4-catholic-block-skill`
**Created**: 2026-03-27
**Status**: Draft
**Input**: User description: "add catholic block and catholic skill. skill should apply proper good christian verbiage to all artifacts except code. block should plug early in specify and pray for successful implementation. update readme when done, etc"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Catholic Skill Applies Christian Verbiage to Artifacts (Priority: P1)

A user runs the tricycle workflow and the catholic skill is active. All generated artifacts (specs, plans, task lists, README updates) are written with reverent, faith-inspired language — blessings in introductions, grateful acknowledgments in completions, scriptural encouragement in descriptions. Code files remain untouched — no religious language in source code, tests, or configuration.

**Why this priority**: The skill is the core deliverable. Without the catholic skill providing the verbiage transformation, the block has nothing to invoke. The skill defines WHAT the language looks like; the block defines WHEN it triggers.

**Independent Test**: Configure the catholic skill as active, run `/trc.specify` on a test feature, and verify the generated spec.md contains faith-inspired language (blessings, references to Providence, grateful tone) while any code files remain secular.

**Acceptance Scenarios**:

1. **Given** the catholic skill is installed in `.claude/skills/catholic/`, **When** Claude generates a spec, plan, or tasks artifact, **Then** the artifact contains reverent Christian verbiage (opening blessings, grateful tone, references to divine guidance) while remaining functionally complete.
2. **Given** the catholic skill is active, **When** Claude writes or modifies source code, test files, or configuration files, **Then** the code contains no religious language — only standard technical comments and naming.
3. **Given** the catholic skill is installed and the user invokes `/catholic`, **Then** Claude applies Christian verbiage to the current artifact or conversation context.

---

### User Story 2 - Catholic Block Prays Early in Specify (Priority: P2)

A user runs `/trc.specify` and the catholic block fires early in the specify step. It inserts a brief prayer for the success of the feature being specified — asking for divine guidance in understanding requirements, clarity of purpose, and a fruitful implementation. This prayer appears in the conversation output (not baked into the spec file itself).

**Why this priority**: The block is the integration mechanism. It plugs the skill into the workflow chain at the right moment. Without it, the skill exists but only triggers on manual `/catholic` invocation.

**Independent Test**: Enable the catholic block on the specify step, run `/trc.specify`, and verify the output includes a prayer before the spec generation begins.

**Acceptance Scenarios**:

1. **Given** the catholic block is enabled for the specify step, **When** the user runs `/trc.specify`, **Then** a brief prayer for the feature's success appears in the conversation output before spec writing begins.
2. **Given** the catholic block is enabled, **When** the specify step completes, **Then** a closing blessing or thanksgiving appears acknowledging the completed specification.
3. **Given** the catholic block is NOT enabled, **When** the user runs `/trc.specify`, **Then** no prayer or religious language appears in the workflow output.

---

### User Story 3 - README Documents the Catholic Block and Skill (Priority: P3)

The project README is updated to document the catholic block and skill — what they do, how to enable/disable them, and example configuration.

**Why this priority**: Documentation is important but does not block functionality. The block and skill work independently of whether the README mentions them.

**Independent Test**: Read the README and verify it contains a section describing the catholic block and skill with enable/disable instructions.

**Acceptance Scenarios**:

1. **Given** the catholic block and skill are implemented, **When** a user reads the README, **Then** they find a section explaining what the catholic block and skill do, how to configure them, and how to disable them.

---

### Edge Cases

- What happens if the catholic skill is installed but the block is not enabled? The skill is available as a manual `/catholic` slash command but does not auto-trigger during workflow steps.
- What happens if the block is enabled but the skill is not installed? The block's skill invocation checks for `.claude/skills/catholic/SKILL.md` and skips gracefully if absent.
- What happens with non-English projects? The skill applies English-language Christian verbiage. Non-English projects would need a localized skill variant (out of scope).
- How does the skill handle existing artifacts that already have content? The skill guides tone for NEW content generation, not retroactive editing of existing files.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A `catholic` skill MUST exist in `core/skills/catholic/` with a SKILL.md containing instructions for applying Christian verbiage to non-code artifacts.
- **FR-002**: The catholic skill MUST instruct the agent to use reverent, faith-inspired language in specs, plans, task documents, and README files.
- **FR-003**: The catholic skill MUST explicitly instruct the agent to NOT apply religious language to source code, test files, configuration files, or any executable content.
- **FR-004**: A `catholic` block MUST exist in `core/blocks/specify/` that fires early in the specify step (low order number).
- **FR-005**: The catholic block MUST output a brief prayer for the feature's success at the beginning of the specify workflow.
- **FR-006**: The catholic block MUST output a closing blessing or thanksgiving when the specify step completes.
- **FR-007**: The catholic block MUST be optional (not required, not default-enabled) so users opt in via config.
- **FR-008**: The README MUST be updated with a section documenting the catholic block and skill, including configuration examples.

### Key Entities

- **Catholic Skill**: A SKILL.md file with YAML frontmatter (`name: catholic`) and markdown body instructing the agent on proper Christian verbiage for artifacts. Installed to `.claude/skills/catholic/`.
- **Catholic Block**: A markdown block file with frontmatter (`name: catholic`, `step: specify`, `required: false`, `default_enabled: false`, low `order` value) containing the prayer and blessing instructions. Located in `core/blocks/optional/specify/` or `core/blocks/specify/`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All non-code artifacts generated during the workflow contain at least one instance of faith-inspired language (blessing, prayer, reference to Providence) when the catholic skill is active.
- **SC-002**: Zero instances of religious language appear in generated source code, test files, or configuration files regardless of skill activation.
- **SC-003**: The specify workflow outputs a prayer at the start and a blessing at the end when the catholic block is enabled.
- **SC-004**: Users can enable the catholic block with a single config change (`workflow.blocks.specify.enable: [catholic]`) and no other modifications.

## Assumptions

- The Christian verbiage is broadly ecumenical Catholic — respectful, reverent, non-denominationally divisive. Think blessings, gratitude, references to Providence and divine guidance, not doctrinal statements.
- The skill applies to artifact CONTENT (text in markdown files), not to file names, branch names, or directory structures.
- The prayer in the block is brief (2-4 sentences) — not a full liturgical passage.
- The skill and block are independent: the skill can be used without the block (manual invocation), and the block references the skill but degrades gracefully without it.

## Scope Boundaries

### In Scope

- Catholic skill with SKILL.md in `core/skills/catholic/`
- Catholic block in `core/blocks/` for the specify step
- README update documenting both
- SOURCE file for the vendored skill
- Configurable via standard `workflow.blocks.specify.enable` and `workflow.blocks.specify.skills` mechanisms

### Out of Scope

- Localization to non-English languages
- Other religious traditions (Orthodox, Protestant, etc.)
- Retroactive editing of existing artifacts
- Religious language in code, tests, or config files
- Integration with steps other than specify (user can add more steps via config if desired)
