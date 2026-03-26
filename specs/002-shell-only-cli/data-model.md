# Data Model: Shell-Only CLI

## Entities

### Config (tricycle.config.yml)

The parsed representation of the YAML config file. After parsing, stored as flat key-value pairs in an associative array (bash 4+) or variable-name-encoded keys (bash 3.2 compat).

**Flat key format**: Dot-separated path with numeric indices for arrays.

| Key Pattern | Example | Type |
|---|---|---|
| `project.{field}` | `project.name=tricycle-pro` | string |
| `apps.{n}.{field}` | `apps.0.name=backend` | string |
| `apps.{n}.{nested}.{field}` | `apps.0.docker.compose=docker-compose.yml` | string |
| `apps.{n}.{nested}.{m}` | `apps.0.env_copy.0=apps/backend/.env` | string (array item) |
| `worktree.{field}` | `worktree.enabled=true` | string (boolean as string) |
| `mcp.custom.{name}.{field}` | `mcp.custom.prisma.command=npx` | string |
| `mcp.custom.{name}.args.{n}` | `mcp.custom.prisma.args.0=prisma` | string |
| `push.{field}` | `push.require_approval=true` | string |
| `constitution.{field}` | `constitution.root=.trc/memory/constitution.md` | string |

**Derived counts** (computed during parsing):
- `apps.__count` — number of app entries
- `apps.{n}.env_copy.__count` — number of env_copy entries per app context
- `worktree.env_copy.__count` — number of env_copy entries
- `deploy.workflows.__count` — number of workflow entries

### Lock File (.tricycle.lock)

JSON file tracking managed files and their checksums.

```json
{
  "version": "0.1.0",
  "installed": "2026-03-24",
  "files": {
    "<relative-path>": {
      "checksum": "<sha256-first-16-chars>",
      "customized": false
    }
  }
}
```

**Fields**:
- `version` — tricycle-pro version at install time
- `installed` — ISO date of initial install
- `files` — map of managed file paths to their state
  - `checksum` — first 16 chars of SHA-256 hash of file contents
  - `customized` — boolean, set to `true` when local modifications detected

### Template Context

The variable context available during template substitution. Built from the parsed Config entity.

| Variable | Source |
|---|---|
| `{{project.name}}` | `config[project.name]` |
| `{{project.package_manager}}` | `config[project.package_manager]` |
| `{{project.base_branch}}` | `config[project.base_branch]` |
| `{{push.pr_target}}` | `config[push.pr_target]` or fallback to `config[project.base_branch]` |
| `{{push.merge_strategy}}` | `config[push.merge_strategy]` |
| `{{qa.primary_tool}}` | `config[qa.primary_tool]` |
| `{{qa.fallback_tool}}` | `config[qa.fallback_tool]` |
| `{{qa.results_dir}}` | `config[qa.results_dir]` |
| `{{app.name}}` | Per-app during `{{#each apps}}` |
| `{{app.path}}` | Per-app during `{{#each apps}}` |
| `{{app.lint}}` | Per-app during `{{#each apps}}` |
| `{{app.test}}` | Per-app during `{{#each apps}}` |
| `{{app.build}}` | Per-app during `{{#each apps}}` |
| `{{app.dev}}` | Per-app during `{{#each apps}}` |
| `{{app.port}}` | Per-app during `{{#each apps}}` |

### YAML Parser Output Specification

**Input**: Raw YAML file content (constrained subset)
**Output**: Stream of `KEY=VALUE` lines, one per leaf node

**Rules**:
1. Indentation determines nesting depth (2-space indent per level)
2. A line with `key:` followed by indented children = object → prefix child keys with `key.`
3. A line starting with `- ` at array indent = new array item → increment index counter for that array path
4. A line with `key: value` at leaf level = emit `prefix.key=value`
5. Inline arrays `["a", "b"]` = emit as `prefix.0=a`, `prefix.1=b`
6. Comments (`#`) and blank lines are skipped
7. Quoted values have quotes stripped
8. Boolean values `true`/`false` are preserved as strings
