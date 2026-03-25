# Data Model: Workflow Chains & Pluggable Blocks

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## Entity: Block

A named partial system prompt scoped to a specific workflow step.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | Unique identifier within step scope (e.g., "spec-writer") |
| step | enum | yes | One of: specify, plan, tasks, implement |
| description | string | yes | One-line description of block behavior |
| required | boolean | yes | If true, cannot be disabled by user config |
| default_enabled | boolean | yes | If true, included in default assembly |
| order | integer | yes | Composition sequence within step (lower = earlier) |
| content | markdown | yes | The partial system prompt text (file body) |

**Constraints**:
- `name` must match `/^[a-z][a-z0-9-]*$/` and be unique within step scope
- `required: true` implies `default_enabled: true`
- `order` range: 10-999. Built-in blocks use increments of 10 (10, 20, 30...) to allow custom insertion between

## Entity: Workflow Chain

An ordered sequence of step names defining the project's workflow.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| steps | list[string] | yes | Ordered step names |

**Valid configurations**:
- `[specify, plan, tasks, implement]` (default)
- `[specify, plan, implement]`
- `[specify, implement]`

**Constraints**: Must start with "specify", end with "implement", follow canonical order, no duplicates.

## Entity: Block Configuration

Per-project block overrides in `tricycle.config.yml`.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| step | string | yes | Step this config applies to |
| disable | list[string] | no | Default block names to disable |
| enable | list[string] | no | Optional block names to enable |
| custom | list[string] | no | Paths to custom block files |

**Constraints**:
- Cannot disable `required` blocks (error)
- Custom block paths must exist with valid frontmatter
- Custom block's `step` must match config section

## Block Decomposition: Specify Step

| Block Name | Required | Default | Order | Description |
|------------|----------|---------|-------|-------------|
| feature-setup | yes | yes | 10 | Create feature branch, run create-new-feature.sh |
| chain-validation | yes | yes | 20 | Validate step is in configured chain |
| input-validation | yes | yes | 30 | Validate prompt detail for chain length |
| spec-writer | no | yes | 40 | Generate spec content from description |
| quality-validation | no | yes | 50 | Spec quality checklist and validation loop |

## Block Decomposition: Plan Step

| Block Name | Required | Default | Order | Description |
|------------|----------|---------|-------|-------------|
| chain-validation | yes | yes | 10 | Validate step is in configured chain |
| setup-context | yes | yes | 20 | Run setup-plan.sh, load spec + constitution |
| constitution-check | no | yes | 30 | Constitution compliance gate |
| research | no | yes | 40 | Phase 0: research unknowns, generate research.md |
| design-contracts | no | yes | 50 | Phase 1: data model, contracts, quickstart |
| agent-context | no | yes | 60 | Update agent context files |
| version-awareness | no | yes | 70 | Note version for bump planning |

## Block Decomposition: Tasks Step

| Block Name | Required | Default | Order | Description |
|------------|----------|---------|-------|-------------|
| chain-validation | yes | yes | 10 | Validate step is in configured chain |
| prerequisites | yes | yes | 20 | Run check-prerequisites.sh |
| task-generation | no | yes | 30 | Generate tasks from plan/spec by user story |
| dependency-graph | no | yes | 40 | Create dependency ordering and parallel markers |

## Block Decomposition: Implement Step

| Block Name | Required | Default | Order | Description |
|------------|----------|---------|-------|-------------|
| chain-validation | yes | yes | 10 | Validate step is in configured chain |
| prerequisites | yes | yes | 20 | Pre-execution checks |
| checklist-validation | no | yes | 30 | Validate checklists before implementing |
| project-setup | no | yes | 40 | Project setup verification (ignore files) |
| task-execution | no | yes | 50 | Execute tasks phase by phase |
| version-bump | no | yes | 60 | Version bump after completion |

## Optional Blocks (not enabled by default)

| Block Name | Step | Description |
|------------|------|-------------|
| test-local-stack | implement | Test against local infrastructure stack |

## Absorption Matrix

| Chain Config | Omitted | Target | Absorbed Blocks (order offset +100 per step) |
|-------------|---------|--------|-----------------------------------------------|
| [S, P, T, I] | (none) | (none) | (none) |
| [S, P, I] | tasks | plan | task-generation (+100→130), dependency-graph (+100→140) |
| [S, I] | plan, tasks | specify | constitution-check (+100→130), research (+100→140), design-contracts (+100→150), agent-context (+100→160), version-awareness (+100→170), task-generation (+200→230), dependency-graph (+200→240) |

Only non-required, default-enabled blocks from omitted steps are absorbed. Infrastructure blocks (chain-validation, prerequisites, setup-context) are NOT absorbed.
