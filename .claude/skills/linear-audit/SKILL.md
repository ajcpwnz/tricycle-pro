---
name: linear-audit
description: >
  Route audit findings to Linear as issues. Reads the most recent audit
  report from docs/audits/, parses findings at warning severity or above,
  and creates Linear issues in the project's configured team. Requires
  Linear MCP server to be available.
---

# Linear Audit Output Skill

## When to use this Skill

`/trc.audit --linear` invokes this skill after it writes the report. You can also
invoke it by hand with `/linear-audit` after an audit.

## Prerequisites

- **A Linear MCP server** must be connected, under any server name.
- **An audit report** must exist in `docs/audits/`. This skill reads the most recent report.
- **Linear team** must be configured. Check project memory or config for the team name/ID.

## Execution Steps

### 1. Check Linear MCP Availability

Check that a Linear `save_issue` tool is available (`mcp__<server>__save_issue`, for any server name).

- If available: proceed.
- If NOT available: output "Linear MCP not available — audit findings remain in docs/audits/ only." and STOP. Do not error — this is expected graceful degradation.

### 2. Find the Most Recent Audit Report

If the caller passed a report path, read that file. Otherwise read the newest file in `docs/audits/` that matches `audit-*.md`.

- If no audit report exists: output "No audit report found in docs/audits/. Run `/trc.audit` first." and STOP.

### 3. Parse Findings

Extract all findings from the report that have severity **critical** or **warning**. For each finding, capture:
- **Severity**: critical or warning
- **Rule/criterion**: what was violated
- **File**: path and line number
- **Evidence**: the code snippet
- **Recommendation**: suggested fix

Skip **info** severity findings — they are observations, not actionable issues.

### 4. Determine Linear Team

Read the project's Linear team configuration. Check in order:
1. Project memory files for a Linear team reference
2. `tricycle.config.yml` for a `linear.team` field
3. If neither found: list available teams via Linear MCP and ask the user which team to use

### 5. Create Linear Issues

For each finding (critical and warning):

**Issue title**: `[Audit] <severity>: <rule/criterion> in <filename>`

**Issue body**:
```
## Audit Finding

**Severity**: <critical|warning>
**Rule**: <rule or criterion violated>
**File**: <path:line>

### Evidence
\`\`\`
<code snippet>
\`\`\`

### Recommendation
<suggested fix>

---
*Created by `/trc.audit` on YYYY-MM-DD*
```

**Issue labels**: Add "audit" label if it exists in the team. If not, create it.

**Priority**: Map severity — critical → Urgent, warning → High.

### 6. Report Results

Output a summary:
- Number of issues created
- Link to each created issue (if Linear MCP returns URLs)
- Any findings that failed to create (with error details)

## Things to Avoid

- Do not create duplicate issues — if an issue with the same title already exists in the team, skip it and note "already tracked."
- Do not create issues for info-level findings — those are informational only.
- Do not fail the entire skill if one issue creation fails — continue with remaining findings and report errors at the end.