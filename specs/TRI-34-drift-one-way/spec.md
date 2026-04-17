# Feature Specification: One-way drift check (src → dst, not bidirectional)

**Feature Branch**: `TRI-34-drift-one-way`
**Created**: 2026-04-17
**Status**: Draft
**Input**: User description: "TRI-34" — [Rethink dogfood drift check as one-way src→dst (not bidirectional diff -r)](https://linear.app/d3feat/issue/TRI-34/rethink-dogfood-drift-check-as-one-way-srcdst-not-bidirectional-diff-r)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Contributor's local test suite runs green when runtime-generated files live in the managed paths (Priority: P1)

A contributor in the tricycle-pro meta-repo runs `bash tests/run-tests.sh`. The dogfood-drift check reports OK, even when runtime-generated files (like `.claude/hooks/.session-context.conf` — output of `tricycle generate settings`) exist under the destination paths without a `core/` counterpart. The test only flags real drift: a file that exists in `core/` but is missing from the mirror, or a file whose content differs between `core/` and the mirror.

**Why this priority**: This is the exact false positive that surfaced immediately after v0.20.1 released. The test as-shipped flags every runtime-generated file as drift, which means any contributor who has ever run `tricycle generate settings` fails the drift check locally. Blocks dogfood adoption in practice.

**Independent Test**: In a synced meta-repo checkout, run `tricycle generate settings` (creates `.claude/hooks/.session-context.conf`), then run `bash tests/test-dogfood-drift.sh` → exit 0, output `dogfood-drift: OK`. Remove the runtime file, rerun → still exit 0.

**Acceptance Scenarios**:

1. **Given** `.claude/hooks/.session-context.conf` exists (or any other file in a managed path that has no `core/` counterpart), **When** the drift test runs, **Then** it exits 0 and reports OK — the extra file is not drift.
2. **Given** a file is modified in `core/` without a corresponding `tricycle dogfood --yes` run, **When** the drift test runs, **Then** it exits 1 and names the mismatched file with a diff.
3. **Given** a file exists in `core/` that is missing from the matching destination, **When** the drift test runs, **Then** it exits 1 and names the missing destination path.

---

### User Story 2 — Modified-file drift is still caught with actionable output (Priority: P1)

When a file actually drifts between `core/` and its mirror (a contributor edited `core/` and forgot to sync, or a merge introduced a difference), the test reports the offending path(s) with the actual diff — same actionable output the bidirectional check produced.

**Why this priority**: Defending the main value of the test. Dropping bidirectional coverage must not dull the detection of real drift.

**Independent Test**: In a synced meta-repo, edit `core/scripts/bash/derive-branch-name.sh` (append a byte), run the drift test → exit 1 with the path listed and the diff shown. Restore via `git checkout --`, rerun → exit 0.

**Acceptance Scenarios**:

1. **Given** a `core/` file differs from its destination, **When** the drift test runs, **Then** the failure output names the destination path and shows the content diff (the form the bidirectional test produced remains actionable).
2. **Given** multiple paths drift in a single run, **When** the test runs, **Then** all drifted paths are listed, not just the first.

---

### Edge Cases

- **Missing destination directory**: `core/commands/` exists but `.claude/commands/` is absent. The test MUST flag the entire mapping pair as drifted (missing dst), same as the current behavior.
- **Destination has an extra file that happens to share a name pattern with `core/` files** (e.g. an `.md` under `.trc/blocks/`): still not drift — one-way means extras are ignored regardless of their shape.
- **Stale orphan** (file removed from `core/` but still present in `.trc/`): intentionally NOT flagged. Documented in the ticket's "won't fix" — if orphans become a problem, a future `tricycle dogfood --prune` covers it.
- **Consumer fixture without `core/`**: unchanged from v0.20.1 — early skip with "not a meta-repo" message.
- **Non-text files** (hypothetical — no binaries in managed paths today): byte-identical checksum comparison handles them correctly; no text-specific logic.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The drift test MUST iterate every file under `core/<src>` for each mapping pair and assert that a byte-identical file exists at the corresponding `<dst>/<relative-path>`.
- **FR-002**: The drift test MUST NOT flag files present in `<dst>` that have no counterpart under `core/<src>`. Such files are either runtime-generated (legitimate) or stale orphans (out-of-scope per the ticket).
- **FR-003**: On failure, the test MUST list each drifted destination path on its own line, followed by the actual content diff for that pair (produced via `diff` on the two files). The failure output must be as actionable as the pre-TRI-34 bidirectional output.
- **FR-004**: When `core/` does not exist at the repo root (ordinary consumer fixtures), the test MUST exit 0 with the existing "not a meta-repo, skipping" message — unchanged from v0.20.1.
- **FR-005**: When `core/<src>` exists but its matching `<dst>` directory is missing, the test MUST flag that entire mapping pair as drifted (same as the current "missing" behavior).
- **FR-006**: The test MUST match the semantics of `tricycle dogfood --yes`: every `core/` file must exist and match at its mapped destination. Anything the dogfood command would not touch (files-only-in-dst) is not drift.
- **FR-007**: The test MUST not require any new runtime dependency — POSIX `diff`, `find`, `shasum` (or equivalent) already in use are sufficient.

### Key Entities

- **Source file set**: Every regular file under `core/<src>` for each mapping pair in `TRICYCLE_MANAGED_PATHS`.
- **Expected destination set**: For each source file, the destination path is `<dst>/<relative-path>`. The test asserts existence and content-identity of each member.
- **Destination extras** (runtime-generated files or orphans): Out of scope — neither flagged nor deleted. One-way semantics match `tricycle dogfood --yes`'s cp-only behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a synced meta-repo where `tricycle generate settings` has been run, `bash tests/test-dogfood-drift.sh` exits 0 in 100% of invocations — no false positives from runtime-generated files.
- **SC-002**: When a single `core/` file is modified without a corresponding `dogfood --yes`, `bash tests/test-dogfood-drift.sh` exits 1 and the output names that exact destination path in 100% of invocations.
- **SC-003**: When multiple `core/` files drift in the same run, the test output names every drifted path (not just the first).
- **SC-004**: In a consumer fixture without `core/`, the test exits 0 with an unchanged skip message — zero regression against v0.20.1 behavior.
- **SC-005**: Test runtime stays within the same order of magnitude as the current bidirectional check (< 500 ms on the tricycle-pro repo).

## Assumptions

- Orphan cleanup (files in `<dst>` that were removed from `core/`) is out of scope. Documented in TRI-34's "won't fix" section; future extension via `tricycle dogfood --prune` if warranted.
- Runtime-generated files in managed paths are a real and expected pattern (`.session-context.conf` today, possibly more in the future). The one-way semantics accommodate all current and future cases without needing a per-file allow-list.
- The mapping table (`TRICYCLE_MANAGED_PATHS`) stays in sync between `bin/tricycle` and the test script by convention. That coupling already exists in v0.20.1's drift test and isn't newly introduced here.
