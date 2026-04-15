# Feature Specification: Fix /trc.specify worktree provisioning gap

**Feature Branch**: `TRI-26-worktree-provisioning`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "Fix /trc.specify worktree provisioning gap — when worktree-setup is enabled, the block creates the worktree but never installs dependencies or runs the project's worktree setup script, leaving the agent stranded without node_modules or a per-worktree database."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Feature work begins in a fully provisioned worktree (Priority: P1)

A developer on a monorepo project invokes `/trc.specify "<feature>"`. The project's `tricycle.config.yml` has `worktree.enabled: true`, a configured `package_manager`, a `worktree.setup_script`, and an `env_copy` list. When the command finishes, the agent is already inside a new worktree where dependencies are installed, the setup script has run to completion (per-worktree database provisioned, `.env` files copied, migrations applied), and every file listed in `env_copy` is present. No follow-up instructions are required from the user.

**Why this priority**: This is the entire reason the issue was filed. Every other user story is secondary to restoring the "one command lands me in a ready-to-code environment" promise that the worktree-setup block currently breaks.

**Independent Test**: Run `/trc.specify "add X"` in a project configured as above and confirm, without any further prompts, that `node_modules/` exists at the worktree root, the setup script's side-effects are visible (e.g., per-worktree DB file, copied `.env`), and every `env_copy` path resolves inside the worktree.

**Acceptance Scenarios**:

1. **Given** a project with `worktree.enabled: true`, `project.package_manager: bun`, `worktree.setup_script: apps/backend/scripts/worktree-db-setup.sh`, and a non-empty `worktree.env_copy` list, **When** the user runs `/trc.specify "<feature>"`, **Then** the new worktree contains installed dependencies, the setup script has executed, and every `env_copy` path exists inside the worktree.
2. **Given** the same project, **When** `worktree.setup_script` fails (non-zero exit), **Then** the command stops with a clear error that names the failing script and does not silently continue into spec generation on a half-provisioned worktree.
3. **Given** the same project, **When** the setup script completes but one of the `env_copy` paths is still missing, **Then** the command fails loudly, reports which path is missing, and does not claim success.

---

### User Story 2 - Projects without worktree provisioning still work unchanged (Priority: P1)

A developer on a simpler project has `worktree.enabled: true` but no `setup_script` and no `env_copy`. They run `/trc.specify "<feature>"` and expect the existing behavior: a fresh worktree with the spec directory and template, nothing more. The fix must not introduce new failure modes or required config for projects that previously worked.

**Why this priority**: Backward compatibility is explicitly called out as a constraint. A regression here would break every existing consumer of the `worktree-setup` block.

**Independent Test**: Run `/trc.specify "<feature>"` in a project where `worktree.setup_script` and `worktree.env_copy` are unset. Confirm the worktree is created, the spec directory is initialized, and the command succeeds with no errors related to missing scripts or unknown paths.

**Acceptance Scenarios**:

1. **Given** a project with `worktree.enabled: true` but no `setup_script` and no `env_copy`, **When** the user runs `/trc.specify "<feature>"`, **Then** the worktree is created and the command succeeds without attempting to run a setup script or verify any env files.
2. **Given** a project with only `setup_script` set (no `env_copy`), **When** the user runs `/trc.specify "<feature>"`, **Then** the setup script runs and the env-copy verification step is a no-op.
3. **Given** a project with `worktree.enabled: false`, **When** the user runs `/trc.specify "<feature>"`, **Then** no provisioning logic runs at all (the block is inactive) and the existing non-worktree flow is preserved.

---

### User Story 3 - Package manager is selected from config, not hardcoded (Priority: P2)

A project using `npm` (or `pnpm`, or `yarn`) invokes `/trc.specify` and expects the provisioning step to run `npm install` (or the equivalent), not `bun install`. The fix must honor `project.package_manager` from `tricycle.config.yml`.

**Why this priority**: Explicitly called out as a constraint ("not hardcoded to bun"). Without this, the fix would solve the gap for polst while creating the same gap for any other project.

**Independent Test**: In a project with `project.package_manager: npm`, run `/trc.specify "<feature>"` and confirm the install command executed was `npm install`, not `bun install`.

**Acceptance Scenarios**:

1. **Given** `project.package_manager: bun`, **When** provisioning runs, **Then** the install command is `bun install`.
2. **Given** `project.package_manager: npm`, **When** provisioning runs, **Then** the install command is `npm install`.
3. **Given** `project.package_manager: pnpm`, **When** provisioning runs, **Then** the install command is `pnpm install`.
4. **Given** `project.package_manager: yarn`, **When** provisioning runs, **Then** the install command is `yarn install`.
5. **Given** `project.package_manager` is unset, **When** provisioning runs, **Then** the system falls back to a sensible default (`npm install`) rather than erroring.

---

### Edge Cases

- **Setup script path exists in config but the file is missing on disk**: command fails loudly with a clear error naming the missing script path, rather than silently skipping it.
- **Setup script is present but not executable**: permissions error is surfaced, not swallowed.
- **`env_copy` contains a path that already existed before the setup script ran**: verification still passes (verification is a post-condition, not proof of script activity).
- **`env_copy` path is relative and resolves differently in the worktree vs. main checkout**: verification must resolve paths relative to the worktree root.
- **Worktree already exists from a previous aborted run**: existing `create-new-feature.sh` failure mode is preserved — the fix does not add recovery logic for this case.
- **Dependency install fails (network down, lockfile conflict)**: command stops and surfaces the install failure rather than proceeding into the setup script against a broken `node_modules`.
- **Monorepo with per-app `node_modules`**: the install command runs from the worktree root; per-app installs, if needed, are the responsibility of `worktree.setup_script`, not this fix.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The specify workflow MUST, when the `worktree-setup` block is active and a worktree is being created, install dependencies inside the new worktree using the package manager declared in `project.package_manager`.
- **FR-002**: The specify workflow MUST, when `worktree.setup_script` is set in `tricycle.config.yml`, execute that script from the worktree root after dependency installation and before spec authoring begins.
- **FR-003**: The specify workflow MUST, after the setup script has run, verify that every path listed in `worktree.env_copy` exists inside the worktree, and MUST fail with a clear error naming the missing path(s) if any are absent.
- **FR-004**: The specify workflow MUST preserve existing behavior for projects that do not configure `worktree.setup_script` and/or `worktree.env_copy` — those sub-steps MUST become no-ops rather than errors.
- **FR-005**: The specify workflow MUST NOT hardcode any package manager; the choice MUST come from `project.package_manager`, with a sensible default when unset.
- **FR-006**: The fix MUST NOT require changes to `CLAUDE.md` or any user-authored documentation; the entire fix MUST live under `.trc/`.
- **FR-007**: The specify workflow MUST fail loudly and stop the command if dependency installation exits non-zero, rather than proceeding into the setup script or spec authoring on a broken worktree.
- **FR-008**: The specify workflow MUST fail loudly and stop the command if `worktree.setup_script` exits non-zero.
- **FR-009**: The `worktree-setup` optional block MUST surface `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` as part of its configuration handoff, so the feature-setup block (or the script it delegates to) has a single source of truth instead of re-parsing `tricycle.config.yml`.
- **FR-010**: The fix MUST apply to any project that enables the `worktree-setup` block, not only to projects resembling the original reporter's setup.
- **FR-011**: All provisioning steps (package install, setup script execution, env-copy verification) MUST run from the worktree root so that relative paths resolve correctly.
- **FR-012**: The specify workflow SHOULD consolidate the provisioning recipe into a single invocation of `.trc/scripts/bash/create-new-feature.sh` (via a new `--provision-worktree` flag or equivalent) so the markdown block narrates one step instead of a multi-step recipe the agent can skip. If this is not feasible, the markdown block MUST spell out each sub-step explicitly and in a way that cannot be partially executed.

### Key Entities *(include if feature involves data)*

- **`tricycle.config.yml`**: Source of truth for worktree provisioning inputs. Relevant fields: `project.package_manager`, `worktree.enabled`, `worktree.setup_script`, `worktree.env_copy`, `project.name`.
- **Worktree**: A git worktree created under `../{project.name}-{branch}` that, after provisioning, must contain installed dependencies, the side-effects of `setup_script`, every file in `env_copy`, and the standard spec scaffolding (`specs/<branch>/spec.md`, `.trc/`).
- **`feature-setup.md` block** (`.trc/blocks/specify/feature-setup.md`): The block whose Step 2b currently ends too early; the primary site of the fix (either directly extended with sub-steps or refactored to delegate to the script).
- **`worktree-setup.md` optional block** (`.trc/blocks/optional/specify/worktree-setup.md`): The block whose Configuration section currently surfaces only `project.name` and `path_pattern`; must be extended to hand off the three additional fields.
- **`create-new-feature.sh`** (`.trc/scripts/bash/create-new-feature.sh`): The script that today handles branch creation, worktree creation, and spec scaffolding. The preferred fix adds a `--provision-worktree` flag that bundles install + setup-script + verify into a single call.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a project configured with `worktree.enabled: true`, `project.package_manager`, `worktree.setup_script`, and a non-empty `worktree.env_copy`, running `/trc.specify "<feature>"` leaves the agent in a worktree that is 100% ready for code work (dependencies installed, setup script completed, every env-copy path present) with zero additional prompts or instructions from the user.
- **SC-002**: In a project with `worktree.enabled: true` but no `setup_script` and no `env_copy`, running `/trc.specify "<feature>"` succeeds with the same observable outcome as before the fix (worktree exists, spec directory initialized) — measured as a regression test that passes on both the pre-fix and post-fix code paths.
- **SC-003**: 100% of supported package managers (`bun`, `npm`, `pnpm`, `yarn`) produce the correct install command when specified as `project.package_manager`; no test relies on the literal string `bun`.
- **SC-004**: When any provisioning sub-step fails (install non-zero, setup script non-zero, env-copy path missing), the command terminates with an error message that names the failing sub-step and the specific cause, and the user can identify the root cause without re-reading the source.
- **SC-005**: The number of manual follow-up instructions required from the user after `/trc.specify` in a fully configured worktree project drops from "several each time" to zero.
- **SC-006**: `CLAUDE.md` is unchanged by the fix (verified by diff).

## Assumptions

- Projects that use the `worktree-setup` block have already set `worktree.enabled: true`. Projects with `worktree.enabled: false` are out of scope — the block does not run and no provisioning happens.
- `tricycle.config.yml` already exposes `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` in the shape described by the issue; no schema migration is required.
- `worktree.env_copy` entries are file paths (possibly with simple globs), not directories. The fix treats them as paths to check for existence.
- The setup script itself is responsible for producing the files listed in `env_copy`; the fix only verifies the post-condition. It does not replace or duplicate what the setup script does.
- The preferred refactor into `create-new-feature.sh --provision-worktree` is acceptable to the project owners; if not, the fallback is to extend the markdown block with explicit sub-steps.
- A reasonable default package manager exists when `project.package_manager` is unset (the project-level default is `npm`).
