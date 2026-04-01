# Data Model: Local Config Overrides

**Branch**: `TRI-23-local-config-overrides` | **Date**: 2026-03-31

## Entities

### Override File (`tricycle.config.local.yml`)

An optional YAML file using the same schema as `tricycle.config.yml`, containing only the fields a developer wants to override.

| Field | Type | Description |
|-------|------|-------------|
| (any overridable key) | YAML subset | Sparse subset of `tricycle.config.yml` structure |

**Constraints**:
- Must be valid YAML parseable by `parse_yaml()`
- Only keys from the overridable whitelist are applied
- Non-overridable keys produce warnings and are ignored
- Empty or missing file = no overrides (no error)

**Location**: Project root, alongside `tricycle.config.yml`

**VCS**: Always excluded from version control

### Overridable Field Whitelist

A code-level constant defining which top-level config paths can be overridden.

| Overridable Path | Affects Assembly | Notes |
|-----------------|-----------------|-------|
| `push.*` | No | Runtime enforcement by push scripts |
| `qa.*` | Yes (block enable) | Two-pass assembly handles divergence |
| `worktree.*` | Yes (block enable) | Two-pass assembly handles divergence |
| `workflow.blocks.*.enable` | Yes | Two-pass assembly handles divergence |
| `workflow.blocks.*.disable` | Yes | Two-pass assembly handles divergence |
| `stealth.*` | No | Per-developer VCS preference |

| Non-Overridable Path | Reason |
|---------------------|--------|
| `project.*` | Shared project identity |
| `apps.*` | Shared app definitions |
| `workflow.chain` | Shared workflow structure |
| `branching.*` | Shared branch naming |
| `constitution.*` | Shared governance |
| `mcp.*` | Shared tool config |
| `context.*` | Shared session context |

### Merged Config (Runtime)

The result of deep-merging base + override config. Exists only in memory as the `CONFIG_DATA` variable.

**Merge rules**:
- Scalar values: override wins
- Object keys: recursive merge (override adds/replaces keys, base keys not in override are preserved)
- Arrays: override replaces entire array (no append semantics)

### Local Command Overlay (`.trc/local/commands/`)

Assembly output generated from merged config. Mirrors `.claude/commands/` structure.

| File | Source Config | VCS Status |
|------|-------------|------------|
| `.claude/commands/trc.*.md` | Base only | Committed |
| `.trc/local/commands/trc.*.md` | Merged (base + override) | Gitignored |

**Runtime resolution**: Session start hook detects overlay files and injects context note for Claude to prefer local variants.

## State Transitions

### Config Loading Flow

```
[No override file] → load base config → CONFIG_DATA (base only)
[Override file exists] → load base → validate override → merge → CONFIG_DATA (merged)
[Override file invalid] → load base → warn → CONFIG_DATA (base only, warning emitted)
```

### Assembly Flow

```
[No override] → single pass (base config) → .claude/commands/
[Override exists] → pass 1 (base) → .claude/commands/
                  → pass 2 (merged) → .trc/local/commands/
```
