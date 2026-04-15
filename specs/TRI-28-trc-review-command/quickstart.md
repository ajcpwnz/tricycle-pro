# Quickstart — /trc.review

**Feature**: TRI-28 /trc.review — PR Code Review Command

A three-minute walkthrough for trying the command after it ships.

## Prerequisites

- `gh` installed and authenticated (`gh auth status` returns a logged-in account).
- A tricycle-pro project with this feature installed (either via `tricycle assemble` or manual copy of `core/commands/trc.review.md` and the `trc.review/profiles/` directory into `.claude/commands/`).
- An open (or merged) PR in the repo to review.

## 1. Run a default review

Pick any PR number in your repo. From inside Claude Code, type:

```
/trc.review 42
```

Expected output:

```
Reviewing PR #42 — "<title>" by <author>
Sources: constitution (fallback), quality, style, security, complexity
Fetching PR metadata...
Fetching diff... (240 lines touched)
Evaluating...
Report written to docs/reviews/review-2026-04-16-PR42.md
Summary: 1 critical, 3 warnings, 5 info, 2 passed
```

Open the report and verify it has:

- A header block with the PR title, author, branches, and change counts.
- A "Sources Used" list naming each profile and the constitution.
- One section per profile (zero-findings sections render `_No findings._`).
- A summary table with a row per source and a total row.

## 2. Focus on one category

For a faster, targeted review:

```
/trc.review 42 --profile security
```

Verify the report contains only the Security Findings section (plus the header and summary table with a single row).

## 3. Add an ad-hoc criterion

```
/trc.review 42 --prompt "flag any new magic numbers that should be named constants"
```

Verify the report includes a "Custom Prompt Findings" section evaluated against the diff lines only. The section exists even if zero findings are produced.

## 4. Add a remote source

Edit `tricycle.config.yml` to add:

```yaml
review:
  sources:
    - name: company-style
      url: https://raw.githubusercontent.com/your-org/your-style-guide/main/README.md
```

Run the command twice:

```
/trc.review 42      # first run — fetches and caches
/trc.review 42      # second run — uses cache
```

Verify:

- The first run writes `.trc/cache/review-sources/<sha256>.md`.
- The second run is noticeably faster.
- Both reports include a "Remote Source: company-style" findings section and list the source under "Sources Used".
- Deleting the cache file (`rm .trc/cache/review-sources/*.md`) causes the next run to refetch.

## 5. Scope to only that remote source

```
/trc.review 42 --source company-style
```

Verify the report omits all bundled profile sections and contains only the constitution + custom prompt (if any) + the remote source.

## 6. Post to the PR

**Use a throwaway PR for this step — the comment is visible to the team.**

```
/trc.review 42 --post
```

Expected interaction:

```
Post review findings to PR #42 as a comment? (y/N)
```

Answer `y` and verify a new top-level PR comment appears containing only critical and warning findings, the header block, and a footer line pointing at the local report.

Answer `n` and verify the local report is still written but no PR comment is created.

## 7. Wire up a downstream skill (optional)

If your project uses `linear-audit`, add to `tricycle.config.yml`:

```yaml
workflow:
  blocks:
    review:
      skills:
        - linear-audit
```

Run the command on a PR that will produce at least one warning-or-higher finding. Verify `linear-audit` is invoked after the report is written and creates a Linear ticket for each eligible finding.

## Troubleshooting

- **`Error: /trc.review requires the GitHub CLI (gh).`** — Install `gh` and run `gh auth login`.
- **`Error: PR #42 not found or not accessible.`** — Check that the PR exists in the current repo's remote and that your `gh` token has access.
- **`Error: Unknown profile "<name>".`** — Misspelled profile or a bundled profile file was removed. Run `ls core/commands/trc.review/profiles/` to see the available names.
- **Warning: `Remote source "<name>" fetch failed and no cache entry.`** — Network issue; the command continues with the other sources. Check the URL and your network.
- **Report has no findings at all** — Try `--prompt "be strict about edge cases"` or expand the constitution. A clean PR legitimately produces empty sections; zero findings is not an error.

## Uninstall / rollback

The feature is purely additive. To remove it:

1. Delete `core/commands/trc.review.md` and `core/commands/trc.review/`.
2. Delete the `review:` block and `workflow.blocks.review` entry from `tricycle.config.yml` if present.
3. Optionally delete `docs/reviews/` and `.trc/cache/review-sources/`.

No data migrations, no config migrations, no shared-state cleanup required.
