# Implementation Plan: Fix /trc.specify worktree provisioning gap

**Branch**: `TRI-26-worktree-provisioning` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/TRI-26-worktree-provisioning/spec.md`
**Current VERSION**: `0.16.4` → planned bump: **patch** (`0.16.5`). This is a correctness fix, not a new user-facing feature.

## Summary

`/trc.specify`'s `worktree-setup` block creates a git worktree but never installs dependencies or runs the project's configured `worktree.setup_script`, so the agent lands in a half-baked worktree every time. The fix is a single new entry point in `create-new-feature.sh` — `--provision-worktree` — that bundles four ordered side-effects: copy `.trc/`, run `{package_manager} install`, execute `worktree.setup_script`, and verify every `worktree.env_copy` path exists. `feature-setup.md` Step 2b collapses from a multi-step recipe the agent can skip into one script invocation. `worktree-setup.md` is extended to surface the three new config fields as part of its configuration handoff. All failures are loud; missing config is a no-op, not an error. `CLAUDE.md` is untouched.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default), Node.js (tests only)
**Primary Dependencies**: None new — reuses existing `common.sh` helpers, `json_builder.sh` patterns, and the in-repo YAML parsing style already used by `parse_chain_config` / `parse_block_overrides`
**Storage**: Filesystem only — reads `tricycle.config.yml`, writes into an existing worktree directory
**Testing**: `bash tests/run-tests.sh` (shell smoke test) + `node --test tests/test-*.js` (unit-style)
**Target Platform**: Developer workstation (macOS + Linux); no remote execution
**Project Type**: CLI / workflow tooling (single-app `tricycle-pro` / `.trc/` workflow framework)
**Performance Goals**: Not performance-sensitive. The script runs once per `/trc.specify` invocation and is dominated by the dependency install, which we do not control.
**Constraints**:
- Must keep Bash 3.2 compatibility (no associative arrays, no `readarray`).
- Must not mutate `CLAUDE.md` or any file outside `.trc/` and `specs/`.
- Must not break existing tests (`run-tests.sh` + every `test-*.js`).
- Must be backwards compatible: projects without `setup_script` / `env_copy` get no-ops, not errors.
- Must not hardcode any package manager.
**Scale/Scope**: One script extended (~80 new LoC), two markdown blocks updated, one new test file. Target: < 200 net changed lines.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.trc/memory/constitution.md` currently contains only the placeholder seed (`Run /trc.constitution to populate this file`). **No constitutional gates apply.** This check is recorded as PASSED with a note: once the constitution is populated, re-run this gate.

Implicit gates from project conventions (`CLAUDE.md`):
- [x] Lint & test before done — plan includes `bash tests/run-tests.sh` as an explicit exit criterion (FR-MUST from CLAUDE.md, NONNEGOTIABLE).
- [x] Package manager = `npm` (for this repo's own tests). The feature under development is generic, but the project's *own* test harness must continue to run with `npm` / bare `node`.
- [x] No changes to `CLAUDE.md`.

## Phase 0: Outline & Research

The spec has no `[NEEDS CLARIFICATION]` markers, and the problem is well-scoped to files already in this repository. Research is limited to confirming assumptions about the existing code, not investigating unknowns.

Findings consolidated in [research.md](./research.md):

1. **Decision**: Put provisioning logic in `create-new-feature.sh --provision-worktree`, not in the markdown block. **Rationale**: FR-012 prefers this, and the markdown block is an "agent-interpreted recipe" which the agent has historically skipped sub-steps of (root cause of this ticket). A single script invocation is deterministic. **Alternatives rejected**: (a) Extending `feature-setup.md` with more sub-steps — same failure mode as today; (b) A new standalone `provision-worktree.sh` — adds surface area without benefit.
2. **Decision**: Parse `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` directly in `create-new-feature.sh` using the same line-based YAML pattern used by `parse_chain_config` in `common.sh`. **Rationale**: No new dependencies (Bash 3.2+ only); consistent with existing code style; `yq` is not a project dependency. **Alternatives rejected**: (a) Shelling out to `yq` — adds a system dependency; (b) Python one-liner — CLAUDE.md forbids mixing package managers and we don't ship Python.
3. **Decision**: Verification of `env_copy` is a simple `[ -e "$worktree_root/$path" ]` check per entry, emitting every missing path before exiting non-zero. **Rationale**: FR-003 + Edge Case "fail loudly and name the missing path(s)" — collecting all misses gives the user a single, actionable error instead of a one-at-a-time failure loop. **Alternatives rejected**: Fail-fast on the first missing path — worse UX.
4. **Decision**: The `--provision-worktree` flag is **additive**. It implies `--no-checkout` (because provisioning happens inside the worktree, not the main checkout), but does not remove or alter any existing flag semantics. **Rationale**: Backward compatibility (FR-004, SC-002). **Alternatives rejected**: Making `--provision-worktree` the default whenever worktree-setup is active — too invasive and hides the control point.
5. **Decision**: `worktree-setup.md` gains a "Configuration" block that **reads** the three new fields and **documents** them as the handoff. The actual parsing stays in the script; the markdown just narrates what will flow into the `--provision-worktree` invocation. **Rationale**: FR-009 (single handoff point) without duplicating parse logic in two places.

**Output**: [research.md](./research.md) with the five decisions above. No `NEEDS CLARIFICATION` left.

## Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete ✓

### Data Model

Documented in [data-model.md](./data-model.md). The "entities" here are not runtime data but config shape and script I/O:

- **`ProvisioningConfig`** (parsed from `tricycle.config.yml`):
  - `package_manager: string` (default `npm` when unset)
  - `setup_script: string | null` (relative to repo root; null/unset = no-op)
  - `env_copy: string[]` (paths relative to worktree root; empty/unset = no-op)
- **`ProvisioningInputs`** (script arguments):
  - `worktree_path: string` (absolute)
  - `source_trc: string` (absolute path to `.trc/` in main checkout)
  - `ProvisioningConfig` (inlined above, read from config in the script)
- **`ProvisioningOutcome`** (observable post-condition):
  - `.trc/` copied into worktree (no-op if already present)
  - `{package_manager} install` exited 0 inside worktree root
  - `setup_script` exited 0 (or absent)
  - Every `env_copy[i]` resolves to an existing path under worktree root

### Contracts

This project is a CLI/workflow tool. The contract surface is the **CLI flags of `create-new-feature.sh`** and the **markdown block handoff**. Contract artifacts in [contracts/](./contracts/):

- [`contracts/create-new-feature-cli.md`](./contracts/create-new-feature-cli.md): New `--provision-worktree` flag spec (synopsis, preconditions, success/failure exits, error message format).
- [`contracts/worktree-setup-handoff.md`](./contracts/worktree-setup-handoff.md): The exact set of variables the `worktree-setup.md` optional block must surface to `feature-setup.md` (name, source, fallback, lifetime).

### Quickstart

[quickstart.md](./quickstart.md) — a runnable, copy-pasteable demonstration in a throwaway repo:
1. `mkdir /tmp/prov-demo && cd /tmp/prov-demo && git init && npm init -y`
2. Drop in a minimal `tricycle.config.yml` with `worktree.enabled: true`, a `setup_script` that touches `.env.local`, and `env_copy: [.env.local]`.
3. Run `/trc.specify "add demo"` (simulated via direct script call).
4. Assert: `node_modules/` present, `.env.local` present, command exit 0.
5. Negative path: remove the script, rerun, observe the exact error message format.

### Agent Context Update

Run `.trc/scripts/bash/update-agent-context.sh claude` as the last step of Phase 1 to record:
- **New technology**: none (Bash 3.2+ already listed in `Active Technologies`).
- **Feature ID**: `TRI-26-worktree-provisioning`.
- **Recent Changes** entry: "TRI-26-worktree-provisioning: provisioning happens inside `create-new-feature.sh --provision-worktree`; extends `feature-setup.md` + `worktree-setup.md` handoff".

Manual sections between markers are preserved per the script's existing semantics.

### Post-Phase-1 Constitution Re-check

Still PASSED. Design introduces no new dependencies, no new files outside the plan's scope, and no rule that conflicts with `CLAUDE.md`. The test gate remains mandatory at implement time.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-26-worktree-provisioning/
├── plan.md              # This file
├── spec.md              # Produced by /trc.specify
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── create-new-feature-cli.md
│   └── worktree-setup-handoff.md
├── checklists/
│   └── requirements.md  # Produced by /trc.specify
└── tasks.md             # Produced by /trc.tasks (NOT this command)
```

### Source Code (repository root)

Single-app `.trc/` workflow project. No `src/` layout — the "source" is `.trc/scripts/` plus `.trc/blocks/`. Concrete paths touched by this feature:

```text
.trc/
├── scripts/
│   └── bash/
│       ├── create-new-feature.sh   # EXTEND: add --provision-worktree
│       └── common.sh               # EXTEND: add parse_worktree_config helper
└── blocks/
    ├── specify/
    │   └── feature-setup.md        # UPDATE: Step 2b calls --provision-worktree
    └── optional/
        └── specify/
            └── worktree-setup.md   # UPDATE: Configuration section surfaces new fields

tests/
├── run-tests.sh                    # EXISTING: entry point, do not reshape
├── test-worktree-provisioning.js   # NEW: unit-style node tests for the new helper
└── (existing test-*.js files)      # UNCHANGED

specs/TRI-26-worktree-provisioning/
└── (docs only; no code here)
```

**Structure Decision**: Single-app `.trc/` layout (the only option that applies to this repo). The feature lives entirely in `.trc/scripts/bash/` and `.trc/blocks/`. No new top-level directories.

## Complexity Tracking

No Constitution violations to justify — section intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_  | _(n/a)_    | _(n/a)_                              |

## Exit Criteria (for `/trc.implement`)

1. `.trc/scripts/bash/create-new-feature.sh --provision-worktree ...` runs to completion on a seeded fixture and leaves a ready worktree.
2. `.trc/scripts/bash/create-new-feature.sh --provision-worktree ...` fails loudly on each of: install non-zero, setup-script non-zero, missing `env_copy` path, missing setup-script file.
3. `bash tests/run-tests.sh` passes (MANDATORY per CLAUDE.md).
4. `node --test tests/test-*.js` passes, including the new `test-worktree-provisioning.js`.
5. `git diff -- CLAUDE.md` is empty (SC-006).
6. `VERSION` bumped from `0.16.4` to `0.16.5` by `/trc.implement` (patch bump; correctness fix).
