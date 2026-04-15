# Phase 0 Research: Fix /trc.specify worktree provisioning gap

**Feature**: TRI-26-worktree-provisioning
**Date**: 2026-04-15

The spec has no `[NEEDS CLARIFICATION]` markers. The problem is entirely contained in files already in this repository, so research here is about confirming implementation choices, not investigating unknowns.

## Decision 1 — Put provisioning logic in `create-new-feature.sh --provision-worktree`

**Decision**: Add a single new flag, `--provision-worktree`, to `.trc/scripts/bash/create-new-feature.sh`. This flag triggers four ordered side-effects after the script has created the branch and the worktree:
1. Copy `.trc/` from the main checkout into the worktree (idempotent).
2. Run `{project.package_manager} install` from the worktree root.
3. Execute `worktree.setup_script` from the worktree root, if set.
4. Verify every path in `worktree.env_copy` exists under the worktree root.

**Rationale**:
- FR-012 explicitly prefers this shape over "more markdown sub-steps".
- The markdown block is interpreted by an agent, which has historically skipped sub-steps — that skip is the root cause of this ticket. A single script invocation removes that entire class of failure.
- A script is unit-testable in `tests/test-*.js`; a markdown recipe is not.
- The script already handles branch + worktree creation, so provisioning is its natural next responsibility.

**Alternatives considered**:
- **Extend `feature-setup.md` with more explicit sub-steps (no script change)**. Rejected: same failure mode as today. Even with explicit numbered sub-steps, the agent can skip any of them, and we'd be fixing the problem by asking more nicely.
- **New standalone script `provision-worktree.sh`**. Rejected: adds surface area, forces two script invocations from the block, doubles the chance of a partial run.
- **Inline provisioning into `setup-plan.sh` or a new hook**. Rejected: wrong phase — provisioning must happen before spec authoring, not before plan.

## Decision 2 — Parse the three new config fields in-script using the existing YAML idiom

**Decision**: Add a `parse_worktree_config` helper to `.trc/scripts/bash/common.sh` that reads `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` from `tricycle.config.yml`. Emit results as `KEY=VALUE` lines on stdout (env_copy items each on their own line prefixed `env_copy=`), the same shape `parse_block_overrides` uses today.

**Rationale**:
- Matches the line-based YAML parsing already in `common.sh` (`parse_chain_config`, `parse_block_overrides`), keeping the codebase consistent.
- Bash 3.2 compatible (no associative arrays).
- No new system dependencies — `yq` is not a project dependency and adding it would break the Bash-only constraint from the config.
- Single point of truth: if the YAML shape changes later, we update one helper.

**Alternatives considered**:
- **Shell out to `yq`**. Rejected: new system dependency; the project's helpers have deliberately avoided `yq`.
- **Python one-liner**. Rejected: Python is not in Active Technologies; CLAUDE.md forbids mixing package managers.
- **Node.js one-liner**. Rejected: would work (tests already use Node), but violates the "Bash 3.2+ only" ceiling the rest of `common.sh` holds to.

## Decision 3 — `env_copy` verification collects all misses, then fails once

**Decision**: Loop through every entry in `worktree.env_copy`, check `[ -e "$worktree_root/$path" ]`, collect every miss, then exit non-zero with a single error message that lists all missing paths.

**Rationale**:
- FR-003 requires naming the missing path(s) — plural is explicit.
- Fail-fast on the first miss forces the user into a painful one-at-a-time loop ("fix, rerun, discover next miss, repeat"). Collecting all misses lets them fix once.
- Marginal implementation cost: a Bash array of misses.

**Alternatives considered**:
- **Fail on the first missing path**. Rejected: worse UX for the explicit reason above.
- **Warn instead of fail**. Rejected: FR-003 says "fail with a clear error"; a warning would let `/trc.specify` proceed on a broken worktree.

## Decision 4 — `--provision-worktree` is additive and implies `--no-checkout`

**Decision**: `--provision-worktree` can be combined with existing flags without conflicts. It implies `--no-checkout` (the provisioning runs *inside* the worktree, not the main checkout), but does not replace, remove, or mutate any existing flag's semantics.

**Rationale**:
- Backward compatibility (FR-004, SC-002): every existing invocation of `create-new-feature.sh` must continue to work exactly as before.
- Making provisioning opt-in via an explicit flag keeps the main-checkout path (no worktree) untouched.
- Implying `--no-checkout` is safe because provisioning *requires* a worktree — there is no meaningful "provision the main checkout" use case.

**Alternatives considered**:
- **Make provisioning the default whenever `worktree-setup` is active**. Rejected: too invasive, hides the control point, makes the test matrix larger.
- **Require the caller to pass both `--no-checkout` and `--provision-worktree`**. Rejected: unnecessary friction; the markdown block would just always pass both.

## Decision 5 — `worktree-setup.md` narrates the handoff; the script owns the parse

**Decision**: The `worktree-setup.md` optional block's Configuration section is extended to list `project.package_manager`, `worktree.setup_script`, and `worktree.env_copy` as fields that are surfaced to the feature-setup block. The actual parsing stays in `create-new-feature.sh` — the markdown only *documents* that these fields flow into the `--provision-worktree` invocation.

**Rationale**:
- FR-009 requires a single handoff point. Duplicating parse logic between the markdown block and the script would violate that.
- The markdown block is the right place to explain *what* happens ("the script will install deps and run your setup script"), not *how* to parse YAML.
- Keeps the block short and agent-proof.

**Alternatives considered**:
- **Parse the YAML in the markdown block via an embedded shell snippet**. Rejected: duplicates logic; parse errors surface in the wrong place.
- **Skip updating the block entirely**. Rejected: FR-009 explicitly requires the handoff to be surfaced.

## Summary

| # | Decision | Risk if wrong | Mitigation |
|---|----------|---------------|------------|
| 1 | `--provision-worktree` flag in the script | Reintroduces agent-skip class of bugs | Backed by unit tests — script is deterministic |
| 2 | In-script YAML parse via `common.sh` helper | Parse drift vs. the real YAML | Matches existing helpers; covered by tests |
| 3 | Batch env_copy miss reporting | User hits one miss at a time | Straightforward array loop in Bash |
| 4 | Additive flag, implies `--no-checkout` | Regression in existing flows | Zero-touch on the non-worktree path |
| 5 | Block narrates, script parses | Fields get re-parsed somewhere else later | Code review + `grep` for duplicate parsing |

All five decisions are low-risk, contained to files listed in the plan, and compatible with the "no CLAUDE.md edits" and "Bash 3.2+ only" constraints.
