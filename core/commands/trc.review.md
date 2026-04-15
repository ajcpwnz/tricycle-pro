---
description: >-
  Review an open pull request against bundled profiles (quality, style,
  security, complexity), the project constitution, and optional custom
  or remote rule sources. Produces a structured report in docs/reviews/.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

This command mirrors the shape of `/trc.audit` (argument parsing, constitution loading, severity-tagged findings, markdown report, output-skill hand-off) but operates on a pull request's **diff lines** — not whole files — and evaluates against multiple rule sources in a single run.

## Review Execution

### 1. Parse Arguments

Parse the user input for:

- **`<pr-ref>`** (positional, required): a pull request reference in one of three forms. Normalize to a positive integer `PR_NUMBER`:
  1. Bare number (`42`) — use as-is.
  2. Hash-prefixed (`#42`) — strip the leading `#`.
  3. Full GitHub PR URL (`https://github.com/<owner>/<repo>/pull/42`) — extract the trailing `\d+`.
  Any value that does not resolve to a positive integer is a parse error:
  `Error: /trc.review: expected PR number, got "<input>"`.

- **`--prompt "<text>"`**: ad-hoc review criteria. Multiple `--prompt` flags are concatenated with newlines. Empty prompt text is an error:
  `Error: --prompt requires a non-empty argument.`

- **`--profile <name>[,<name>...]`** or **`--profile all`**: comma-separated subset of bundled profiles to evaluate. Whitespace around commas is ignored. `all` is a synonym for "evaluate every profile present". Default (flag omitted) behaves like `all`. Unknown names produce:
  `Error: Unknown profile "<name>". Available profiles: <list>.`

- **`--post`**: after writing the local report, post a condensed version (critical + warning findings only, info excluded) as a top-level PR comment via `gh pr comment`. Requires interactive confirmation before posting (see step 7b). There is no `--yes` auto-confirm flag.

- **`--source <name>`**: restrict evaluation to a single configured remote source (from `review.sources[]`). When used, **bundled profiles are skipped entirely**; constitution and custom prompt still run. Unknown source names produce:
  `Error: Unknown source "<name>". Configured sources: <list>.`

All flags may be combined freely.

### Preflight

Before any other work:

1. Verify `gh` is on `$PATH`. If not, abort with:
   `Error: /trc.review requires the GitHub CLI (gh). Install it from https://cli.github.com/ and run gh auth login.`
2. Verify `core/commands/trc.review/profiles/` exists relative to the repo root. If not, abort with:
   `Error: bundled profiles directory not found. The /trc.review install is incomplete.`

### 2. Load Config

Read `tricycle.config.yml` from the repo root and parse the `review:` block using the existing YAML patterns (`bin/lib/yaml_parser.sh`). Apply defaults per `contracts/config-schema.md`:

- `review.profiles` — default `[quality, style, security, complexity]`
- `review.sources` — default `[]`
- `review.report_dir` — default `docs/reviews`
- `review.post_to_pr` — default `false` (reserved; not read in this version)
- `workflow.blocks.review.skills` — default `[]`

**Validation** (abort with the exact error message on any violation):

1. Every name in `review.profiles` must correspond to a file under `core/commands/trc.review/profiles/<name>.md`. Unknown names:
   `Error: Unknown profile "<name>". Available profiles: <list>.`
2. `review.sources[]` entry names must be unique:
   `Error: duplicate review source name "<name>".`
3. Every `review.sources[].url` must start with `https://`:
   `Error: review source "<name>" must use https:// (got <url>).`
4. `review.report_dir` must be a relative path and must not contain `..`:
   `Error: review.report_dir must be a relative path inside the repo (got <value>).`

### 3. Load Constitution

Read the constitution path from `tricycle.config.yml` (`constitution.root`, default `.trc/memory/constitution.md`). Mirror `trc.audit`'s behavior exactly:

- File missing: ERROR `Constitution file not found at <path>.`
- File contains only the placeholder `_Run \`/trc.constitution\` to populate this file._`: WARN `Constitution not populated — proceeding with profiles + custom prompt + remote sources.` and mark the constitution source as "fallback" in Sources Used.
- File has real content: parse each top-level heading or numbered item as an individual auditable rule.

### 4. Fetch PR Data

Run:

```bash
gh pr view "$PR_NUMBER" --json number,title,author,headRefName,baseRefName,state,additions,deletions,url,body
```

Parse with `jq` into a `PullRequestRef` record (see `specs/TRI-28-trc-review-command/data-model.md`). Errors from `gh`:

- Not found / no access: `Error: PR #<N> not found or not accessible.`
- Auth / network: propagate the `gh` error text prefixed with `Error: gh pr view failed: `.

Fetch the diff into a temp file:

```bash
DIFF_PATH="$(mktemp -t trc-review-diff.XXXXXX)"
gh pr diff "$PR_NUMBER" > "$DIFF_PATH"
```

Record `$DIFF_PATH` and any other temp files created during this run (e.g. the condensed comment body in step 7b) so step 9 can delete them before returning. If the diff is empty (zero `+`/`-` lines after excluding hunk headers), set `EMPTY_DIFF=true` and skip straight to step 7 to write the minimal "No reviewable changes" report.

### 4b. Load Remote Sources

For each entry in `review.sources[]` (or the single entry matching `--source <name>` if that flag is set):

1. Compute the cache path: `CACHE_PATH=$(.trc/scripts/bash/review-cache.sh path "<url>")`.
2. If the cache file exists and is non-empty, read it (`status: CACHED`).
3. Otherwise, invoke Claude Code's `WebFetch` tool to fetch the URL. On success, run `.trc/scripts/bash/review-cache.sh ensure-dir`, write the content to `CACHE_PATH`, set `status: FETCHED`.
4. On any fetch failure, set `status: FAILED`, emit a warning `Warning: remote source "<name>" fetch failed: <reason>. Skipping.`, and exclude this source from evaluation. It will appear under "Sources Skipped" in the report.

If `--source <name>` is set but no configured source matches that name, abort with:
`Error: Unknown source "<name>". Configured sources: <list>.`

### 5. Load Profiles

Discover bundled profile files:

```bash
for f in core/commands/trc.review/profiles/*.md; do ... done
```

For each file, parse its YAML frontmatter for `name` and `source[]`; parse the body (everything after the second `---`) as the rules text. Build a list of `ReviewProfile` records.

Filter the list:

- If `--profile` is set, keep only profiles whose `name` is in the requested list. Unknown names abort.
- If `--profile` is not set, keep every profile whose name appears in `review.profiles` from the config (default: all four).
- If `--source <name>` is set, **skip bundled profiles entirely** — `ACTIVE_PROFILES=[]`.

A profile file that fails to parse (missing frontmatter, unreadable) is skipped with a warning and added to "Sources Skipped". The command does not abort on a single bad profile.

### 6. Evaluate Diff

For each **active source** — constitution (if populated), each active profile, each successfully loaded remote source, and the custom prompt (if `--prompt` was passed) — walk the diff hunks in `$DIFF_PATH` and produce `Finding` records per `specs/TRI-28-trc-review-command/data-model.md`.

Binary file detection: skip files whose `+++` / `---` hunk header is `/dev/null` with a "Binary files differ" line, or whose path matches any of these extensions: `.png .jpg .jpeg .gif .ico .woff .woff2 .ttf .eot .pdf .zip .tar .gz .bin .exe .dll .so .dylib`. Record each skipped binary in `SKIPPED_FILES`.

For each finding, capture: `source_label`, `severity` (`critical | warning | info`), `file`, `line`, `evidence` (quoted diff line), `recommendation`. **Quality gate**: drop any finding that is missing all three of `file`, `line`, and `recommendation`, and log the drop count. This enforces SC-002 (≥ 90% of findings include concrete references).

Evaluation uses the agent's own reasoning driven by each source's rules text as a system prompt. Ground every finding in a specific diff line — do not invent references.

### 7. Render Report

Write the markdown report to `{review.report_dir}/review-YYYY-MM-DD-PR<N>.md`. If a file already exists at that path, append `-1`, `-2`, ... to the filename stem until a free name is found. Reports are append-only; the command MUST NOT overwrite an existing report.

Use the structure from `specs/TRI-28-trc-review-command/contracts/report-schema.md`:

1. Header block (7 lines: title, date, PR link, author, branch, state, changes, summary counts).
2. Sources Used — one bullet per source that fed the review, with attribution lines for profiles.
3. Sources Skipped (omit section if empty) — one bullet per failed remote source / unloadable profile / empty constitution.
4. One `## <Source> Findings` section per active source. Zero-finding sections render `_No findings._` as the only body. Order within a section: `CRITICAL` → `WARNING` → `INFO`, ties broken by file then line.
5. Skipped Files section (omit if empty).
6. Summary table with one row per source plus a Total row. Columns: Source, Critical, Warning, Info, Passed.

**Empty diff variant**: if `EMPTY_DIFF=true`, replace all findings sections and the summary table with a single block:

```markdown
## No reviewable changes

This PR contains no text diff to review. See the Skipped Files section for any binaries that were omitted.
```

After writing, print the report path to stdout.

### 7b. Optional: Post to PR

If `--post` was passed:

1. Render the condensed variant: keep the header, keep only `critical` and `warning` findings (drop `info`), omit Skipped Files, include a summary table with Info column zeroed, append footer `_Generated by /trc.review — full report at <report_path>._`. Write to a tempfile.
2. Prompt the user interactively:
   ```
   Post review findings to PR #<N> as a comment? (y/N)
   ```
3. Only if the user answers `y` or `yes` (case-insensitive), run:
   ```bash
   gh pr comment "$PR_NUMBER" --body-file "$CONDENSED_TMP"
   ```
4. Print one of: `Posted condensed review to PR #<N>.`, `Skipped posting (user declined).`, or an error message from `gh pr comment` prefixed with `Error: gh pr comment failed: `.
5. Delete the temp file in all paths (success, decline, error).

### 8. Invoke Output Skills

Read `workflow.blocks.review.skills` from the config. For each listed skill name:

1. Check if `.claude/skills/<skill-name>/SKILL.md` exists.
2. If installed: invoke `/<skill-name>` and pass context about the review report location (`<report_path>`).
3. If not installed: skip silently.

If no skills are configured, skip this step entirely.

### 9. Report Completion

Clean up all temp files recorded during the run (`$DIFF_PATH`, the condensed comment body if any). Then print a summary:

- Report file path
- Total findings by severity (critical / warning / info / passed)
- Which sources fed the review (constitution status, active profiles, remote source statuses)
- Whether a PR comment was posted (posted / declined / skipped / error)
- Which output skills were invoked
- If all checks passed with zero findings across all sources: `All checks passed — no findings.`

## Structural analogue

This command mirrors `core/commands/trc.audit.md` intentionally. When in doubt about helper usage (constitution loading, binary-file filtering, output-skill invocation), consult that file — the shapes are identical.
