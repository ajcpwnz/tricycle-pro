# AI-Assisted Development: A Spec-Driven Workflow for Monorepos

A practical guide to building features with AI agents using structured specifications, isolated environments, and automated guardrails. Based on a production monorepo (TypeScript, Next.js, Express, Prisma, tRPC) — but the patterns are framework-agnostic.

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
11. [Key Decisions & Tradeoffs](#key-decisions--tradeoffs)
12. [Setting This Up From Scratch](#setting-this-up-from-scratch)

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
│  /specify        │────▶│  /plan        │────▶│  /tasks       │
│  Natural language│     │  Architecture │     │  Ordered work │
│  → structured    │     │  + data model │     │  items with   │
│    spec          │     │  + contracts  │     │  dependencies │
└─────────────────┘     └──────────────┘     └──────────────┘
                                                     │
    ┌────────────────────────────────────────────────┘
    ▼
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐
│  /implement      │────▶│  Lint & Test  │────▶│  /wait-ci     │
│  Phase-by-phase  │     │  (enforced    │     │  Push, poll,  │
│  execution       │     │   by hook)    │     │  auto-diagnose│
└─────────────────┘     └──────────────┘     └──────────────┘
```

Each step is a **slash command** — a reusable prompt template that Claude Code executes. The agent can't skip steps because hooks enforce the sequence.

---

## Project Governance: Constitutions

A **constitution** is a markdown file that defines architectural principles, tech stack decisions, and invariants for the project. The agent reads it before every planning and implementation step.

```
.specify/
  memory/
    constitution.md          # Root — cross-project rules
apps/backend/
  .specify/
    memory/
      constitution.md        # App-level — overrides root on conflicts
apps/frontend/
  .specify/
    memory/
      constitution.md
```

### What goes in a constitution

```markdown
# Project Constitution v2.0

## Principles

### 1. Workspace Isolation
Apps MUST NOT import from sibling apps. All sharing flows through
explicit workspace packages. This makes each app independently deployable.

### 2. Shared Type Contract
Types flow end-to-end via tRPC inference. The backend's Zod schemas
automatically type frontend procedure calls. No codegen step needed.

### 3. Single Package Manager
Bun only. No npm/yarn/pnpm. Single lockfile eliminates version conflicts.

## App-Specific Constraints

### Frontend
- Mobile-first (320px+), 44×44px touch targets
- Client state: Jotai. Server state: TanStack Query (via tRPC)

### Backend
- Express + tRPC v11. All procedures in src/trpc/routers/
- Database: PostgreSQL via Prisma. Docker compose mandatory.
```

### Why this matters

Without a constitution, the agent makes ad-hoc architecture decisions. Session A might use Redux, session B might use Jotai, session C might use Context. The constitution makes these decisions once and enforces them forever.

The **hierarchy** (root overrides by app-level) handles the reality that different apps in a monorepo have different constraints — a mobile-first frontend and a desktop-only admin panel shouldn't share the same responsive design rules.

---

## Feature Lifecycle

### Phase 1: Specification

The `/specify` command converts a natural language feature description into a structured spec.

**Input**: A sentence or paragraph describing what you want.

```
/specify Add SEO-friendly URL slugs so polsts are accessible via
human-readable URLs instead of random IDs
```

**What happens**:

1. A **git worktree** is created automatically (isolated branch + working directory).
2. A new spec directory is created: `specs/053-polst-url-slugs/`.
3. The agent writes `spec.md` using a template with mandatory sections.
4. A quality **checklist** is auto-generated and validated.

**Output structure** (`spec.md`):

```markdown
# Feature: SEO-Friendly URL Slugs

## User Scenarios & Testing

### US1: Human-Readable URLs [P1]
**Why P1**: Core value proposition — without this, the feature has no purpose.
**Independent test**: Create a polst → verify slug in response → visit /p/{slug}.

#### Acceptance Scenarios
- **Given** a user creates a polst with title "Best Coffee in NYC"
  **When** the polst is saved
  **Then** the URL contains a slug like "best-coffee-in-nyc-x7k2m3"

### US2: Category-Prefixed URLs [P2]
...

## Requirements
### Functional
- FR-1: Slugs are generated from the title + 6-char random suffix
- FR-2: Old short-ID URLs continue to work (backward compatibility)

### Key Entities
- Polst: add nullable `slug` field (unique, max 200 chars)

## Success Criteria
- SC-1: 100% of new polsts have slugs in their URLs
- SC-2: Zero broken links from old URL format
```

**Key design decisions**:

- **User stories have explicit priorities** (P1, P2, P3). P1 is the MVP — you can ship with just P1 implemented.
- **Each story is independently testable**. This means the agent can implement and verify one story at a time.
- **Max 3 clarification questions**. The agent makes informed guesses for gaps instead of asking 20 questions. Only genuinely ambiguous requirements get flagged.
- **Success criteria are technology-agnostic**. No "API latency < 200ms" — instead "users can share polst URLs on social media and they load correctly."

### Phase 2: Planning

The `/plan` command reads the spec and constitution, then produces technical design artifacts.

```
/plan
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

The `/tasks` command converts the plan into an ordered, dependency-aware task list.

```
/tasks
```

**Output** (`tasks.md`):

```markdown
# Tasks: SEO-Friendly URL Slugs

## Phase 1: Setup
- [ ] T001 Create slug generation utility in `src/utils/slug.ts`

## Phase 2: Foundational
- [ ] T002 Add `slug` field to Prisma schema
- [ ] T003 Run migration
- [ ] T004 [P] Add slug to PolstRecord type in `src/types/polst.ts`
- [ ] T005 [P] Add findPolstBySlug function in `src/models/polst.ts`
- [ ] T006 Update formatPolstRecord to include slug

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

The `/implement` command executes tasks phase by phase.

```
/implement
```

**What happens**:

1. **Pre-flight checks**: Verifies Docker is running, checklists pass, all design docs exist.
2. **Phase-by-phase execution**: Completes each phase before starting the next.
3. **Parallel execution**: Tasks marked `[P]` run concurrently.
4. **Progress tracking**: Each completed task gets marked `[x]` in `tasks.md`.
5. **Post-implementation hook fires**: Enforces lint/test (see [Enforcement](#enforcement-hooks--gates)).

### Phase 5: Validation & Ship

After implementation, the agent:

1. Runs **lint** for all affected apps.
2. Runs **tests** for affected apps.
3. Creates a **PR** targeting the staging branch.
4. Uses `/wait-ci` to **poll CI status** until checks pass.
5. On CI failure: reads logs, diagnoses, fixes, pushes again.
6. On CI pass: **merges** (squash merge).

---

## Environment Isolation

### Git Worktrees

Every feature gets its own **git worktree** — a separate working directory with its own branch, checked out from the same repo.

```bash
# Created automatically by the /specify hook, but manually it's:
git worktree add -b 053-polst-url-slugs ../myproject-053-polst-url-slugs
```

**Why worktrees instead of branches?**

With regular branches, switching between features means stashing changes, switching branches, reinstalling dependencies, and re-running migrations. With worktrees, each feature is a separate directory. You can have 5 features in progress simultaneously without any switching.

```
~/projects/
  myproject/                        # main checkout (staging branch)
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
{"decision":"block","reason":"You are in the main checkout. Spec files must be edited in a git worktree. Run /specify to create one."}
EOJSON
fi
```

### Per-Branch Databases

The problem: all worktrees share the same local Postgres. Branch A adds a `slug` column. Branch B doesn't have that migration. When you switch between them, Prisma sees drift and demands a reset.

The solution: each worktree gets its own database.

```bash
#!/usr/bin/env bash
# scripts/worktree-db-setup.sh

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# main/staging use the default database
if [[ "$BRANCH" == "main" || "$BRANCH" == "staging" ]]; then
  DB_NAME="myproject"
else
  # Sanitize branch name → valid postgres identifier
  DB_NAME="myproject_$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g')"
  DB_NAME="${DB_NAME:0:63}"  # postgres max identifier length
fi

# Create if it doesn't exist
docker exec my-postgres psql -U myuser -d postgres -c \
  "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';" \
  | grep -q 1 || \
  docker exec my-postgres psql -U myuser -d postgres -c \
  "CREATE DATABASE \"$DB_NAME\";"

# Write connection string to .env
DATABASE_URL="postgresql://myuser:mypass@localhost:5433/${DB_NAME}"
export DATABASE_URL

# Apply all existing migrations + generate client
npx prisma migrate deploy
npx prisma generate
```

**Result**: `feature-url-slugs` uses `myproject_feature_url_slugs`. `feature-search` uses `myproject_feature_search`. No drift. No resets.

### Non-Interactive Tooling

AI agents run in non-interactive terminals. Commands that prompt for confirmation (`prisma migrate dev`, `npm init`, `rm -i`) will hang or fail.

**The pattern**: wrap interactive tools with non-interactive scripts.

```bash
#!/usr/bin/env bash
# scripts/migrate-dev.sh <migration-name>
# Replaces: prisma migrate dev --name <name>

set -euo pipefail
MIGRATION_NAME="$1"

# Load DATABASE_URL from .env if not set
if [[ -z "${DATABASE_URL:-}" ]]; then
  DATABASE_URL=$(grep '^DATABASE_URL=' .env | cut -d= -f2- | tr -d '"')
fi
export DATABASE_URL

# Generate SQL diff (non-interactive — no prompts)
DIFF_SQL=$(npx prisma migrate diff \
  --from-config-datasource \
  --to-schema prisma/schema.prisma \
  --script)

if [[ -z "$DIFF_SQL" || "$DIFF_SQL" == "-- This is an empty migration." ]]; then
  echo "No schema changes detected."
  exit 0
fi

# Create migration directory
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
MIGRATION_DIR="prisma/migrations/${TIMESTAMP}_${MIGRATION_NAME}"
mkdir -p "$MIGRATION_DIR"
echo "$DIFF_SQL" > "$MIGRATION_DIR/migration.sql"

# Apply (non-interactive)
npx prisma migrate deploy

# Regenerate client
npx prisma generate

echo "Migration complete: $MIGRATION_DIR"
```

**Why `migrate diff` instead of `migrate dev`?**

`prisma migrate dev` is designed for humans — it prompts on warnings ("this might delete data"), drift detection, and schema conflicts. There's no `--force` or `--yes` flag. The `migrate diff` command generates the same SQL but never prompts. Combined with `migrate deploy` (also non-interactive), you get the same result without the interactivity.

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
if [ "$SKILL" != "speckit.implement" ]; then
  exit 0
fi

cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
"MANDATORY: Run lint and test for ALL affected apps before declaring done.
Fix any failures. Do NOT skip this step."}}
EOJSON
```

This hook fires every time `/implement` finishes. The agent receives the message as if the system told it — it can't ignore it. Without this hook, the agent frequently says "implementation complete!" without running tests.

---

## Shared Permissions

Claude Code asks for permission before running commands. In the main checkout, you approve `git`, `docker`, `bun`, etc. once and they're saved to `.claude/settings.local.json`. But that file is gitignored — **worktrees don't inherit those permissions**.

**The fix**: Create a committed `.claude/settings.json` with core permissions:

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
      "Bash(cp:*)",
      "Bash(mkdir:*)",
      "Bash(rm:*)",
      "Bash(docker:*)",
      "Bash(bun:*)",
      "Bash(bunx:*)",
      "Bash(npx:*)",
      "Bash(node:*)",
      "Bash(./scripts:*)",
      // MCP tools
      "mcp__playwright__browser_navigate",
      "mcp__playwright__browser_click",
      "mcp__playwright__browser_snapshot",
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

MCP (Model Context Protocol) servers extend what the agent can do beyond reading files and running commands.

### Configured Servers

| Server | Purpose | When to use |
|--------|---------|-------------|
| **Chrome DevTools** | Screenshots, DOM inspection, console logs | UI verification (primary) |
| **Playwright** | Automated browser flows | Multi-step testing (fallback) |
| **Prisma** | Schema inspection, migration status | Database work |
| **Docker** | Container management, logs | Dev environment issues |
| **GitHub** | PR reviews, issue tracking, code search | Repo operations |
| **Linear** | Issue creation, status updates | Bug tracking |
| **Context7** | Framework documentation lookup | Before proposing patterns |

### Usage Priority

The key insight: **not all tools are equal**. Chrome DevTools is faster and more visual than Playwright. Context7 documentation is more reliable than the agent's training data.

```jsonc
// .mcp.json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["@anthropic-ai/chrome-devtools-mcp@latest"],
      "env": { "CHROME_CDP_URL": "http://localhost:9222" }
    },
    "playwright": {
      "command": "npx",
      "args": ["@anthropic-ai/playwright-mcp@latest"]
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
    // ...
  }
}
```

**Rule in CLAUDE.md**: "Use Chrome DevTools MCP as the PRIMARY testing tool. Use Playwright only as a fallback." This prevents the agent from defaulting to heavier automation when a screenshot would suffice.

---

## Memory: Teaching the Agent Over Time

Claude Code's memory system persists across conversations. When the agent makes a mistake and you correct it, the correction is saved — and applies to all future sessions.

### Memory Types

| Type | What it stores | Example |
|------|---------------|---------|
| **feedback** | Corrections + confirmations | "Never run `prisma migrate dev` directly — use the wrapper script" |
| **user** | Your role, expertise, preferences | "Senior engineer, deep Go expertise, new to React" |
| **project** | Ongoing work, deadlines, context | "Merge freeze starts March 5 for mobile release" |
| **reference** | Pointers to external systems | "Pipeline bugs are tracked in Linear project INGEST" |

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
- [feedback_pr_base_staging.md] — All PRs target staging, not main
- [feedback_backend_docker_only.md] — Backend runs via docker compose, never bun run dev
- [project_monorepo_migration.md] — Migrated from 4 repos to monorepo on 2026-03-17
```

**Key insight**: Record both **failures** (corrections) and **successes** (confirmed approaches). If you only save mistakes, the agent becomes overly cautious and stops making good judgment calls.

---

## CI Integration

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

### CI Pipeline Structure

```yaml
# .github/workflows/ci-backend.yml
on:
  pull_request:
    paths: ['apps/backend/**']
jobs:
  test:
    services:
      postgres:
        image: postgres:17
      redis:
        image: redis:7
    steps:
      - run: bun install
      - run: bunx prisma generate
      - run: bunx prisma migrate deploy
      - run: bun run lint
      - run: bun run test
```

Each app has its own CI workflow triggered by path filters. Only affected apps run on each PR.

---

## Testing

Testing has three layers: **local validation** (lint + unit tests), **QA testing** (browser-based flows), and **CI** (automated on every PR).

### Local Validation

After implementation, the agent runs lint and tests for all affected apps:

```bash
# Backend — Jest tests require Docker compose running (postgres + redis)
cd apps/backend && docker compose up -d  # ensure DB is available
cd apps/backend && bun run lint && bun run test

# Frontend/Dashboard/Manager — lint only (no unit tests at this stage)
cd apps/frontend && bun run lint
cd apps/manager && bun run lint
cd apps/dashboard && bun run lint
```

**Backend tests require infrastructure**: The dev Docker compose must be running (postgres on port 5433, redis on 6379), Prisma client must be generated, and migrations must be applied. The `PostToolUse` hook on `/implement` enforces this gate — the agent can't skip it.

### QA Testing (Browser-Based)

QA uses a structured test plan (`qa/test-plan-ai-agent.md`) executed against the local dev stack via MCP servers.

**Priority**: Chrome DevTools MCP first (screenshots, console inspection, network monitoring), Playwright MCP as fallback (multi-step auth flows, file uploads, headless automation).

**Test plan structure**:

```markdown
# Suite 1: Authentication (AF-AUTH) — 8 flows
# Suite 2: Polst Lifecycle (AF-POLST) — 9 flows
# Suite 3: Voting (AF-VOTE) — 6 flows
# ...
# Suite 19: Full-Text Search (AF-SEARCH) — 7 flows
```

Each test case has:
- **Dependencies** (which earlier tests must pass first)
- **Actions** in pseudocode
- **Verification checklist** (what to assert)

**Execution order matters**: Tests that create data run first. Auth creates accounts, Polst creates content, then everything else builds on that data.

**Beyond the test plan**: The agent monitors for network errors on every page — 4xx, 5xx, CORS errors, uncaught exceptions. These are recorded even when not part of the test plan.

**Results** go to `qa/results-<date>/results.md` with screenshots in the same directory.

### Conflict Detection in CI

A common pitfall: the PR has merge conflicts, but the agent doesn't check — it polls CI status and sees no workflows running (GitHub doesn't run workflows on conflicting PRs). The agent then says "no checks reported" and stalls.

**The fix**: `/wait-ci` checks `gh pr view --json mergeable` before declaring success. If `CONFLICTING`, it reports the conflict instead of waiting forever. The CLAUDE.md workflow also includes an explicit conflict check step after creating the PR.

---

## Issue Tracking with Linear

When QA testing or code review uncovers bugs, they're tracked in **Linear** via MCP.

### Workflow: Bug Discovery → Ticket → Fix

```
QA testing finds bug
    │
    ▼
Create Linear ticket (via MCP)
    │  Team: Polst
    │  State: Backlog
    │  Labels: claude-ticket, needs-review
    │  Attach: screenshot, repro steps, expected vs actual
    │
    ▼
Developer picks up ticket
    │
    ▼
Fix → Lint/Test → PR → CI → Merge → Deploy
    │
    ▼
Re-test the specific QA flow → Close ticket
```

### Rules

- **One ticket per issue** — don't batch multiple bugs into one ticket.
- **Labels**: `claude-ticket` (created by the AI agent) and `needs-review` (needs human triage).
- **Screenshots are mandatory** when the bug is visual.
- **Reproduction steps** should be specific enough for another developer (or agent) to reproduce.

### Integration with the Spec Workflow

When `/speckit.taskstoissues` runs, it converts task items from `tasks.md` into Linear issues — one issue per task, with dependencies mapped. This bridges the spec-driven workflow with the issue tracker.

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

Each git worktree gets its own Postgres database (`myproject_feature_slugs`, `myproject_feature_search`).

**Why**: Shared databases cause migration drift. Branch A applies migration X. Branch B doesn't have migration X in its migration directory. Prisma detects drift and refuses to proceed. The only fix is a full database reset — destroying all dev data. Per-worktree databases eliminate this entirely.

### "Non-interactive scripts over interactive commands"

Wrapper scripts replace any command that prompts for confirmation.

**Why**: AI agents run in non-interactive terminals. `prisma migrate dev` prompts for "are you sure?" on warnings. There's no `--yes` flag. The script uses `prisma migrate diff` (generates SQL, never prompts) + `prisma migrate deploy` (applies SQL, never prompts) to achieve the same result.

---

## Setting This Up From Scratch

### 1. Create the directory structure

```
.claude/
  commands/          # Slash command templates
    specify.md
    plan.md
    tasks.md
    implement.md
    wait-ci.md
  hooks/             # Pre/Post tool use hooks
    worktree-on-specify.sh
    block-spec-in-main.sh
    post-implement-lint.sh
  settings.json      # Shared permissions (committed)
.specify/
  memory/
    constitution.md  # Project governance
  templates/
    spec-template.md # Spec structure template
scripts/
  migrate-dev.sh         # Non-interactive migrations
  worktree-db-setup.sh   # Per-branch database setup
  cleanup-worktree.sh    # Worktree + database cleanup
CLAUDE.md                # Agent instructions
.mcp.json                # MCP server configuration
```

### 2. Start with CLAUDE.md

This is the agent's "onboarding doc." Write it like you're onboarding a new developer — but one that follows instructions literally.

```markdown
# My Project

## Commands
bun install              # Install dependencies
docker compose up -d     # Start dev environment
bun run dev              # Start dev server

## Rules
- Always run lint before declaring work done: `bun run lint`
- Always run tests: `bun run test`
- Never commit directly to main — create PRs targeting staging
- Use ./scripts/migrate-dev.sh for database migrations (never prisma migrate dev)
```

### 3. Add a constitution

Start simple. Add principles as you discover them through actual development.

### 4. Add hooks one at a time

Start with the post-implement lint hook (highest impact). Add others as pain points emerge.

### 5. Build the memory over time

Don't pre-populate memory. Let it grow organically from corrections and confirmations during real work. The best memories come from "no, don't do that" moments.

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
