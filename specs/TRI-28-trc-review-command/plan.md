# Implementation Plan: /trc.review — PR Code Review Command

**Branch**: `TRI-28-trc-review-command` | **Date**: 2026-04-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/TRI-28-trc-review-command/spec.md`

**Version**: 0.17.0 → 0.18.0 (minor bump — new user-facing command)

## Summary

Add a new first-class command `/trc.review <pr-number>` that produces a structured, diff-aware code review for an open pull request. The command mirrors the shape of `/trc.audit` (argument parsing, constitution loading, severity-tagged findings, markdown report, output-skill hand-off) but operates on PR diff lines instead of whole files. It evaluates the diff against four bundled markdown review profiles (quality, style, security, complexity) curated from permissively-licensed open-source prompt libraries (`baz-scm/awesome-reviewers`, `qodo-ai/pr-agent`), plus the project constitution, an optional `--prompt`, and optional user-configured remote sources fetched at runtime and cached locally under `.trc/cache/review-sources/`. Output is a markdown report at `docs/reviews/review-YYYY-MM-DD-PR<N>.md`, with optional `--post` to publish a condensed version as a PR comment (gated by a confirmation prompt), and optional hand-off to skills listed in `workflow.blocks.review.skills` (e.g. `linear-audit` for auto-ticketing).

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default); Node.js ≥ 18 (tests only, via `node --test`). No new runtime languages.
**Primary Dependencies**: Existing in-repo helpers only — `bin/lib/helpers.sh`, `bin/lib/yaml_parser.sh`, `bin/lib/common.sh`, `core/scripts/bash/json_builder.sh`. External CLI: `gh` (GitHub CLI, user-provided, authenticated). Agent-side tool: Claude Code's `WebFetch` (for remote sources).
**Storage**: Filesystem only. Markdown reports under `docs/reviews/`; remote-source cache under `.trc/cache/review-sources/<sha256>.md`. No database. No migrations.
**Testing**: `bash tests/run-tests.sh` (integration smoke test with stubbed `gh`), `node --test tests/test-*.js` (unit tests for cache logic and URL normalization).
**Target Platform**: macOS + Linux shells. Runs inside Claude Code sessions as a slash command (`.claude/commands/trc.review.md`) and inside the tricycle-pro CLI install path (`core/commands/trc.review.md`).
**Project Type**: CLI command — markdown-defined trc command, executed by the Claude agent interpreting the command's instructions and invoking shell helpers / MCP tools as needed. No compiled binary, no persistent service.
**Performance Goals**: A typical PR (under 500 changed lines) reviewed end-to-end in under 60 seconds. Repeat runs with cache hits ≥ 30% faster than first run.
**Constraints**: Must run without network access when only bundled profiles are used. Must never mutate source tree or commit history. Must never post to a PR without explicit user confirmation. Remote source documents assumed ≤ a few hundred KB.
**Scale/Scope**: Single command file (~200 lines markdown) + 4 profile files (~100 lines each) + 2 test files + 1 config block + minimal helper script for cache path resolution if shared across sources.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: Constitution is unpopulated (contains only the `/trc.constitution` placeholder). No explicit project-level gates to evaluate.

**Fallback gates** (common-sense, derived from the existing codebase's conventions):

| Gate | Check | Result |
|---|---|---|
| **Reuse over novelty** | New feature must reuse existing helper libraries where practical | PASS — plan uses `helpers.sh`, `yaml_parser.sh`, `json_builder.sh`, `common.sh` and mirrors `trc.audit` structure verbatim for steps 2/3/6 |
| **Single-purpose scripts** | No monolithic scripts | PASS — command is a markdown instruction file; any shell helpers are scoped to one purpose (cache resolution) |
| **Test coverage for new logic** | Non-trivial logic must have tests | PASS — cache key/hit-miss logic and PR reference normalization get unit tests; end-to-end flow gets a stubbed-`gh` smoke test |
| **No side effects without confirmation** | Writes that affect shared state need approval gates | PASS — local report writes are opt-in via user running the command; `--post` is opt-in and additionally confirmation-gated |
| **Respect `worktree.enabled` flag** | Spec work happens in worktree when enabled | PASS — this very feature is being authored in a worktree at `../tricycle-pro-TRI-28-trc-review-command` |
| **Branching style** | Use configured `branching.style`/`prefix` | PASS — branch is `TRI-28-trc-review-command`, matching `issue-number` style with `TRI` prefix |

**Re-check after Phase 1**: No new gates triggered; design stays within existing patterns.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-28-trc-review-command/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file (/trc.plan output)
├── research.md          # Phase 0: open-source prompt source evaluation + licensing
├── data-model.md        # Phase 1: entity and config schema details
├── quickstart.md        # Phase 1: how to try the command after install
├── contracts/
│   ├── command-args.md  # Phase 1: /trc.review argument schema
│   ├── config-schema.md # Phase 1: new review: block in tricycle.config.yml
│   └── report-schema.md # Phase 1: markdown report structure and summary table
├── checklists/
│   └── requirements.md  # Spec quality checklist (complete)
└── tasks.md             # Phase 2 output (/trc.tasks command — NOT created here)
```

### Source Code (repository root)

```text
core/
├── commands/
│   ├── trc.review.md                     # NEW — main command definition (mirrors trc.audit.md)
│   └── trc.review/
│       └── profiles/
│           ├── quality.md                # NEW — bundled profile, adapted from qodo-ai/pr-agent
│           ├── style.md                  # NEW — bundled profile, adapted from baz-scm/awesome-reviewers
│           ├── security.md               # NEW — bundled profile, adapted from awesome-reviewers + OWASP
│           └── complexity.md             # NEW — bundled profile, adapted from awesome-reviewers
├── scripts/
│   └── bash/
│       └── review-cache.sh               # NEW (optional) — small helper for cache path + fetch fallback
└── skills/
    └── (unchanged — code-reviewer skill already exists and is not modified)

bin/
└── lib/                                  # UNCHANGED — reused as-is
    ├── helpers.sh
    ├── yaml_parser.sh
    └── common.sh

tricycle.config.yml                       # MODIFIED — add review: block + workflow.blocks.review
CLAUDE.md                                 # MODIFIED — add trc.review to Recent Changes
VERSION                                   # MODIFIED by /trc.implement — bump to 0.18.0

tests/
├── test-trc-review.sh                    # NEW — bash smoke test with stubbed `gh`
└── test-trc-review-cache.js              # NEW — node --test unit test for cache hit/miss and URL hashing

docs/
└── reviews/                              # NEW directory — populated at runtime by the command
    └── .gitkeep                          # NEW — so the tracked directory exists after install

.trc/
└── cache/
    └── review-sources/                   # NEW directory — gitignored, populated at runtime
```

**Structure Decision**: Single-project layout (Option 1). The feature adds one new command package under `core/commands/trc.review/`, one optional shared helper script under `core/scripts/bash/`, a new config block, two test files, and a `.gitkeep`-seeded report directory. No new top-level directories; no new language runtimes; no changes to existing helpers.

## Phase 0 plan — Outline & Research

The feature has no `[NEEDS CLARIFICATION]` markers in the spec. Phase 0 therefore focuses on validating the two external inputs the design depends on:

1. **Open-source review-prompt source selection & licensing** — confirm that `baz-scm/awesome-reviewers` and `qodo-ai/pr-agent` are both under permissive licenses (MIT/Apache/CC-BY) so content can be adapted into bundled profiles with attribution. Document the exact files to draw from and any attribution text to include in the profile frontmatter.
2. **GitHub CLI integration patterns** — confirm the minimal `gh` commands needed (`pr view`, `pr diff`, `pr comment`) and their JSON output shapes, and how existing tricycle-pro commands invoke them (no new wrapper needed).

These are documented in `research.md` as decisions with rationale and alternatives, so the implementation phase doesn't revisit them.

## Phase 1 plan — Design & Contracts

Phase 1 produces three contract documents, a lightweight data-model file, and a quickstart:

- **`contracts/command-args.md`** — formal argument schema for `/trc.review`: positional PR reference (accepts `42`, `#42`, `https://github.com/owner/repo/pull/42`), flags (`--prompt`, `--profile`, `--post`, `--source`), exit behavior, error messages.
- **`contracts/config-schema.md`** — the new `review:` block in `tricycle.config.yml`: fields, defaults, validation rules, plus the `workflow.blocks.review` entry. Documents that the block is additive and has no migration path because the default behavior works with zero config.
- **`contracts/report-schema.md`** — the markdown report structure: header block, Sources Used list, per-source findings sections with severity tags, Skipped Files section, Summary table columns, and the condensed variant used when posting as a PR comment.
- **`data-model.md`** — the six entities from the spec (Pull Request reference, Review profile, Remote source, Finding, Review report, Config block) expressed as record-shaped structures with field names and types, for consistency across the command text, report renderer, and cache helper.
- **`quickstart.md`** — three-minute walkthrough: install, run on a real PR, read the report, add a remote source, rerun, optionally `--post` on a test PR.

**Agent context update**: Run `.trc/scripts/bash/update-agent-context.sh claude` after Phase 1 so CLAUDE.md gains a Recent Changes entry pointing at this branch. No new languages or dependencies to add — only the new command path.

**Version note**: This is a new user-facing command → minor bump. Plan targets `0.17.0 → 0.18.0`. `/trc.implement` will perform the bump at the end.

## Phase 2 (out of scope for /trc.plan)

`/trc.tasks` will consume this plan plus `research.md`, `data-model.md`, and the contracts to emit a dependency-ordered `tasks.md`. Implementation executes from there.

## Complexity Tracking

No constitution violations to justify. The design sits within the existing `trc.audit`-shaped pattern, reuses existing helpers, and adds no new runtime dependencies.
