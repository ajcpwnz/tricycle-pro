# Contract: Assembly CLI Interface

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## Command: `tricycle assemble`

Assembles block files into command files based on chain and block configuration.

```bash
tricycle assemble [--dry-run] [--verbose]
```

| Option | Description |
|--------|-------------|
| --dry-run | Show what would be generated without writing files |
| --verbose | Show block composition details for each step |

## Behavior

1. Read `tricycle.config.yml` → extract `workflow.chain` and `workflow.blocks`
2. For each step in the chain:
   a. Collect enabled blocks from `.specify/blocks/{step}/`
   b. Apply config overrides (disable/enable/custom)
   c. Determine absorbed blocks from omitted steps
   d. Sort all blocks by `order`
   e. Validate: no required blocks disabled, all files exist
   f. Concatenate into `.claude/commands/trc.{step}.md`
3. For each step NOT in the chain:
   a. Generate minimal "blocked" stub in `.claude/commands/trc.{step}.md`
4. Generate `.claude/commands/trc.headless.md` based on chain
5. Update `.tricycle.lock` with new checksums
6. Non-chain commands (clarify, analyze, checklist, constitution, taskstoissues) are untouched

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Assembly successful |
| 1 | Configuration error (invalid chain, missing files) |
| 2 | Block validation error (required block disabled, scope mismatch) |

## Dry Run Output Example

```
Chain: [specify, plan, implement]

Step: specify (5 blocks)
  ✓ feature-setup (required, order: 10)
  ✓ chain-validation (required, order: 20)
  ✓ input-validation (required, order: 30)
  ✓ spec-writer (default, order: 40)
  ✓ quality-validation (default, order: 50)
  → .claude/commands/trc.specify.md

Step: plan (9 blocks — 2 absorbed from tasks)
  ✓ chain-validation (required, order: 10)
  ✓ setup-context (required, order: 20)
  ✓ constitution-check (default, order: 30)
  ✓ research (default, order: 40)
  ✓ design-contracts (default, order: 50)
  ✓ agent-context (default, order: 60)
  ✓ version-awareness (default, order: 70)
  + task-generation (absorbed from tasks, order: 130)
  + dependency-graph (absorbed from tasks, order: 140)
  → .claude/commands/trc.plan.md

Step: tasks (BLOCKED — not in chain)
  → .claude/commands/trc.tasks.md (stub)

Step: implement (6 blocks)
  ...
  → .claude/commands/trc.implement.md

Headless: 3 phases (specify → plan → implement)
  → .claude/commands/trc.headless.md
```
