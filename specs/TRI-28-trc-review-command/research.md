# Phase 0 Research — /trc.review

**Feature**: TRI-28 /trc.review — PR Code Review Command
**Date**: 2026-04-16

The spec has no `[NEEDS CLARIFICATION]` markers. This research document validates the two external inputs the design depends on and records concrete decisions so the implementation phase does not have to revisit them.

---

## Decision 1: Source repositories for bundled review profiles

**Decision**: Adapt content from **`baz-scm/awesome-reviewers`** (Apache 2.0) for the `style`, `security`, and `complexity` profiles, and from **`google/eng-practices`** (CC-BY 3.0) for the `quality` profile. Do **not** use `qodo-ai/pr-agent`.

**Rationale**:

- The spec's Assumptions section explicitly excludes copyleft sources. `qodo-ai/pr-agent` is licensed **AGPL-3.0**, which is strong copyleft and would force downstream users of tricycle-pro to adopt AGPL obligations. It is therefore excluded despite being technically the best match for prompt content.
- `baz-scm/awesome-reviewers` is **Apache 2.0**, a permissive license compatible with adaptation into this repo provided attribution is preserved. The repository contains ~8,000 review prompts organized under `_reviewers/` with YAML frontmatter (`title`, `description`, `repository`, `label`, `language`). The `label` field is how prompts are grouped (`Security`, `Error Handling`, `Code Style`, `Complexity`, etc.), which maps cleanly onto the four bundled profiles.
- `google/eng-practices` is **CC-BY 3.0**, a permissive Creative Commons license. Its `review/reviewer/looking-for.md` and sibling docs provide a well-regarded, concise set of code review heuristics that suit the `quality` profile. CC-BY requires attribution, which will live in the profile file's frontmatter.

**Attribution format** (shared by all four profiles):

```yaml
---
name: <profile name>
source:
  - name: <upstream repo or doc>
    url: <canonical URL>
    license: <SPDX identifier>
    attribution: <one-line credit>
---
```

**Alternatives considered**:

- **Write all four profiles from scratch** — rejected because the spec explicitly asks for "configs from internet" and the user wants curated content, not invented content. Permissive open-source sources exist and are the right input.
- **Pull from `qodo-ai/pr-agent` under AGPL** — rejected for the licensing reason above.
- **Pull from OWASP cheat sheets for the security profile** — deferred. The OWASP Cheat Sheet Series is licensed CC-BY-SA 4.0 (share-alike). Share-alike is weaker than AGPL but still imposes license viral-ity on any derivative work. Using *category names* (e.g. "Injection", "Broken Access Control") is fine because those are domain terminology, but adapting verbatim prose would require adopting CC-BY-SA for the profile file. Decision: use awesome-reviewers' `Security`-tagged entries as the primary source and paraphrase category names from OWASP Top 10 as mere section headers (which are not protected expression).

---

## Decision 2: Concrete upstream files to adapt

**Decision**: Draw from the following upstream entries, cited here so the implementation phase knows exactly which URLs to reference and attribute.

| Profile | Upstream file(s) | License |
|---|---|---|
| `quality.md` | `google/eng-practices/master/review/reviewer/looking-for.md` (primary), supplemented by awesome-reviewers entries labeled `Error Handling` and `Testing` | CC-BY 3.0, Apache 2.0 |
| `style.md` | awesome-reviewers entries labeled `Code Style`, `Naming`, `Documentation`, `Consistency` (curated short list, not wholesale copy) | Apache 2.0 |
| `security.md` | awesome-reviewers entries labeled `Security` (SQL injection, command injection, authz, secret handling, path traversal) | Apache 2.0 |
| `complexity.md` | awesome-reviewers entries labeled `Complexity`, `Maintainability`, `Refactoring` | Apache 2.0 |

The exact `_reviewers/*.md` file list will be finalized by `/trc.tasks` during task expansion, since it depends on browsing the ~8k file set for the best-fit short list per profile. Each selected entry contributes at most a couple of sentences (not wholesale copy), and all selections will be cited in the profile frontmatter's `source` array.

**Rationale**: This level of detail is enough for the implementer to proceed without re-doing license research, without committing to specific line counts up front.

**Alternatives considered**: Auto-generating profiles from a runtime query to `awesomereviewers.com` — rejected because bundled profiles should be reviewable in git (so users can see what rules are being applied) and work offline. Runtime generation is what `review.sources[]` is for.

---

## Decision 3: GitHub CLI integration — exact commands and JSON shapes

**Decision**: Use the following `gh` invocations. No wrapper library needed.

- **Fetch PR metadata**:
  ```bash
  gh pr view <N> --json number,title,author,headRefName,baseRefName,state,additions,deletions,url,body
  ```
  Returns a JSON object; parse with `jq` (already available in the dev environment alongside `gh`).

- **Fetch PR diff**:
  ```bash
  gh pr diff <N>
  ```
  Returns raw unified diff on stdout. Stash to a temp file under `$(mktemp -d)` for the duration of the run.

- **Post a comment** (only when `--post` and user confirms):
  ```bash
  gh pr comment <N> --body-file <tmp-comment-file>
  ```

**Rationale**: These commands already appear in `core/blocks/implement/push-deploy.md` (step 43-52 — `gh pr create`, `gh pr merge`). The tricycle-pro codebase treats `gh` as a documented runtime dependency, so `/trc.review` can assume its availability and fail fast with a clear error when it is missing (FR-002).

**Fallback**: If `gh` is not on `$PATH`, the command emits:

```
Error: /trc.review requires the GitHub CLI (`gh`). Install it from https://cli.github.com/ and run `gh auth login`.
```

and exits before any other side effects.

**Alternatives considered**:

- **Use the GitHub REST API directly with `curl`** — rejected. Would require handling token storage, pagination, and auth refresh; `gh` already solves all of these and is the conventional tool in this repo.
- **Use an MCP GitHub server** — rejected for now. No MCP GitHub server is configured in `.mcp.json`, and adding one would expand the dependency footprint beyond what this feature needs.

---

## Decision 4: Remote source cache key and invalidation

**Decision**: Cache key is `sha256(url)` (hex-encoded), file extension `.md`. Cache lives at `.trc/cache/review-sources/<sha256>.md`. No TTL — a cache hit is always used. To refresh, the user deletes the cached file (or the whole cache directory).

**Rationale**:

- Keeps the cache logic trivially simple: one file per URL, no metadata, no expiry computation.
- Puts refresh control in the user's hands (delete-to-refresh), matching the spec's philosophy of explicit user control.
- Avoids clock skew and "why did it silently refetch" surprises.
- `sha256` is already used elsewhere in `bin/lib/helpers.sh` for content hashing — no new dependency.

**Alternatives considered**:

- **Time-based TTL (e.g. 24 hours)** — rejected for the first version. Adds complexity (storing fetch timestamps), and most rule documents change rarely. Users who want freshness can delete the cache.
- **ETag / Last-Modified conditional requests** — rejected. `WebFetch` does not expose HTTP headers in a useful form, and this would add complexity for marginal benefit.
- **Cache in-memory only** — rejected. Contradicts the spec's ≥ 30% speedup on repeat runs (SC-003) because each invocation is a new agent session.

---

## Summary

All unknowns resolved. No remaining `NEEDS CLARIFICATION`. The implementation phase can proceed from these decisions without re-doing source vetting, licensing research, or GitHub integration design.
