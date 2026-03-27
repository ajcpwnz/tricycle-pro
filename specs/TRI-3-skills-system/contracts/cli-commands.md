# CLI Command Contracts: Skills System

**Date**: 2026-03-27

## Modified Commands

### `tricycle init`

**Current behavior**: Copies all skills from `core/skills/` to `.claude/skills/` unconditionally.

**New behavior**:
1. Read `skills.disable` from config
2. Iterate `core/skills/*/` directories individually
3. Skip skills whose directory name appears in `skills.disable`
4. For each non-disabled skill: call `install_dir` per-skill
5. Generate SOURCE file for each installed vendored skill
6. Read `skills.install` from config
7. For each external source: fetch and install (see `fetch_external_skill` below)

**Output changes**:
```
Installing core...
  WRITE .claude/skills/code-reviewer/SKILL.md
  WRITE .claude/skills/code-reviewer/SOURCE
  SKIP  .claude/skills/tdd (disabled)
  FETCH github:daymade/claude-code-skills/security-audit
  WRITE .claude/skills/security-audit/SKILL.md
  WRITE .claude/skills/security-audit/SOURCE
  ERROR github:example/nonexistent/skill — fetch failed (continuing)
```

### `tricycle update`

**Current behavior**: Updates commands, templates, scripts, hooks, blocks. Does NOT include skills.

**New behavior**: Add `core/skills:.claude/skills` to the update mappings with the same disable filtering as init. Also re-fetch external skills (if source changed or not yet installed).

**Output changes**: Same ADD/UPDATE/SKIP pattern as existing update, plus FETCH for external skills.

## New Commands

### `tricycle skills list`

**Usage**: `tricycle skills list`

**Output format**:
```
Skills installed in .claude/skills/:

  Name               Source                                    Status
  ─────────────────  ────────────────────────────────────────  ──────────
  code-reviewer      vendored:core/skills/code-reviewer        clean
  debugging          vendored:core/skills/debugging             modified
  monorepo-structure vendored:core/skills/monorepo-structure    clean
  security-audit     github:daymade/claude-code-skills/...     clean
  my-custom-skill    (user-created)                            —

  5 skills installed (1 modified, 1 user-created)
```

**Fields**:
- **Name**: Skill directory name
- **Source**: From SOURCE file's `origin` field, or `(user-created)` if no SOURCE file
- **Status**: `clean` (matches source checksum), `modified` (differs), or `—` (no tracking)

**Exit codes**: 0 always (informational command)

**Edge cases**:
- No `.claude/skills/` directory → "No skills installed. Run `tricycle init` to install defaults."
- Empty `.claude/skills/` directory → Same message

## Internal Functions

### `install_skills()`

**Location**: `bin/lib/helpers.sh` (new function)

**Signature**: `install_skills src_base_dir dest_rel_base`

**Behavior**:
1. Read disabled skills: iterate `skills.disable.*` from CONFIG_DATA
2. For each subdirectory in `src_base_dir`:
   - If directory name is in disabled list → `info "SKIP .claude/skills/<name> (disabled)"`, continue
   - Else → `install_dir "$subdir" "$dest_rel_base/$name"`
3. Generate SOURCE file for each installed skill

### `fetch_external_skill()`

**Location**: `bin/lib/helpers.sh` (new function)

**Signature**: `fetch_external_skill source_uri dest_base_dir`

**Behavior**:
1. Parse `source_uri`:
   - `github:<owner>/<repo>/<path>` → git sparse checkout
   - `local:<path>` → direct copy
2. For GitHub sources:
   - Create temp directory
   - `git clone --depth=1 --filter=blob:none --sparse "https://github.com/<owner>/<repo>.git" "$tmp"`
   - `cd "$tmp" && git sparse-checkout set "<path>"`
   - Copy `$tmp/<path>/` to `$dest_base_dir/<skill-name>/`
   - Record commit hash: `git -C "$tmp" rev-parse HEAD`
   - Clean up temp directory
3. For local sources:
   - Validate path exists
   - Copy directory contents
4. Generate SOURCE file with origin, commit (if applicable), installed date, checksum
5. Return 0 on success, 1 on failure (caller continues)

### `generate_source_file()`

**Location**: `bin/lib/helpers.sh` (new function)

**Signature**: `generate_source_file skill_dir origin commit`

**Behavior**:
1. Compute checksum of all skill files (concatenated, sorted by path)
2. Write SOURCE file to `$skill_dir/SOURCE`

### `skill_checksum()`

**Location**: `bin/lib/helpers.sh` (new function)

**Signature**: `skill_checksum skill_dir`

**Behavior**:
1. Find all files in `skill_dir` except SOURCE
2. Sort by relative path
3. Concatenate contents
4. Return SHA256 (first 16 chars)
