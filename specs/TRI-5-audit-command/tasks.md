# Tasks: Audit Command

By the grace of God, we set forth the following tasks — each a small act of stewardship toward the completion of this good work.

**Input**: Design documents from `specs/TRI-5-audit-command/`
**Prerequisites**: plan.md, spec.md, research.md

**Tests**: Included — project has existing test suite.

**Organization**: Tasks grouped by user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

- [x] T001 Create docs/audits/.gitkeep — empty directory placeholder so git tracks the audit output directory

---

## Phase 2: Foundational

_(No foundational tasks — the audit command is self-contained)_

---

## Phase 3: User Story 1 - Audit Files Against Constitution (Priority: P1) MVP

**Goal**: `/trc.audit` command that evaluates scoped files against the project constitution and produces a structured report in `docs/audits/`.

**Independent Test**: Run `/trc.audit bin/` on a project with a populated constitution and verify a report is generated.

### Implementation for User Story 1

- [x] T002 [US1] Create core/commands/trc.audit.md — standalone command file with YAML frontmatter (description), User Input section with $ARGUMENTS, and execution flow: (1) parse scope from arguments (file paths, globs, or --feature flag), (2) read constitution from configured path, validate it's populated (not placeholder), (3) resolve scope to file list (skip binaries), (4) evaluate each file against each constitution rule, (5) generate structured markdown report in docs/audits/ with timestamped filename, findings grouped by source with severity/file/evidence/recommendation, (6) read workflow.blocks.audit.skills from tricycle.config.yml at runtime and invoke each configured skill if installed

**Checkpoint**: `/trc.audit bin/` produces a report in `docs/audits/`. Core audit works.

---

## Phase 4: User Story 2 - Audit with Custom Prompt (Priority: P2)

**Goal**: Support `--prompt` flag for custom audit criteria alongside or instead of constitution rules.

**Independent Test**: Run `/trc.audit src/ --prompt "check for hardcoded strings"` and verify findings specific to that criterion appear in the report.

### Implementation for User Story 2

- [x] T003 [US2] Update core/commands/trc.audit.md — add --prompt flag handling: (1) parse --prompt from arguments, (2) when present, evaluate scoped files against the custom prompt criteria in addition to constitution rules, (3) when no constitution AND no prompt, fall back to common-sense engineering best practices (naming, complexity, error handling, security basics), (4) group findings by source (Constitution / Custom Prompt / Common Sense) in the report

**Checkpoint**: Custom prompt findings appear in separate section of audit report. Common-sense fallback works when no constitution or prompt provided.

---

## Phase 5: User Story 3 - Pluggable Output via Skills (Priority: P3)

**Goal**: `linear-audit` skill that reads audit reports and creates Linear issues for findings.

**Independent Test**: Install `linear-audit` skill, configure it on the audit step, run an audit, verify it attempts to create Linear issues (or gracefully warns if MCP unavailable).

### Implementation for User Story 3

- [x] T004 [P] [US3] Create core/skills/linear-audit/SKILL.md — skill with frontmatter (name: linear-audit, description) and instructions: (1) read the most recent audit report from docs/audits/, (2) parse findings with severity critical or warning, (3) for each finding create a Linear issue in the project's configured team with title, description containing evidence and recommendation, and label "audit", (4) if Linear MCP is unavailable output warning and skip, (5) report count of issues created
- [x] T005 [P] [US3] Create core/skills/linear-audit/README.md — skill documentation with usage, config example (workflow.blocks.audit.skills: [linear-audit]), requirements (Linear MCP server)
- [x] T006 [US3] Create core/skills/linear-audit/SOURCE — origin vendored:core/skills/linear-audit with current commit hash

**Checkpoint**: `linear-audit` skill exists and can be invoked. When Linear MCP is available, it creates issues from audit findings.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T007 [P] Add audit command test to tests/run-tests.sh — verify core/commands/trc.audit.md exists, has valid frontmatter with description field, contains constitution loading instructions, contains report generation instructions
- [x] T008 [P] Add linear-audit skill test to tests/run-tests.sh — verify core/skills/linear-audit/SKILL.md exists with name: linear-audit frontmatter, SOURCE file present
- [x] T009 Bump version from 0.7.0 to 0.8.0 in VERSION file
- [x] T010 Run full test suite and fix any failures

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **US1 (Phase 3)**: Depends on Setup (T001 creates output directory)
- **US2 (Phase 4)**: Depends on US1 (extends the same command file)
- **US3 (Phase 5)**: No dependency on US1/US2 — separate skill files. Can run in parallel.
- **Polish (Phase 6)**: Depends on all user stories complete

### Parallel Opportunities

- T004, T005 — linear-audit skill files (different files)
- T007, T008 — test additions (different test groups)
- US3 can run in parallel with US1/US2 (separate directories)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 (setup) + T002 (audit command)
2. **STOP and VALIDATE**: `/trc.audit bin/` produces a report
3. This alone delivers constitution auditing

### Incremental Delivery

1. Setup + US1 → Constitution audit works (MVP)
2. US2 → Custom prompt and common-sense fallback
3. US3 → Linear output skill
4. Polish → Tests, version bump

---

## Notes

- The audit command is a standalone markdown file (not assembled from blocks)
- Skill invocation is runtime — reads config dynamically, no assembly needed
- Report format must be parseable by output skills (structured headings, consistent finding format)
- The command file is a prompt template — all "logic" is instructions the AI agent follows
