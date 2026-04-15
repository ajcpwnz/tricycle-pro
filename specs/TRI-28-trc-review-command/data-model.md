# Data Model — /trc.review

**Feature**: TRI-28 /trc.review — PR Code Review Command
**Date**: 2026-04-16

This document expresses the six entities from the spec as record-shaped structures with field names and types. These are the shared vocabulary for the command text, the report renderer, the cache helper, and the tests. No database is involved — entities are in-memory during a command run and the final `Review report` is the only persistent artifact.

---

## PullRequestRef

Normalized pointer to a specific PR. Produced by parsing the positional argument (`42`, `#42`, or a PR URL) and enriched by `gh pr view`.

| Field | Type | Source | Notes |
|---|---|---|---|
| `number` | integer | user arg (normalized) | Required; the only identifier used in paths and filenames |
| `title` | string | `gh pr view` | Used in report header |
| `author` | string | `gh pr view` (`.author.login`) | Used in report header |
| `head_ref` | string | `gh pr view` (`.headRefName`) | Branch name the PR is from |
| `base_ref` | string | `gh pr view` (`.baseRefName`) | Branch name the PR targets |
| `state` | enum `OPEN \| CLOSED \| MERGED` | `gh pr view` (`.state`) | Used in report header |
| `additions` | integer | `gh pr view` | Used in report header |
| `deletions` | integer | `gh pr view` | Used in report header |
| `url` | string | `gh pr view` | Used in report header (linkifies the PR number) |
| `body` | string | `gh pr view` | Stored but not rendered into the report; available to the agent for context |
| `diff_path` | string (filepath) | `gh pr diff <N> > <tmp>` | Temp file; deleted at end of run |

---

## ReviewProfile

A bundled markdown file that expresses one category of review rules. Loaded from `core/commands/trc.review/profiles/<name>.md` at command time.

| Field | Type | Source | Notes |
|---|---|---|---|
| `name` | string | frontmatter `name` | One of `quality`, `style`, `security`, `complexity` for bundled profiles |
| `sources` | array of `{name, url, license, attribution}` | frontmatter `source` | One entry per upstream source adapted into this profile |
| `body` | string (markdown) | file body after frontmatter | The rules themselves; rendered as a system prompt to the evaluating agent |

Discovery rule: bundled profiles are whatever `.md` files exist under `core/commands/trc.review/profiles/` at runtime. Adding a new file is how a user adds a new bundled profile. Invalid profiles (missing frontmatter, unreadable) are skipped with a warning and listed in the report's "Skipped Profiles" subsection.

---

## RemoteSource

User-configured URL declared in `tricycle.config.yml` under `review.sources[]`. Fetched at runtime and cached.

| Field | Type | Source | Notes |
|---|---|---|---|
| `name` | string | config | Human-readable label. Used for `--source <name>` and in the report |
| `url` | string (URL) | config | HTTPS URL to a markdown or plain-text document |
| `cache_path` | string (filepath) | derived | `.trc/cache/review-sources/<hash>.md` where `<hash>` is the 16-char prefix of `sha256(url)` produced by `sha256_str` in `bin/lib/helpers.sh` |
| `status` | enum `CACHED \| FETCHED \| FAILED` | runtime | Populated during the command run, rendered in "Sources Used" |
| `body` | string (markdown) | file or network | The fetched document content |

Cache rule: if `cache_path` exists and is non-empty, use it (`status: CACHED`). The 16-char hash gives a 2^64 collision space which is more than enough for a per-user cache. Otherwise attempt `WebFetch(url)`; on success, write to `cache_path` and set `status: FETCHED`. On failure, set `status: FAILED`, emit a warning, and exclude this source from evaluation.

---

## Finding

A single observation about a specific line in the PR diff.

| Field | Type | Source | Notes |
|---|---|---|---|
| `source_label` | string | evaluator | E.g. `quality`, `security`, `constitution`, `custom-prompt`, or a remote source `name` |
| `severity` | enum `critical \| warning \| info` | evaluator | Controls report grouping and `--post` filtering |
| `file` | string (filepath) | evaluator | Relative to repo root, extracted from the diff hunk |
| `line` | integer | evaluator | Line number in the head of the PR, extracted from the diff hunk `@@ -x,y +n,m @@` |
| `evidence` | string | evaluator | Quoted snippet of the diff line(s) that triggered the finding |
| `recommendation` | string | evaluator | Concrete, actionable advice — not a generic observation |

Constraint (SC-002): at least 90% of findings must have a non-empty `file`, `line`, and `recommendation`. The command's own quality gate should drop any finding that lacks all three and log how many were dropped.

---

## ReviewReport

The persistent markdown artifact produced by the command.

| Field | Type | Source | Notes |
|---|---|---|---|
| `date` | string (YYYY-MM-DD) | runtime | Used in filename |
| `pr` | `PullRequestRef` | runtime | Rendered in the header block |
| `sources_used` | array of `{label, kind, status, attribution?}` | runtime | One entry per constitution / profile / remote source / custom prompt that fed the review |
| `sources_skipped` | array of `{label, reason}` | runtime | Profiles that failed to load, remote sources that failed to fetch, empty constitution, etc. |
| `findings_by_source` | map<string, array<Finding>> | runtime | Grouped for rendering; one section per key |
| `skipped_files` | array of filepath | runtime | Binary files in the diff |
| `summary_table` | array of `{source, critical, warning, info, passed}` | runtime | One row per source plus a Total row |
| `report_path` | string (filepath) | runtime | `docs/reviews/review-<date>-PR<N>.md` (or `review.report_dir` override) |

Filename collision policy: if the target path already exists, append a numeric suffix (`-1`, `-2`, ...) so prior reports are never overwritten. Reports are append-only from the command's perspective.

---

## ConfigBlock

The new `review:` section in `tricycle.config.yml` plus the `workflow.blocks.review` entry. See `contracts/config-schema.md` for the full schema; this section lists the runtime-loaded shape.

| Field | Type | Default | Notes |
|---|---|---|---|
| `review.profiles` | array of string | `[quality, style, security, complexity]` | Which bundled profiles are on by default |
| `review.sources` | array of `{name, url}` | `[]` | User-supplied remote sources |
| `review.report_dir` | string (filepath) | `docs/reviews` | Where reports are written |
| `review.post_to_pr` | boolean | `false` | Default for the `--post` flag |
| `workflow.blocks.review.skills` | array of string | `[]` | Output skills invoked after report generation |

Validation:

- `review.profiles` must only reference profile names that exist under `core/commands/trc.review/profiles/`. Unknown names are an error.
- `review.sources[].url` must be an `https://` URL. Non-HTTPS URLs are rejected at parse time.
- `review.sources[].name` must be unique within the list.
- `review.report_dir` must be a relative path (no absolute paths, no `..` traversal).
- All fields are optional; the block may be omitted entirely and the defaults apply.
