# Implementation Plan: One-way drift check (src → dst)

**Branch**: `TRI-34-drift-one-way` | **Date**: 2026-04-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `/specs/TRI-34-drift-one-way/spec.md`

## Summary

Narrow test-file refactor. Replace `tests/test-dogfood-drift.sh`'s bidirectional `diff -r` with a one-way walk: for each mapping pair, iterate every file under `core/<src>` and assert a byte-matching destination exists at `<dst>/<rel>`. Extras under `<dst>` (runtime-generated files like `.claude/hooks/.session-context.conf`) are intentionally not flagged — aligning the test with what `tricycle dogfood --yes` actually does.

No runtime code changes. No CLI surface. No new dependencies. The five-entry mapping table stays hardcoded in the test for scope containment; tightening the coupling with `bin/tricycle`'s `TRICYCLE_MANAGED_PATHS` is explicitly deferred (research R3).

**Version impact**: Patch bump: `0.20.1` → `0.20.2`. Test-harness fix, no observable runtime behavior change.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default).
**Primary Dependencies**: POSIX `find`, `cmp`, `diff` — all already used elsewhere in the suite.
**Storage**: None.
**Testing**: `bash tests/run-tests.sh`. The drift test itself is both the change and the verification — exercised by the full suite on every run.
**Target Platform**: macOS + Linux developer workstations.
**Project Type**: CLI / developer tooling (single-app meta-repo).
**Performance Goals**: < 500 ms test runtime (same order of magnitude as v0.20.1).
**Constraints**: Must not reintroduce bidirectional comparison (see contract invariants). Must preserve the actionable failure output shape (R6). Must continue to silently skip in consumer fixtures.
**Scale/Scope**: ~40 LoC rewrite of one test file (`tests/test-dogfood-drift.sh`). No other files touched except `VERSION` at the end.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.trc/memory/constitution.md` is a placeholder. No codified principles to violate. CLAUDE.md NONNEGOTIABLES observed:

- **Lint & Test Before Done**: `bash tests/run-tests.sh` before completion.
- **Worktree-before-side-effects**: Work is in `../tricycle-pro-TRI-34-drift-one-way/`.
- **Branching style**: `issue-number` + `TRI` — branch is `TRI-34-drift-one-way`.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-34-drift-one-way/
├── plan.md                       # This file
├── research.md                   # R1–R6 decisions (primitive, iteration, mapping coupling,
│                                 # fixture-test scope, orphan exclusion, output format)
├── data-model.md                 # Stateless — per-file states (match/missing/differ)
├── quickstart.md                 # 6 manual tests
├── contracts/
│   └── drift-check.md            # Test contract: exit codes, output shape, invariants
├── checklists/
│   └── requirements.md           # From /trc.specify
└── tasks.md                      # Phase 2 output (/trc.tasks)
```

### Source Code (repository root)

```text
tests/
└── test-dogfood-drift.sh         # REWRITTEN — one-way walk, cmp-based per-file check,
                                  # diff-based failure details. Invariant: no `diff -r`.
```

Nothing else changes. `bin/tricycle`, `tests/test-dogfood-cmd.sh`, and every other file stay as-is.

**Structure Decision**: Single-file rewrite in `tests/`. No new files. No changes to `core/` or `bin/`.

## Implementation phases

### Phase 0 — Research (complete)

See `research.md`. Six decisions:

1. `cmp -s` for happy-path identity, `diff` only on failure (actionable output).
2. `find -type f` walks `core/<src>` only — explicit one-way.
3. Mapping table stays hardcoded in the test for scope containment.
4. No fixture-based unit test for the drift test itself — integration via real suite is sufficient.
5. Orphan cleanup stays out of scope; future `tricycle dogfood --prune` if needed.
6. Failure-output format mirrors v0.20.1's shape (Drifted paths + Detail blocks + Fix line).

### Phase 1 — Design & Contracts (complete)

See `data-model.md` (stateless, per-file state machine), `contracts/drift-check.md` (exit codes + output + invariants), `quickstart.md` (6 tests mapped to FRs/SCs).

### Phase 2 — Tasks (delegated to `/trc.tasks`)

Skeleton:

1. Rewrite `tests/test-dogfood-drift.sh` per `contracts/drift-check.md`. Replace the `diff -r` loop with a `find`-based one-way walk using `cmp -s` + `diff` fallback.
2. Verify: with `.claude/hooks/.session-context.conf` present, the test exits 0.
3. Verify: intentionally drift a `core/` file, test fails with the expected output shape.
4. Verify: remove the drift, test passes again.
5. Run the full suite — must be 111/111 (or whatever the live count is) green, with the "no false positive on runtime files" holding in the main checkout.
6. VERSION bump `0.20.1` → `0.20.2` in the final commit.

## Version awareness

Current VERSION: `0.20.1`.
Planned next: `0.20.2` — patch bump. Test-harness-only change; no runtime behavior change observable to any consumer of `tricycle` commands.

## Complexity Tracking

No constitution violations. Complexity budget respected:

- 1 file rewritten (~40 LoC).
- No new dependencies.
- No new files.
- Five-line mapping-table duplication with `bin/tricycle` is acknowledged (R3) and out of scope to refactor here.
