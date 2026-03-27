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

This skill is invoked automatically by the `/trc.audit` command when configured on the audit step:

```yaml
workflow:
  blocks:
    audit:
      skills:
        - linear-audit
```

You can also invoke it manually via `/linear-audit` after running an audit.

## Prerequisites

- **Linear MCP server** must be configured and running. Check `.mcp.json` for a `linear-server` entry.
- **An audit report** must exist in `docs/audits/`. This skill reads the most recent report.
- **Linear team** must be configured. Check project memory or config for the team name/ID.

## Execution Steps

### 1. Check Linear MCP Availability

Verify that Linear MCP tools are available by checking if `mcp__linear-server__save_issue` is callable.

- If available: proceed.
- If NOT available: output "Linear MCP not available — audit findings remain in docs/audits/ only." and STOP. Do not error — this is expected graceful degradation.

### 2. Find the Most Recent Audit Report

Look for the newest file in `docs/audits/` matching the pattern `audit-*.md`. Read its contents.

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
3. If neither found: list available teams via Linear MCP and ask the user to confirm which team to use

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
