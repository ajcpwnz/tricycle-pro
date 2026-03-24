# CI Watch Module

Monitors GitHub Actions CI and deploy workflows, waiting for completion and diagnosing failures.

## What it includes

- **commands/wait-ci.md** -- Slash command to poll CI status until all checks pass or fail
- **skills/deploy-watch/** -- Skill to monitor deploy workflows after merging to staging

## Installation

```bash
npx tricycle-pro add ci-watch
```

## Usage

In Claude Code:

```
/wait-ci           # Poll CI for current branch
/wait-ci 123       # Poll CI for PR #123
```

The `wait-ci` command polls every 15 seconds (max 20 iterations), checks for merge conflicts,
and on failure fetches logs to diagnose the error. The deploy-watch skill monitors post-merge
deploy workflows and reports success or failure with log diagnosis.

## Requirements

- GitHub CLI (`gh`) must be installed and authenticated
- GitHub MCP server recommended for richer integration
