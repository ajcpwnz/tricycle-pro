# Research: TRI-3 Skills System

**Date**: 2026-03-27
**Branch**: TRI-3-skills-system

## Decision 1: GitHub Skill Fetching Strategy

**Decision**: Use `git clone --depth=1 --filter=blob:none --sparse` with `git sparse-checkout set <skill-path>` into a temporary directory, then copy the skill directory out.

**Rationale**:
- Works with public repos without API tokens (uses standard git)
- Handles full directory structure (SKILL.md, Templates/, Examples/) in one operation
- Depth-1 sparse clone is fast and bandwidth-efficient
- Falls back naturally to user's existing git auth for private repos (out of scope but doesn't break)
- Pure bash — no curl/jq JSON parsing needed for directory traversal

**Alternatives considered**:
- GitHub REST API (list contents + download files): More complex in bash, requires jq, subject to API rate limits
- GitHub tarball download (`/tarball/HEAD`): Downloads entire repo, wasteful for a single skill
- Direct raw content URLs: Requires knowing exact file list in advance, no directory traversal

## Decision 2: SOURCE File Format

**Decision**: Plain text key-value format (one key per line, colon-separated).

**Rationale**:
- Trivially parseable in bash with `grep` and `cut` — no jq or yaml parser needed
- Human-readable and editable
- Consistent with the project's "no external dependencies" philosophy

**Format**:
```
origin: github:anthropics/skills/code-reviewer
commit: abc1234def5678
installed: 2026-03-27
checksum: a1b2c3d4e5f67890
```

The `checksum` field stores the SHA256 (first 16 chars) of the concatenated skill contents at install time. This enables local-only modification detection without re-fetching.

**Alternatives considered**:
- JSON: Requires jq or awk-based parser — overkill for 4 fields
- YAML: Would need the yaml_parser.sh — heavier than necessary

## Decision 3: Modification Detection for External Skills

**Decision**: Store the original content checksum in the SOURCE file at install time. On update, compare the current installed checksum against the stored checksum. If different, the user modified it — skip update.

**Rationale**:
- Fully local — no network access needed for modification detection
- Reuses the same checksum approach as the lock file system
- The SOURCE file's `checksum` field serves as the "original state" reference

**Alternatives considered**:
- Re-fetch source and compare: Requires network, slow, fragile
- Track per-file checksums in lock file: Already works for vendored skills via `install_dir()`, but external skills need SOURCE-level tracking since they aren't in `core/skills/`

## Decision 4: Skill Disable Mechanism

**Decision**: Replace the single `install_dir "$TOOLKIT_ROOT/core/skills" ".claude/skills"` call with a loop that iterates `core/skills/*/` and skips entries matching `skills.disable` list items.

**Rationale**:
- Minimal change to existing `cmd_init()` flow
- Reuses `install_dir()` per-skill (directory level) while adding filter
- `cmd_update()` already doesn't include skills — adding skills with the same filter pattern is consistent

**Alternatives considered**:
- Post-install deletion: Wastes work, leaves lock file entries
- Separate install function: Over-engineering for a simple filter

## Decision 5: Skills Subcommand Architecture

**Decision**: Add `cmd_skills()` dispatcher that routes to `cmd_skills_list()`. Future subcommands (e.g., `skills add`, `skills remove`) can be added to the same dispatcher.

**Rationale**:
- Follows existing CLI pattern (`cmd_add`, `cmd_generate` with sub-routing)
- `tricycle skills list` is the only subcommand in scope; dispatcher structure avoids future refactoring

## Decision 6: Block Integration Pattern

**Decision**: Use conditional markdown in block templates. Blocks check for skill directory existence (`.claude/skills/<name>/SKILL.md`) and include a conditional invocation instruction. The AI agent interprets this — no bash logic needed.

**Rationale**:
- Blocks are markdown templates interpreted by AI agents, not executable scripts
- Existence check is a simple file-path condition the agent can evaluate
- Graceful degradation is natural — if the file doesn't exist, the agent skips the instruction
- No code changes needed to the block assembly system

**Pattern**:
```markdown
If `.claude/skills/code-review/SKILL.md` exists, invoke `/code-review` on the staged changes before requesting push approval.
```

## Decision 7: Vendoring Process

**Decision**: Manually copy skills from `anthropics/skills` repo into `core/skills/` as a one-time commit. Each skill gets a `SOURCE` file recording the origin commit. Future upstream syncs are manual (developer runs sparse checkout, copies, updates SOURCE).

**Rationale**:
- The project has no build system or CI — automated upstream sync would add complexity
- Vendored skills are reviewed and committed; this is intentional curation, not automation
- SOURCE file provides traceability back to upstream

**Alternatives considered**:
- Git submodule: Heavy, fragile, requires submodule init on clone
- Automated sync script: Premature — manual process is fine for 4 skills updated infrequently
