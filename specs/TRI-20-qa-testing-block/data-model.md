# Data Model: QA Testing Block

**Date**: 2026-03-30
**Branch**: TRI-20-qa-testing-block

## Entities

### QA Block File

**Location**: `core/blocks/optional/implement/qa-testing.md`

| Field | Value | Notes |
|-------|-------|-------|
| name | `qa-testing` | Must match config enable key |
| step | `implement` | Lives in implement step |
| description | QA testing gate — runs tests, reads instructions, halts on failure | |
| required | `false` | Optional block |
| default_enabled | `false` | Only enabled by `qa.enabled` or manual enable |
| order | `55` | After task-execution (50), before push-deploy (65) |
| companions | (none) | No cross-step dependencies |

### QA Instructions File

**Location**: `qa/ai-agent-instructions.md` (project root, user-maintained)

| Section | Purpose | Mutability |
|---------|---------|------------|
| Header / overview | Project testing overview | User-written |
| Prerequisites | Stack setup, env vars, service startup order | User-written |
| Operational rules | Tool preferences, data setup, cleanup | User-written |
| Learnings | Agent-appended discoveries | Agent-appended, dated |

### Config Surface

**Location**: `tricycle.config.yml`

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `qa.enabled` | boolean | `false` | Auto-enables qa-testing block in implement step |
| `apps[].test` | string | (none) | Test command per app, read by agent at runtime |
| `apps[].lint` | string | (none) | Lint command per app (existing, unchanged) |

No new config fields are introduced beyond `qa.enabled` (which already exists in the config schema).

## State Transitions

```
qa.enabled: false → Block not included in assembly
qa.enabled: true  → Block included at order 55

qa/ai-agent-instructions.md absent  → Agent skips instructions, runs tests directly
qa/ai-agent-instructions.md present → Agent reads and follows before running tests

Tests pass  → Agent proceeds to push-deploy block
Tests fail  → Agent retries (max 3), then HALT
```

## Relationships

```
tricycle.config.yml
  ├── qa.enabled ──→ assemble-commands.sh (auto-enable logic)
  ├── apps[].test ──→ qa-testing block (runtime read by agent)
  └── apps[].lint ──→ qa-testing block (runtime read by agent)

qa/ai-agent-instructions.md
  ├── read by ──→ qa-testing block (agent reads at runtime)
  └── appended by ──→ qa-testing block (agent writes learnings)

core/blocks/optional/implement/qa-testing.md
  ├── enabled by ──→ qa.enabled OR manual workflow.blocks.implement.enable
  ├── assembled into ──→ trc.implement.md (between task-execution and push-deploy)
  └── references ──→ qa-run skill (via standard skill injection, if installed)
```
