# Data Model: TRI-3 Skills System

**Date**: 2026-03-27

## Entities

### Skill

A self-contained unit of knowledge installed in `.claude/skills/<name>/`.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | Directory name; lowercase alphanumeric + hyphens, max 64 chars |
| SKILL.md | file | yes | Primary skill definition with YAML frontmatter + markdown body |
| README.md | file | no | Integration guide and usage notes |
| Templates/ | directory | no | Reusable template files |
| Examples/ | directory | no | Good/bad pattern examples |
| SOURCE | file | conditional | Origin tracking; required for vendored and external skills, absent for user-created |

**Identity**: Directory name under `.claude/skills/` is the unique identifier.

**Validation rules**:
- Name must match pattern: `^[a-z0-9][a-z0-9-]*[a-z0-9]$` (min 2 chars)
- SKILL.md must exist and contain valid YAML frontmatter (delimited by `---`)
- Frontmatter must include `name` and `description` fields

### SOURCE Metadata

A plain-text file tracking the origin of a vendored or externally-installed skill.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| origin | string | yes | Source identifier: `vendored:core/skills/<name>`, `github:<owner>/<repo>/<path>`, or `local:<path>` |
| commit | string | conditional | Git commit hash; present for vendored and github sources, absent for local |
| installed | date (YYYY-MM-DD) | yes | Date the skill was installed or last updated from source |
| checksum | string (hex, 16 chars) | yes | SHA256 of concatenated skill file contents at install time |

**Format**: Plain text, one key-value pair per line, colon-separated.

### Skills Configuration

The `skills` section of `tricycle.config.yml`.

```yaml
skills:
  install:
    - source: "github:owner/repo/skill-path"
    - source: "local:.trc/skills/my-skill"
  disable:
    - "tdd"
    - "document-writer"
```

**Parsed representation** (via yaml_parser.sh):
```
skills.install.0.source=github:owner/repo/skill-path
skills.install.1.source=local:.trc/skills/my-skill
skills.disable.0=tdd
skills.disable.1=document-writer
```

**Access patterns**:
- `cfg_count "skills.install"` → number of external sources
- `cfg_get "skills.install.0.source"` → first source URI
- `cfg_count "skills.disable"` → number of disabled skills
- `cfg_get "skills.disable.0"` → first disabled skill name

### Lock File Entries

Skills installed via `install_dir()`/`install_file()` are tracked in `.tricycle.lock` like all other core files.

| Field | Type | Description |
|-------|------|-------------|
| filepath | string | Relative path (e.g., `.claude/skills/code-reviewer/SKILL.md`) |
| checksum | string (hex, 16 chars) | SHA256 of file content at install time |
| customized | boolean | Whether user has modified the file since installation |

**Note**: Lock file tracks individual files within a skill. SOURCE file tracks the skill as a whole unit. Both are needed: lock file for `cmd_update()` file-level diffing, SOURCE for `tricycle skills list` skill-level status.

## Relationships

```
Skills Configuration (tricycle.config.yml)
  ├── skills.disable[] ──→ prevents installation of Skill by name
  └── skills.install[] ──→ defines external Skill sources

Skill (directory in .claude/skills/)
  ├── contains SOURCE (origin tracking)
  ├── tracked by Lock File Entries (per-file checksums)
  └── referenced by Blocks (conditional invocation)

core/skills/ (vendored source)
  └── copied to .claude/skills/ during init/update (filtered by disable list)
```

## State Transitions

### Skill Lifecycle

```
[Not Installed] ──init/update──→ [Installed (clean)]
                                      │
                          user edits ──┤
                                      ▼
                                [Installed (modified)]
                                      │
                         update ──────┤
                                      ▼
                                [Installed (modified, update skipped)]
                                      │
                    user re-inits ────┤── (still preserved if modified)
                                      │
                      user deletes ───→ [Not Installed]
```

A disabled skill transitions directly to a terminal state:
```
[Configured in disable list] ──init/update──→ [Not Installed] (skipped)
```
