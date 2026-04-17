# Research: One-way drift check

**Feature**: TRI-34 — Rethink dogfood drift check as one-way src→dst
**Date**: 2026-04-17

## R1 — Per-file comparison primitive

**Question**: The one-way walk iterates every `core/<src>` file and asserts it has a byte-matching destination. What's the per-file primitive: `diff -q`, `cmp -s`, or a checksum-compare?

**Decision**: Use `cmp -s "<src>" "<dst>"` for the existence+identity test, and fall back to `diff` (with default output, which is line-diff) only when `cmp` fails — the `diff` output becomes the actionable failure context (FR-003).

**Rationale**:

- `cmp -s` returns non-zero on any byte difference or missing file; it's the minimal primitive matching FR-001.
- Reserving `diff` for the failure path keeps the happy-path fast (`cmp` is linear in file size with no line-parsing overhead).
- Retaining `diff`'s textual output on failure preserves the actionable quality the bidirectional check produced — contributors still see exactly what changed.

**Alternatives considered**:

- *`diff -q` in the happy path*: Rejected — `diff` always reads both files through its line machinery; fine for small files, but `cmp` is strictly simpler. No correctness difference.
- *Checksum-compare (`shasum` of each file, then string-compare)*: Rejected — two `shasum` invocations per file plus a string compare is strictly more work than one `cmp -s`. Only worth it if we were going to cache checksums across runs, which we're not.
- *`git diff --no-index`*: Rejected — requires git in `$PATH` (already present, but couples the test to git config) and its output shape is less predictable across git versions.

## R2 — How the test iterates sources

**Question**: v0.20.1's drift test uses `diff -r` which recursively walks both trees. The new check needs an explicit walk of `core/<src>` only. Use `find`?

**Decision**: Use `find "$src" -type f` for each mapping pair. Path-arithmetic the destination as `<dst>/${src_file#$src/}`. Standard, POSIX, no surprises.

**Rationale**:

- `find -type f` explicitly excludes directories from the walk — we only want to compare regular files. The bidirectional check implicitly did this via `diff -r`, but now that it's an explicit walk we need to be explicit too.
- The same pattern is already used in `bin/tricycle`'s `cmd_update` and `cmd_dogfood`. Consistency across the codebase.

**Alternatives considered**:

- *Bash-globstar `**`*: Rejected — requires `shopt -s globstar` and has less predictable symlink semantics across bash versions.
- *`git ls-files`*: Rejected — would only work in git-tracked files; `core/` IS tracked in tricycle-pro but the primitive shouldn't depend on git state.

## R3 — Keep the mapping table hardcoded in the test, or source from `bin/tricycle`?

**Question**: v0.20.1's drift test hardcodes the five mapping pairs, duplicating `TRICYCLE_MANAGED_PATHS` from `bin/tricycle`. Is TRI-34 the right time to fix that coupling?

**Decision**: Keep the hardcoded duplicate. Lifting the coupling is out of scope; the duplicate is five lines and has the same drift-risk as the pre-TRI-33 inline literal. If it becomes a pain (e.g. a sixth mapping lands), extract both consumers to source a shared file.

**Rationale**:

- Scope: the spec is about the drift-check semantics, not about refactoring the mapping definition. Widening to refactor invites scope creep.
- The duplication is already a known and accepted condition (v0.20.1 tests shipped with it). This change doesn't worsen it.
- The follow-up refactor (source the array into the test) is easy to do later if needed — `bin/lib/managed-paths.sh` or similar, sourced by both `bin/tricycle` and `tests/test-dogfood-drift.sh`.

**Alternatives considered**:

- *Source `bin/tricycle` into the test*: Rejected — sourcing `bin/tricycle` executes the entire argv-parsing block and dispatch. It's not a library; making it safely sourceable is a bigger refactor.
- *Extract a tiny shared file `bin/lib/managed-paths.sh`*: Rejected as out-of-scope — clean refactor but not this ticket's job.

## R4 — Do we need a fixture-based unit test for the drift test itself?

**Question**: The real drift test runs on every `bash tests/run-tests.sh` invocation against the actual tricycle-pro repo. Is a fixture test (where we seed a drift, assert the test fails) worth adding?

**Decision**: **No.** The integration path — intentionally drift a `core/` file, run the test, expect failure — is exercised manually during implementation (part of the quickstart) and by the real suite on every green-after-drift cycle. A fixture test would duplicate that with more mechanism and less signal.

**Rationale**:

- The test IS the check; meta-testing the check adds a layer whose benefit (catches bugs in the test logic) is small relative to the test's complexity (~40 LoC of bash).
- If we add a fixture test, it'd be close to a line-for-line mirror of the real test with fake inputs. Low return.
- If the test ever grows richer (multiple modes, subcommands), reconsider.

**Alternatives considered**:

- *Add a fixture test that plants a drift in a temp copy of `core/` + `.trc/`*: Rejected on scope grounds. Could do as a follow-up if the test grows.

## R5 — Orphan files (in `<dst>` but not in `core/`): confirm out-of-scope

**Question**: Reconfirm TRI-34's explicit scope exclusion for orphan cleanup.

**Decision**: Out of scope. Orphans are not drift; they're stale files that `tricycle dogfood --yes` doesn't touch (it only does `cp -f src dst`, never `rm`).

**Rationale**:

- Aligns the test with what `tricycle dogfood --yes` can actually fix (FR-006).
- `tricycle dogfood --prune` is a sensible future extension; a matching orphan check would ship alongside. Neither belongs here.

**Alternatives considered**:

- *Add an orphan warning (non-fatal) to the test*: Rejected — warnings that don't fail the test quickly become noise contributors ignore. If we want the signal, it goes in the cmd (`dogfood --prune --dry-run`), not in a silent test warning.

## R6 — Test output format on failure (FR-003 preservation)

**Question**: The bidirectional v0.20.1 test printed each drifted path followed by the full `diff -r` block. The one-way version needs similar actionable output. What's the exact format?

**Decision**: On failure, print each drifted destination path on its own line (prefixed with spaces for readability), then print a `Detail:` block containing one `--- diff <src> vs <dst> ---` header per drifted file followed by the `diff` output. Match the pre-TRI-34 format closely; only the semantics of "what counts as drift" changes, not the failure-output shape.

**Rationale**:

- Contributors have built muscle memory for the existing failure format. Preserve it.
- The content of the failure is still a content diff, just scoped to actual `core/`-sourced drift.
