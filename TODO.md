# TODO

## Building Blocks for Different Project Types
- [ ] Define project type templates (e.g., Node.js, Python, Go, monorepo)
- [ ] Create composable block system — mix and match lint, test, deploy configs per type
- [ ] Support custom project type definitions via config
- [ ] Ship sensible defaults for common stacks (React, Express, FastAPI, etc.)

## Stage Hooks
- [ ] Design hook lifecycle stages (pre-spec, post-spec, pre-plan, post-plan, pre-implement, post-implement, etc.)
- [ ] Allow user-defined hooks per stage (shell scripts, node scripts)
- [ ] Support hook chaining and conditional execution
- [ ] Add built-in hooks for common tasks (lint, test, format)

## Interactive Installation
- [ ] Build CLI installer (`npx tricycle-pro init` or similar)
- [ ] Prompt for project type selection
- [ ] Prompt for which stages/hooks to enable
- [ ] Auto-detect existing tooling and suggest matching blocks
- [ ] Generate initial `tricycle.config.yml` from user choices
- [ ] Support non-interactive mode with flags for CI/scripting

## Bugs / Issues
- [ ] `check-prerequisites.sh` script missing — `.trc/scripts/bash/check-prerequisites.sh` does not exist (exit code 127). Need to either create the script or remove the reference.
- [ ] Write hook blocks spec file creation on `main` even when the branch was already created by the script — hook doesn't detect that a worktree branch exists and should either auto-switch or give a more actionable error
