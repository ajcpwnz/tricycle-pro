# Contract: /trc.review argument schema

**Feature**: TRI-28 /trc.review — PR Code Review Command

## Invocation

```
/trc.review <pr-ref> [--prompt "<text>"] [--profile <list>|all] [--post] [--source <name>]
```

## Positional

### `<pr-ref>` (required)

A pull request reference. Accepted forms:

- Bare number: `42`
- Hash-prefixed: `#42`
- Full GitHub PR URL: `https://github.com/<owner>/<repo>/pull/42`

Normalization rules:

1. Strip a leading `#` if present.
2. If the input matches `https?://github\.com/[^/]+/[^/]+/pull/(\d+)`, extract the trailing `\d+` as the number.
3. The final normalized form is a positive integer. Any value that does not resolve to a positive integer is a parse error.

Error: `/trc.review: expected PR number, got "<input>"`.

## Flags

### `--prompt "<text>"`

Ad-hoc review criteria. The text is evaluated against the PR diff and findings appear in a dedicated "Custom Prompt Findings" section of the report. Multiple `--prompt` flags in one invocation are concatenated into a single custom-prompt criterion. Empty prompt text is an error.

### `--profile <name>[,<name>...]` or `--profile all`

Restricts evaluation to a subset of bundled profiles. Comma-separated list; whitespace around commas is ignored.

- Default (flag omitted): evaluate all bundled profiles under `core/commands/trc.review/profiles/`.
- `all`: synonym for the default; included for explicitness.
- Any name that does not correspond to an existing profile file is an error that lists available profile names.
- The flag does not affect constitution, custom prompt, or remote-source evaluation — those run based on their own presence/config.

### `--post`

After writing the local report, post a condensed version (critical and warning findings only, info excluded) as a top-level PR comment via `gh pr comment`. The command MUST prompt the user for confirmation before posting:

```
Post review findings to PR #42 as a comment? (y/N)
```

If the user answers anything other than `y` or `yes` (case-insensitive), posting is skipped and the command completes successfully with the local report only. Confirmation is always interactive — there is no `--yes` auto-confirm flag in this ticket.

### `--source <name>`

Restricts evaluation to a single configured remote source (by `name` as declared in `tricycle.config.yml` → `review.sources[]`). When this flag is used, bundled profiles are skipped entirely. The constitution and custom prompt still run. An unknown source name is an error that lists available source names.

## Flag combinations

All flags may be combined freely. Examples:

- `/trc.review 42` — full default review
- `/trc.review 42 --profile security` — security profile only
- `/trc.review 42 --prompt "flag hardcoded timeouts"` — default profiles plus a custom criterion
- `/trc.review 42 --source company-style` — remote source only, no bundled profiles
- `/trc.review 42 --profile security,complexity --post` — two profiles plus PR comment posting

## Exit behavior

- **Success**: report file written; report path printed; summary counts printed; returns `0`.
- **Parse error**: error message printed to stderr; no files written; returns `2`.
- **Runtime error** (e.g. `gh` missing, PR not found, all sources failed): error message printed to stderr; no partial report written; returns `1`.
- **Empty diff**: a minimal report is still written noting "No reviewable changes"; returns `0`.

## Error message canonical forms

- `Error: /trc.review requires the GitHub CLI (gh). Install it from https://cli.github.com/ and run gh auth login.`
- `Error: PR #<N> not found or not accessible.`
- `Error: Unknown profile "<name>". Available profiles: <list>.`
- `Error: Unknown source "<name>". Configured sources: <list>.`
- `Error: --prompt requires a non-empty argument.`

## Non-goals

- No inline per-line GitHub review comments (only top-level PR comments when `--post`).
- No `--fix` flag (the command is read-only on source).
- No `--yes` auto-confirm for `--post`.
- No `--format json` output for the first version (markdown report is the sole output format).
