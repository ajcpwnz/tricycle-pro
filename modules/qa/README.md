# QA Module

Provides a structured QA testing framework for AI agent and human testers.

## What it includes

- **skills/qa-run/** — Claude Code skill for running QA test suites via MCP
- **templates/** — Starter templates for test plans and agent instructions

## Installation

```bash
npx tricycle-pro add qa
```

This creates:
- `qa/ai-agent-instructions.md` — Operational instructions for the AI agent
- `qa/test-plan-ai-agent.md` — Agent-executable test flows
- `qa/test-plan-human.md` — Human-readable test instructions
- `.claude/skills/qa-run/` — QA runner skill

## Configuration

In `tricycle.config.yml`:

```yaml
qa:
  enabled: true
  primary_tool: "chrome-devtools"   # chrome-devtools | playwright
  fallback_tool: "playwright"
  results_dir: "qa/results-{date}"
  issue_tracker: "linear"           # linear | github | jira | none
```

## QA Testing Block

When `qa.enabled: true`, the assembly pipeline automatically includes a **QA testing block** in the implement step. This block runs between task-execution and push-deploy, ensuring all configured tests pass before code is pushed.

The block:
1. Reads `qa/ai-agent-instructions.md` for setup prerequisites (if the file exists)
2. Runs all `apps[].test` commands from `tricycle.config.yml`
3. Halts on failure (max 3 fix attempts) — does NOT proceed to push
4. Appends testing learnings back to the instructions file

No manual `workflow.blocks.implement.enable` entry is needed — `qa.enabled: true` is sufficient.

You can also enable the block manually without the full qa config:
```yaml
workflow:
  blocks:
    implement:
      enable:
        - qa-testing
```

If no `apps[].test` commands are defined, the block still runs but outputs a warning suggesting you add test commands to your config.

### Halt behavior

If any test fails, the agent attempts to fix and re-run all tests (max 3 attempts). If still failing after 3 attempts, it **halts completely** — it will not proceed to push-deploy. This is the core enforcement: the agent structurally cannot push without passing tests.

### Instructions file

`qa/ai-agent-instructions.md` is a living document. Write your testing prerequisites and operational rules here — Docker setup, dev server startup, environment variables, operational quirks. The agent reads it before running tests.

After each session, the agent appends new discoveries under a dated `## Learnings` section:

```markdown
## Learnings

### 2026-03-30
- Need to run `prisma generate` before backend tests
- Docker compose `--wait` flag avoids manual polling for service readiness
```

The agent reads existing content first to avoid duplicates, and creates the file if it doesn't exist.

## Usage

### QA-run skill (browser-based QA)

In Claude Code:
```
/qa-run              # Run all suites
/qa-run auth polst   # Run specific suites
```

To include the qa-run skill in the implement workflow, add it to your config:
```yaml
workflow:
  blocks:
    implement:
      skills:
        - qa-run
```

Results are written to `qa/results-<date>/results.md` with screenshots.
