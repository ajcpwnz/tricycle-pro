# Worktree Module

Provides git worktree isolation for parallel feature development.

## What it includes

- **hooks/worktree-on-specify.sh** — Enforces worktree creation before `/trc.specify`
- **scripts/cleanup-worktree.sh** — Remove worktrees and their per-branch databases
- **scripts/worktree-db-setup.sh** — Create per-worktree database and copy .env files
- **adapters/** — Database-specific isolation logic (postgres, mysql, sqlite)

## Configuration

In `tricycle.config.yml`:

```yaml
worktree:
  enabled: true
  path_pattern: "../{project}-{branch}"   # Where worktrees are created
  db_isolation: true                       # Per-branch databases
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

1. When you run `/trc.specify`, the `worktree-on-specify.sh` hook detects you're in the main checkout
2. It creates a new worktree at the configured path pattern
3. You `cd` into the worktree, run package install, and set up the database
4. Each worktree gets its own database (named from the branch) so migrations don't conflict
5. After merging, `cleanup-worktree.sh` removes the worktree directory, database, and branch
