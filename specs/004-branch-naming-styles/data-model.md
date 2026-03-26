# Data Model: Configurable Branch Naming Styles

## Configuration Schema

### `tricycle.config.yml` — New `branching` Section

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `branching.style` | enum: `feature-name`, `issue-number`, `ordered` | `feature-name` | Branch naming strategy |
| `branching.prefix` | string | _(none)_ | Issue prefix for `issue-number` style (e.g., `TRI`, `JIRA`) |

**Parsed flat keys** (via `parse_yaml`):

| Flat Key | Example Value |
|----------|---------------|
| `branching.style` | `feature-name` |
| `branching.prefix` | `TRI` |

### Validation Rules

- `branching.style` must be one of: `feature-name`, `issue-number`, `ordered`. Invalid values produce a warning and fall back to `feature-name`.
- `branching.prefix` is optional. When `style=issue-number` and no prefix is set, the system uses a generic `[A-Z]+-\d+` pattern.
- `branching.prefix` should be uppercase letters only. The system normalizes to uppercase if lowercase is provided.

## Script Interface Changes

### `create-new-feature.sh` — New `--style` Flag

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--style` | enum: `feature-name`, `issue-number`, `ordered` | `ordered` | Branch naming style (backward compat: defaults to `ordered` when not passed) |
| `--issue` | string | _(none)_ | Issue identifier for `issue-number` style (e.g., `TRI-042`) |
| `--prefix` | string | _(none)_ | Expected issue prefix for extraction (e.g., `TRI`) |

### Branch Name Formats by Style

| Style | Format | Example | Spec Directory |
|-------|--------|---------|----------------|
| `feature-name` | `<slug>` | `dark-mode-toggle` | `specs/dark-mode-toggle/` |
| `issue-number` | `<ISSUE>-<slug>` | `TRI-042-export-csv` | `specs/TRI-042-export-csv/` |
| `ordered` | `<###>-<slug>` | `004-notifications` | `specs/004-notifications/` |

### Issue Extraction Logic

When `style=issue-number`:
1. If `--issue` is passed: use it directly.
2. If `--prefix` is passed: search description for `<PREFIX>-<DIGITS>` (case-insensitive). Use first match.
3. If no prefix: search for generic `[A-Z]+-\d+` pattern. Use first match.
4. If no match found: exit with code 2 (special "needs input" code) and message indicating issue number is needed.

The agent (feature-setup block) catches exit code 2, prompts the user, then re-runs with `--issue`.
