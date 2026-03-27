---
description: >-
  Audit scoped files against the project constitution, a custom prompt,
  or common-sense best practices. Produces structured reports in docs/audits/.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Audit Execution

### 1. Parse Arguments

Parse the user input for:

- **Scope** (positional): File paths or glob patterns (e.g., `src/`, `bin/*.sh`, `tests/`). If no scope is provided, audit all tracked files in the repository (`git ls-files`).
- **`--feature <branch-name>`**: Scope to files changed by a feature. Resolve by running `git diff --name-only main...<branch-name>` and including the feature's spec directory (`specs/<branch-name>/`).
- **`--prompt "<criteria>"`**: Custom audit criteria to evaluate alongside or instead of the constitution.

If both `--feature` and file paths are provided, combine them (union of both scopes).

### 2. Load Constitution

Read the constitution path from `tricycle.config.yml` (`constitution.root`, default `.trc/memory/constitution.md`).

**Validation**:
- If the file does not exist: ERROR "Constitution file not found at <path>."
- If the file contains the placeholder text `_Run \`/trc.constitution\` to populate this file._`: The constitution is NOT populated.
  - If a `--prompt` was provided: WARN "Constitution not populated — auditing against custom prompt only." Proceed with custom prompt.
  - If NO `--prompt` was provided: WARN "Constitution not populated — auditing against common-sense best practices." Proceed with common-sense fallback.
- If the file has real content: Extract individual rules/principles. Each top-level heading or numbered item in the constitution is treated as a separate auditable rule.

### 3. Resolve Scope to File List

1. Expand file paths and globs to a concrete list of files.
2. For `--feature`, run `git diff --name-only main...<branch>` to get changed files.
3. Filter out binary files (images, compiled assets, fonts). Detect by checking if `file --mime-type` reports a non-text type, or if the extension is in: `.png`, `.jpg`, `.jpeg`, `.gif`, `.ico`, `.woff`, `.woff2`, `.ttf`, `.eot`, `.pdf`, `.zip`, `.tar`, `.gz`, `.bin`, `.exe`, `.dll`, `.so`, `.dylib`.
4. Report skipped binary files in the output.
5. If no files remain after filtering: ERROR "No auditable files found in scope."

### 4. Evaluate Files

For each audit source (constitution rules, custom prompt, common-sense), evaluate every file in scope:

**Constitution audit** (if constitution is populated):
- For each rule in the constitution, check whether the file complies.
- Record findings with severity:
  - **critical**: Clear violation of a mandatory rule
  - **warning**: Partial compliance or borderline violation
  - **info**: Observation or suggestion related to the rule
- Include evidence: quote the specific code or text that triggers the finding.

**Custom prompt audit** (if `--prompt` provided):
- Evaluate each file against the user's custom criteria.
- Apply the same severity levels and evidence format.

**Common-sense audit** (fallback when no constitution and no prompt):
- Evaluate files against standard engineering best practices:
  - **Naming**: Are function, variable, and file names clear and descriptive?
  - **Complexity**: Are functions reasonably sized (not excessively long)?
  - **Error handling**: Are errors handled rather than silently swallowed?
  - **Security**: No hardcoded credentials, no command injection risks, no path traversal?
  - **Dead code**: No commented-out code blocks, no unreachable code?
  - **Consistency**: Does the code follow patterns established elsewhere in the project?

### 5. Generate Report

Create a markdown report at `docs/audits/audit-YYYY-MM-DD-<scope-summary>.md`:

```markdown
# Audit Report

**Date**: YYYY-MM-DD
**Scope**: <files or feature audited>
**Sources**: <Constitution, Custom Prompt, Common Sense — whichever were used>
**Summary**: X critical, Y warning, Z info, W passed

## Constitution Findings

### CRITICAL: <Rule name>
- **File**: path/to/file.ext:line
- **Evidence**: `<relevant code snippet>`
- **Recommendation**: <what to fix>

### WARNING: <Rule name>
- **File**: path/to/file.ext:line
- **Evidence**: `<relevant code snippet>`
- **Recommendation**: <what to fix>

## Custom Prompt Findings

### <severity>: <criterion>
- **File**: path/to/file.ext:line
- **Evidence**: `<relevant code snippet>`
- **Recommendation**: <what to fix>

## Common Sense Findings

### <severity>: <category>
- **File**: path/to/file.ext:line
- **Evidence**: `<relevant code snippet>`
- **Recommendation**: <what to fix>

## Skipped Files

- path/to/image.png (binary)
- path/to/font.woff2 (binary)

## Summary

| Source | Critical | Warning | Info | Passed |
|--------|----------|---------|------|--------|
| Constitution | X | Y | Z | W |
| Custom Prompt | X | Y | Z | W |
| Common Sense | X | Y | Z | W |
| **Total** | **X** | **Y** | **Z** | **W** |
```

Report the file path to the user after generation.

### 6. Invoke Output Skills

After the report is written, check `tricycle.config.yml` for configured output skills:

1. Read `workflow.blocks.audit.skills` from the config (using the same config access pattern as other steps).
2. For each listed skill name:
   - Check if `.claude/skills/<skill-name>/SKILL.md` exists.
   - If installed: invoke `/<skill-name>` and pass context about the audit report location (`docs/audits/<filename>.md`).
   - If not installed: skip silently.
3. If no skills are configured, skip this step entirely — the local report is the only output.

### 7. Report Completion

Output a summary:
- Report file path
- Total findings by severity
- Which output skills were invoked (if any)
- If all checks passed: "All checks passed — no findings."
