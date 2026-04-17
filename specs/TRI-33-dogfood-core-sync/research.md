# Research: Dogfood drift — keep `.trc/` in sync with `core/`

**Feature**: TRI-33 — Keep tricycle-pro's own `.trc/` in sync with `core/`
**Date**: 2026-04-17

## R1 — CLI shape: subcommand vs flag vs config

**Question**: Three shapes were floated in the spec — dedicated `tricycle dogfood` subcommand, `tricycle update --force-adopt-core` flag, or a repo-local `dogfood.mirror_core: true` config flag that auto-flips `cmd_update`'s default. Which?

**Decision**: **Dedicated `tricycle dogfood` subcommand.** Dry-run by default; `--yes` (or `-y`) required to actually write. Detects "this is a meta-repo" by checking for `core/` at the repo root and silently/cleanly refuses when it's absent.

**Rationale**:

- Separation of concerns: `tricycle update` means "pull the latest from the toolkit root and sync it into my consumer state". `tricycle dogfood` means "mirror this repo's own `core/` into this repo's own `.trc/`". Different inputs (tarball vs local tree), different semantics. Keeping them distinct avoids the confusing mental model of one command that behaves differently based on context.
- Safer by default: a dedicated subcommand that prints what it would change and requires `--yes` to commit the change matches the spec's FR-004 (explicit confirmation) and edge-case protection against buggy destructive runs.
- Discoverable: `tricycle --help` gains one new line, and it's obvious from its presence alone that "dogfood" is a contributor-only tool.
- Consumer repos never accidentally invoke it — it's a no-op by detection (no `core/` → silently exit 0 with a one-line explanation).

**Alternatives considered**:

- *`tricycle update --force-adopt-core` flag*: Rejected — couples two distinct behaviors under one command. The flag also invites misreading as "force the update to adopt upstream core" (meaning toolkit-root core), not "force adoption from this repo's own core". Mental-model hazard.
- *`dogfood.mirror_core: true` config flag*: Rejected — implicit. Contributor wouldn't know why `tricycle update` is suddenly destructive. Harder to dry-run vs commit. Risk of leaving the flag on in a fork that's no longer a meta-repo.

## R2 — How to share the mapping table with `cmd_update`?

**Question**: `cmd_update` in `bin/tricycle` already encodes the `core/...→.trc/...` + `core/hooks→.claude/hooks` mapping. The new `cmd_dogfood` needs the same table. Duplicate or share?

**Decision**: Extract the mapping to a shared array declared once near the top of `bin/tricycle`, consumed by both `cmd_update` and `cmd_dogfood`. The existing mapping lives in a for-loop literal today; lifting it to a named array `TRICYCLE_MANAGED_PATHS` (or similar) is a cheap refactor that scales naturally when a future addition lands.

**Rationale**:

- FR-003 mandates both code paths use the same mapping. A shared variable enforces that structurally rather than by discipline.
- Cost is ~5 LoC (declare the array + two loops that consume it). No new abstraction.
- Future mapping additions (e.g. a hypothetical `core/integrations → .claude/integrations`) become a one-line edit reflected in both commands.

**Alternatives considered**:

- *Duplicate the literal*: Rejected per FR-003 — drift inevitable.
- *Source a separate mapping file*: Rejected — overkill for a 5-entry table. Adds a file for no benefit.

## R3 — How `cmd_dogfood` actually mirrors a file

**Question**: Destructive overwrite. What's the primitive?

**Decision**: For each mapping pair, walk `core/<src>/**/*` with `find`, compute the destination path, overwrite the destination file unconditionally (`cp -f`), preserve `+x` on `.sh` files, update `.tricycle.lock` via the existing `lock_set` helper with the new checksum and `customized: false`.

**Rationale**:

- `cp -f` is the minimal primitive matching FR-005 (preserve executable) + FR-006 (lock adoption).
- Reusing `lock_set` from `bin/lib/helpers.sh` keeps the lock format consistent with every other write path in the CLI.
- Handling the add-new-file case (file exists in `core/` but not yet in `.trc/`) is free — `cp -f` creates it.

**Alternatives considered**:

- *Use `install_file` from `bin/lib/helpers.sh`*: Rejected — `install_file` has a built-in "locally modified? → SKIP" guard that is the exact behavior this feature is working around. Using it would defeat the purpose.
- *`rsync -a --delete`*: Rejected — deletes-when-missing semantics are too aggressive; if a contributor happens to have a legitimate `.trc/` file outside the mapping (unlikely but possible), `rsync --delete` would wipe it.

## R4 — Dry-run vs write confirmation (FR-004)

**Question**: Interactive prompt (y/n) or required `--yes` flag?

**Decision**: `--yes` (or `-y`) required to write. Default is dry-run: print one line per file that would change, print a final summary count, exit 0. If `--yes` is passed, the output is identical but writes actually land.

**Rationale**:

- `--yes` is scriptable; a prompt isn't without `yes |` plumbing. Contributors can wire `tricycle dogfood --yes` into git hooks or CI without interactive trickery.
- Dry-run default is FR-004's "safe path". Matches the pattern `tricycle update --dry-run` already uses (though here the default is inverted: safe mode is default, `--yes` opts in).
- An interactive prompt can be added later if desired; scope-limited for MVP.

**Alternatives considered**:

- *Interactive prompt always*: Rejected for scriptability reasons.
- *Destructive-by-default with `--dry-run` opt-in*: Rejected — violates FR-004's spirit. One accidental `tricycle dogfood` against uncommitted work is a support incident waiting to happen.

## R5 — Drift-check test shape (FR-009)

**Question**: How does `tests/run-tests.sh` detect drift between `core/` and the mirrored paths?

**Decision**: New test script `tests/test-dogfood-drift.sh`. Skips (exits 0 with a one-line "not a meta-repo, skipping" message) if `core/` does not exist at the repo root. Otherwise walks every mapping pair, runs `diff -r` between source and destination, and reports any drifted paths.

**Rationale**:

- Using `diff -r` rather than per-file `sha256sum` gives contributors the actual diff in the failure output — not just "these paths drifted", but "here's what changed". Actionable on first read.
- Skipping when `core/` is absent satisfies FR-009's guard without branching the test harness.
- Separate test script (vs inline in `run-tests.sh`) follows the established pattern and is directly runnable via `bash tests/test-dogfood-drift.sh` for spot-checks.

**Alternatives considered**:

- *Hash each file and compare*: Rejected — less helpful failure output.
- *Add drift check inside `cmd_validate`*: Rejected — `validate` is about config correctness, not repo-meta-state integrity. Different concern.

## R6 — What about the `--provision-worktree` / `npm install` failure that surfaced during this kickoff?

**Question**: The `/trc.specify` kickoff for TRI-33 itself exited 11 because `provision_worktree` runs `npm install` unconditionally, and tricycle-pro has no `package.json`. Is this TRI-33's scope?

**Decision**: **Out of scope for TRI-33.** File a separate ticket.

**Rationale**:

- TRI-33's spec is specifically about keeping `.trc/` in sync with `core/`. The npm-install failure is a distinct class of dogfood friction — the provisioning pipeline assumes node projects.
- Folding it in would expand scope unbounded; there are likely more per-repo-shape assumptions lurking (e.g. Python projects won't have `package.json` either).
- Fix once this lands: a new follow-up ticket (TRI-34 candidate) that makes `provision_worktree`'s npm-install step conditional on `package.json` existing — or more generally, makes the provisioning pipeline aware of repo shape.

**Alternatives considered**:

- *Add npm-install skip logic inside this PR*: Rejected. Scope creep; motivates a spec-phase clarification that wasn't surfaced.

## R7 — Are mirrored paths committed (not gitignored)?

**Question**: Edge case in spec — recovery via `git checkout --` requires the mirrored paths be tracked by git, not `.gitignore`d. Is this already the case?

**Decision**: **Corrected during implementation.** In the tricycle-pro meta-repo itself, `.trc/` is fully gitignored and `.claude/*` is gitignored except for an allow-list (commands, hooks, skills). The spec's original claim that recovery via `git checkout --` works was wrong — it only holds for consumer repos where the gitignore pattern includes the allow-list exceptions.

**Practical recovery path in tricycle-pro**: re-run `tricycle dogfood --yes`. The sync is idempotent and restores `.trc/` + `.claude/*` from `core/` — functionally equivalent recovery since `core/` is the source of truth. Dry-run-by-default (FR-004) remains the primary safety valve against an accidental destructive run.

**Contributor workflow**:
1. Before making edits, consider running `tricycle dogfood` (dry-run) to see drift.
2. Make edits in `core/` (source of truth).
3. Run `tricycle dogfood --yes` to mirror into `.trc/` / `.claude/`.
4. Edits to `core/` are committed via normal git; the `.trc/` + `.claude/*` mirror is gitignored and rebuilt on demand.

**Alternatives considered**:

- *Un-gitignore `.trc/` + full `.claude/` in tricycle-pro to enable `git checkout --` recovery*: Rejected — would bloat the repo with duplicate copies of `core/` content and forces every PR that touches `core/` to also touch `.trc/`, doubling review surface. The dry-run safety + idempotent re-sync is sufficient.
