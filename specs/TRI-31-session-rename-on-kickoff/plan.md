# Implementation Plan: Rename Claude Code session on workflow kickoff

**Branch**: `TRI-31-session-rename-on-kickoff` | **Date**: 2026-04-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `/specs/TRI-31-session-rename-on-kickoff/spec.md`

## Summary

Add a `UserPromptSubmit` hook that intercepts `/trc.specify`, `/trc.headless`, and `/trc.chain` invocations, derives the target session label (branch name for solo commands, `trc-chain-<range>` convention for chain), and sets `hookSpecificOutput.sessionTitle`. The hook fires before the agent's first turn, satisfying the "first thing done" rule structurally rather than by convention.

A new pure helper `core/scripts/bash/derive-branch-name.sh` is extracted from `create-new-feature.sh` so the hook and the branch-creation script share slug logic (FR-007). Command templates get a `/rename`-based fallback instruction for installs where the hook isn't registered.

**Version impact**: This is a new feature with durable developer-facing behavior change. Bump minor: `0.18.3` → `0.19.0`.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`).
**Primary Dependencies**: Claude Code `UserPromptSubmit` hook contract with `hookSpecificOutput.sessionTitle` (available v2.1.94+ per R1). Existing in-repo: `core/scripts/bash/common.sh`, `bin/tricycle` settings generator, `bin/lib/helpers.sh`.
**Storage**: None — feature is stateless.
**Testing**: `bash tests/run-tests.sh` (entry point per CLAUDE.md); unit tests via `node --test`.
**Target Platform**: macOS + Linux developer workstations running Claude Code.
**Project Type**: CLI / developer tooling (single-app).
**Performance Goals**: < 500 ms hook execution on cold cache; < 10 ms no-op path for non-matching prompts.
**Constraints**: Must gracefully degrade when `hookSpecificOutput.sessionTitle` is unsupported by the host (SC-005). Must not duplicate slug logic (FR-007). Must not change any existing `create-new-feature.sh` behavior (parity test).
**Scale/Scope**: 1 new bash helper (~80 LoC), 1 new hook script (~120 LoC), refactor of `create-new-feature.sh` slug section (~40 LoC moved to helper), updates to 3 command templates (~20 LoC each), `bin/tricycle` `cmd_generate_settings` addition (~15 LoC), 4–6 new tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.trc/memory/constitution.md`) is currently a placeholder ("Run `/trc.constitution` to populate this file."). There are no codified principles to violate. Gate passes trivially.

CLAUDE.md rules observed:

- **Lint & Test Before Done (NONNEGOTIABLE)**: `bash tests/run-tests.sh` must pass before `/trc.implement` declares done. Plan includes test tasks.
- **MCP Usage**: No MCP services required at runtime for this feature; Linear MCP was used once at spec time to create TRI-31 and is not a runtime dependency.
- **Worktree-before-side-effects**: All implementation work happens in `../tricycle-pro-TRI-31-session-rename-on-kickoff/` — already provisioned.
- **Branching style**: `issue-number` + `TRI`, observed — branch is `TRI-31-session-rename-on-kickoff`.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-31-session-rename-on-kickoff/
├── plan.md                       # This file
├── research.md                   # R1–R5 decisions (mechanism, slug reuse, chain label, workers, ordering)
├── data-model.md                 # Stateless — invocation + derived label
├── quickstart.md                 # 6 manual verification tests
├── contracts/
│   └── derive-branch-name.md     # Helper + hook + fallback command-template contracts
├── checklists/
│   └── requirements.md           # Spec quality checklist (already produced in /trc.specify)
└── tasks.md                      # Phase 2 output (/trc.tasks — NOT created by /trc.plan)
```

### Source Code (repository root)

```text
core/
├── commands/
│   ├── trc.specify.md             # UPDATED — Step 0.5 rename fallback instruction
│   ├── trc.chain.md               # UPDATED — orchestrator rename fallback + worker rename brief rule
│   └── trc.headless.md            # UPDATED — rename fallback instruction
├── hooks/
│   └── rename-on-kickoff.sh       # NEW — UserPromptSubmit hook (primary mechanism)
└── scripts/
    └── bash/
        ├── derive-branch-name.sh  # NEW — pure slug/branch derivation
        └── create-new-feature.sh  # REFACTORED — sources derive-branch-name.sh

bin/
└── tricycle                       # UPDATED — cmd_generate_settings registers the new hook

tests/
├── test-derive-branch-name.sh     # NEW — parity with create-new-feature.sh output
├── test-rename-hook.sh            # NEW — hook fires on kickoff commands, no-op otherwise,
│                                  #       emits correct sessionTitle JSON, idempotent
├── test-chain-md-contract.sh      # UPDATED — add grep anchors for the new fallback rule
└── run-tests.sh                   # UPDATED — wire the two new test scripts
```

**Structure Decision**: No new top-level directory. The feature extends three existing areas (`core/hooks/`, `core/scripts/bash/`, `core/commands/`) with one file each plus in-place updates. A new helper script avoids modifying `create-new-feature.sh`'s interface while honoring FR-007.

## Implementation phases

### Phase 0 — Research (complete)

See `research.md`. Five decisions locked:

1. Primary mechanism: `UserPromptSubmit` hook emitting `hookSpecificOutput.sessionTitle`. `/rename` is the fallback only.
2. Extract slug logic into `derive-branch-name.sh`; `create-new-feature.sh` sources it.
3. Chain label convention: `trc-chain-<first>..<last>` (range) or `trc-chain-<first>+<N-1>` (list/singleton).
4. Worker labels: worker brief instructs `/rename <branch-name>` as first action; graceful degradation if unsupported in sub-agent context.
5. Rename hook is the first `UserPromptSubmit` entry; settings generator documents the ordering rule for future hooks.

### Phase 1 — Design & Contracts (complete)

See `data-model.md` (stateless), `contracts/derive-branch-name.md` (script + hook + fallback contracts), `quickstart.md` (six manual tests aligned 1:1 with user stories and critical FRs).

### Phase 2 — Tasks (delegated to `/trc.tasks`)

The tasks file will roughly follow this skeleton, dependency-ordered:

1. Add `core/scripts/bash/derive-branch-name.sh` matching its contract.
2. Add parity test `tests/test-derive-branch-name.sh`.
3. Refactor `core/scripts/bash/create-new-feature.sh` to source the helper. Parity test stays green.
4. Add `core/hooks/rename-on-kickoff.sh` matching its contract.
5. Add `tests/test-rename-hook.sh` covering match, no-match, idempotency, error paths, chain label form.
6. Update `bin/tricycle`'s `cmd_generate_settings` to register the new hook under `UserPromptSubmit`.
7. Update `tests/test-tricycle-update-adopt.sh` (or add a small adjacent test) to confirm `tricycle generate settings` writes the hook entry.
8. Update `core/commands/trc.specify.md`, `trc.headless.md`, `trc.chain.md` with the Step 0.5 fallback instruction, and `trc.chain.md`'s worker brief with the worker `/rename` rule.
9. Extend `tests/test-chain-md-contract.sh` with grep anchors for the new rules.
10. Bump `VERSION` to `0.19.0` as part of the /trc.implement close-out (version bump happens at release time, not in the feature branch itself per repo convention).

## Version awareness

Current VERSION: `0.18.3` (just released with the post-shakedown batch).
Planned next: `0.19.0` — minor bump. Rationale: new developer-facing default behavior (sessions are renamed automatically on every kickoff for any consumer that runs `tricycle update` + `tricycle generate settings`). Not a patch because behavior change is observable without opt-in.

## Complexity Tracking

No constitution violations. Complexity budget respected:

- 1 new script, 1 new hook, 1 thin refactor of an existing script.
- No new language runtime. No new MCP. No new external CLI dependency beyond what Claude Code already provides.
- No durable state. No migrations.
