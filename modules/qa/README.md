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

## Usage

In Claude Code:
```
/qa-run              # Run all suites
/qa-run auth polst   # Run specific suites
```

Results are written to `qa/results-<date>/results.md` with screenshots.
