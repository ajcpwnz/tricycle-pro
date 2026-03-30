# Research: Stealth Mode

**Branch**: `TRI-21-stealth-mode` | **Date**: 2026-03-31

## Decision 1: Where to store the stealth flag

**Decision**: Store `stealth.enabled: true` inside `tricycle.config.yml` itself. The config file is gitignored in stealth mode (along with everything else), so there is no bootstrap paradox — the config lives on disk but is invisible to git.

**Rationale**: The config file already exists and is the canonical source of truth for all tricycle settings. Adding a separate local-only config file introduces complexity (config layering, merge semantics, load order). Since stealth mode gitignores `tricycle.config.yml` itself, the flag is self-hiding.

**Alternatives considered**:
- `.tricycle.local.yml` (separate local file) — adds config layering complexity with no benefit since stealth ignores the main config anyway
- `.git/config` custom key — non-standard use of git config, harder to discover
- Environment variable — non-persistent, easy to forget
- `.claude/.stealth` marker file — another file to track; config field is simpler

## Decision 2: Default ignore target

**Decision**: Default to `.git/info/exclude` for stealth ignore rules. Configurable via `stealth.ignore_target: gitignore` to use `.gitignore` instead.

**Rationale**: `.git/info/exclude` is truly local — it is never committed, never shows in `git status`, and leaves zero trace. This matches the "maximum stealth" requirement. Users who prefer `.gitignore` (e.g., for discoverability in shared repos where teammates also use tricycle) can override.

**Alternatives considered**:
- Default to `.gitignore` — would show stealth rules to teammates if `.gitignore` is committed; violates maximum stealth
- Global gitignore (`~/.gitignore_global`) — affects all repos, not per-repo

## Decision 3: Ignore rule management strategy

**Decision**: Use clearly demarcated comment blocks around stealth rules so they can be added and removed cleanly.

**Rationale**: Using markers (`# >>> tricycle stealth` / `# <<< tricycle stealth`) allows the toggle-off path to find and remove only stealth rules without disturbing user rules. This is the same pattern tricycle already uses for its normal gitignore block.

**Alternatives considered**:
- Rewrite the entire file — dangerous, could destroy user rules
- Track line numbers — brittle, breaks if user edits the file

## Decision 4: What paths to ignore in stealth mode

**Decision**: Ignore the following paths (superset of normal mode):
- `.claude/` (entire directory — no negation exceptions)
- `.trc/`
- `specs/`
- `tricycle.config.yml`
- `.tricycle.lock`
- `.mcp.json` (if tricycle manages it)

**Rationale**: In normal mode, `.claude/settings.json`, `.claude/commands/`, `.claude/hooks/`, and `.claude/skills/` are whitelisted via negation patterns. In stealth mode, nothing is whitelisted — everything is ignored.

**Alternatives considered**:
- Only ignore new paths (keep normal whitelist) — defeats the purpose; commands and hooks would still be committed

## Decision 5: Integration points in the CLI

**Decision**: Modify three functions in `bin/tricycle`:
1. `cmd_generate_gitignore()` — stealth-aware: choose target file, write full-ignore rules
2. `cmd_init()` — call gitignore generation early (before other file writes) when stealth
3. Add `cmd_stealth_disable()` — remove stealth rules from target file on toggle-off

Assemble (`assemble-commands.sh`) needs no changes — it writes to `.claude/commands/` which is already under the stealth ignore umbrella.

**Rationale**: Minimal surface area. The gitignore function already exists; stealth just changes its output and target. Init already calls it; just move the call earlier. No other scripts read the stealth flag — they don't need to, because stealth only affects VCS visibility.
