# MCP Module

Provides preset configurations for Model Context Protocol (MCP) servers.

## What it includes

- **presets/minimal.json** -- GitHub MCP server only
- **presets/backend-only.json** -- Context7, Docker, and GitHub servers
- **presets/web-fullstack.json** -- Chrome DevTools, Playwright, Context7, Docker, and GitHub servers

## Installation

```bash
npx tricycle-pro add mcp
```

Note: The MCP module is primarily consumed by `tricycle generate mcp`, which reads the preset
name from your config and merges it with any custom server definitions.

## Configuration

In `tricycle.config.yml`:

```yaml
mcp:
  preset: "web-fullstack"    # minimal | backend-only | web-fullstack
  custom:
    prisma:
      command: "npx"
      args: ["prisma", "mcp"]
```

## Usage

```bash
npx tricycle-pro generate mcp   # Generates .mcp.json from config
```

The generated `.mcp.json` is gitignored by default. Each worktree inherits MCP configuration
from the shared `tricycle.config.yml`.
