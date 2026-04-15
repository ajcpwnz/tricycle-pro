# Contract: Review report markdown schema

**Feature**: TRI-28 /trc.review — PR Code Review Command

The review report is the sole persistent artifact the command produces. It is plain markdown written to `{review.report_dir}/review-YYYY-MM-DD-PR<N>.md`. Filename collisions get a numeric suffix (`-1`, `-2`, ...) so reports are never overwritten.

## Full report structure

```markdown
# Review Report — PR #<N>

**Date**: 2026-04-16
**PR**: [#<N> — <title>](<url>)
**Author**: <author>
**Branch**: <head_ref> → <base_ref>
**State**: <OPEN|CLOSED|MERGED>
**Changes**: +<additions> −<deletions>
**Summary**: X critical, Y warning, Z info, W passed

## Sources Used

- **Constitution** — `.trc/memory/constitution.md` (populated | fallback: common sense)
- **Profile: quality** — adapted from: google/eng-practices (CC-BY 3.0); baz-scm/awesome-reviewers (Apache 2.0)
- **Profile: style** — adapted from: baz-scm/awesome-reviewers (Apache 2.0)
- **Profile: security** — adapted from: baz-scm/awesome-reviewers (Apache 2.0)
- **Profile: complexity** — adapted from: baz-scm/awesome-reviewers (Apache 2.0)
- **Custom Prompt** — "<verbatim prompt text>"
- **Remote Source: company-style** — https://example.com/style-guide.md (CACHED | FETCHED)

## Sources Skipped

- **Remote Source: old-wiki** — network fetch failed and no cache entry

## Constitution Findings

### CRITICAL: <rule name>
- **File**: `path/to/file.ext:42`
- **Evidence**: `<quoted diff line>`
- **Recommendation**: <concrete advice>

## Quality Findings

_No findings._

## Style Findings

### WARNING: Inconsistent naming
- **File**: `src/foo.ts:17`
- **Evidence**: `const user_name = ...`
- **Recommendation**: Use camelCase to match the rest of the file (`userName`).

## Security Findings

### CRITICAL: Possible SQL injection
- **File**: `src/db.ts:83`
- **Evidence**: `db.query("SELECT * FROM users WHERE id = " + req.params.id)`
- **Recommendation**: Use a parameterized query: `db.query("SELECT * FROM users WHERE id = ?", [req.params.id])`.

## Complexity Findings

### INFO: Function is long (68 lines)
- **File**: `src/handler.ts:120`
- **Evidence**: function `processOrder` spans lines 120–188
- **Recommendation**: Consider extracting the tax and shipping calculation blocks into helpers.

## Custom Prompt Findings

### WARNING: Hardcoded timeout
- **File**: `src/client.ts:9`
- **Evidence**: `setTimeout(fn, 5000)`
- **Recommendation**: Move `5000` to a named constant so it can be tuned per environment.

## Remote Source: company-style Findings

### INFO: Missing JSDoc
- **File**: `src/util.ts:3`
- **Evidence**: `export function slugify(input: string): string`
- **Recommendation**: Per the company style guide, public exports require a JSDoc summary.

## Skipped Files

- `assets/logo.png` (binary)
- `fonts/inter.woff2` (binary)

## Summary

| Source          | Critical | Warning | Info | Passed |
|-----------------|----------|---------|------|--------|
| Constitution    | 1        | 0       | 0    | 0      |
| Quality         | 0        | 0       | 0    | 1      |
| Style           | 0        | 1       | 0    | 0      |
| Security        | 1        | 0       | 0    | 0      |
| Complexity      | 0        | 0       | 1    | 0      |
| Custom Prompt   | 0        | 1       | 0    | 0      |
| company-style   | 0        | 0       | 1    | 0      |
| **Total**       | **2**    | **2**   | **2**| **1**  |
```

## Rendering rules

1. **Section presence**: every enabled source gets a section header even when it has zero findings. A zero-findings section renders `_No findings._` as its only body line. This guarantees the user can see *what was evaluated*, not just *what failed*.
2. **Severity ordering within a section**: `CRITICAL` → `WARNING` → `INFO`. Ties are resolved by file path, then line number.
3. **Evidence formatting**: single-line evidence uses inline code; multi-line evidence uses a fenced code block with the file's language hint if easily derivable from the extension.
4. **File references**: always `path/to/file.ext:line` (colon-separated, relative to repo root) so IDEs and terminals can jump to them.
5. **Header block**: the seven lines from `# Review Report` through `**Summary**` are always present in that order.
6. **Empty-diff variant**: when the PR has zero reviewable lines (e.g. binary-only or revert), replace all findings sections and the summary table with a single block:

   ```markdown
   ## No reviewable changes

   This PR contains no text diff to review. See the Skipped Files section for any binaries that were omitted.
   ```

7. **Append-only semantics**: if the target path already exists, append a numeric suffix (`-1`, `-2`) to the filename stem. The command MUST NOT overwrite an existing report.

## Condensed variant (for `--post`)

When `--post` is used and confirmed, a separate condensed markdown body is rendered for the PR comment. Rules:

- Keep the header block.
- Include only `critical` and `warning` findings; drop `info` and "passed" sources entirely.
- Omit the "Skipped Files" section.
- Include the summary table but with an `Info` column always zero.
- Append a footer line: `_Generated by `/trc.review` — full report at `<report_path>`._`

The condensed body is written to a temp file and passed to `gh pr comment --body-file <tmp>`. The temp file is deleted after the command runs regardless of posting success.

## Filename convention

- Primary: `review-YYYY-MM-DD-PR<N>.md` (ISO date, zero-padded PR number not required).
- On collision: `review-YYYY-MM-DD-PR<N>-1.md`, `-2.md`, ...

Example: `docs/reviews/review-2026-04-16-PR42.md`.
