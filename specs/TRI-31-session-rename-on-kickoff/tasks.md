# Tasks: Rename Claude Code session on workflow kickoff

**Feature**: TRI-31-session-rename-on-kickoff
**Branch**: `TRI-31-session-rename-on-kickoff`
**Plan**: [plan.md](./plan.md)
**Spec**: [spec.md](./spec.md)
**Contracts**: [contracts/derive-branch-name.md](./contracts/derive-branch-name.md)

All file paths below are repo-root-relative. Absolute worktree root: `/Users/alex/projects/tricycle-pro-TRI-31-session-rename-on-kickoff/`.

## Legend

- `[P]` — parallelizable with any other `[P]` task in the same phase (different files, no mutual dependency).
- `[US1]`, `[US2]`, `[US3]` — ties the task to the matching user story in `spec.md`.
- No story label on Setup, Foundational, or Polish tasks.

---

## Phase 1 — Setup

This feature adds no new runtime dependencies and no new top-level directories. The worktree is already provisioned. No setup tasks are required beyond confirming the pre-check gate.

- [X] T001 Verify worktree + branch are correct by running `pwd` (must end `/tricycle-pro-TRI-31-session-rename-on-kickoff`) and `git rev-parse --abbrev-ref HEAD` (must print `TRI-31-session-rename-on-kickoff`). No file written; gate check only.

---

## Phase 2 — Foundational (blocks all user stories)

The helper extraction, the hook, and the settings-generator wiring are shared infrastructure every user story depends on. US1/US2/US3 cannot begin until Phase 2 is green.

- [X] T002 Create `core/scripts/bash/derive-branch-name.sh` per `contracts/derive-branch-name.md` — pure slug/branch derivation, no side effects, exit codes 0/1/2, single stdout line. Source `core/scripts/bash/common.sh` for shared utilities.
- [X] T003 [P] Add `tests/test-derive-branch-name.sh` asserting (a) byte-parity with `create-new-feature.sh` output across every `--style`/`--prefix`/`--issue`/`--short-name` combination exercised by the existing "Branch naming styles" block in `tests/run-tests.sh`; (b) exit code 2 for `issue-number` style with no `--issue` and no extractable ID in the description; (c) stdout is a single line with no trailing whitespace other than one `\n`.
- [X] T004 Refactor `core/scripts/bash/create-new-feature.sh` to source `derive-branch-name.sh` for the slug+branch-name block (functions: `generate_branch_name`, `generate_ordered_branch`, `generate_feature_name_branch`, `generate_issue_number_branch`, and the `clean_branch_name`/stop-word logic they call). The script's public flags, exit codes, and JSON output MUST be unchanged.
- [X] T005 [P] Wire `tests/test-derive-branch-name.sh` into `tests/run-tests.sh` in the "Core files integrity" region so it runs on every `bash tests/run-tests.sh`. Confirm the existing "Branch naming styles" tests continue to pass unchanged (parity guard).
- [X] T006 Create `core/hooks/rename-on-kickoff.sh` per the hook contract in `contracts/derive-branch-name.md`. Implementation notes: read JSON from stdin via `jq -r '.prompt // empty'`; match `^/trc\.(specify|headless|chain)\b`; for specify/headless read `branching.style` and `branching.prefix` from `tricycle.config.yml` (reuse `bin/lib/yaml_parser.sh` if callable from a hook context, else an inline awk parse consistent with `create-new-feature.sh`'s `read_project_name`); for chain, parse the range-or-list arg per the rules in `data-model.md`; emit `{"hookSpecificOutput":{"sessionTitle":"<target>"}}` on success, empty stdout on no-match or error. `chmod +x` the file.
- [X] T007 [P] Add `tests/test-rename-hook.sh` covering: (a) no-op on non-kickoff prompts (exit 0, empty stdout); (b) correct `sessionTitle` for `/trc.specify` with explicit `TRI-XXX` in the description; (c) correct `sessionTitle` for `/trc.specify` with no ticket (empty stdout — defers to command-template fallback); (d) correct `sessionTitle` for `/trc.chain TRI-100..TRI-104` → `trc-chain-TRI-100..TRI-104`; (e) correct `sessionTitle` for `/trc.chain TRI-100,TRI-103,POL-42` → `trc-chain-TRI-100+2`; (f) singleton `/trc.chain TRI-100` → `trc-chain-TRI-100+0`; (g) idempotency — when `CLAUDE_SESSION_TITLE` env var already equals the target, stdout is empty; (h) cold-path timing under 500 ms on the local machine (best-effort assertion, `time` + upper bound).
- [X] T008 Update `bin/tricycle` `cmd_generate_settings` to register `.claude/hooks/rename-on-kickoff.sh` as the first `UserPromptSubmit` hook entry. Output JSON schema: `"UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": ".claude/hooks/rename-on-kickoff.sh", "timeout": 5 } ] } ]`. Place the new `UserPromptSubmit` array between `PreToolUse` and `PostToolUse` in the generated `settings.json`. Install the hook file via the existing `install_dir "$TOOLKIT_ROOT/core/hooks" ".claude/hooks"` path — no new plumbing needed.
- [X] T009 [P] Add `tests/test-generate-settings-rename-hook.sh` asserting: (a) after `tricycle generate settings`, `.claude/settings.json` contains a `UserPromptSubmit` entry pointing at `.claude/hooks/rename-on-kickoff.sh`; (b) the hook file is `+x` and sits at `.claude/hooks/rename-on-kickoff.sh` after `tricycle init` or `tricycle update`.
- [X] T010 [P] Wire `tests/test-rename-hook.sh` and `tests/test-generate-settings-rename-hook.sh` into `tests/run-tests.sh` under a new `Session rename hook:` block near the existing hook-integrity block.

---

## Phase 3 — User Story 1: Solo `/trc.specify` renames the session [P1]

**Story goal**: When a developer invokes `/trc.specify <description>`, the current session is renamed to the would-be branch name before any side effect. The primary mechanism (hook) is already in place after Phase 2; this phase wires the command-template fallback for hosts/installs that don't honor the hook.

**Independent test (from `spec.md` User Story 1 and `quickstart.md` Test 1)**: Invoke `/trc.specify TRI-200 Export user data to CSV` in a fresh session. Session label must be `TRI-200-export-user-data-csv` after the first agent turn. Verified via the Claude Code session list — no transcript-derived placeholder label.

- [X] T011 [US1] Update `core/commands/trc.specify.md` by inserting a new **Step 0.5: Session rename (fallback)** block between the existing Step 0 (branch-naming configuration) and Step 1 (generate slug). The block instructs the agent to: (a) derive the target label by calling `.trc/scripts/bash/derive-branch-name.sh` with the same flags it's about to pass to `create-new-feature.sh`; (b) compare to the current session label (env var, see T006); (c) if different, emit `/rename <target>` as the first text in the agent's turn before any further tool call; (d) if equal, skip silently. The block must explicitly state that this step is a fallback and that the `UserPromptSubmit` hook already performs the rename in most installs.
- [X] T012 [P] [US1] Extend `tests/test-chain-md-contract.sh` with grep anchors for the new Step 0.5 — or if the trc.specify.md guards belong in a sibling test, create `tests/test-specify-md-contract.sh` with anchors: `"Step 0.5"`, `"Session rename (fallback)"`, `"/rename"`, `"derive-branch-name.sh"`. Wire the new test into `tests/run-tests.sh`.

**Checkpoint**: `bash tests/run-tests.sh` is green. `/trc.specify` on a consumer repo renames the session in the happy path (hook) and on a hook-less install (fallback).

---

## Phase 4 — User Story 2: `/trc.chain` orchestrator and workers get labeled [P1]

**Story goal**: The orchestrator session carries a chain-scoped label; every spawned worker sub-agent carries its per-ticket branch-name label.

**Independent test (from `spec.md` User Story 2 and `quickstart.md` Test 2)**: Run two concurrent `/trc.chain` invocations over different ranges. Session list shows `trc-chain-TRI-300..TRI-302` and `trc-chain-POL-42+1` unambiguously. While a worker is running, introspecting the worker shows the per-ticket label (degrades gracefully if sub-agent rename isn't supported).

- [X] T013 [US2] Update `core/commands/trc.chain.md` by inserting a **Step 0.5: Session rename (fallback)** at the top of the Pre-Flight Validation block, before the "Empty input check". The instruction: (a) compute the chain-scoped label per `data-model.md` rules (range or list form); (b) if different from current label, emit `/rename <target>`; (c) if equal, skip. Add a line noting the `UserPromptSubmit` hook normally handles this and the block is the fallback.
- [X] T014 [US2] In the same update to `core/commands/trc.chain.md`, extend the Worker Brief Template's HARD CONTRACT section with a new rule: **"First action: `/rename <branch-name>`"**. The rule instructs the worker to emit `/rename <branch-name>` as its very first output before any tool call or file read. Add a graceful-degradation note: if the primitive is unsupported in the sub-agent conversation, the worker continues; this is an explicit non-failure per SC-005.
- [X] T015 [P] [US2] Extend `tests/test-chain-md-contract.sh` with grep anchors for: (a) orchestrator fallback block ("trc-chain-", "Step 0.5"); (b) worker rename rule in the brief ("First action: `/rename`"). Test must fail if either is dropped in a future edit.

**Checkpoint**: `bash tests/run-tests.sh` is green. Running `/trc.chain TRI-300..TRI-302` in a consumer repo renames the orchestrator session and each worker session (where supported).

---

## Phase 5 — User Story 3: `/trc.headless` inherits the rename [P2]

**Story goal**: `/trc.headless` is a thin wrapper that calls `/trc.specify` (plus downstream phases). The rename happens through whichever of the two commands is invoked outermost, and downstream invocations do not clobber.

**Independent test (from `spec.md` User Story 3 and `quickstart.md` Test 5)**: `/trc.headless TRI-400 Add rate limiting` renames to `TRI-400-add-rate-limiting` exactly once at the start. Downstream `/trc.specify` is a no-op rename.

- [X] T016 [US3] Update `core/commands/trc.headless.md` with a **Step 0.5: Session rename (fallback)** mirroring T011, placed before any other kickoff work. Explicitly note the idempotency contract: when `/trc.specify`'s internal Step 0.5 later runs inside the headless flow, it MUST detect the label already matches and skip.
- [X] T017 [P] [US3] Extend the relevant `*-md-contract.sh` test (from T012 or a dedicated `tests/test-headless-md-contract.sh`) with grep anchors for headless Step 0.5. Wire into `tests/run-tests.sh` if new.

**Checkpoint**: `bash tests/run-tests.sh` is green. `/trc.headless` renames exactly once in a fresh session.

---

## Phase 6 — Polish & Cross-Cutting Concerns

- [X] T018 Walk through every step of `quickstart.md` manually in a consumer repo (`../polst` or a scratch fixture). Record any divergence between documented behavior and observed behavior as a blocker issue — do NOT mark `/trc.implement` done until all six quickstart tests pass.
- [X] T019 [P] Run `bash tests/run-tests.sh` end-to-end. Must be green (the 103 pre-existing tests plus the ~5 new ones added in this feature).
- [X] T020 [P] Confirm no regressions against the "Branch naming styles" and "`--provision-worktree` flag" test blocks in `tests/run-tests.sh` — these exercise `create-new-feature.sh`'s behavior and are the parity guard for T004's refactor.
- [X] T021 Update `/Users/alex/projects/tricycle-pro-TRI-31-session-rename-on-kickoff/CLAUDE.md` "Recent Changes" section manually if the auto-update didn't land it cleanly (already partially done by `update-agent-context.sh` in the plan phase).

---

## Dependencies

```text
Phase 1 (T001)  ──▶  Phase 2 (T002–T010)  ──┬──▶  Phase 3 (T011–T012) [US1]
                                             ├──▶  Phase 4 (T013–T015) [US2]
                                             └──▶  Phase 5 (T016–T017) [US3]

Phase 3, 4, 5 are independent of each other — they can proceed in parallel
once Phase 2 is complete — but each user story's contract test (T012, T015,
T017) depends on its own command-template edit landing first.

Phase 6 (T018–T021) requires all prior phases complete.
```

Inside Phase 2:

- T002 blocks T003, T004, T005. (Helper must exist before its parity test runs and before `create-new-feature.sh` can source it.)
- T004 (refactor) must not start until T002 and T003 are both green — parity is the guard.
- T006 (hook) is independent of T002–T005 at the file level but semantically depends on T002 because the hook calls the helper. Serialize T006 after T002.
- T007 blocks on T006.
- T008 (generator wiring) blocks on T006 (file must exist for `install_dir` to find it).
- T009 blocks on T008.
- T005, T007, T009, T010 are all `[P]` with each other where their file lists don't overlap.

---

## Parallel execution opportunities

**Phase 2 fast lane**: after T002 is in, T003 and T005 can run in parallel with T006 (different files). T007 can land in parallel with T008/T009 once T006 is in. Net: Phase 2 is ~3 serial chunks instead of 9.

**Phase 3/4/5**: all three user-story phases are independent of each other and can be pipelined — one agent per story — because no file is shared across them (specify.md, chain.md, headless.md are distinct; contract tests are distinct or append-only).

---

## Implementation strategy (MVP first, incremental)

**MVP (User Story 1 + Phase 2)**: Ship `derive-branch-name.sh`, the `UserPromptSubmit` hook, the settings-generator wiring, and the `/trc.specify` fallback. This delivers the primary value — the most common kickoff path is correctly labeled — with no dependency on `/trc.chain` or `/trc.headless` edits. If time runs out, merging the MVP alone is still useful: it is a strict improvement over today.

**Increment 2 (User Story 2)**: Add the `/trc.chain` orchestrator fallback and worker-brief `/rename` rule. Unlocks the chain-distinction flow.

**Increment 3 (User Story 3)**: Add the `/trc.headless` fallback. Closes coverage.

**Polish (Phase 6)**: Manual quickstart + full-suite regression. Version bump to `0.19.0` happens at release time, in the main branch, post-merge — not in this feature branch (per repo convention).

---

## Format validation

Every task above begins with `- [ ]`, carries a sequential `T0NN` ID, has a `[P]` marker only when genuinely parallelizable, and includes the concrete file path or explicit no-file-written note. Story labels appear only on Phase 3/4/5 tasks. Confirmed.

## Task totals

- Setup (Phase 1): 1 task
- Foundational (Phase 2): 9 tasks (T002–T010)
- US1 (Phase 3): 2 tasks (T011–T012)
- US2 (Phase 4): 3 tasks (T013–T015)
- US3 (Phase 5): 2 tasks (T016–T017)
- Polish (Phase 6): 4 tasks (T018–T021)

**Total: 21 tasks.**

Independent test criteria: each user-story phase lists its own verification tied to the matching quickstart test.
Suggested MVP: Phases 1–3 + T019 polish sweep (≈12 tasks, delivers User Story 1 end-to-end).
