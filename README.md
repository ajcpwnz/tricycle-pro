# Tricycle Pro

AI-driven, spec-first development workflow toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Based on [Spec Kit](https://github.com/github/spec-kit) — an open-source framework for structured, spec-driven AI development. Tricycle Pro packages those patterns into an installable toolkit with slash commands, hooks, templates, and optional modules.

## What It Does

Gives your AI agent structure: **specs before code**, constitutions for consistency, pluggable blocks for customization, worktrees for isolation, and hooks for enforcement.

```
/specify → /plan → /tasks → /implement → lint/test (enforced by hook)
```

The workflow chain is configurable — you can run the full pipeline or skip steps:

```yaml
# tricycle.config.yml
workflow:
  chain: [specify, plan, tasks, implement]   # full (default)
  chain: [specify, plan, implement]          # tasks absorbed into plan
  chain: [specify, implement]                # plan+tasks absorbed into specify
```

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/ajcpwnz/tricycle-pro/main/install.sh | bash

# Initialize a project
tricycle init
tricycle init --preset monorepo-turborepo

# Or with npx
npx tricycle-pro init
```

After init, open Claude Code and run:

```
/trc.specify Add user authentication with OAuth2
```

Or run the full chain in one shot:

```
/trc.headless Add user authentication with OAuth2
```

## Workflow Overview

Every feature flows through a chain of steps. Each step produces structured artifacts that feed the next:

| Step | Command | Input | Output |
|------|---------|-------|--------|
| **Specify** | `/trc.specify` | Natural language description | `spec.md`, quality checklist |
| **Clarify** | `/trc.clarify` | Spec with ambiguities | Updated spec with resolved questions |
| **Plan** | `/trc.plan` | Spec | `plan.md`, `research.md`, `data-model.md`, `contracts/` |
| **Tasks** | `/trc.tasks` | Plan + spec | `tasks.md` (dependency-ordered, phased) |
| **Implement** | `/trc.implement` | Tasks + plan | Working code, tests, version bump |
| **Headless** | `/trc.headless` | Description | All of the above in one invocation |

Additional commands: `/trc.analyze` (consistency audit), `/trc.checklist` (quality checklists), `/trc.constitution` (project principles), `/trc.taskstoissues` (GitHub issue creation).

## Blocks & Steps

Each workflow step's behavior is composed from **blocks** — pluggable partial system prompts. Blocks let you customize what each step does without editing command files.

### How It Works

1. Block files live in `core/blocks/{step}/` — each is a markdown file with YAML frontmatter
2. `tricycle assemble` reads your chain + block config and generates command files
3. Claude Code reads the assembled command files (static, zero runtime overhead)

### Block Inventory

**Specify** (5 default blocks):

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `feature-setup` | 10 | yes | Create feature branch via `create-new-feature.sh` |
| `chain-validation` | 20 | yes | Validate step is in configured chain |
| `input-validation` | 30 | yes | Validate prompt detail for chain length |
| `spec-writer` | 40 | no | Generate spec content (scenarios, requirements, criteria) |
| `quality-validation` | 50 | no | Quality checklist and validation loop |

**Plan** (7 default blocks):

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `chain-validation` | 10 | yes | Validate step is in configured chain |
| `setup-context` | 20 | yes | Run setup script, load spec + constitution |
| `constitution-check` | 30 | no | Constitution compliance gate |
| `research` | 40 | no | Phase 0: research unknowns, generate `research.md` |
| `design-contracts` | 50 | no | Phase 1: data model, contracts, quickstart |
| `agent-context` | 60 | no | Update AI agent context files |
| `version-awareness` | 70 | no | Version bump planning |

**Tasks** (4 default blocks):

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `chain-validation` | 10 | yes | Validate step is in configured chain |
| `prerequisites` | 20 | yes | Validate feature directory and docs |
| `task-generation` | 30 | no | Generate tasks organized by user story |
| `dependency-graph` | 40 | no | Dependency ordering and parallel markers |

**Implement** (6 default blocks):

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `chain-validation` | 10 | yes | Validate step is in configured chain |
| `prerequisites` | 20 | yes | Pre-execution checks |
| `checklist-validation` | 30 | no | Gate on incomplete checklists |
| `project-setup` | 40 | no | Verify/create ignore files per tech stack |
| `task-execution` | 50 | no | Execute tasks phase by phase with TDD |
| `version-bump` | 60 | no | Bump VERSION after completion |

### Optional Blocks

Not enabled by default — opt in via config:

| Block | Step | Order | Description |
|-------|------|-------|-------------|
| `worktree-setup` | specify | 5 | Create git worktree before spec work |
| `test-local-stack` | implement | 45 | Test against local infrastructure |
| `worktree-cleanup` | implement | 70 | Suggest worktree cleanup after merge |

### Customizing Blocks

```yaml
# tricycle.config.yml
workflow:
  chain: [specify, plan, tasks, implement]
  blocks:
    plan:
      disable:
        - design-contracts      # skip contract generation
    implement:
      enable:
        - test-local-stack      # add local stack testing
      custom:
        - .specify/blocks/custom/security-review.md  # your own block
    specify:
      enable:
        - worktree-setup        # worktree-cleanup auto-enabled via companion
```

After changing config, run `tricycle assemble` to regenerate command files.

### Companion Blocks

Some blocks are paired — enabling one auto-enables its companion. For example, enabling `worktree-setup` in specify automatically enables `worktree-cleanup` in implement. Declared via the `companions` frontmatter field.

### Chain Absorption

When steps are omitted from the chain, their blocks merge into the preceding step:

- `[specify, plan, implement]` — tasks blocks (task-generation, dependency-graph) absorbed into plan
- `[specify, implement]` — plan blocks + tasks blocks absorbed into specify

The AI doesn't know about absorption — it just follows the assembled prompt which includes the absorbed instructions.

### Block File Format

```markdown
---
name: my-block
step: implement
description: What this block does
required: false
default_enabled: false
order: 45
companions: implement:other-block  # optional
---

## Block Instructions

Your prompt instructions here. This content becomes part of the
assembled command file that Claude Code follows.
```

## CLI Commands

```bash
tricycle init [--preset <name>]     # Initialize project
tricycle add <module>               # Add module (worktree, qa, ci-watch, mcp, memory)
tricycle assemble [--dry-run]       # Assemble commands from blocks
tricycle generate <target>          # Generate files (claude-md, settings, mcp)
tricycle update [--dry-run]         # Update core files
tricycle update-self                # Update CLI itself
tricycle validate                   # Validate configuration
```

## Configuration

`tricycle.config.yml` at project root:

```yaml
project:
  name: my-project
  type: single-app              # or monorepo
  package_manager: npm          # npm, bun, yarn, pnpm
  base_branch: main

apps:
  - name: web
    path: "."
    type: web
    lint: "npm run lint"
    test: "npm test"

workflow:
  chain: [specify, plan, tasks, implement]
  blocks:
    # per-step overrides (see Blocks & Steps)

worktree:
  enabled: false
  path_pattern: "../{project}-{branch}"

push:
  require_approval: true
  require_lint: true
  require_tests: true
  pr_target: main
  merge_strategy: squash

constitution:
  root: .specify/memory/constitution.md
```

## Presets

```bash
tricycle init --preset <name>
```

| Preset | Description |
|--------|-------------|
| `single-app` | Minimal single-app project |
| `nextjs-prisma` | Next.js + Prisma + PostgreSQL with worktree isolation |
| `express-prisma` | Express API + Prisma + PostgreSQL with worktree isolation |
| `monorepo-turborepo` | Turborepo monorepo with Bun, QA, deployment workflows |

## Modules

```bash
tricycle add <module>
```

| Module | Description |
|--------|-------------|
| `worktree` | Git worktree support with per-branch DB isolation |
| `qa` | QA testing (Chrome DevTools, Playwright) |
| `ci-watch` | CI pipeline monitoring |
| `mcp` | Model Context Protocol server presets |
| `memory` | Agent memory persistence via seeds |

## Project Structure

```
tricycle-pro/
├── bin/
│   ├── tricycle              # CLI entry point
│   └── lib/                  # CLI libraries (yaml, json, helpers, templates, assembly)
├── core/
│   ├── blocks/               # Block source files (the "what each step does")
│   │   ├── specify/          # 5 blocks
│   │   ├── plan/             # 7 blocks
│   │   ├── tasks/            # 4 blocks
│   │   ├── implement/        # 6 blocks
│   │   └── optional/         # Opt-in blocks (worktree, test-local-stack)
│   ├── commands/             # Assembled command files (generated by tricycle assemble)
│   ├── hooks/                # Enforcement hooks (lint gate, branch protection)
│   ├── scripts/bash/         # Shared scripts (common.sh, assembly, feature creation)
│   ├── skills/               # Skill modules
│   └── templates/            # Spec, plan, tasks, checklist templates
├── modules/                  # Optional modules (worktree, qa, ci-watch, mcp, memory)
├── presets/                  # Starter configs (single-app, nextjs-prisma, etc.)
├── generators/               # CLAUDE.md section templates
├── docs/                     # Workflow guide
└── specs/                    # Dogfooding artifacts (see below)
```

## Dogfooding

Tricycle Pro is built with itself. Every feature goes through the same `/specify → /plan → /tasks → /implement` chain that ships to users. The `specs/` directory contains the real artifacts:

**[`001-headless-mode`](specs/001-headless-mode/)** — Added `/trc.headless` for single-command workflow execution. JavaScript/Node.js implementation with `node:test`. Full artifact set: spec, plan, research, data model, contracts, tasks, checklist.

**[`002-shell-only-cli`](specs/002-shell-only-cli/)** — Rewrote the CLI as pure Bash with zero npm/Node.js dependencies. Defined CLI interface contracts and migration strategy from the Node.js version.

**[`003-workflow-chains-blocks`](specs/003-workflow-chains-blocks/)** — The blocks and chains system itself. Decomposed all commands into 22 pluggable blocks, added configurable workflow chains, build-time assembly, and companion blocks. Includes config schema, block format, and assembly CLI contracts.

This means:

- **Templates are battle-tested.** Every template has been used to build real features.
- **Hooks catch real problems.** The lint/test gate and push approval hooks run on every contribution.
- **The workflow scales.** A single-command feature and a full architecture rewrite both flow through the same pipeline.
- **Blocks are proven.** The block decomposition was done on the toolkit's own commands — they're not theoretical.

Browse `specs/` to see what the workflow produces in practice.

## Documentation

Full workflow guide: **[AI-Assisted Development: A Spec-Driven Workflow](docs/ai-development-workflow.md)**

## License

MIT
