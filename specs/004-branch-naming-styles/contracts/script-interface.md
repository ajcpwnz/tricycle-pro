# Contract: create-new-feature.sh CLI Interface

## Current Interface (preserved)

```
create-new-feature.sh [--json] [--short-name <name>] [--number N] <description>
```

## Extended Interface

```
create-new-feature.sh [--json] [--short-name <name>] [--number N] [--style <style>] [--issue <id>] [--prefix <prefix>] <description>
```

### New Flags

| Flag | Values | Description |
|------|--------|-------------|
| `--style <style>` | `feature-name`, `issue-number`, `ordered` | Naming strategy. Default: `ordered` (backward compat) |
| `--issue <id>` | e.g., `TRI-042` | Explicit issue identifier (for `issue-number` style) |
| `--prefix <prefix>` | e.g., `TRI` | Issue prefix for extraction from description |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success — branch created |
| 1 | Error — invalid input, branch exists, git failure |
| 2 | Needs input — `issue-number` style, no issue found in description. Agent should prompt user and retry with `--issue` |

### JSON Output (unchanged structure)

```json
{
  "BRANCH_NAME": "TRI-042-export-csv",
  "SPEC_FILE": "/abs/path/to/specs/TRI-042-export-csv/spec.md",
  "FEATURE_NUM": "042"
}
```

Note: `FEATURE_NUM` is the issue number for `issue-number` style, the sequential number for `ordered` style, and empty string for `feature-name` style.

### Behavior by Style

**`--style feature-name`**:
- Uses `generate_branch_name()` or `--short-name` to produce slug
- No numeric prefix
- `BRANCH_NAME` = `<slug>`

**`--style issue-number`**:
- If `--issue` provided: use directly
- Else if `--prefix` provided: extract `<PREFIX>-\d+` from description
- Else: extract generic `[A-Z]+-\d+` from description
- If no match: exit 2 with message
- `BRANCH_NAME` = `<ISSUE>-<slug>`

**`--style ordered`** (current behavior):
- Auto-detect next `###` from specs + branches
- `BRANCH_NAME` = `<###>-<slug>`

### Backward Compatibility

- When `--style` is not passed, defaults to `ordered` (preserves current behavior)
- `--number` only applies to `ordered` style (ignored for other styles)
- `--short-name` works with all styles (overrides slug generation)
