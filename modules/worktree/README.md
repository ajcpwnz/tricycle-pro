# Worktree Module

Provides git worktree isolation for parallel feature development.

## What it includes

- **scripts/cleanup-worktree.sh** — Remove worktrees and their per-branch databases
- **scripts/worktree-db-setup.sh** — Create per-worktree database and copy .env files
- **adapters/** — Database-specific isolation logic (postgres, mysql, sqlite)

## Configuration

In `tricycle.config.yml`:

```yaml
worktree:
  enabled: true
  env_copy:                                # .env files to copy from main checkout
    - apps/backend/.env
    - apps/frontend/.env
  setup_script: scripts/worktree-db-setup.sh
```

## Database adapters

The `adapters/` directory contains database-specific scripts for creating and dropping
per-worktree databases. The `worktree-db-setup.sh` script sources the appropriate adapter
based on the `database.type` in your app config.

Supported: `postgres`, `mysql`, `sqlite`

## How it works

1. With `worktree.enabled: true`, `/trc.implement` creates a worktree beside the main checkout before it starts work, installs dependencies and runs `setup_script`
2. Each worktree gets its own database (named from the branch) so migrations don't conflict
3. After merging, `cleanup-worktree.sh` removes the worktree directory, database, and branch
