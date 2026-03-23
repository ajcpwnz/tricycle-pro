# Tricycle Pro

AI-driven, spec-first development workflow toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Based on [Spec Kit](https://github.com/mub7865/spec-kit) — an open-source framework for structured, spec-driven AI development. Tricycle Pro packages those patterns into an installable toolkit with slash commands, hooks, templates, and optional modules.

## What It Does

Gives your AI agent structure: **specs before code**, constitutions for consistency, hooks for enforcement, worktrees for isolation, and QA for validation.

```
/specify → /plan → /tasks → /implement → lint/test (enforced by hook)
```

## Quick Start

```bash
npx tricycle-pro init
npx tricycle-pro init --preset monorepo-turborepo
```

## Documentation

See the full workflow guide: **[AI-Assisted Development: A Spec-Driven Workflow](docs/ai-development-workflow.md)**

## License

MIT
