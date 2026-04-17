# Feature Specification: Keep tricycle-pro's own `.trc/` in sync with `core/` (dogfood drift)

**Feature Branch**: `TRI-33-dogfood-core-sync`
**Created**: 2026-04-17
**Status**: Draft
**Input**: User description: "TRI-33" — [Keep tricycle-pro's own .trc/ in sync with core/ (dogfood drift)](https://linear.app/d3feat/issue/TRI-33/keep-tricycle-pros-own-trc-in-sync-with-core-dogfood-drift)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Contributor-to-tricycle-pro kicks off a new feature without manual `.trc/` patching (Priority: P1)

A contributor working inside the `tricycle-pro` repo invokes `/trc.specify` (or `/trc.chain`, or `/trc.headless`). Every helper script that runs under `.trc/scripts/bash/` — `create-new-feature.sh`, `derive-branch-name.sh`, `common.sh`, and any future additions — is byte-identical to its counterpart under `core/scripts/bash/`. Hooks under `.claude/hooks/` likewise mirror `core/hooks/`. The contributor does NOT have to `cp -R core/... .trc/...` by hand to get the latest features working.

**Why this priority**: This is the entire motivation. The bug has compounded three times (TRI-31, TRI-32, and the v0.20.0 update), each time costing minutes of manual recovery and producing confusing failure modes (silently-dropped flags, missing functions, stale hook behavior). Without this, every future feature that touches `core/` will keep re-breaking dogfood kickoffs.

**Independent Test**: Modify a file under `core/scripts/bash/` (e.g. add a `# marker` comment). Run the tricycle-pro-dogfood sync mechanism. Verify the same change appears in `.trc/scripts/bash/` byte-for-byte. Run a kickoff (`/trc.specify` with a small fixture) and verify the new behavior reaches the script that actually executes.

**Acceptance Scenarios**:

1. **Given** a clean `tricycle-pro` checkout where `core/scripts/bash/foo.sh` differs from `.trc/scripts/bash/foo.sh`, **When** the sync mechanism is invoked, **Then** `.trc/scripts/bash/foo.sh` is overwritten to match `core/scripts/bash/foo.sh` byte-for-byte and the mirroring is recorded (no more "locally modified" SKIPs for that path on subsequent `tricycle update` runs).
2. **Given** a new file added to `core/hooks/`, **When** the sync mechanism is invoked, **Then** the same file appears at the matching path under `.claude/hooks/` and is `+x`.
3. **Given** a contributor runs the sync mechanism and then immediately runs `/trc.specify` or any kickoff, **Then** the kickoff behaves identically to running `core/scripts/bash/create-new-feature.sh` directly — no stale-script bugs.

---

### User Story 2 — Ordinary consumer repo is unaffected (Priority: P1)

A project that used `npx tricycle-pro init` in its own (non-tricycle-pro) repo has no `core/` tree of its own. Any mirroring behavior must be a silent no-op for those projects and MUST NOT change their existing `tricycle update` semantics (which correctly preserve their legitimate local customizations).

**Why this priority**: The fix for the dogfood problem cannot regress the primary use case. If the mirror-from-core behavior leaked into ordinary consumer repos, every `tricycle update` would blow away the customizations consumers intentionally maintain.

**Independent Test**: In a fixture repo that has `tricycle.config.yml` and managed files but NO `core/` directory, run `tricycle update` before and after this feature lands. The output (SKIPs, WRITEs, ADOPTs) must be identical in both runs.

**Acceptance Scenarios**:

1. **Given** a consumer repo with no `core/` directory, **When** the new sync mechanism is invoked (via whatever CLI surface it ships with), **Then** it either refuses cleanly or is a silent no-op; it never touches managed files.
2. **Given** a consumer repo with intentionally-customized hooks (e.g. a site-specific `block-spec-in-main.sh`), **When** any normal `tricycle update` is run, **Then** the behavior matches the pre-TRI-33 baseline — the local customization is preserved as before.

---

### User Story 3 — The drift is caught automatically, not manually rediscovered (Priority: P2)

A test in `tests/run-tests.sh` fails if `core/` and `.trc/` (or `core/hooks/` and `.claude/hooks/`) drift apart in the tricycle-pro repo itself. The contributor sees the failure immediately on `bash tests/run-tests.sh`, not three kickoffs later when a feature silently breaks.

**Why this priority**: Defense in depth. Even after the sync mechanism lands, contributors may forget to run it, or a race may sneak a `core/` edit past without an accompanying sync. A CI-visible drift check makes re-breaking dogfood noisy instead of silent.

**Independent Test**: Intentionally make `.trc/scripts/bash/create-new-feature.sh` differ from `core/scripts/bash/create-new-feature.sh` (add a stray line). Run `bash tests/run-tests.sh`. The dogfood-drift check must fail with a clear message naming the offending path(s).

**Acceptance Scenarios**:

1. **Given** `core/` and `.trc/` differ on any mirrored path, **When** `bash tests/run-tests.sh` runs, **Then** a dedicated test fails with a clear, actionable message listing the drifted paths.
2. **Given** `core/` and `.trc/` are in sync, **When** `bash tests/run-tests.sh` runs, **Then** the drift test passes silently as one of the suite's green checkmarks.

---

### Edge Cases

- **Contributor has made legitimate in-progress edits under `.trc/`**: The sync is destructive by design for tricycle-pro itself, but the contributor should get a clear, loud warning listing files about to be overwritten before anything is changed, with an option to abort. An "are you sure?" prompt or a required `--yes` flag both satisfy.
- **`core/` has files that don't fit any `.trc/` mapping** (e.g. a new top-level subdirectory under `core/` not covered by the existing `core/* → .trc/*` mapping table): The sync mechanism must either map it explicitly or flag it as unmapped and halt, rather than silently dropping new files.
- **Skills trees**: `.claude/skills/` has its own upstream-fetch mechanism (per the existing `install_skills` / `fetch_external_skill` paths). The sync mechanism should NOT claim skills — leave them to their existing update flow.
- **Lock file**: The `.tricycle.lock` entries for mirrored paths must reflect the post-sync state, so future `tricycle update` runs against `core/` don't re-SKIP them as "locally modified". Running the sync followed by `tricycle update --dry-run` should report zero SKIPs on the mirrored paths.
- **Empty/absent `core/`**: Already covered by User Story 2 — sync is a no-op or clean refusal.
- **The mechanism itself is buggy and trashes a contributor's repo**: This is the worst failure mode. The mechanism MUST NOT run destructively without explicit opt-in (flag, prompt, or commit requirement). Recovery from `git checkout -- .trc/` must always be possible — i.e. the mirrored paths must be committed to the repo, not `.gitignore`d, so git itself is the rollback.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A contributor to `tricycle-pro` MUST have a single command that brings all mirrored paths under `.trc/` and `.claude/` into byte-identical agreement with the authoritative copies under `core/`, and records that agreement in `.tricycle.lock` so `tricycle update` no longer SKIPs them.
- **FR-002**: The mechanism MUST be a silent no-op (or clean, explicit refusal with a one-line explanation) in any repo that does not contain a `core/` directory at its root — i.e. ordinary consumer repos (User Story 2).
- **FR-003**: The mapping of source to destination MUST match the existing `cmd_update` mapping table: `core/commands → .claude/commands`, `core/templates → .trc/templates`, `core/scripts/bash → .trc/scripts/bash`, `core/hooks → .claude/hooks`, `core/blocks → .trc/blocks`. Any future addition to the mapping must be a single-file edit.
- **FR-004**: Before any destructive overwrite, the mechanism MUST list the files it would touch and require explicit confirmation — either an interactive prompt or a `--yes` flag. Running it without confirmation is a dry run (prints what would change, exits 0).
- **FR-005**: The mechanism MUST preserve executable bits (`+x`) on shell scripts and hooks.
- **FR-006**: The mechanism MUST update `.tricycle.lock` so each mirrored path is recorded with the post-sync checksum and `customized: false`. A subsequent `tricycle update` against the same `core/` must not SKIP those paths.
- **FR-007**: The mechanism MUST NOT touch `.claude/skills/` (skills have their own upstream-fetch flow).
- **FR-008**: The mechanism MUST NOT touch files outside the known mapping table. If `core/` contains directories or files that don't fit the mapping, the mechanism MUST surface them as unmapped rather than silently dropping or mirroring them to an invented location.
- **FR-009**: `tests/run-tests.sh` MUST include a drift-check test that compares every mirrored path between `core/` and `.trc/` / `.claude/`, failing if any differ. The test runs only when `core/` exists locally (so it's a no-op in consumer fixtures).
- **FR-010**: The mechanism MUST be discoverable — `tricycle --help` must mention it, and documentation (README or equivalent) must note it is meant for tricycle-pro contributors and similar meta-repos, not for ordinary consumers.
- **FR-011**: The drift-check test (FR-009) MUST produce a one-line-per-file list of offending paths on failure so contributors can run the sync or inspect the drift without rerunning a grep.

### Key Entities

- **Mirrored path mapping**: The existing `core/{commands,templates,scripts/bash,hooks,blocks} → {.claude,.trc}/...` table from `cmd_update` in `bin/tricycle`. The sync mechanism reuses this exact table.
- **Contributor repo (meta-repo)**: A repo where `core/` and the managed consumer paths coexist in the same tree. Detected by the presence of `core/` at the repo root. `tricycle-pro` is the canonical example.
- **Lock adoption**: Writing a file's post-sync checksum into `.tricycle.lock` with `customized: false` so future `tricycle update` runs recognize it as tracked.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The next three kickoffs inside the `tricycle-pro` repo after this feature lands complete without ANY manual `cp -R core/... .trc/...` intervention.
- **SC-002**: A one-line test failure (from FR-009) fires within one `bash tests/run-tests.sh` invocation after `core/` and `.trc/` are drifted by any single line.
- **SC-003**: Running the sync mechanism followed by `tricycle update --dry-run` reports zero SKIPs on mirrored paths in the tricycle-pro repo.
- **SC-004**: In a consumer-fixture repo with no `core/` directory, `tricycle update`'s full output before and after this feature is byte-identical — no behavioral regression for ordinary consumers.
- **SC-005**: The sync mechanism refuses to destroy uncommitted edits under `.trc/` or `.claude/` unless the contributor explicitly passes a confirmation flag. Dry-run-by-default is the safe path.

## Assumptions

- Mirrored paths in the `tricycle-pro` repo are committed to git (not `.gitignore`d), so any accidental destructive sync can be reverted via `git checkout --`. This is the case today.
- Adding a drift-check test to the standard `tests/run-tests.sh` suite is acceptable even though it is only meaningful in repos where `core/` exists — it's a silent pass in consumer fixtures (FR-009's "only when `core/` exists locally" guard).
- `.claude/skills/` is deliberately out of scope; those are upstream-fetched with their own checksum discipline and haven't been implicated in the drift incidents.
- The mechanism is for contributors to this toolkit, not a user-facing feature of tricycle-pro for its consumers — so it can live behind a subcommand like `tricycle dogfood` or a flag on `tricycle update` without needing a marketing pass.
- Interactive prompt vs `--yes` flag: a `--yes` flag is sufficient for MVP; interactive prompt is a nice-to-have deferred to follow-ups if it's not already in the prompt utility library.
