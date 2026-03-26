# AI-Assisted Development: A Spec-Driven Workflow with Tricycle Pro

A practical guide to building features with AI agents using structured specifications, isolated environments, and automated guardrails — powered by [Tricycle Pro](https://github.com/anthropics/tricycle-pro), a pure-Bash toolkit for Claude Code. The patterns are framework-agnostic; examples below use a TypeScript monorepo for illustration.

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Workflow Overview](#workflow-overview)
3. [Project Governance: Constitutions](#project-governance-constitutions)
4. [Feature Lifecycle](#feature-lifecycle)
   - [Phase 1: Specification](#phase-1-specification)
   - [Phase 2: Planning](#phase-2-planning)
   - [Phase 3: Task Generation](#phase-3-task-generation)
   - [Phase 4: Implementation](#phase-4-implementation)
   - [Phase 5: Validation & Ship](#phase-5-validation--ship)
5. [Environment Isolation](#environment-isolation)
   - [Git Worktrees](#git-worktrees)
   - [Per-Branch Databases](#per-branch-databases)
   - [Non-Interactive Tooling](#non-interactive-tooling)
6. [Enforcement: Hooks & Gates](#enforcement-hooks--gates)
7. [Shared Permissions](#shared-permissions)
8. [MCP Servers: Giving the Agent Eyes and Hands](#mcp-servers-giving-the-agent-eyes-and-hands)
9. [Memory: Teaching the Agent Over Time](#memory-teaching-the-agent-over-time)
10. [CI Integration](#ci-integration)
11. [Testing & Validation](#testing--validation)
12. [Issue Tracking](#issue-tracking)
13. [Key Decisions & Tradeoffs](#key-decisions--tradeoffs)
14. [Setting This Up](#setting-this-up-from-scratch)

---

## The Problem

AI coding agents are powerful but naive. Without structure, they:

- **Start coding before understanding the problem** — producing code that technically works but misses the actual requirement.
- **Make inconsistent decisions** — different conversations produce different patterns for the same problem.
- **Can't handle interactive prompts** — tools like `prisma migrate dev` or `npm init` expect a human at the keyboard.
- **Lose context between sessions** — every conversation starts from zero.
- **Skip validation** — declare "done" without running tests or linting.
- **Stomp on parallel work** — multiple features in the same repo create conflicts.

This workflow solves all of these. The core idea: **don't let the agent write code until it has a spec, a plan, and a task list. Then enforce the rules with hooks, not hope.**

---

## Workflow Overview

```
Feature Idea
    │
    ▼
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐
│  /trc.specify    │────▶│  /trc.plan    │────▶│  /trc.tasks   │
│  Natural language│     │  Architecture │     │  Ordered work │
│  → structured    │     │  + data model │     │  items with   │
│    spec          │     │  + contracts  │     │  dependencies │
└─────────────────┘     └──────────────┘     └──────────────┘
                                                     │
    ┌────────────────────────────────────────────────┘
    ▼
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐
│  /trc.implement  │────▶│  Lint & Test  │────▶│  PR & Merge   │
│  Phase-by-phase  │     │  (enforced    │     │  Push, review,│
│  execution       │     │   by hook)    │     │  squash-merge │
└─────────────────┘     └──────────────┘     └──────────────┘

Or run the entire chain automatically:  /trc.headless <feature description>
```

Each step is a **slash command** (`trc.*`) — a reusable prompt template that Claude Code executes. The agent can't skip steps because hooks enforce the sequence. Tricycle Pro installs these commands, hooks, and templates via its CLI (`tricycle init`).

---

## Project Governance: Constitutions

A **constitution** is a markdown file that defines architectural principles, tech stack decisions, and invariants for the project. The agent reads it before every planning and implementation step.

```
.trc/
  memory/
    constitution.md          # Root — cross-project rules
apps/backend/
  .trc/
    memory/
      constitution.md        # App-level — overrides root on conflicts
apps/frontend/
  .trc/
    memory/
      constitution.md
```

### What goes in a constitution

The constitution captures decisions that should never be made ad-hoc. Here's an example for a TypeScript monorepo:

```markdown
# Project Constitution v2.0

## Principles

### 1. Workspace Isolation
Apps MUST NOT import from sibling apps. All sharing flows through
explicit workspace packages.

### 2. Single Package Manager
npm only. No yarn/pnpm/bun. Single lockfile eliminates version conflicts.

### 3. API Contract
All API endpoints use REST with OpenAPI specs. No GraphQL.

## App-Specific Constraints

### Frontend
- Mobile-first (320px+), 44×44px touch targets
- State management: Zustand for client, TanStack Query for server

### Backend
- Express. All routes in src/routes/
- Database: PostgreSQL. Docker compose mandatory for dev.
```

The specifics don't matter — what matters is that these decisions are made **once** and enforced **forever**. Without a constitution, session A might use Redux, session B might use Zustand, session C might use Context.

### Constitution hierarchy

In monorepos, the root constitution sets cross-app rules. App-level constitutions override on conflicts. A mobile-first consumer app and a desktop-only admin panel shouldn't share responsive design rules — but they should share the same API patterns.

Tricycle Pro initializes the constitution at `.trc/memory/constitution.md` and fills it via the `/trc.constitution` command.

---

## Feature Lifecycle

### Phase 1: Specification

The `/trc.specify` command converts a natural language feature description into a structured spec.

**Input**: A sentence or paragraph describing what you want.

```
/trc.specify Add SEO-friendly URL slugs so posts are accessible via
human-readable URLs instead of random IDs
```

**What happens**:

1. A **git worktree** is created automatically (isolated branch + working directory).
2. A new spec directory is created: `specs/053-url-slugs/`.
3. The agent writes `spec.md` using a template with mandatory sections.
4. A quality **checklist** is auto-generated and validated.

**Output structure** (`spec.md`):

```markdown
# Feature: SEO-Friendly URL Slugs

## User Scenarios & Testing

### US1: Human-Readable URLs [P1]
**Why P1**: Core value proposition — without this, the feature has no purpose.
**Independent test**: Create a post → verify slug in response → visit /p/{slug}.

#### Acceptance Scenarios
- **Given** a user creates a post with title "Best Coffee in NYC"
  **When** the post is saved
  **Then** the URL contains a slug like "best-coffee-in-nyc-x7k2m3"

### US2: Category-Prefixed URLs [P2]
...

## Requirements
### Functional
- FR-1: Slugs are generated from the title + 6-char random suffix
- FR-2: Old short-ID URLs continue to work (backward compatibility)

### Key Entities
- Post: add nullable `slug` field (unique, max 200 chars)

## Success Criteria
- SC-1: 100% of new posts have slugs in their URLs
- SC-2: Zero broken links from old URL format
```

**Key design decisions**:

- **User stories have explicit priorities** (P1, P2, P3). P1 is the MVP — you can ship with just P1 implemented.
- **Each story is independently testable**. This means the agent can implement and verify one story at a time.
- **Max 3 clarification questions**. The agent makes informed guesses for gaps instead of asking 20 questions. Only genuinely ambiguous requirements get flagged.
- **Success criteria are technology-agnostic**. No "API latency < 200ms" — instead "users can share post URLs on social media and they load correctly."

### Phase 2: Planning

The `/trc.plan` command reads the spec and constitution, then produces technical design artifacts.

```
/trc.plan
```

**Output** (in the same spec directory):

| File | Purpose |
|------|---------|
| `plan.md` | Architecture, tech stack validation, file structure |
| `data-model.md` | Schema changes, validation rules, state transitions |
| `contracts/` | API contracts for each modified endpoint |
| `research.md` | Technical decisions with alternatives considered |

The plan is where the agent validates choices against the constitution. If the spec says "add a REST endpoint" but the constitution says "tRPC only", this is where the conflict gets caught.

### Phase 3: Task Generation

The `/trc.tasks` command converts the plan into an ordered, dependency-aware task list.

```
/trc.tasks
```

**Output** (`tasks.md`):

```markdown
# Tasks: SEO-Friendly URL Slugs

## Phase 1: Setup
- [ ] T001 Create slug generation utility in `src/utils/slug.ts`

## Phase 2: Foundational
- [ ] T002 Add `slug` field to Prisma schema
- [ ] T003 Run migration
- [ ] T004 [P] Add slug to Post type in `src/types/post.ts`
- [ ] T005 [P] Add findBySlug function in `src/models/post.ts`
- [ ] T006 Update formatPost to include slug

## Phase 3: US1 — Human-Readable URLs
- [ ] T010 Update getById procedure (accept slug or shortId)
- [ ] T011 Update create procedure (generate slug on creation)
- [ ] T012 Add [slug] catch-all route in frontend

## Phase 4: Polish
- [ ] T019 Run lint for all affected apps
- [ ] T020 Run backend tests
- [ ] T021 Verify end-to-end in browser
```

**Key patterns**:

- **`[P]` marks parallel tasks**. T004 and T005 can run concurrently because they touch different files.
- **Tasks are organized by user story**, not by technical layer. This means you can implement and ship US1 without touching US2.
- **Every task includes exact file paths**. No ambiguity about where code goes.
- **Phase 2 (Foundational) blocks everything**. Schema changes, types, and model functions must exist before any story work begins.

### Phase 4: Implementation

The `/trc.implement` command executes tasks phase by phase.

```
/trc.implement
```

**What happens**:

1. **Pre-flight checks**: Verifies Docker is running, checklists pass, all design docs exist.
2. **Phase-by-phase execution**: Completes each phase before starting the next.
3. **Parallel execution**: Tasks marked `[P]` run concurrently.
4. **Progress tracking**: Each completed task gets marked `[x]` in `tasks.md`.
5. **Post-implementation hook fires**: Enforces lint/test (see [Enforcement](#enforcement-hooks--gates)).

> **Headless mode**: `/trc.headless <description>` runs the entire specify → plan → tasks → implement chain automatically. It auto-resolves non-critical clarifications, pausing only for destructive actions or push approval.

### Phase 5: Validation & Ship

After implementation, the agent:

1. Runs **lint** for all affected apps/packages.
2. Runs **tests** for affected apps/packages.
3. Creates a **PR** targeting the main branch.
4. Optionally uses `/wait-ci` (from the `ci-watch` module) to **poll CI status** until checks pass.
5. On CI failure: reads logs, diagnoses, fixes, pushes again.
6. On CI pass: **merges** (squash merge).

---

## Environment Isolation

### Git Worktrees

Every feature gets its own **git worktree** — a separate working directory with its own branch, checked out from the same repo. Enable this with:

```bash
tricycle add worktree
```

The worktree module installs a hook that automatically creates worktrees when you run `/trc.specify`. Manually:

```bash
git worktree add -b 053-url-slugs ../myproject-053-url-slugs
```

**Why worktrees instead of branches?**

With regular branches, switching between features means stashing changes, switching branches, reinstalling dependencies, and re-running migrations. With worktrees, each feature is a separate directory. You can have 5 features in progress simultaneously without any switching.

```
~/projects/
  myproject/                        # main checkout
  myproject-053-url-slugs/          # feature worktree
  myproject-054-fulltext-search/    # another feature worktree
  myproject-055-og-images/          # another one
```

**Enforcement**: A `PreToolUse` hook blocks spec edits in the main checkout:

```bash
#!/bin/bash
# .claude/hooks/block-spec-in-main.sh
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check spec files
if [[ "$FILE" != *specs/*/spec.md* ]]; then
  exit 0
fi

# In worktrees, .git is a file. In main checkout, .git is a directory.
if [ -d ".git" ]; then
  cat <<EOJSON
{"decision":"block","reason":"You are in the main checkout. Spec files must be edited in a git worktree. Run /trc.specify to create one."}
EOJSON
fi
```

### Per-Branch Databases

The problem: all worktrees share the same local database. Branch A adds a `slug` column. Branch B doesn't have that migration. The ORM detects drift and demands a reset.

The solution: each worktree gets its own database. Tricycle Pro's worktree module includes database adapters for Postgres, MySQL, and SQLite:

```yaml
# tricycle.config.yml
worktree:
  enabled: true
  db_isolation: true
  setup_script: scripts/worktree-db-setup.sh
  env_copy:
    - .env
```

The `worktree-db-setup.sh` script sanitizes the branch name into a valid database identifier, creates the database if it doesn't exist, and applies migrations. Each adapter handles the specifics for its database engine.

**Result**: `feature-url-slugs` uses `myproject_feature_url_slugs`. `feature-search` uses `myproject_feature_search`. No drift. No resets.

### Non-Interactive Tooling

AI agents run in non-interactive terminals. Commands that prompt for confirmation (`prisma migrate dev`, `npm init`, `rm -i`) will hang or fail.

**The pattern**: wrap interactive tools with non-interactive scripts. Put these in your project's `scripts/` directory and reference them in CLAUDE.md.

Common examples:
- **Database migrations**: Replace `prisma migrate dev` (interactive) with `prisma migrate diff` + `prisma migrate deploy` (both non-interactive)
- **Package init**: Replace `npm init` (prompts) with `npm init -y` or a template script
- **Destructive operations**: Replace `rm -i` with explicit `rm` in a script that logs what it deletes

**The principle**: find the non-interactive equivalent of every interactive command your team uses, wrap it in a script, and tell the agent to use the script via CLAUDE.md or a feedback memory.

---

## Enforcement: Hooks & Gates

Hooks are shell scripts that run before or after Claude Code uses a tool. They can **block** actions, **modify** behavior, or **inject** instructions.

### Hook Types

| Hook | When | Use Case |
|------|------|----------|
| `PreToolUse` | Before a tool runs | Block forbidden actions, inject context |
| `PostToolUse` | After a tool runs | Enforce follow-up steps |

### Configured Hooks

```jsonc
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",           // Fires on slash command execution
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/worktree-on-specify.sh",
          "timeout": 15
        }]
      },
      {
        "matcher": "Write|Edit",       // Fires on any file write/edit
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/block-spec-in-main.sh",
          "timeout": 5
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Skill",           // Fires after slash command completes
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/post-implement-lint.sh",
          "timeout": 5
        }]
      }
    ]
  }
}
```

### Post-Implement Lint Gate

The most important hook — prevents the agent from declaring "done" without running lint/test:

```bash
#!/bin/bash
# .claude/hooks/post-implement-lint.sh
INPUT=$(cat)

SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
if [ "$SKILL" != "trc.implement" ]; then
  exit 0
fi

cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
"MANDATORY: Run lint and test for ALL affected apps before declaring done.
Fix any failures. Do NOT skip this step."}}
EOJSON
```

This hook fires every time `/trc.implement` finishes. The agent receives the message as if the system told it — it can't ignore it. Without this hook, the agent frequently says "implementation complete!" without running tests.

---

## Shared Permissions

Claude Code asks for permission before running commands. In the main checkout, you approve `git`, `docker`, `npm`, etc. once and they're saved to `.claude/settings.local.json`. But that file is gitignored — **worktrees don't inherit those permissions**.

**The fix**: Create a committed `.claude/settings.json` with core permissions. Tricycle Pro generates this automatically via `tricycle init`, with permissions tailored to your preset's package manager and tools:

```jsonc
// .claude/settings.json (committed to repo, shared by all worktrees)
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git:*)",
      "Bash(cd:*)",
      "Bash(ls:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(node:*)",
      "Bash(docker:*)",
      "Bash(./scripts:*)"
      // ...
    ]
  }
}
```

**Gitignore setup** — allow `settings.json` but keep `settings.local.json` ignored:

```gitignore
# .gitignore
.claude/*
!.claude/settings.json
!.claude/commands/
!.claude/hooks/
!.claude/skills/
```

The pattern `.claude/*` (not `.claude/`) is critical — the trailing slash ignores the **directory**, making negation impossible. The wildcard ignores **contents**, allowing selective un-ignoring.

**Result**: New worktrees start with all core permissions. No more "allow `git status`?" prompts.

---

## MCP Servers: Giving the Agent Eyes and Hands

MCP (Model Context Protocol) servers extend what the agent can do beyond reading files and running commands. Tricycle Pro ships MCP presets you can install via the `mcp` module:

```bash
tricycle add mcp
```

### Available Presets

Presets live in `modules/mcp/presets/` and generate a `.mcp.json` file:

| Preset | Includes |
|--------|----------|
| **minimal** | Context7 (framework docs) |
| **web-fullstack** | Chrome DevTools, Playwright, Context7 |
| **backend-only** | Docker, database tools |

Configure in `tricycle.config.yml`:

```yaml
mcp:
  preset: web-fullstack    # or minimal, backend-only
  custom:                  # add project-specific servers
    github:
      type: command
      command: npx
      args: ["@anthropic-ai/github-mcp"]
```

### Usage Priority

The key insight: **not all tools are equal**. Chrome DevTools is faster and more visual than Playwright. Context7 documentation is more reliable than the agent's training data. Set priority rules in your CLAUDE.md so the agent picks the right tool for the job.

---

## Memory: Teaching the Agent Over Time

Claude Code's memory system persists across conversations. When the agent makes a mistake and you correct it, the correction is saved — and applies to all future sessions.

### Memory Types

| Type | What it stores | Example |
|------|---------------|---------|
| **feedback** | Corrections + confirmations | "Never run `prisma migrate dev` directly — use the wrapper script" |
| **user** | Your role, expertise, preferences | "Senior engineer, deep Go expertise, new to React" |
| **project** | Ongoing work, deadlines, context | "Merge freeze starts March 5 for mobile release" |
| **reference** | Pointers to external systems | "Bug reports are tracked in the GitHub project board" |

### How feedback accumulates

Session 1:
```
Agent: I'll run prisma migrate dev to create the migration.
You: Don't — it fails in non-interactive mode. Use ./scripts/migrate-dev.sh.
→ Memory saved: "Never run prisma migrate dev directly"
```

Session 5:
```
Agent: I'll use ./scripts/migrate-dev.sh to create the migration.
→ Agent reads the feedback memory and gets it right automatically.
```

Session 12:
```
Agent: Schema changed. Running ./scripts/migrate-dev.sh add-user-avatar...
→ No correction needed. The behavior is permanent.
```

### Memory file structure

```markdown
<!-- .claude/projects/<project-hash>/memory/feedback_no_manual_migrations.md -->
---
name: Never create migration files manually
description: All Prisma migrations must use ./scripts/migrate-dev.sh
type: feedback
---

NEVER run `prisma migrate dev` directly — it requires interactive prompts.
Use `./scripts/migrate-dev.sh <name>` instead.

**Why:** prisma migrate dev prompts for confirmation on warnings and drift.
No flag exists to skip this. Caused repeated failures in every feature branch.

**How to apply:** After editing schema.prisma, run `./scripts/migrate-dev.sh <name>`.
```

### The index

```markdown
<!-- .claude/projects/<project-hash>/memory/MEMORY.md -->
# Memory Index

- [feedback_no_manual_migrations.md] — Use migrate-dev.sh, not prisma migrate dev
- [feedback_worktree_db_drift.md] — Per-worktree databases prevent migration drift
- [feedback_pr_workflow.md] — Always create PRs, never push directly to main
- [feedback_docker_dev.md] — Backend runs via docker compose for dev
- [project_v2_migration.md] — Migrating from v1 to v2 API, started 2026-03-17
```

**Key insight**: Record both **failures** (corrections) and **successes** (confirmed approaches). If you only save mistakes, the agent becomes overly cautious and stops making good judgment calls.

---

## CI Integration

Tricycle Pro's optional `ci-watch` module adds a `/wait-ci` command that automates GitHub Actions polling:

```bash
tricycle add ci-watch
```

### The `/wait-ci` Command

Instead of manually checking GitHub Actions:

```
/wait-ci        # polls current branch
/wait-ci 123    # polls PR #123
```

**What it does**:

1. Waits 30 seconds for checks to appear.
2. Polls every 15 seconds (max 20 iterations).
3. On success: prints summary table, says "ready to merge."
4. On failure: fetches failed logs, diagnoses the error, suggests a fix.

### Conflict Detection

A common pitfall: the PR has merge conflicts, but the agent doesn't check — it polls CI status and sees no workflows running (GitHub doesn't run workflows on conflicting PRs). The agent then says "no checks reported" and stalls.

**The fix**: `/wait-ci` checks `gh pr view --json mergeable` before declaring success. If `CONFLICTING`, it reports the conflict instead of waiting forever.

---

## Testing & Validation

Testing has two layers enforced by Tricycle Pro: **local validation** (lint + tests after `/trc.implement`) and optional **QA testing** (browser-based flows).

### Local Validation

The `PostToolUse` hook on `/trc.implement` fires after implementation completes and injects a mandatory instruction to run lint and tests. The agent can't declare "done" without passing them. Your CLAUDE.md defines which commands to run:

```markdown
## Commands
- lint: `npm run lint`
- test: `npm test`
```

The hook doesn't care what your stack is — it just enforces that the agent runs whatever lint/test commands your project defines.

### QA Testing (Optional)

The `qa` module adds structured test plans for browser-based verification:

```bash
tricycle add qa
```

This installs:
- **Test plan templates** — for both AI-agent and human execution
- **AI agent instructions** — how the agent should use MCP servers for QA
- **Suite mapping** — maps test suites to app routes/features

QA test plans are structured with dependencies, pseudocode actions, and verification checklists. Results go to `qa/results-<date>/results.md` with screenshots.

---

## Issue Tracking

The `/trc.taskstoissues` command bridges the spec workflow with issue tracking. It converts task items from `tasks.md` into GitHub issues — one issue per task, with dependencies mapped and labels applied.

```
/trc.taskstoissues
```

This creates issues directly from the dependency-ordered task list, so your issue tracker mirrors the implementation plan exactly.

---

## Key Decisions & Tradeoffs

### "Informed guesses over interrogation"

The agent fills gaps with reasonable defaults instead of asking 20 clarification questions. Max 3 `[NEEDS CLARIFICATION]` markers per spec, prioritized by impact (scope > security > UX > technical details).

**Why**: Asking too many questions kills momentum. Most gaps have obvious answers that the agent can infer from context. The rare genuinely ambiguous requirements get flagged.

### "Tasks organized by user story, not by layer"

Tasks are grouped as "US1: URL Slugs" → "US2: Category URLs" → "US3: Author URLs", not "Backend" → "Frontend" → "Database".

**Why**: Story-based organization means each story is independently implementable and testable. You can ship US1 as the MVP without touching US2. Layer-based organization forces you to implement everything or nothing.

### "Constitution hierarchy, not a monolith"

Root constitution for cross-app rules, app-level constitutions for app-specific rules. App overrides root on conflicts.

**Why**: A mobile-first consumer app and a desktop-only admin panel shouldn't share responsive design rules. But they should share the same type system and API patterns.

### "Hooks over documentation"

Rules like "run lint after implementation" are enforced by `PostToolUse` hooks, not just written in CLAUDE.md.

**Why**: Documentation gets skipped. Hooks don't. The agent literally can't proceed without satisfying the hook's requirements. CLAUDE.md is for context and rationale; hooks are for enforcement.

### "Per-worktree databases over shared dev DB"

Each git worktree gets its own database (`myproject_feature_slugs`, `myproject_feature_search`). Tricycle Pro's worktree module (`tricycle add worktree`) supports Postgres, MySQL, and SQLite adapters.

**Why**: Shared databases cause migration drift. Branch A applies migration X. Branch B doesn't have it. The ORM detects drift and refuses to proceed. The only fix is a full database reset — destroying all dev data. Per-worktree databases eliminate this entirely.

### "Non-interactive scripts over interactive commands"

Wrapper scripts replace any command that prompts for confirmation.

**Why**: AI agents run in non-interactive terminals. Many CLI tools (`prisma migrate dev`, `npm init`, interactive installers) prompt for confirmation with no `--yes` flag. Wrapper scripts achieve the same result without interactivity.

---

## Setting This Up From Scratch

### Option A: Use Tricycle Pro (recommended)

Install the CLI and scaffold everything in one command:

```bash
# Install Tricycle Pro
curl -fsSL https://raw.githubusercontent.com/anthropics/tricycle-pro/main/install.sh | bash

# Initialize a project (choose a preset)
tricycle init --preset single-app        # minimal single-app
tricycle init --preset nextjs-prisma     # Next.js + Prisma
tricycle init --preset express-prisma    # Express API + Prisma
tricycle init --preset monorepo-turborepo # Turborepo monorepo
```

This creates the full directory structure:

```
.claude/
  commands/          # Slash command templates (trc.specify.md, trc.plan.md, etc.)
  hooks/             # Pre/Post tool use hooks
  settings.json      # Shared permissions (committed)
.trc/
  memory/
    constitution.md  # Project governance
  templates/         # Spec, plan, tasks templates
  scripts/bash/      # Helper scripts (create-new-feature.sh, etc.)
tricycle.config.yml  # Toolkit configuration
.tricycle.lock       # Tracks installed file checksums
CLAUDE.md            # Agent instructions (auto-generated)
```

Add optional modules as needed:

```bash
tricycle add worktree    # Git worktree isolation + per-branch DB adapters
tricycle add qa          # QA testing templates + test plans
tricycle add mcp         # MCP server configuration presets
tricycle add memory      # Agent memory seed files
tricycle add ci-watch    # CI polling commands
```

### Option B: Manual setup

If you prefer to set things up by hand, create the structure above manually. The key files are:

1. **CLAUDE.md** — the agent's "onboarding doc." Write it like you're onboarding a new developer — but one that follows instructions literally.

2. **Constitution** (`.trc/memory/constitution.md`) — start simple. Add principles as you discover them through actual development.

3. **Hooks** — start with the post-implement lint hook (highest impact). Add others as pain points emerge.

4. **Memory** — don't pre-populate. Let it grow organically from corrections and confirmations during real work. The best memories come from "no, don't do that" moments.

---

## Summary

The core loop:

1. **Govern** with constitutions (decisions made once, enforced forever)
2. **Specify** before coding (structured specs prevent wasted work)
3. **Isolate** with worktrees + per-branch databases (parallel work without conflicts)
4. **Enforce** with hooks (lint/test gates, worktree requirements)
5. **Remember** with memory (corrections persist across sessions)
6. **Automate** the boring parts (CI polling, migration scripts, cleanup)

The agent writes better code when it has structure. Give it a spec, a plan, and guardrails — then get out of its way.

To get started: `tricycle init --preset single-app` and run `/trc.headless <your feature idea>`.
