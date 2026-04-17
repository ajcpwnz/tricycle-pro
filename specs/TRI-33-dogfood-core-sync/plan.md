# Implementation Plan: Keep tricycle-pro's own `.trc/` in sync with `core/`

**Branch**: `TRI-33-dogfood-core-sync` | **Date**: 2026-04-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `/specs/TRI-33-dogfood-core-sync/spec.md`

## Summary

Add a dedicated `tricycle dogfood` subcommand that mirrors `tricycle-pro`'s own `core/` tree into `.trc/` and `.claude/` and records the mirrored checksums in `.tricycle.lock` so subsequent `tricycle update` runs stop flagging them as "locally modified". Dry-run by default; `--yes` required to write. Silently skips in ordinary consumer repos (where `core/` doesn't exist).

Extract the existing `core/ → .trc/`/`.claude/` mapping table from `cmd_update`'s inline literal into a named shared array `TRICYCLE_MANAGED_PATHS`, consumed by both `cmd_update` (refactored) and `cmd_dogfood` (new). Add `tests/test-dogfood-drift.sh` that runs `diff -r` across mapping pairs and fails fast when the meta-repo drifts — silent no-op when `core/` is absent.

**Version impact**: Patch bump: `0.20.0` → `0.20.1`. The feature adds a new CLI surface that is a silent no-op in every non-meta-repo — zero observable change for consumers. Minor would also be defensible, but patch matches the spirit of "contributor-only tooling, consumers unaffected".

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`).
**Primary Dependencies**: git (read-only usage for `diff -r` semantics via shell), `find` (existing), `cp -f`, `diff -r`.
**Storage**: `.tricycle.lock` (existing). No new files.
**Testing**: `bash tests/run-tests.sh`. New `tests/test-dogfood-drift.sh` + possibly a fixture-based `tests/test-dogfood-cmd.sh` to exercise the subcommand against a synthetic meta-repo fixture.
**Target Platform**: macOS + Linux developer workstations.
**Project Type**: CLI / developer tooling.
**Performance Goals**: < 1 s for a full dogfood run over the current `core/` tree. < 500 ms for the drift test.
**Constraints**: Never touch `.claude/skills/` (FR-007). Never touch files outside `TRICYCLE_MANAGED_PATHS` (FR-008). Never overwrite without `--yes` (FR-004). Never regress consumer `tricycle update` behavior (User Story 2 / SC-004).
**Scale/Scope**: ~90 LoC for `cmd_dogfood` + `TRICYCLE_MANAGED_PATHS` refactor of `cmd_update` + `--help` line + dispatch entry. ~60 LoC for `tests/test-dogfood-drift.sh`. ~50 LoC for an optional `tests/test-dogfood-cmd.sh` fixture test. Total: ~200 LoC across 2 files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.trc/memory/constitution.md` is a placeholder. No codified principles to violate. CLAUDE.md NONNEGOTIABLES observed:

- **Lint & Test Before Done**: `bash tests/run-tests.sh` before completion.
- **Worktree-before-side-effects**: Work is in `../tricycle-pro-TRI-33-dogfood-core-sync/`.
- **Branching style**: `issue-number` + `TRI` — branch is `TRI-33-dogfood-core-sync`.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-33-dogfood-core-sync/
├── plan.md                       # This file
├── research.md                   # R1–R7 decisions
├── data-model.md                 # Stateless — mapping + transient outcomes
├── quickstart.md                 # 8 manual tests
├── contracts/
│   └── dogfood.md                # Subcommand + shared mapping + drift-test contracts
├── checklists/
│   └── requirements.md           # From /trc.specify
└── tasks.md                      # Phase 2 output (/trc.tasks)
```

### Source Code (repository root)

```text
bin/
└── tricycle                      # UPDATED — new TRICYCLE_MANAGED_PATHS array,
                                  # new cmd_dogfood function, dispatch entry,
                                  # --help line, cmd_update refactored to
                                  # iterate over the shared array

tests/
├── test-dogfood-drift.sh         # NEW — runs `diff -r` across mapping pairs,
                                  # silent no-op when core/ absent
├── test-dogfood-cmd.sh           # NEW — fixture-based test of `tricycle dogfood`
│                                 # (optional; may be folded into drift test if
│                                 # scope stays small)
└── run-tests.sh                  # UPDATED — wire new tests into a new block:
                                  # "Dogfood drift sync (TRI-33):"
```

**Structure Decision**: Single-file code change (`bin/tricycle`) + new tests. No new top-level files. `core/commands/`, `core/hooks/`, etc. are NOT modified — this feature only changes the CLI surface and test harness, not any of the managed paths themselves.

## Implementation phases

### Phase 0 — Research (complete)

See `research.md`. Seven decisions locked:

1. CLI shape: dedicated `tricycle dogfood` subcommand (not a flag on update, not an auto-config).
2. Shared mapping table extracted into `TRICYCLE_MANAGED_PATHS` array; consumed by both `cmd_update` and `cmd_dogfood`.
3. Primitive: per-file `cp -f` + `lock_set`. Skip `install_file`'s locally-modified guard (that's the very behavior we're working around).
4. Dry-run by default; `--yes` required to write.
5. Drift-check test uses `diff -r` for actionable failure output.
6. `--provision-worktree` npm-install failure is out of scope; file a follow-up ticket.
7. Verified mirrored paths are tracked in git (not gitignored), so recovery via `git checkout --` works.

### Phase 1 — Design & Contracts (complete)

See `data-model.md` (stateless), `contracts/dogfood.md` (subcommand + shared-array + drift-test contracts), `quickstart.md` (8 tests).

### Phase 2 — Tasks (delegated to `/trc.tasks`)

Dependency-ordered skeleton:

1. Extract `TRICYCLE_MANAGED_PATHS` array in `bin/tricycle`.
2. Refactor `cmd_update` to iterate over the array; verify no behavior change (existing tests green).
3. Add `cmd_dogfood` function per `contracts/dogfood.md`: meta-repo detection → dry-run pass → confirmation gate → write pass → unmapped-core guard → summary.
4. Add dispatch entry `dogfood)  cmd_dogfood ;;` to the main case.
5. Add `--help` line for `tricycle dogfood [--yes]`.
6. Add `tests/test-dogfood-drift.sh`.
7. Add `tests/test-dogfood-cmd.sh` (synthetic meta-repo fixture: build a temp repo with `core/foo`, `.trc/foo` out of sync; invoke `tricycle dogfood`, assert dry-run output + no writes; invoke with `--yes`, assert writes land and `.tricycle.lock` updates).
8. Wire both tests into `tests/run-tests.sh` under a new `Dogfood drift sync (TRI-33):` block.
9. Run the full suite; must be green.
10. Walk `quickstart.md` manually on the real tricycle-pro repo.
11. VERSION bump `0.20.0` → `0.20.1` in the final commit.

## Version awareness

Current VERSION: `0.20.0`.
Planned next: `0.20.1` — patch bump. Rationale: the feature is contributor-only and is a silent no-op for ordinary consumers. Zero observable behavior change on `tricycle init`, `tricycle update`, `tricycle status`, `tricycle generate`, `tricycle validate`, or any existing surface in a consumer repo.

## Complexity Tracking

No constitution violations. Complexity budget respected:

- 1 file touched in `bin/` + 2 new tests.
- No new runtime language, no new MCP, no new external CLI dependency (`diff` is POSIX).
- No new config keys. No migration.
- The only new surface is the `tricycle dogfood` subcommand, which exists precisely to close the drift class and is bounded by the mapping array + dry-run-by-default safety.
