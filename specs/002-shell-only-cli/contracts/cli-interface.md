# CLI Interface Contract

## Entry Point

**Binary**: `bin/tricycle` (bash script, `#!/usr/bin/env bash`)

## Commands

### `tricycle init [--preset <name>]`

Initialize a project with Tricycle Pro.

| Input | Type | Required | Default |
|---|---|---|---|
| `--preset <name>` | string | no | (interactive wizard) |

**Interactive wizard prompts** (when no `--preset`):
1. Project name — free text, default `my-project`
2. Project type — choice: `monorepo`, `single-app`, default index 0
3. Package manager — choice: `bun`, `npm`, `yarn`, `pnpm`, default index 0
4. Base branch — free text, default `staging`

**Output files**:
- `tricycle.config.yml`
- `.claude/commands/*` (from `core/commands/`)
- `.specify/templates/*` (from `core/templates/`)
- `.specify/scripts/bash/*` (from `core/scripts/bash/`)
- `.claude/hooks/*` (from `core/hooks/`)
- `.claude/skills/*` (from `core/skills/`)
- `.claude/settings.json`
- `.specify/memory/constitution.md` (placeholder if missing)
- `.gitignore` (appended or created)
- `.tricycle.lock`

**Exit codes**: 0 success, 1 preset not found

---

### `tricycle add <module>`

Install an optional module.

| Input | Type | Required |
|---|---|---|
| `module` | string (`worktree`, `qa`, `ci-watch`, `mcp`, `memory`) | yes |

**Exit codes**: 0 success, 1 module not found or no module specified

---

### `tricycle generate <target>`

Generate configuration files from `tricycle.config.yml`.

| Input | Type | Required |
|---|---|---|
| `target` | string (`claude-md`, `settings`, `mcp`) | yes |

**Targets**:
- `claude-md` → writes `CLAUDE.md` (assembled from `generators/sections/*.md.tpl`)
- `settings` → writes `.claude/settings.json`
- `mcp` → writes `.mcp.json`

**Exit codes**: 0 success, 1 invalid target or missing config

---

### `tricycle update [--dry-run]`

Update managed core files to latest version.

| Input | Type | Required | Default |
|---|---|---|---|
| `--dry-run` | flag | no | false |

**Behavior**: Compares checksums of installed files vs source. Updates unmodified files, skips locally modified ones.

**Exit codes**: 0 always

---

### `tricycle validate`

Validate configuration and installed files.

**Checks**:
- `project.name` and `project.type` exist in config
- All app paths exist on disk
- Core directories present (`.claude/commands`, `.specify/templates`, `.specify/scripts/bash`, `.claude/hooks`)
- Constitution file exists
- Hook scripts are executable

**Exit codes**: 0 all checks pass, 1 any check fails

---

### `tricycle --help` / `tricycle -h`

Print usage information.

**Exit codes**: 0

---

## Bootstrapper Script

### One-off mode

```
bash <(curl -sL <url>/install.sh) <subcommand> [args...]
```

Clones repo to temp directory, runs subcommand, cleans up.

### Install mode

```
bash <(curl -sL <url>/install.sh) --install [target-path]
```

Clones repo to `target-path` (default `~/.tricycle-pro`), prints PATH instructions or creates symlink.
