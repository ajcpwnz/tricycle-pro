---
description: >-
  Audit files against the project constitution, a custom prompt, or a fixed
  set of engineering checks. Writes a report to docs/audits/, and with
  --linear files the findings in Linear.
---

## User Input

```text
$ARGUMENTS
```

## What this command is

An audit is your judgment, not a linter run. You read each file and decide where
it breaks a rule. Every finding quotes the line that proves it. Some claims can be
tested by running something, such as a hook, a script or an endpoint. Run it and
record the result as evidence.

### 1. Parse the arguments

- **Paths** (positional): files, directories or globs.
- **`--feature <branch>`**: the files that `<branch>` changes against the base.
- **`--prompt "<criteria>"`**: custom criteria, checked as well as the
  constitution.
- **`--linear`**: after the report, file the findings in Linear.

The base branch is `push.pr_target` in `tricycle.config.yml`, then
`project.base_branch`, then `main`. Use `origin/<base>` when it exists.

### 2. Resolve the scope

- **Paths given:** expand them to a list of files.
- **`--feature <branch>`:** `git diff --name-only <base>...<branch>`. Combine it
  with any paths given.
- **Nothing given:** the files that the current branch changes against the base.
  Add the uncommitted and untracked files. Use
  `git diff --name-only <base>...HEAD`, `git diff --name-only HEAD` and
  `git ls-files --others --exclude-standard`. Never audit the whole repository by
  default.

Drop deleted files and binary files (images, fonts, archives, compiled output),
and list the binary files that you dropped. If no file is left, stop and tell the
user to pass a path.

### 3. Load the rules

Read the constitution at `constitution.root` (default
`.trc/memory/constitution.md`). Each top-level heading or numbered item is one
rule.

- **Missing file:** stop with an error.
- **Placeholder only** (`Run /trc.constitution to populate this file.`): warn the
  user. Use `--prompt` if it was given. Otherwise use the fixed checks: naming,
  function size, error handling, security (credentials, injection, path
  traversal), dead code, and consistency with the rest of the project.

### 4. Evaluate

Check each file against each rule. For more than 15 files, split the files into
groups of about 15. Give each group to a worker subagent (Agent tool, model from
`models.workers` in `tricycle.config.yml`, default `opus`), and run the workers in
parallel. Give each worker the
rules, its files and the finding format. Ask it for findings only, not file
contents.

Record each finding with:

- **Severity:** `critical` for a clear break of a mandatory rule, `warning` for a
  partial or borderline break, `info` for an observation.
- **Location:** `path:line`.
- **Evidence:** the quoted line, or the command and its output.
- **Recommendation:** what to change.

Check each worker finding before you keep it. Open the cited line and check that
it says what the finding claims.

### 5. Write the report

Write `docs/audits/audit-YYYY-MM-DD-<scope-summary>.md`:

```markdown
# Audit Report

**Date**: YYYY-MM-DD
**Scope**: <the scope and how it was resolved>
**Sources**: <Constitution, Custom Prompt, Fixed Checks>
**Summary**: X critical, Y warning, Z info

## Findings

### CRITICAL: <rule>
- **File**: path/to/file.ext:line
- **Evidence**: `<quoted line or command output>`
- **Recommendation**: <what to change>

## Skipped Files

- path/to/image.png (binary)
```

### 6. File in Linear (only with --linear)

Invoke the `linear-audit` skill with the report path. If the skill or a Linear MCP
server is not available, say so. The report stays the only output.

### 7. Report

State the report path, the counts by severity, and whether the findings went to
Linear. If no rule broke, say "All checks passed: no findings."
