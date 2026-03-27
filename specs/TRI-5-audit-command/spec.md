# Feature Specification: Audit Command

May this specification, crafted with care and guided by Providence, serve as a faithful blueprint for the work ahead. We ask for clarity of purpose and wisdom in discerning the true needs of those we serve.

**Feature Branch**: `TRI-5-audit-command`
**Created**: 2026-03-27
**Status**: Draft
**Input**: User description: "add audit command that verifies given scope (files or feature) against constitution rules OR custom prompt AND OR common sense and produces output artifacts in docs/ or in linear if linear mcp and skill are present"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Audit Files Against Constitution (Priority: P1)

A user wants to verify that a set of files or a feature's artifacts comply with the project constitution. They run `/trc.audit` with a scope (file paths, glob patterns, or a feature branch name) and the command reads the constitution, examines the scoped files, and produces a structured audit report identifying violations, warnings, and passing checks. The report is saved to `docs/audits/`.

**Why this priority**: Constitution compliance is the primary use case. The constitution defines the project's principles and constraints — auditing against it is the most valuable and well-defined check.

**Independent Test**: Create a constitution with 3 rules, create files that violate one rule, run `/trc.audit` on those files, and verify the report identifies exactly the expected violation.

**Acceptance Scenarios**:

1. **Given** a populated constitution and a set of source files, **When** the user runs `/trc.audit src/`, **Then** a structured audit report is generated in `docs/audits/` listing each constitution rule with pass/fail status and evidence.
2. **Given** a populated constitution and a feature branch name, **When** the user runs `/trc.audit --feature TRI-3-skills-system`, **Then** the audit scopes to all files changed in that feature's spec directory and implementation, producing a report.
3. **Given** no constitution exists (placeholder only), **When** the user runs `/trc.audit`, **Then** the command outputs an error: "Constitution not populated. Run `/trc.constitution` first."

---

### User Story 2 - Audit with Custom Prompt (Priority: P2)

A user wants to audit files against a custom set of criteria instead of (or in addition to) the constitution. They provide a custom prompt describing what to check — for example, "verify all error messages are user-friendly" or "check that no files exceed 300 lines." The audit evaluates the scoped files against these custom criteria and produces a report.

**Why this priority**: Custom prompts extend the audit beyond constitution rules, making it a general-purpose quality gate. This flexibility is valuable but secondary to the core constitution audit.

**Independent Test**: Run `/trc.audit src/ --prompt "verify all functions have descriptive names"` and verify the report evaluates each file against that criterion.

**Acceptance Scenarios**:

1. **Given** a custom prompt and a file scope, **When** the user runs `/trc.audit src/ --prompt "check for hardcoded strings"`, **Then** the audit report evaluates files against the custom prompt and reports findings.
2. **Given** both a constitution and a custom prompt, **When** the user runs `/trc.audit src/ --prompt "no magic numbers"`, **Then** the report includes findings from BOTH the constitution rules AND the custom prompt, clearly separated.
3. **Given** no constitution and no custom prompt, **When** the user runs `/trc.audit src/`, **Then** the audit applies common-sense engineering best practices (naming, complexity, error handling, security basics) as a fallback.

---

### User Story 3 - Pluggable Output via Skills (Priority: P3)

After the audit produces findings, configured output skills are invoked to route findings to external systems. A `linear-audit` skill, when installed and configured on the audit step, reads the audit report and creates Linear issues for findings above a severity threshold. The audit command itself has no knowledge of Linear — it just produces the report and invokes whatever skills are wired to it.

**Why this priority**: Output routing is an enhancement. The core audit produces a local report (US1/US2). Skills extend where those findings go — Linear, Slack, GitHub Issues, or any future integration. The pattern is the same as code-reviewer being pluggable on the implement step.

**Independent Test**: Install the `linear-audit` skill, configure it on the audit step via `workflow.blocks.audit.skills: [linear-audit]`, run an audit that produces findings, and verify Linear issues are created.

**Acceptance Scenarios**:

1. **Given** the `linear-audit` skill is installed and configured on the audit step, **When** an audit produces findings, **Then** the skill reads the report from `docs/audits/` and creates Linear issues for findings at or above the configured severity threshold.
2. **Given** no output skills are configured on the audit step, **When** an audit completes, **Then** the report is saved to `docs/audits/` and no external actions are taken.
3. **Given** the `linear-audit` skill is configured but the Linear MCP server is unavailable, **Then** the skill warns "Linear MCP not available" and the report remains in `docs/audits/` only.

---

### Edge Cases

- What happens when the scoped files don't exist? The command reports "No files found matching scope" and exits cleanly.
- What happens when the constitution has no actionable rules (just a placeholder)? The command reports the constitution is not populated and suggests running `/trc.constitution`.
- What happens with very large scopes (hundreds of files)? The audit processes files in batches and reports progress, avoiding context window overflow.
- How are binary files handled? Binary files (images, compiled assets) are skipped with a note in the report.
- What happens when the audit is run on a feature that has no spec directory? The audit scopes to the feature branch's changed files via git diff against the base branch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a `/trc.audit` command that accepts a scope (file paths, glob patterns, or `--feature <branch-name>`).
- **FR-002**: System MUST read the project constitution from the configured path (`constitution.root` in `tricycle.config.yml`) and evaluate scoped files against each rule.
- **FR-003**: System MUST support a `--prompt` flag for custom audit criteria, evaluated alongside or instead of constitution rules.
- **FR-004**: System MUST apply common-sense engineering best practices as a fallback when neither constitution nor custom prompt is provided.
- **FR-005**: System MUST produce a structured audit report in `docs/audits/` with a timestamped filename (e.g., `audit-2026-03-27-TRI-5.md`).
- **FR-006**: Each audit finding MUST include: rule/criterion violated, severity (critical/warning/info), file and location, evidence (relevant code or text), and recommendation.
- **FR-007**: The audit command MUST support skill invocations at completion — output skills configured on the audit step are invoked after the report is written, following the same assembly pattern as other workflow steps.
- **FR-008**: System MUST skip binary files and report them as skipped in the audit output.
- **FR-009**: System MUST validate that the constitution is populated before auditing against it, and error clearly if it is only a placeholder.
- **FR-010**: A `linear-audit` skill MUST be provided that reads the audit report and creates Linear issues for findings, with graceful degradation when Linear MCP is unavailable.

### Key Entities

- **Audit Report**: A markdown document containing the audit scope, rules evaluated, findings (with severity, evidence, recommendations), and a summary of pass/fail counts. Stored in `docs/audits/`.
- **Audit Finding**: An individual violation or observation with severity (critical/warning/info), the rule it violates, the file and location, evidence, and a recommended fix.
- **Audit Scope**: The set of files to evaluate — specified as paths, globs, or derived from a feature branch's changed files.
- **Output Skill**: A pluggable skill configured on the audit step via `workflow.blocks.audit.skills` that routes audit findings to an external system. The `linear-audit` skill is the first implementation of this pattern.

## Success Criteria *(mandatory)*

With grateful hearts we present these measurable outcomes, trusting they will guide the implementation faithfully.

### Measurable Outcomes

- **SC-001**: Users can audit any set of files against the project constitution with a single command and receive a structured report within one invocation.
- **SC-002**: Users can provide custom audit criteria via a prompt and receive findings specific to those criteria.
- **SC-003**: Audit reports clearly identify violations with severity, evidence, and actionable recommendations — no ambiguous or unexplained findings.
- **SC-004**: Output skills can be plugged into the audit step via config, following the same pattern as skills on other workflow steps — no changes to the audit command itself are needed to add new output destinations.
- **SC-005**: The audit command works without any external dependencies — all output skills are optional and degrade gracefully.

## Assumptions

- The constitution, when populated, contains actionable rules that can be evaluated against source files (not just aspirational statements). Rules like "all functions must be under 50 lines" are auditable; "code should be beautiful" is not.
- The `/trc.audit` command is a Claude Code slash command (a command file in `.claude/commands/`), not a bash CLI command in `bin/tricycle`. It runs within the agent context.
- The "common sense" fallback uses standard engineering best practices: naming clarity, reasonable function length, error handling presence, no hardcoded secrets, no dead code, basic security hygiene.
- The `linear-audit` skill checks for Linear MCP availability at runtime and degrades gracefully. It is a separate skill file in `core/skills/linear-audit/`, not embedded in the audit command.
- Audit reports are append-only — running the audit again creates a new report file, it does not overwrite previous audits.
- The audit step can be added to the assembly system alongside specify/plan/tasks/implement, allowing skills to be configured on it via `workflow.blocks.audit.skills`.

## Scope Boundaries

### In Scope

- `/trc.audit` command as a Claude Code command file
- Constitution-based auditing
- Custom prompt-based auditing
- Common-sense fallback auditing
- Structured markdown report output to `docs/audits/`
- Skill invocation section in the audit command for pluggable output
- `linear-audit` skill that routes findings to Linear via MCP
- Feature-scoped auditing via `--feature` flag
- File and glob-based scoping

### Out of Scope

- Automated scheduling of audits (user triggers manually)
- Fix-it mode (auto-fixing violations — report only)
- Integration with CI/CD pipelines
- Audit against external standards (OWASP, SOC2, etc.) beyond what's in the constitution
- Historical audit comparison (diffing two audit reports)
- Audit of non-text artifacts (images, binaries beyond skipping them)
- Output skills for other systems (Slack, GitHub Issues, etc.) — only `linear-audit` is in scope; others follow the same pattern later
