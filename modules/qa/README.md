# QA Module

Provides a structured QA testing framework for AI agent and human testers.

## What it includes

- **templates/** — Starter agent instructions for browser QA runs

## Installation

```bash
tricycle add qa
```

This creates:
- `qa/ai-agent-instructions.md` — Operational instructions for the AI agent

## Configuration

In `tricycle.config.yml`:

```yaml
qa:
  enabled: true
  primary_tool: "chrome-devtools"   # chrome-devtools | playwright
  fallback_tool: "playwright"
  results_dir: "qa/results-{date}"
```

## QA Testing Block

When `qa.enabled: true`, the assembly pipeline automatically includes a **QA testing block** in the implement step. It runs after the `test` block and before `version-bump` and `push-deploy`, so all configured tests pass before code is pushed.

The block:
1. Reads `qa/ai-agent-instructions.md` for setup prerequisites (if the file exists)
2. Runs all `apps[].test` commands from `tricycle.config.yml`
3. Repairs and re-runs until every command passes, and stops only for a blocker the user must clear
4. Records new learnings in the instructions file, under their topic

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

### Instructions file

`qa/ai-agent-instructions.md` is a living document. Write your testing prerequisites and operational rules here — Docker setup, dev server startup, environment variables, operational quirks. The agent reads it before running tests.

After each session, the agent adds new discoveries to the section that covers their topic, as one line each, and removes lines that are no longer true.

## Usage

Results are written to `qa/results-<date>/results.md` with screenshots.
