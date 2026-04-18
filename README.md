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
| **Audit** | `/trc.audit` | File scope + criteria | `docs/audits/audit-*.md` report |
| **Headless** | `/trc.headless` | Description | All of the above in one invocation |

Additional commands: `/trc.analyze` (consistency audit), `/trc.checklist` (quality checklists), `/trc.constitution` (project principles), `/trc.taskstoissues` (GitHub issue creation).

### Audit

`/trc.audit` evaluates scoped files against the project constitution, a custom prompt, or common-sense best practices.

```bash
/trc.audit src/                          # audit src/ against constitution
/trc.audit --feature TRI-42             # audit files changed in a feature branch
/trc.audit --prompt "check for XSS"     # custom criteria
```

Reports are saved to `docs/audits/audit-YYYY-MM-DD-<summary>.md`. Configured output skills (e.g., `linear-audit`) can route findings to external systems like Linear.

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

**Implement** (7 default blocks):

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `chain-validation` | 10 | yes | Validate step is in configured chain |
| `prerequisites` | 20 | yes | Pre-execution checks |
| `checklist-validation` | 30 | no | Gate on incomplete checklists |
| `project-setup` | 40 | no | Verify/create ignore files per tech stack |
| `task-execution` | 50 | no | Execute tasks phase by phase with TDD |
| `version-bump` | 60 | no | Bump VERSION after completion |
| `push-deploy` | 65 | no | Push, create PR, merge, and artifact cleanup |

### Optional Blocks

Not enabled by default — opt in via config:

| Block | Step | Order | Description |
|-------|------|-------|-------------|
| `worktree-setup` | specify | 5 | Create git worktree before spec work |
| `catholic` | specify | 8 | Prayer and blessing wrapper for non-code artifacts |
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
        - .trc/blocks/custom/security-review.md  # your own block
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

### Creating Your Own Blocks

Blocks are markdown files with YAML frontmatter. The body is a prompt — instructions that the AI agent follows during that workflow step.

**1. Create the file:**

```bash
# Project-local custom block
mkdir -p .trc/blocks/custom
cat > .trc/blocks/custom/security-review.md << 'EOF'
---
name: security-review
step: implement
description: Run security review before push
required: false
default_enabled: false
order: 55
---

## Security Review

Before marking implementation complete, review all changes for:

1. **Input validation**: Check all user inputs are sanitized
2. **Auth boundaries**: Verify no endpoints are accidentally public
3. **Secrets**: Confirm no credentials are hardcoded or committed

If any issue is found, fix it before proceeding.
EOF
```

**2. Enable it in config:**

```yaml
# tricycle.config.yml
workflow:
  blocks:
    implement:
      custom:
        - .trc/blocks/custom/security-review.md
```

**3. Reassemble:**

```bash
tricycle assemble
```

Your block is now part of the implement step, ordered at 55 (between task-execution and version-bump).

### Block Authoring Guide

**Frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique identifier (kebab-case) |
| `step` | yes | Which workflow step: `specify`, `plan`, `tasks`, or `implement` |
| `description` | yes | One-line summary |
| `required` | yes | `true` blocks cannot be disabled |
| `default_enabled` | yes | `true` = active without config, `false` = opt-in |
| `order` | yes | Execution order within the step (lower = earlier) |
| `companions` | no | Auto-enable another block, e.g. `implement:my-cleanup` |

**Writing the body:**

- Write in imperative voice ("Read the config", "Check for conflicts")
- Use numbered steps for sequential actions
- Use `**HALT**` or `**STOP**` for gates where the agent must wait
- Reference config values by their `tricycle.config.yml` path (e.g., `push.pr_target`)
- The agent sees the assembled markdown — it has no runtime, no variables, no templating. Everything is a prompt instruction.

**Order spacing convention:**

| Range | Purpose |
|-------|---------|
| 10-20 | Validation and prerequisites |
| 30-40 | Setup and preparation |
| 45-55 | Core execution |
| 60-70 | Post-execution (version bump, push, cleanup) |

Leave gaps between your blocks so others can slot in between.

### Contributing Blocks

Built a block that others might find useful? We accept contributions to `core/blocks/optional/`:

1. Place the block in `core/blocks/optional/{step}/your-block.md`
2. Set `default_enabled: false` (opt-in only)
3. Add a row to the Optional Blocks table in this README
4. Add test coverage in `tests/run-tests.sh` (block file exists) and `tests/test-block-assembly.js` (assembles correctly when enabled)
5. Open a PR

Blocks in `core/blocks/optional/` ship with the toolkit but are inactive unless enabled in config. This keeps the default workflow lean while making community blocks discoverable.

### Catholic Block & Skill

Tricycle Pro ships with an optional **catholic** block and skill that infuse non-code artifacts with reverent, faith-inspired Christian verbiage — blessings, gratitude, and references to divine guidance.

**What it does**:
- The **catholic skill** (`/catholic`) guides Claude to use reverent language in specs, plans, tasks, and READMEs
- The **catholic block** fires at the start of the specify step with a prayer for the feature's success and closes with a blessing
- Source code, tests, and config files are never affected

**Enable it**:

```yaml
# tricycle.config.yml
workflow:
  blocks:
    specify:
      enable:
        - catholic
      skills:
        - catholic
```

Then run `tricycle assemble` to rebuild commands.

**Disable it**: Remove `catholic` from the `enable` and `skills` lists, then `tricycle assemble`.

## Skills

Skills are pluggable prompt modules that provide specialized capabilities during workflow steps. They are installed to `.claude/skills/` and invoked conditionally — if a skill isn't installed, it's silently skipped.

| Skill | Description |
|-------|-------------|
| `catholic` | Reverent, faith-inspired verbiage for non-code artifacts |
| `code-reviewer` | Structured PR review: correctness, security, performance, maintainability |
| `debugging` | Reproduce-isolate-trace-fix-verify debugging workflow |
| `document-writer` | Generate DOCX, PDF, PPTX, and other formatted documents |
| `linear-audit` | Route audit findings to Linear as issues |
| `tdd` | Red-Green-Refactor test-driven development workflow |

Configure skills per workflow step:

```yaml
# tricycle.config.yml
workflow:
  blocks:
    implement:
      skills:
        - code-reviewer
        - tdd
    specify:
      skills:
        - document-writer
```

Then run `tricycle assemble` to regenerate commands.

## SessionStart Hook

The SessionStart hook auto-injects the project constitution and configured context files into Claude's context at the start of every session — no manual command needed.

```yaml
# tricycle.config.yml
context:
  session_start:
    constitution: true              # inject constitution (default: true)
    files:                          # additional files to inject
      - docs/architecture.md
      - .trc/memory/decisions.md
```

Run `tricycle generate settings` to wire up the hook. It writes `.claude/hooks/.session-context.conf` and registers the hook in `.claude/settings.json`. Files that don't exist or contain only placeholder content are silently skipped.

## CLI Commands

```bash
tricycle init [--preset <name>]     # Initialize project
tricycle add <module>               # Add module (worktree, qa, ci-watch, mcp, memory)
tricycle assemble [--dry-run]       # Assemble commands from blocks
tricycle generate <target>          # Generate files (claude-md, settings, mcp)
tricycle skills list                # List installed skills and their status
tricycle update [--dry-run]         # Update core files
tricycle update-self                # Update CLI itself
tricycle validate                   # Validate configuration
tricycle graphify <sub>             # Manage optional graphify integration
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
  root: .trc/memory/constitution.md

context:
  session_start:
    constitution: true            # inject constitution on session start (default)
    files: []                     # additional files to inject
```

## Local Config Overrides

Create `tricycle.config.local.yml` in your project root to override a subset of config fields per-developer, without modifying the shared `tricycle.config.yml`.

```yaml
# tricycle.config.local.yml
qa:
  enabled: true

push:
  require_approval: false

worktree:
  enabled: true
```

### How It Works

1. `load_config()` detects `tricycle.config.local.yml` and merges it over the base config at runtime
2. Only whitelisted prefixes can be overridden: `push.`, `qa.`, `worktree.`, `workflow.blocks.`, `stealth.`
3. Non-overridable keys (e.g., `project.name`) emit a warning and are ignored
4. The override file is automatically gitignored in both normal and stealth modes

### Assembly Two-Pass Strategy

When an override file exists, `tricycle assemble` runs two passes:

1. **Pass 1** (base config) generates `.claude/commands/` — committed, identical for all developers
2. **Pass 2** (merged config) generates `.trc/local/commands/` — gitignored, reflects local overrides

The session-context hook detects `.trc/local/commands/` and instructs Claude to prefer local command variants when available.

### Overridable Fields

| Prefix | Example Keys |
|--------|-------------|
| `push.` | `push.require_approval`, `push.require_tests` |
| `qa.` | `qa.enabled`, `qa.suites` |
| `worktree.` | `worktree.enabled`, `worktree.path_pattern` |
| `workflow.blocks.` | `workflow.blocks.implement.enable` |
| `stealth.` | `stealth.enabled` |

### Graceful Degradation

- Missing override file: no effect, no warning
- Empty override file: no effect, no warning
- Unreadable or invalid YAML: warning emitted, base config used
- Non-overridable keys: per-key warning with list of valid sections

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

## Graphify Integration (optional)

[Graphify](https://github.com/safishamsi/graphify) is a separately-distributed
skill + PyPI package (`graphifyy`) that builds a persistent, queryable knowledge
graph of your repo. When enabled, tricycle:

1. **Refreshes the graph automatically** at every `/trc.specify`, `/trc.chain`,
   or `/trc.headless` kickoff (fire-and-forget, cached — no-op is cheap when
   nothing changed).
2. **Registers a per-chain MCP entry** in `.mcp.json` at `/trc.chain` start,
   so worker sub-agents' Claude Code hosts spawn the graphify MCP stdio
   server on demand and workers can query architectural context via tools
   instead of re-reading the tree.
3. **Pipes graph context into every worker's brief** — GRAPH_REPORT.md excerpt,
   MCP PID, guidance on when to query vs skip.

All disabled by default. **Zero impact on upgrade** — when the flag is off, the
hook is a silent no-op and the chain integration is skipped entirely.

### Quickstart

```bash
tricycle graphify install               # pip install graphifyy
tricycle graphify bootstrap             # first-time `graphify .` on the repo
# Then flip the flag in tricycle.config.yml:
#   integrations:
#     graphify:
#       enabled: true
tricycle generate settings              # re-register the kickoff hook
```

### Config

```yaml
integrations:
  graphify:
    enabled: false            # master switch — required for any of the below
    auto_install: false       # let the hook `pip install graphifyy` if missing
    auto_bootstrap: false     # let the hook run first-time `graphify .`
    refresh_on_kickoff: true  # async `graphify . --update` at every kickoff
    mcp_per_chain: true       # spawn `graphify --mcp` per `/trc.chain` run
```

### Commands

```bash
tricycle graphify status [--json]       # show install/graph/mcp state
tricycle graphify install               # pip install graphifyy
tricycle graphify bootstrap             # first-time graph build
tricycle graphify refresh               # async --update (hook uses this)
tricycle graphify mcp-start [--run-id X]   # register graphify in .mcp.json
tricycle graphify mcp-stop  [--run-id X]   # unregister graphify from .mcp.json
```

### Troubleshooting

- **Hook silently did nothing** — check `tricycle graphify status`. If
  `installed: false`, either run `tricycle graphify install` or set
  `auto_install: true`. If `graph: false`, run `tricycle graphify bootstrap`
  or set `auto_bootstrap: true`.
- **Refresh log** — every async refresh writes to `graphify-out/.refresh.log`
  and stores the PID in `graphify-out/.refresh.pid`.
- **MCP registration** — `tricycle graphify status` shows whether `.mcp.json`
  has a `graphify` entry. Your Claude Code host spawns the stdio server
  on demand when workers first call a graphify tool.
- **Stale graph after bulk code changes** — run `tricycle graphify refresh`
  manually; don't trust nodes after you've rewritten large swaths of the tree.
- **macOS Homebrew Python** — `install` falls back to
  `--break-system-packages`. If you'd rather keep the system Python clean,
  install graphify into a venv and put its `graphify` shim on your PATH
  before invoking tricycle.

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
│   │   ├── implement/        # 7 blocks
│   │   └── optional/         # Opt-in blocks (worktree, catholic, test-local-stack)
│   ├── commands/             # Assembled command files (generated by tricycle assemble)
│   ├── hooks/                # Enforcement hooks (lint gate, branch protection, session context)
│   ├── scripts/bash/         # Shared scripts (common.sh, assembly, feature creation)
│   ├── skills/               # Skill modules (catholic, code-reviewer, debugging, etc.)
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

**[`003-workflow-chains-blocks`](specs/003-workflow-chains-blocks/)** — The blocks and chains system itself. Decomposed all commands into 22 pluggable blocks, added configurable workflow chains, build-time assembly, and companion blocks.

Browse `specs/` for additional feature artifacts (skills system, audit command, session hooks, and more).

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
