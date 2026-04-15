# Contract: tricycle.config.yml `review:` block

**Feature**: TRI-28 /trc.review — PR Code Review Command

## Schema (YAML)

```yaml
review:
  profiles:                # Which bundled profiles to evaluate by default.
    - quality              # Valid names are filenames (without .md) under
    - style                # core/commands/trc.review/profiles/.
    - security
    - complexity

  sources:                 # User-configured remote rule sources.
    - name: company-style  # Human-readable label; unique within the list.
      url: https://example.com/style-guide.md   # Must be https://.

  report_dir: docs/reviews # Where review reports are written. Relative path.

  post_to_pr: false        # Reserved for a future default. In this ticket
                           # the --post flag must always be passed explicitly
                           # and the confirmation prompt is always interactive;
                           # this field is accepted and stored for forward
                           # compatibility but has no runtime effect yet.

workflow:
  blocks:
    review:                # Output-skill hand-off, mirrors other blocks.
      skills:
        - linear-audit     # Example: auto-create Linear tickets from findings.
```

## Field reference

| Path | Type | Default | Required | Notes |
|---|---|---|---|---|
| `review` | map | `{}` | no | The whole block may be omitted; defaults below apply |
| `review.profiles` | array of string | `[quality, style, security, complexity]` | no | Must reference existing profile files |
| `review.sources` | array of map | `[]` | no | May be omitted; empty means bundled profiles only |
| `review.sources[].name` | string | — | yes (per entry) | Unique within `sources` |
| `review.sources[].url` | string (URL) | — | yes (per entry) | Must start with `https://` |
| `review.report_dir` | string (relative path) | `docs/reviews` | no | No absolute paths, no `..` |
| `review.post_to_pr` | bool | `false` | no | Reserved; not read in this ticket |
| `workflow.blocks.review.skills` | array of string | `[]` | no | Skill names; each must resolve to `.claude/skills/<name>/SKILL.md` at runtime to be invoked |

## Validation rules (enforced at command run, not at config load)

1. **Unknown profile name**: if `review.profiles` contains a name with no corresponding file, abort with `Error: Unknown profile "<name>". Available profiles: <list>.`
2. **Duplicate source name**: if two entries in `review.sources` share a `name`, abort with `Error: duplicate review source name "<name>".`
3. **Non-HTTPS URL**: if any `review.sources[].url` does not start with `https://`, abort with `Error: review source "<name>" must use https:// (got <url>).`
4. **Report dir escape**: if `review.report_dir` contains `..` or is absolute, abort with `Error: review.report_dir must be a relative path inside the repo (got <value>).`
5. **Missing bundled profile directory**: if `core/commands/trc.review/profiles/` does not exist, abort with `Error: bundled profiles directory not found. The /trc.review install is incomplete.`

All validations happen before any file writes or network calls, so a misconfigured config never produces a partial report.

## Cache implementation note

The cache key is the 16-char hex prefix of `sha256(url)`, produced by `sha256_str` in `bin/lib/helpers.sh` (the existing convention across the codebase). 2^64 collision space is ample for a per-user cache. The cache path is `.trc/cache/review-sources/<hash>.md` and is gitignored via the project-wide `.trc/` ignore.

## Migration

None. The block is additive and has no effect on existing commands. Projects that upgrade tricycle-pro but do not edit their config will automatically get the default behavior (all four bundled profiles, no remote sources, report in `docs/reviews/`).
