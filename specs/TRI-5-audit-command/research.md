# Research: TRI-5 Audit Command

**Date**: 2026-03-27
**Branch**: TRI-5-audit-command

## Decision 1: Command Type — Standalone vs Assembled

**Decision**: Standalone command file at `core/commands/trc.audit.md`, NOT assembled from blocks.

**Rationale**:
- The audit command is not part of the workflow chain (specify→plan→tasks→implement)
- Existing non-chain commands (trc.analyze, trc.checklist, trc.clarify, trc.constitution) are all standalone files
- The assembly system only processes chain steps — extending it for a one-off command is overkill
- Skills are invoked at runtime by reading config, not baked in at assembly time

**Alternatives considered**:
- Add "audit" as a chain step: Too heavy — the chain is a sequential pipeline, audit is an ad-hoc utility
- Assemble from blocks: No benefit — the audit command is a single coherent prompt, not composable blocks

## Decision 2: Skill Invocation — Runtime vs Assembly-Time

**Decision**: The audit command reads `workflow.blocks.audit.skills` from `tricycle.config.yml` at runtime and invokes each configured skill after producing the report.

**Rationale**:
- Standalone commands can't use the assembly skill injection (that's only for chain steps)
- Runtime reading is actually MORE flexible — users change config without re-assembling
- The pattern is simple: "read config, for each skill, check if installed, invoke it"
- Same config path convention as chain steps: `workflow.blocks.<step>.skills`

**Alternatives considered**:
- Hardcode linear-audit invocation: Not pluggable — violates the spec's requirement for pluggable output
- Extend assembly system: Complex change for one command — not worth it

## Decision 3: Audit Report Format

**Decision**: Structured markdown with YAML-like metadata header, findings grouped by source (constitution/prompt/common-sense), each finding with severity/file/evidence/recommendation.

**Rationale**:
- Markdown is human-readable and version-controllable
- Structured format allows output skills to parse findings programmatically
- Consistent with all other tricycle artifacts (specs, plans, tasks)

**Format**:
```markdown
# Audit Report

**Date**: 2026-03-27
**Scope**: src/
**Sources**: Constitution, Custom prompt
**Summary**: 3 critical, 2 warning, 12 info, 8 passed

## Constitution Findings

### CRITICAL: [Rule name]
- **File**: src/foo.sh:42
- **Evidence**: `hardcoded_password="admin123"`
- **Recommendation**: Use environment variables for credentials

## Custom Prompt Findings
...

## Common Sense Findings
...
```

## Decision 4: Scope Resolution

**Decision**: Three scope modes:
1. **File paths/globs**: `trc.audit src/ tests/*.js` — direct file listing
2. **Feature flag**: `trc.audit --feature TRI-3-skills-system` — git diff against base branch to find changed files + spec directory
3. **No scope**: `trc.audit` — audits entire project (all tracked files)

**Rationale**: Covers the three natural use cases — targeted audit, feature review, and full project scan.

## Decision 5: linear-audit Skill Architecture

**Decision**: Standard skill at `core/skills/linear-audit/SKILL.md` that:
1. Reads the most recent audit report from `docs/audits/`
2. Parses findings above a severity threshold (default: warning and above)
3. Creates Linear issues via MCP tools for each qualifying finding
4. Tags issues with audit metadata (date, scope, rule violated)

**Rationale**:
- Follows the exact same pattern as other skills (SKILL.md with instructions)
- The skill has no knowledge of the audit command — it just reads the report file
- Any future output skill (slack-audit, github-issues-audit) follows the same pattern

## Decision 6: Constitution Validation

**Decision**: Before auditing against constitution, validate that the constitution file exists AND contains content beyond the placeholder. Check for `_Run \`/trc.constitution\` to populate this file._` — if that text is present, the constitution is not populated.

**Rationale**: Prevents meaningless audits against an empty constitution. The error message guides users to populate it first.
