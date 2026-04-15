---
description: "Task list for TRI-28 /trc.review command"
---

# Tasks: /trc.review — PR Code Review Command

**Input**: Design documents from `/specs/TRI-28-trc-review-command/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. The spec mandates `tests/run-tests.sh` and `node --test` cover new logic, and the feature's correctness is non-trivial enough to warrant both unit and integration tests.

**Organization**: Tasks are grouped by user story so each story can be implemented and shipped as an independent increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US6)
- Include exact file paths in descriptions

## Path Conventions

Single-project layout. The command lives under `core/commands/trc.review/` (mirroring how `core/commands/trc.audit.md` is laid out). Bundled profiles live alongside the command. Tests go in `tests/`. Config is `tricycle.config.yml` at the repo root.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory skeleton and gitignore/tracked-path seeds so subsequent tasks can drop files into known locations without repeated scaffolding.

- [x] T001 Create directory `core/commands/trc.review/profiles/` for bundled profile files
- [x] T002 [P] Create tracked directory `docs/reviews/` with a `.gitkeep` so the default report dir exists after install
- [x] T003 [P] Add `.trc/cache/` to `.gitignore` at the repo root if not already ignored (verify first with a read; skip the edit if already covered)
- [x] T004 [P] Create empty stub `tests/test-trc-review.sh` with `#!/usr/bin/env bash` + `set -euo pipefail` header and an `exit 0` placeholder, to be filled in later tasks
- [x] T005 [P] Create empty stub `tests/test-trc-review-cache.js` with a `node:test` import and a single `test('placeholder', () => {})` to be filled in later tasks

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Everything in this phase must land before any user story work begins. It creates the command-file skeleton, the config-schema loader behavior, and the shared argument-parsing and `gh`-availability contract the stories rely on.

**⚠️ CRITICAL**: No user story work can begin until Phase 2 is complete.

- [x] T006 Create `core/commands/trc.review.md` skeleton with YAML frontmatter (`description`), the `## User Input` / `$ARGUMENTS` block (mirror `core/commands/trc.audit.md` exactly), and numbered step headings (`### 1. Parse Arguments` through `### 8. Report Completion`) with placeholder bodies. Leave step bodies empty except for step 1, which has the full argument-parsing spec from `contracts/command-args.md`.
- [x] T007 In `core/commands/trc.review.md` step 1, encode PR reference normalization (bare number, `#`-prefixed, PR URL) and all flag parsing (`--prompt`, `--profile`, `--post`, `--source`) with the canonical error messages from `contracts/command-args.md`.
- [x] T008 In `core/commands/trc.review.md`, add a "Preflight" sub-step after step 1 that verifies `gh` is on `$PATH` (fail fast with the canonical error from `contracts/command-args.md`) and that `core/commands/trc.review/profiles/` exists.
- [x] T009 In `core/commands/trc.review.md`, encode step 2 (Load Config): read `review:` block from `tricycle.config.yml` via existing `bin/lib/yaml_parser.sh` patterns, apply defaults from `contracts/config-schema.md`, run all 5 validation rules, abort with the canonical error messages on any violation.
- [x] T010 In `core/commands/trc.review.md`, encode step 3 (Load Constitution): mirror `core/commands/trc.audit.md` step 2 verbatim — read `constitution.root` from config, detect placeholder, warn-and-fallback.
- [x] T011 [P] Create `core/scripts/bash/review-cache.sh` (executable, `set -euo pipefail`): pure helper that given a URL prints the cache path (`.trc/cache/review-sources/<sha256>.md`) using existing `sha256` helper from `bin/lib/helpers.sh`. Also exposes `ensure_cache_dir` that `mkdir -p`'s the directory. No fetching logic — that stays in the command markdown because it needs `WebFetch`.
- [x] T012 [P] Add an end-of-file reference to `core/commands/trc.review.md` that links to `core/commands/trc.audit.md` as the structural analogue, so future maintainers understand the relationship. Single comment line only.

**Checkpoint**: Command skeleton loads, argument parser is canonical, config validation works. User stories can now layer on top.

---

## Phase 3: User Story 1 — Default review against full ruleset (Priority: P1) 🎯 MVP

**Goal**: Running `/trc.review <pr-number>` with no flags produces a complete markdown report under `docs/reviews/` that evaluates the PR diff against the constitution plus all four bundled profiles (quality, style, security, complexity) and lists findings grouped by source with severity tags.

**Independent Test**: Run `/trc.review 26` in this repo. Expect `docs/reviews/review-<today>-PR26.md` to exist with the header block, a "Sources Used" list naming all four profiles, one findings section per profile (zero-findings sections show `_No findings._`), a "Skipped Files" section for binaries, and a summary table. No flags, no config changes.

### Tests for User Story 1 ⚠️

> Write these first and ensure they fail before implementation.

- [x] T013 [P] [US1] Add a `bash` integration test case to `tests/test-trc-review.sh` named `test_default_review_writes_report`: stub `gh` on `$PATH` (via a tmpdir shim that emits canned JSON and a canned diff), invoke the command rendering pipeline, and assert the resulting report file exists at `docs/reviews/review-*-PR42.md` and contains the five header fields and all four profile section headings.
- [x] T014 [P] [US1] Add a `node:test` unit test case to `tests/test-trc-review-cache.js` named `PR reference normalization`: covers inputs `42`, `#42`, `https://github.com/owner/repo/pull/42`, and the invalid input `abc`; asserts each produces the expected normalized number or a parse error. The normalization logic itself is exercised by a small Node helper at `core/scripts/node/normalize-pr-ref.js` (created in T015).

### Implementation for User Story 1

- [x] T015 [P] [US1] Create `core/scripts/node/normalize-pr-ref.js` exporting a single pure function `normalizePrRef(input)` that returns `{ok: true, number}` or `{ok: false, error}` per the rules in `contracts/command-args.md`. No dependencies, no I/O. Required by T014 and imported by T020.
- [x] T016 [P] [US1] Create `core/commands/trc.review/profiles/quality.md` with YAML frontmatter (`name: quality`, `source: [{name: google/eng-practices, url: https://github.com/google/eng-practices/blob/master/review/reviewer/looking-for.md, license: CC-BY-3.0, attribution: "Adapted from Google Engineering Practices, used under CC-BY 3.0"}, {name: baz-scm/awesome-reviewers, url: https://github.com/baz-scm/awesome-reviewers, license: Apache-2.0, attribution: "Adapted from baz-scm/awesome-reviewers, used under Apache-2.0"}]`) and a body listing the quality review rules (correctness, edge cases, error handling, test coverage, input validation). Follow the guidance in research.md Decision 2.
- [x] T017 [P] [US1] Create `core/commands/trc.review/profiles/style.md` with YAML frontmatter citing `baz-scm/awesome-reviewers` (Apache-2.0) and a body listing style rules (naming, formatting, documentation, language-idiomatic patterns). Short and opinionated.
- [x] T018 [P] [US1] Create `core/commands/trc.review/profiles/security.md` with YAML frontmatter citing `baz-scm/awesome-reviewers` (Apache-2.0) and a body listing security rules (injection, authz, secret handling, path traversal, unsafe deserialization, hardcoded credentials).
- [x] T019 [P] [US1] Create `core/commands/trc.review/profiles/complexity.md` with YAML frontmatter citing `baz-scm/awesome-reviewers` (Apache-2.0) and a body listing complexity rules (function length, cognitive load, premature abstraction, dead code, nested conditionals).
- [x] T020 [US1] In `core/commands/trc.review.md`, encode step 4 (Fetch PR): run `gh pr view <N> --json number,title,author,headRefName,baseRefName,state,additions,deletions,url,body`, parse with `jq`, populate a `PullRequestRef` per `data-model.md`. Then run `gh pr diff <N> > <tmp-diff-path>`. Handle the `PR not found` error with the canonical message. Uses normalized PR number from the helper at `core/scripts/node/normalize-pr-ref.js` (depends on T015).
- [x] T021 [US1] In `core/commands/trc.review.md`, encode step 5 (Load Profiles): scan `core/commands/trc.review/profiles/*.md`, read frontmatter, build a list of `ReviewProfile` records per `data-model.md`. Unknown profiles requested via `--profile` abort with the canonical error; default evaluates every profile present (depends on T016–T019).
- [x] T022 [US1] In `core/commands/trc.review.md`, encode step 6 (Evaluate Diff): for each source (constitution, each profile), walk the diff hunks in `<tmp-diff-path>`, skip binary files per the list in `core/commands/trc.audit.md` step 3, and produce `Finding` records with `{source_label, severity, file, line, evidence, recommendation}` per `data-model.md`. Drop findings missing all three of file/line/recommendation (SC-002 quality gate) and log the drop count.
- [x] T023 [US1] In `core/commands/trc.review.md`, encode step 7 (Render Report): write the markdown report to `{review.report_dir}/review-YYYY-MM-DD-PR<N>.md` following `contracts/report-schema.md` exactly — seven header lines, Sources Used list, per-source findings sections (even empty ones, which render `_No findings._`), Skipped Files section, summary table with per-source rows and a Total row. Apply the filename collision rule (append `-1`, `-2`). Handle the empty-diff special case with the `## No reviewable changes` block.
- [x] T024 [US1] In `core/commands/trc.review.md`, encode step 8 (Report Completion) emitting the success output shown in the quickstart (report path, summary counts, elapsed time).
- [x] T025 [US1] Extend `tests/test-trc-review.sh`: make the stubbed `gh` shim emit a diff containing at least one obvious violation per profile (e.g. `const user_name =` for style, a hardcoded credential for security, a 60-line function for complexity, a missing `try/catch` for quality). Assert the resulting report contains at least one finding per profile section.

**Checkpoint**: `/trc.review <N>` works end-to-end on a real PR with default settings. MVP ships here.

---

## Phase 4: User Story 2 — Custom ad-hoc prompt (Priority: P1)

**Goal**: Users can pass `--prompt "<text>"` and get a dedicated "Custom Prompt Findings" section in the report, evaluated against only the PR diff lines.

**Independent Test**: Run `/trc.review 26 --prompt "flag any hardcoded timeouts"` on a PR that introduces a hardcoded `setTimeout(fn, 5000)`. Expect a Custom Prompt Findings section with a finding pointing at that line.

### Tests for User Story 2 ⚠️

- [x] T026 [P] [US2] Add a test case to `tests/test-trc-review.sh` named `test_custom_prompt_section_present`: invoke with `--prompt "flag hardcoded timeouts"` against a canned diff containing `setTimeout(fn, 5000)`; assert the report has a `## Custom Prompt Findings` section with a finding whose `file:line` references the diff line.
- [x] T027 [P] [US2] Add a second test case to `tests/test-trc-review.sh` named `test_empty_prompt_rejected`: invoke with `--prompt ""` and assert the command exits non-zero with the canonical error message `Error: --prompt requires a non-empty argument.`

### Implementation for User Story 2

- [x] T028 [US2] In `core/commands/trc.review.md` step 1 (already drafted in T007), verify `--prompt` parsing handles multiple `--prompt` flags by concatenating their values with a newline separator. Reject empty strings.
- [x] T029 [US2] In `core/commands/trc.review.md` step 6 (Evaluate Diff from T022), add a new evaluation loop that runs the custom prompt against the diff lines when one is present, produces `Finding` records tagged `source_label: custom-prompt`, and feeds them into the same finding pipeline.
- [x] T030 [US2] In `core/commands/trc.review.md` step 7 (Render Report from T023), add a "Custom Prompt Findings" section directly after the last profile section and a summary-table row for the custom prompt. Verbatim-quote the custom prompt text in the "Sources Used" list (truncated to 120 chars with `…` suffix if longer).

**Checkpoint**: US1 and US2 both work independently. Running `/trc.review <N>` with or without `--prompt` produces a complete report.

---

## Phase 5: User Story 3 — Profile subset (Priority: P2)

**Goal**: Users can pass `--profile <list>` to restrict the review to one or more bundled profiles, and the report omits the other profile sections entirely.

**Independent Test**: Run `/trc.review 26 --profile security,complexity`. Expect only the Security Findings and Complexity Findings sections and a summary table with exactly two rows (plus Total).

### Tests for User Story 3 ⚠️

- [x] T031 [P] [US3] Add a test case to `tests/test-trc-review.sh` named `test_profile_subset_excludes_others`: invoke with `--profile security`, assert the report contains `## Security Findings` and does NOT contain `## Quality Findings`, `## Style Findings`, or `## Complexity Findings`.
- [x] T032 [P] [US3] Add a test case to `tests/test-trc-review.sh` named `test_unknown_profile_errors`: invoke with `--profile typescript`, assert the command exits non-zero with `Error: Unknown profile "typescript". Available profiles:` followed by the list.

### Implementation for User Story 3

- [x] T033 [US3] In `core/commands/trc.review.md` step 1, verify the `--profile` parser accepts `all` as a synonym for the default, trims whitespace around commas, and rejects unknown names with the canonical error listing available profiles.
- [x] T034 [US3] In `core/commands/trc.review.md` step 5 (Load Profiles from T021), filter the loaded profile list by the `--profile` selection before passing to the evaluator. Constitution and custom prompt remain unaffected.

**Checkpoint**: `/trc.review <N> --profile <subset>` produces a focused report and the rejection path works.

---

## Phase 6: User Story 4 — Remote rule sources (Priority: P2)

**Goal**: Users can add URLs to `review.sources[]` in `tricycle.config.yml` and the command fetches them via `WebFetch`, caches to `.trc/cache/review-sources/<sha256>.md`, and includes findings against them. Second run uses the cache. `--source <name>` restricts evaluation to a single source.

**Independent Test**: Add a `review.sources` entry pointing at a small public markdown file. Run twice. Verify first run fetches and caches, second run uses the cache, report contains a "Remote Source: <name> Findings" section, and the source appears in "Sources Used". Then run `/trc.review <N> --source <name>` and verify bundled profiles are skipped.

### Tests for User Story 4 ⚠️

- [x] T035 [P] [US4] Add a `node:test` case to `tests/test-trc-review-cache.js` named `cache path is deterministic sha256`: calls a Node wrapper around `core/scripts/bash/review-cache.sh` (invoke via `child_process.execFileSync`), asserts the returned path is `.trc/cache/review-sources/<64-char hex>.md` and is stable across runs for the same URL.
- [x] T036 [P] [US4] Add a `node:test` case to `tests/test-trc-review-cache.js` named `cache hit uses existing file`: seeds a fake cache file, calls the cache-path helper, confirms the file exists and is non-empty (the test is purely about path resolution and existence checks; actual WebFetch is exercised in the bash smoke test).
- [x] T037 [P] [US4] Add a test case to `tests/test-trc-review.sh` named `test_remote_source_fetch_failure_warns`: configure a `review.sources` entry pointing at a non-resolving URL (e.g. `https://invalid.localhost/does-not-exist.md`), stub `WebFetch` to fail, and assert the command still produces a report and the failed source appears under `## Sources Skipped` with a failure reason.
- [x] T038 [P] [US4] Add a test case to `tests/test-trc-review.sh` named `test_source_flag_skips_bundled_profiles`: configure one remote source, invoke with `--source <name>`, assert the report contains the remote source section and does NOT contain `## Quality Findings`, `## Style Findings`, `## Security Findings`, or `## Complexity Findings`.

### Implementation for User Story 4

- [x] T039 [US4] In `core/commands/trc.review.md` step 2 (Load Config from T009), add `review.sources` array parsing and run the non-HTTPS / duplicate-name validations from `contracts/config-schema.md`.
- [x] T040 [US4] In `core/commands/trc.review.md`, add a new step 4b (Load Remote Sources) between the PR-fetch step and the profile-load step: for each entry in `review.sources[]` (or the one matching `--source` if set), compute the cache path by invoking `core/scripts/bash/review-cache.sh` (from T011), read the cache if present, otherwise `WebFetch` the URL and write to the cache path, otherwise mark the source as FAILED and warn. Produces a list of `RemoteSource` records per `data-model.md`.
- [x] T041 [US4] In `core/commands/trc.review.md` step 1, verify `--source` parsing rejects unknown names with the canonical error listing configured sources.
- [x] T042 [US4] In `core/commands/trc.review.md` step 5 (Load Profiles), short-circuit the bundled profile loop when `--source` is set so only the remote source runs (plus constitution and custom prompt if present).
- [x] T043 [US4] In `core/commands/trc.review.md` step 6 (Evaluate Diff from T022), add a new evaluation loop for each successfully loaded `RemoteSource`; findings are tagged `source_label: <source.name>`.
- [x] T044 [US4] In `core/commands/trc.review.md` step 7 (Render Report from T023), add a "Remote Source: <name> Findings" section per loaded source, add entries to the Sources Used list (with CACHED / FETCHED status), add a "Sources Skipped" section listing any FAILED sources with reasons.

**Checkpoint**: Remote sources work, caching works, offline fallback works. `--source` scopes correctly.

---

## Phase 7: User Story 5 — Post findings as PR comment (Priority: P3)

**Goal**: Passing `--post` posts a condensed version of the findings (critical + warning only, no info) as a top-level PR comment via `gh pr comment`, with an interactive confirmation prompt before posting.

**Independent Test**: On a throwaway PR, run `/trc.review <N> --post`, confirm at the prompt, verify a new comment appears on the PR containing only critical+warning findings and a footer line pointing at the local report. Running without `--post` must post nothing.

### Tests for User Story 5 ⚠️

- [x] T045 [P] [US5] Add a test case to `tests/test-trc-review.sh` named `test_post_requires_confirmation`: stub `gh` to track `pr comment` invocations and feed `n\n` to the confirmation prompt; assert no `gh pr comment` call was made.
- [x] T046 [P] [US5] Add a test case to `tests/test-trc-review.sh` named `test_post_confirmed_invokes_gh_comment`: stub `gh`, feed `y\n`, assert `gh pr comment` was called exactly once with `--body-file` and the body file contains the header block, critical+warning findings, no info findings, and the `_Generated by /trc.review_` footer.
- [x] T047 [P] [US5] Add a test case to `tests/test-trc-review.sh` named `test_no_post_flag_never_posts`: invoke without `--post`, feed `y` to stdin just in case, assert `gh pr comment` was NOT called.

### Implementation for User Story 5

- [x] T048 [US5] In `core/commands/trc.review.md`, add step 7b (Optional: Post to PR) after step 7: if `--post`, render the condensed variant per `contracts/report-schema.md` into a temp file, prompt the user `Post review findings to PR #<N> as a comment? (y/N)`, only on explicit `y`/`yes` invoke `gh pr comment <N> --body-file <tmp>`. Clean up the temp file in all paths. Log the result (posted / declined / error).
- [x] T049 [US5] In `contracts/report-schema.md`, verify the condensed variant rendering rules are referenced by step 7b and link the footer format back to the contract.

**Checkpoint**: `--post` never posts without explicit opt-in and confirmation.

---

## Phase 8: User Story 6 — Hand off to output skills (Priority: P3)

**Goal**: After the report is written, the command reads `workflow.blocks.review.skills` from the config and invokes each installed skill (e.g. `linear-audit`) with the report path, mirroring `/trc.audit` step 6.

**Independent Test**: Add `linear-audit` to `workflow.blocks.review.skills`. Run the command on a PR with at least one warning. Verify the skill is invoked with the report path and creates a Linear ticket.

### Tests for User Story 6 ⚠️

- [x] T050 [P] [US6] Add a test case to `tests/test-trc-review.sh` named `test_output_skill_invoked_when_installed`: create a fake `.claude/skills/test-skill/SKILL.md` and a fake skill invocation recorder, add `test-skill` to `workflow.blocks.review.skills`, run the command, assert the recorder was called once with the report path.
- [x] T051 [P] [US6] Add a test case to `tests/test-trc-review.sh` named `test_uninstalled_skill_skipped_silently`: add `nonexistent-skill` to `workflow.blocks.review.skills`, run the command, assert the command succeeds and no error is emitted about the missing skill.

### Implementation for User Story 6

- [x] T052 [US6] In `core/commands/trc.review.md`, add step 8 (Invoke Output Skills) before step 9 (the existing Report Completion step; renumber as needed): copy the implementation of `core/commands/trc.audit.md` step 6 verbatim, substituting `workflow.blocks.audit.skills` with `workflow.blocks.review.skills` and the report-directory context with the review report path.

**Checkpoint**: Output-skill hand-off is identical to `/trc.audit`'s behavior. Linear-audit, document-writer, and future output skills plug in without further code changes.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Wiring, docs, version bump, and final test-suite run.

- [x] T053 Update `tricycle.config.yml` to add the default `review:` block (all four profiles, empty sources, `docs/reviews` report dir, `post_to_pr: false`) and the `workflow.blocks.review: {skills: []}` entry. This makes the new block visible in the tracked config as documentation.
- [x] T054 [P] Update `CLAUDE.md` Recent Changes section to mention the new command (one line under the existing TRI-28 entry already added by `update-agent-context.sh`). Also add a short mention alongside `trc.audit` in the Commands section if present.
- [x] T055 [P] Bump `VERSION` from `0.17.0` to `0.18.0` (minor bump — new user-facing command; confirmed in plan.md).
- [x] T056 [P] Add `docs/reviews/.gitkeep` (if not already created in T002) and verify `.trc/cache/` is in `.gitignore`.
- [x] T057 Run `bash tests/run-tests.sh` from the repo root; fix any failures surfaced by the new tests.
- [x] T058 Run `node --test tests/test-*.js` from the repo root; fix any failures in the cache tests.
- [x] T059 [P] Manual quickstart pass: execute steps 1, 2, 3 of `specs/TRI-28-trc-review-command/quickstart.md` against a real PR in this repo (TRI-26 PR #25 is a good target), verify each step's expected report structure. Do NOT run step 6 (`--post`) in this pass to avoid posting comments; that path is covered by the stubbed test.
- [x] T060 [P] Documentation pass on `core/commands/trc.review.md`: read end-to-end, tighten language, verify all canonical error messages match `contracts/command-args.md`, no orphaned TODOs remain.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: No dependencies — can start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1. Blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2. This is the MVP.
- **Phase 4 (US2)**: Depends on Phase 3 (extends step 1 parser and steps 6/7 renderer from US1).
- **Phase 5 (US3)**: Depends on Phase 3 (filters the profile list from US1).
- **Phase 6 (US4)**: Depends on Phase 3 (adds a new evaluation and rendering branch). Independent of US2 and US3.
- **Phase 7 (US5)**: Depends on Phase 3 (reads the report produced by US1). Independent of US2, US3, US4.
- **Phase 8 (US6)**: Depends on Phase 3 (uses the report path from US1). Independent of US2, US3, US4, US5.
- **Phase 9 (Polish)**: Depends on whichever user stories are being shipped.

### Task-level parallel opportunities

- Phase 1: T002, T003, T004, T005 are all `[P]` — do together after T001.
- Phase 2: T011 and T012 are `[P]` — can run alongside T006–T010. The sequential chain inside `trc.review.md` (T006 → T007 → T008 → T009 → T010) is forced because they edit the same file.
- Phase 3: Profile files T016, T017, T018, T019 are all `[P]`. T015 (`normalize-pr-ref.js`) is `[P]` with the profile files. Tests T013 and T014 are `[P]` and should be written first.
- Phases 4–8: All tests within a single story are `[P]`. Sequential tasks within a story are generally forced by the shared `core/commands/trc.review.md` file.
- Phase 9: T054, T055, T056, T059, T060 are `[P]`.

### Within each user story

- Tests are written first and must fail before implementation begins.
- Profile files before the load-profile step that reads them (T016–T019 before T021).
- Normalize helper before the fetch step that uses it (T015 before T020).
- Load-Config before any step that depends on validated config values (T009 before T040).

---

## Parallel Example: User Story 1

```bash
# Write tests first (parallel):
Task: "T013 [P] [US1] Add test_default_review_writes_report to tests/test-trc-review.sh"
Task: "T014 [P] [US1] Add PR reference normalization test to tests/test-trc-review-cache.js"

# Then create profile files and helper in parallel:
Task: "T015 [P] [US1] Create core/scripts/node/normalize-pr-ref.js"
Task: "T016 [P] [US1] Create core/commands/trc.review/profiles/quality.md"
Task: "T017 [P] [US1] Create core/commands/trc.review/profiles/style.md"
Task: "T018 [P] [US1] Create core/commands/trc.review/profiles/security.md"
Task: "T019 [P] [US1] Create core/commands/trc.review/profiles/complexity.md"

# Then the sequential pipeline steps (same file, so no parallelism):
# T020 → T021 → T022 → T023 → T024 → T025
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 (Setup) — 5 tasks, ~15 min.
2. Phase 2 (Foundational) — 7 tasks, most of the command-file scaffolding.
3. Phase 3 (US1) — 13 tasks including tests, ~60–90 min; the main event.
4. **STOP and validate**: run `/trc.review <N>` against a real PR in this repo, read the report, confirm it contains meaningful findings.
5. Ship the MVP as its own commit/PR if time-constrained. Remaining phases layer cleanly.

### Incremental Delivery

1. Phases 1 + 2 + 3 → MVP report generation (demo on a real PR).
2. Phase 4 (US2) → add `--prompt`; demo again with a team-specific concern.
3. Phase 5 (US3) → add `--profile`; useful for focused reviews.
4. Phase 6 (US4) → add remote sources; useful for teams with shared style guides.
5. Phase 7 (US5) → add `--post`; first team-visible feature, gate with confirmation.
6. Phase 8 (US6) → hand-off to output skills; useful for ticket routing.
7. Phase 9 (Polish) → version bump + tests + docs + final pass.

### Parallel Team Strategy

- Dev A: Phases 1 → 2 → 3 (MVP path).
- Dev B (after Phase 2): Profiles T016–T019 (all `[P]`, different files).
- Dev C (after MVP): US4 (remote sources) in parallel with Dev A tackling US2.

---

## Task Count

- **Setup**: 5 tasks (T001–T005)
- **Foundational**: 7 tasks (T006–T012)
- **US1 (MVP)**: 13 tasks (T013–T025)
- **US2**: 5 tasks (T026–T030)
- **US3**: 4 tasks (T031–T034)
- **US4**: 10 tasks (T035–T044)
- **US5**: 5 tasks (T045–T049)
- **US6**: 3 tasks (T050–T052)
- **Polish**: 8 tasks (T053–T060)
- **Total**: 60 tasks

Parallel opportunities: roughly 25 tasks are marked `[P]`, concentrated in profile creation, tests, and Phase 9 polish. Sequential tasks are mostly forced by shared edits to `core/commands/trc.review.md`.

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to specific user story for traceability.
- Each user story should be independently shippable after Phase 2 completes.
- Verify tests fail before implementing.
- Commit after each story phase for a clean history.
- Stop at any checkpoint to validate the story independently.
- Avoid: vague tasks, same-file conflicts in parallel tasks, cross-story dependencies that would break independence.
