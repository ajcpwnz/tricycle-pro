# Tricycle Pro

AI-driven, spec-first development workflow toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Based on [Spec Kit](https://github.com/github/spec-kit) — an open-source framework for structured, spec-driven AI development. Tricycle Pro packages those patterns into an installable toolkit with slash commands, hooks, templates, and optional modules.

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

## Built With Itself

Tricycle Pro is developed using its own workflow. Every feature — including the toolkit itself — goes through the same `/specify → /plan → /tasks → /implement` chain that it provides to users.

The [`specs/`](specs/) directory contains the real spec artifacts from building Tricycle Pro features. For example, the [`001-headless-mode`](specs/001-headless-mode/) feature was built entirely through the Tricycle Pro pipeline: a natural language description became a structured spec, then a technical plan with research and contracts, then a dependency-ordered task list, and finally working code — all enforced by the same hooks and constitution that ship with the toolkit.

This means:
- **The templates are battle-tested.** Every spec, plan, and task template has been used to build real features, not just written as documentation.
- **The hooks catch real problems.** The lint/test gate and push approval hooks run on every Tricycle Pro contribution.
- **The workflow scales down.** A single-file feature like `/trc.headless` and a multi-module audit both flow through the same pipeline.

If you want to see what the workflow produces in practice, browse the [`specs/`](specs/) directory — those are the actual artifacts, not examples.

## Documentation

See the full workflow guide: **[AI-Assisted Development: A Spec-Driven Workflow](docs/ai-development-workflow.md)**

## License

MIT
