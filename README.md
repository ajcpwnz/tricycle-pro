# Tricycle Pro

AI-driven, spec-first development workflow toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Tricycle Pro gives Claude Code two commands. `/trc.plan` writes or revalidates one compact spec. `/trc.implement` starts only after an independent validator passes that spec, then works its checklist to the end.

## What It Does

trc is opt-in. A developer who never runs a trc command still works with the project's rules, because `CLAUDE.md` and the constitution load in every Claude Code session. The commands add the strict process on top.

```
/trc.plan <request | ticket | spec>   →   spec (analysis, proposed solution, checklist), validated
/trc.implement <spec>                 →   validation gate → work the checklist → lint/test → ship
```

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/ajcpwnz/tricycle-pro/main/install.sh | bash

# Initialize a project
tricycle init
tricycle init --preset monorepo-turborepo
```

After init, open Claude Code and run:

```
/trc.plan Add user authentication with OAuth2
/trc.implement add-user-authentication
```

## Workflow Overview

| Command | Input | What it does |
|---------|-------|--------------|
| `/trc.plan` | A request, a ticket id or URL, or a spec file | New work: enters plan mode (unless trivial), researches the code and the rules, writes the spec, validates it, stores it. An existing spec or a filled ticket is revalidated and fixed, never rewritten. |
| `/trc.implement` | A spec id, ticket, or spec file | Validates the spec and stops on failure. Then works in a worktree (if configured), works the checklist item by item with proof, runs lint and tests, bumps the version and ships. |
| `/trc.audit` | File scope + criteria | `docs/audits/audit-*.md` report |
| `/trc.constitution` | Principles | Project constitution |

### The spec

One file, three parts (`core/templates/spec-template.md`):

- **Analysis:** the problem, current behavior with `path:line` references, constraints, out of scope.
- **Proposed Solution:** the approach, decisions with the alternatives they beat, risks.
- **Checklist:** one line per outcome, each naming its proof. Outcomes, not edit instructions.

Where it lives is set by `spec.store`:

```yaml
spec:
  store: repo        # repo: <spec.dir>/<id>.md, committed with the work
                     # linear: the ticket description is the spec
  dir: docs/specs
```

### Validation

The `trc-spec-validator` agent (installed to `.claude/agents/`) reads the spec and the code with no context from the session that wrote it, and returns PASS or FAIL. It checks:

- **Truthfulness:** every `path:line`, named file, function or behavior claim against the code.
- **Ambiguity:** anything two engineers would build differently, and any open question.
- **Quality:** cause over symptom, compliance with `CLAUDE.md` and the constitution, provable checklist lines that cover the whole solution.

`/trc.plan` fixes findings and asks the user what only the user can settle. `/trc.implement` never fixes the spec: on FAIL it stops and points to `/trc.plan`.

### Writing style (optional)

Two plugins set the register, and trc wires them in only when they are installed:

| Where | Style | Plugin | How trc applies it |
|-------|-------|--------|--------------------|
| Chat | `ultracave` (terse fragments, payload only) | [caveman](https://github.com/JuliusBrussee/caveman) | `style.chat` writes `.caveman.json`. The plugin injects its rules at session start, after compaction, on every turn and into every subagent. |
| Persisted prose: docs, specs, commits, PR bodies, tickets | Short ASD-STE100 (the `ste-short` skill) | [asd-ste100](https://github.com/danyuchn/asd-ste100-skill) | `style.artifacts: ste-short` registers `style-gate.sh`. It lints the added prose with the plugin's linter and blocks on a hard finding. Commit messages follow the skill but are not gated. |

Without a plugin, its part does nothing: `.caveman.json` is inert and `style-gate.sh` exits 0. A chat style is advice to the model. The artifact gate is a check the model cannot skip.

### Models and workers

`/trc.implement` hands self-contained checklist items and long test runs to worker subagents. The workers report back the diff summary and the evidence, so the main context stays slim. It re-checks every worker's proof itself before marking an item done.

```yaml
models:              # Claude Code aliases: fable, opus, sonnet, haiku
  plan: fable        # /trc.plan (default fable)
  implement: opus    # /trc.implement (default opus)
  workers: opus      # implement's worker subagents (default opus)
  validator: opus    # trc-spec-validator (default opus)
```

### Orchestrators

Both run `/trc.plan` then `/trc.implement` for each ticket, unattended. A spec that passes the validator counts as approved. A worker stops only for input that only the user holds.

Two commands run the workflow across multiple tickets instead of one:

| Command | Shape | Execution | Push policy |
|---------|-------|-----------|-------------|
| `/trc.chain TRI-100..TRI-105` | Flat range/list of 2–8 tickets | Up to `chain.max_parallel` (default 2) workers at a time. A ticket that another ticket in the run blocks starts after its blocker | Approval per ticket |
| `/trc.band TRI-200` | One parent issue broken into sub-issues | Parallel step-controlled workers in dependency waves | One approval for the whole epic |

`/trc.band` takes a parent Linear issue and fetches its sub-issues. It writes a codebase recon into `specs/.band-runs/<run-id>/recon.md`: a high-level epic spec from `recon-template.md`. The recon holds a dependency roadmap: waves of parallel-safe sub-issues, a complexity rating, and a worker model for each sub-issue.

After the user approves the recon, the band starts background worker agents, up to `band.max_parallel` (default 3). Each worker runs in its own git worktree and runs plan, then implement, **one step at a time**. Every step reports back. The orchestrator reviews the step and issues the next one, with any concerns folded in.

Workers never pause. A real ambiguity comes back as a structured `blocked` report, the whole band pauses, and the band asks the user. Completed branches merge locally into an integration branch (`band/<PARENT-ID>`) in roadmap order, with a rebase on conflict (2 rounds at most). Nothing is pushed until the epic is done and fully verified. Then there is one approval gate, one push and one epic PR.

### Audit

`/trc.audit` evaluates scoped files against the project constitution, a custom prompt, or common-sense best practices.

```bash
/trc.audit src/                          # audit src/ against constitution
/trc.audit --feature TRI-42             # audit files changed in a feature branch
/trc.audit --prompt "check for XSS"     # custom criteria
```

Reports are saved to `docs/audits/audit-YYYY-MM-DD-<summary>.md`. Configured output skills (e.g., `linear-audit`) can route findings to external systems like Linear.

## Blocks

Each command is assembled from **blocks**: markdown files with YAML frontmatter whose bodies are prompt text. `tricycle assemble` (also run by `tricycle update`) writes `.claude/commands/trc.plan.md` and `trc.implement.md` from them.

### Block Inventory

**Plan:**

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `resolve-input` | 10 | yes | New work, or an existing spec to revalidate |
| `plan-mode` | 15 | no | Enter Claude Code plan mode unless the work is trivial |
| `graphify-context` | 25 | no | Graphify briefing (runtime gate) |
| `research` | 30 | yes | Ground the spec in the code and the rules |
| `write-spec` | 40 | yes | Fill the spec template |
| `validate` | 50 | yes | Validator loop: fix, ask, revalidate |
| `store-spec` | 60 | yes | Write to the repo or the tracker |

**Implement:**

| Block | Order | Required | Description |
|-------|-------|----------|-------------|
| `load-spec` | 10 | yes | Load the spec named by the input |
| `validate-gate` | 15 | yes | Refuse to start on a failing spec |
| `graphify-context` | 25 | no | Graphify briefing (runtime gate) |
| `execute` | 30 | yes | Work the checklist, proving each item |
| `test` | 40 | yes | Configured lint and test until green |
| `version-bump` | 60 | no | Bump VERSION |
| `push-deploy` | 65 | no | Push, PR, merge |

### Optional Blocks

| Block | Step | Order | Enabled by |
|-------|------|-------|------------|
| `catholic` | plan | 1 | `workflow.blocks.plan.enable` |
| `worktree-setup` | implement | 20 | `worktree.enabled: true` |
| `test-local-stack` | implement | 45 | `workflow.blocks.implement.enable` |
| `qa-testing` | implement | 55 | `qa.enabled: true` |
| `worktree-cleanup` | implement | 70 | `worktree.enabled: true` |

### Customizing Blocks

```yaml
# tricycle.config.yml
workflow:
  blocks:
    plan:
      disable:
        - plan-mode             # required blocks cannot be disabled
    implement:
      enable:
        - test-local-stack
      custom:
        - .trc/blocks/custom/security-review.md  # your own block
```

After changing config, run `tricycle assemble` to regenerate the command files.

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

Your block is now part of the implement command, at order 55: after `test` (40) and before `version-bump` (60).

### Block Authoring Guide

**Frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique identifier (kebab-case) |
| `step` | yes | Which command: `plan` or `implement` |
| `description` | yes | One-line summary |
| `required` | yes | `true` blocks cannot be disabled |
| `default_enabled` | yes | `true` = active without config, `false` = opt-in |
| `order` | yes | Execution order within the step (lower = earlier) |

**Writing the body:**

- Write in imperative voice ("Read the config", "Check for conflicts")
- Use numbered steps for sequential actions
- Use `**STOP**` for gates where the agent must wait
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
4. Add test coverage in `tests/test-assemble-commands.sh`: the block appears, in order, when enabled
5. Open a PR

Blocks in `core/blocks/optional/` ship with the toolkit but are inactive unless enabled in config. This keeps the default workflow lean while making community blocks discoverable.

### Catholic Block & Skill

Tricycle Pro ships an optional **catholic** block and skill. They add reverent Christian wording to non-code artifacts: blessings, gratitude, and references to divine guidance.

**What it does**:
- The **catholic skill** (`/catholic`) guides Claude to use reverent language in specs and READMEs.
- The **catholic block** opens the plan command with a prayer for the feature's success and closes it with a blessing.
- Source code, tests and config files are never affected.

**Enable it**:

```yaml
# tricycle.config.yml
workflow:
  blocks:
    plan:
      enable:
        - catholic
```

Then run `tricycle assemble` to rebuild the commands. To turn it off, remove `catholic` from the list and run `tricycle assemble` again.

## Skills

Skills are prompt modules in `.claude/skills/`. Claude Code reads each skill's description and invokes the skill when the work fits it. `skills.disable` in `tricycle.config.yml` keeps a core skill from being installed.

| Skill | Description |
|-------|-------------|
| `catholic` | Reverent, faith-inspired verbiage for non-code artifacts |
| `code-reviewer` | Structured PR review: correctness, security, performance, maintainability |
| `debugging` | Reproduce-isolate-trace-fix-verify debugging workflow |
| `document-writer` | Generate DOCX, PDF, PPTX, and other formatted documents |
| `linear-audit` | Route audit findings to Linear as issues (`/trc.audit --linear`) |
| `ste-short` | Short ASD-STE100 rules for persisted prose |
| `tdd` | Red-Green-Refactor test-driven development workflow |

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
tricycle generate <target>          # Generate files (claude-md, settings, mcp, gitignore)
tricycle skills list                # List installed skills and their status
tricycle status [<spec id>] [--json]  # Spec status and checklist progress
tricycle update [--dry-run]         # Overwrite core files, remove dropped ones, re-assemble
tricycle dogfood [--yes]            # Mirror core/ into this repo (tricycle-pro only)
tricycle update-self                # Update CLI itself
tricycle validate                   # Validate configuration
tricycle graphify <sub>             # Manage optional graphify integration
```

## Generated Files Are Never Hand-Edited

Every file below is an output. A hand edit to one is discarded the next time its command runs. Make every change in the source column, then regenerate.

| Output | Written by | Change it in |
|--------|-----------|--------------|
| `.claude/settings.json` | `tricycle generate settings` | `tricycle.config.yml` |
| `.mcp.json` | `tricycle generate mcp` | `tricycle.config.yml` |
| `CLAUDE.md` | `tricycle generate claude-md` | `tricycle.config.yml`, `generators/sections/` |
| `.claude/commands/trc.*.md` | `tricycle assemble` (also run by `update`) | custom blocks in `.trc/blocks/custom/`, `workflow.blocks` in `tricycle.config.yml` |
| Core copies in `.trc/`, `.claude/hooks/`, `.claude/skills/` | `tricycle update` | upstream `core/` in tricycle-pro |

`tricycle update` overwrites every core copy that differs from core and removes the copies core no longer ships. A repo-specific need goes into the config, a custom block, or a repo-owned hook script, never into a core copy or an output.

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

spec:
  store: repo                     # repo | linear
  dir: docs/specs

workflow:
  blocks:
    # per-command overrides (see Blocks)

worktree:
  enabled: false

band:
  max_parallel: 3                 # /trc.band: max concurrent sub-issue workers (1-8)

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

claude:                           # sources for .claude/settings.json
  disable_core_hooks:             # trc core hooks to leave out (not registered, not installed)
    - rename-on-kickoff
  permissions:
    allow:
      - "Bash(make:*)"            # appended to the generated allow list
  hooks:                          # repo hooks, registered after trc's own
    - event: PreToolUse
      matcher: Bash
      command: $CLAUDE_PROJECT_DIR/.claude/hooks/guard-db.sh
      timeout: 10                 # optional
```

```yaml
style:                            # optional; each part works only when its plugin is installed
  chat: ultracave                 # caveman plugin default mode, written to .caveman.json
  artifacts: ste-short            # registers style-gate: persisted prose must pass the asd-ste100 linter
```

Core hooks: `guard-main-checkout` (when `worktree.enabled`), `rename-on-kickoff`, `graphify-refresh-on-kickoff`, `session-context`, `style-gate` (when `style.artifacts: ste-short`). Repo hook scripts live in `.claude/hooks/` next to them. `tricycle update` never touches a file that core does not ship.

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
| `worktree.` | `worktree.enabled`, `worktree.env_copy` |
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

1. **Refreshes the graph automatically** at every `/trc.plan`, `/trc.implement`, `/trc.chain`,
   or `/trc.band` kickoff (fire-and-forget, cached — no-op is cheap when
   nothing changed).
2. **Briefs the agent.** The plan and implement commands carry a Graphify Context
   block. It tells the agent to query the graph before a wide search, through the
   `graphify` CLI or through MCP tools after `tricycle graphify mcp-start`.

All disabled by default. When the flag is off, the hook is a silent no-op and
the Graphify Context block tells the agent to skip the graph.

### Language support

Graphify's AST extractor covers these languages:

- Python, JS, TS, Go, Rust, Java, C, C++, Ruby, C#, Kotlin, Scala, PHP.
- Swift, Lua, Zig, PowerShell, Elixir, Objective-C, Julia, Verilog,
  SystemVerilog, Vue, Svelte, Dart.

The CLI-side build (`tricycle graphify bootstrap` and the kickoff refresh) does
**not** extract Bash, shell, YAML or Markdown. For shell-heavy repos, the
auto-built graph is thin. On a mostly-Bash toolkit, the CLI produced 53 nodes,
all from the few JS test files.

The richer build is the skill-side `/graphify .` that you run inside your AI
assistant. It uses an LLM to extract concepts from docs, papers, images and
code in any language. Treat the CLI bootstrap as the code-structure floor, and
run the skill form for fuller context.

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
  manually. Do not trust nodes after you rewrite large parts of the tree.
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
│   ├── agents/               # Subagents (trc-spec-validator)
│   ├── blocks/               # Block source files
│   │   ├── plan/             # /trc.plan blocks
│   │   ├── implement/        # /trc.implement blocks
│   │   └── optional/         # Opt-in blocks (catholic, worktree, qa, local stack)
│   ├── commands/             # Commands (plan and implement are assembled from blocks)
│   ├── hooks/                # Enforcement hooks (lint gate, branch protection, session context)
│   ├── scripts/bash/         # Shared scripts (common.sh, assembly, feature creation)
│   ├── skills/               # Skill modules (catholic, code-reviewer, debugging, etc.)
│   └── templates/            # Spec, constitution and recon templates
├── modules/                  # Optional modules (worktree, qa, ci-watch, mcp, memory)
├── presets/                  # Starter configs (single-app, nextjs-prisma, etc.)
├── generators/               # CLAUDE.md section templates
├── docs/                     # Audit reports, retired designs
└── specs/                    # Dogfooding artifacts (see below)
```

## Dogfooding

Tricycle Pro is built with itself. The `specs/` directory holds the artifacts of the earlier four-step workflow, kept as history:

**[`001-headless-mode`](specs/001-headless-mode/)** — Added `/trc.headless` for single-command workflow execution. JavaScript/Node.js implementation with `node:test`. Full artifact set: spec, plan, research, data model, contracts, tasks, checklist.

**[`002-shell-only-cli`](specs/002-shell-only-cli/)** — Rewrote the CLI as pure Bash with zero npm/Node.js dependencies. Defined CLI interface contracts and migration strategy from the Node.js version.

**[`003-workflow-chains-blocks`](specs/003-workflow-chains-blocks/)** — The blocks and chains system itself. Decomposed all commands into 22 pluggable blocks, added configurable workflow chains, build-time assembly, and companion blocks.

Browse `specs/` for more history: the skills system, the audit command, session hooks and others. Release 1.0 removed `/trc.headless`, configurable chains and companion blocks.


## License

MIT
