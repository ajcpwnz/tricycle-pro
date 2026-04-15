# Feature Specification: /trc.review — PR Code Review Command

**Feature Branch**: `TRI-28-trc-review-command`
**Created**: 2026-04-16
**Status**: Draft
**Input**: User description: "add /trc.review command that takes a PR number and does a code review against user-set criteria plus configurable review profiles (quality, style, security, complexity) curated from open-source prompt libraries on the internet"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review an open PR against the full default ruleset (Priority: P1)

A tricycle-pro user has an open pull request in their repository and wants a structured code review before asking a human teammate to look at it. They run `/trc.review 42` and get back a markdown report that evaluates the PR's diff against four bundled profiles (quality, style, security, complexity) plus the project constitution. The report lists findings grouped by severity with file:line references and actionable recommendations.

**Why this priority**: This is the core value loop — if this single path works end-to-end, the command delivers immediate value even with zero configuration. Every other story builds on top of it.

**Independent Test**: Pick any open PR in the repo, run `/trc.review <N>`, and verify a report is written to `docs/reviews/review-YYYY-MM-DD-PR<N>.md` with non-empty findings sections for each profile. No flags, no config changes required.

**Acceptance Scenarios**:

1. **Given** an open PR numbered 26 in the current repo, **When** the user runs `/trc.review 26`, **Then** a markdown report is created at `docs/reviews/review-<date>-PR26.md` containing a PR header (title, author, branch, additions/deletions), a "Sources Used" section, severity-tagged findings from each bundled profile, and a summary table.
2. **Given** the PR reference is given as `#26` or a full GitHub URL instead of a bare number, **When** the command runs, **Then** it normalizes the input and produces the same report as the bare-number form.
3. **Given** the `gh` CLI is not installed or the PR is not visible to the user, **When** the command runs, **Then** it fails fast with a clear error message and writes no partial report.
4. **Given** the PR has zero findings in a profile, **When** the report is generated, **Then** that profile's section still appears in the report marked as "No findings" so the user knows it was evaluated.

---

### User Story 2 - Review against a custom ad-hoc prompt (Priority: P1)

A user wants to check a specific concern that isn't covered by the default profiles — for example, "flag any new bash commands missing `set -euo pipefail`" or "verify all new database queries use parameterized statements". They pass the criteria via `--prompt "<text>"` and the report includes a dedicated "Custom Prompt Findings" section evaluating only the PR's diff lines against that criterion.

**Why this priority**: Custom prompts are the escape hatch that makes the command useful for project-specific concerns without needing to edit bundled profiles. This is the same UX as `/trc.audit --prompt` so users already know the pattern.

**Independent Test**: Run `/trc.review <N> --prompt "<specific criterion>"` on a PR that contains diff lines matching the criterion, and verify the Custom Prompt Findings section of the report contains at least one finding citing a file:line from the diff.

**Acceptance Scenarios**:

1. **Given** a user runs `/trc.review 26 --prompt "flag hardcoded timeouts"` on a PR that introduces a hardcoded timeout, **When** the command completes, **Then** the report contains a Custom Prompt Findings section with at least one finding pointing to the offending diff line.
2. **Given** a `--prompt` is provided alongside the default profiles, **When** the report is generated, **Then** both the profile findings and the custom-prompt findings appear as separate sections and the summary table has a row for the custom prompt.

---

### User Story 3 - Restrict review to a subset of profiles (Priority: P2)

A user wants a faster, more focused review — for example, only the security and complexity profiles for a quick sanity check on a refactor. They pass `--profile security,complexity` and the report only evaluates those two profiles and omits the others entirely.

**Why this priority**: Valuable for speed and focus but not required for the first working version. The default (all profiles) is good enough to ship.

**Independent Test**: Run `/trc.review <N> --profile security,complexity` and verify the report contains only those two profile sections and the summary table has exactly two rows.

**Acceptance Scenarios**:

1. **Given** a user runs `/trc.review 26 --profile security`, **When** the report is generated, **Then** only the Security Findings section is present and the quality, style, and complexity sections are absent.
2. **Given** a user passes an unknown profile name (e.g. `--profile typescript`), **When** the command runs, **Then** it fails with an error listing the available profile names.

---

### User Story 4 - Add a custom remote rule source (Priority: P2)

A team has a shared style guide published on an internal wiki or a public markdown file. They add the URL to `tricycle.config.yml` under `review.sources[]` and the command fetches the rules at runtime, caches them locally, and includes findings against those rules in the report. Subsequent runs use the cache for speed; the cache can be bypassed by deleting the cached file.

**Why this priority**: This is the "configurable" half of the feature. Bundled profiles cover most needs; remote sources let teams extend without editing the command itself.

**Independent Test**: Add a small public markdown file URL to `review.sources` in the config, run `/trc.review <N>` twice, and verify: (a) the first run fetches the file over the network and writes it to `.trc/cache/review-sources/`, (b) the second run is noticeably faster because it uses the cached copy, (c) the report includes a section labelled with the source name and lists it under Sources Used.

**Acceptance Scenarios**:

1. **Given** a remote source is configured in `tricycle.config.yml`, **When** the command runs for the first time, **Then** the source is fetched, cached under `.trc/cache/review-sources/<hash>.md`, and its findings appear in the report.
2. **Given** the cache already contains the source, **When** the command runs again, **Then** the fetch is skipped and the cached copy is used.
3. **Given** the network is unreachable and a remote source is configured, **When** the command runs, **Then** it emits a warning, continues with constitution + bundled profiles + custom prompt, and still produces a complete report.
4. **Given** the user passes `--source <name>` that matches a configured source name, **When** the command runs, **Then** only that source is evaluated and bundled profiles are skipped.

---

### User Story 5 - Post findings as a PR comment (Priority: P3)

After reviewing the local report, the user wants to share a condensed version of the findings with their team. They pass `--post` and the command posts a PR comment containing only the critical and warning findings (dropping the informational ones) via `gh pr comment`. Before posting, the user is asked to confirm because the comment is visible to the whole team.

**Why this priority**: Nice-to-have for team workflows but not required for a solo user. Posting is user-visible and irreversible, so it must be opt-in and confirmation-gated.

**Independent Test**: On a throwaway PR, run `/trc.review <N> --post`, confirm at the prompt, and verify a new PR comment appears containing the condensed findings. Running without `--post` must post nothing.

**Acceptance Scenarios**:

1. **Given** `--post` is passed and the user confirms at the prompt, **When** the command completes, **Then** a new top-level PR comment is created containing only critical and warning findings.
2. **Given** `--post` is passed and the user declines at the prompt, **When** the command completes, **Then** the local report is still written but no PR comment is created.
3. **Given** `--post` is not passed, **When** the command runs, **Then** no confirmation prompt appears and nothing is posted to the PR.

---

### User Story 6 - Hand off the report to configured output skills (Priority: P3)

A team wants review findings to automatically become Linear tickets. They add `linear-audit` to `workflow.blocks.review.skills` in the config, and after the report is generated the command invokes that skill with the report path, which then creates tickets for each warning-or-higher finding. This mirrors how `/trc.audit` already hands off to output skills.

**Why this priority**: Reuses the existing workflow-block pattern from `/trc.audit`, so implementation cost is low, but it's only useful for teams already using those downstream skills.

**Independent Test**: Add `linear-audit` to `workflow.blocks.review.skills`, run the command on a PR that will produce at least one finding, and verify the skill is invoked with the report file path and creates at least one Linear ticket.

**Acceptance Scenarios**:

1. **Given** `workflow.blocks.review.skills` lists installed skills, **When** the report is written, **Then** each listed skill is invoked with the report path as context.
2. **Given** a listed skill is not installed in `.claude/skills/`, **When** the command runs, **Then** the invocation is skipped silently without aborting the command.
3. **Given** no skills are configured, **When** the command runs, **Then** the output-skill step is skipped entirely and the local report is the only output.

---

### Edge Cases

- **Empty diff**: A PR may contain zero added or modified lines (e.g. a merge or a revert). The command reports "No reviewable changes" and writes a minimal report without profile sections.
- **Binary-only diff**: A PR may touch only images or compiled assets. The command skips binary files, reports them in a "Skipped Files" section, and produces a report that notes no text changes were available.
- **Very large diff**: A PR with thousands of changed lines may exceed practical evaluation limits. The command should still produce a report; it may note that the review is best-effort on oversized diffs.
- **Merged or closed PR**: The command should still accept merged or closed PRs (the diff is still fetchable via `gh pr diff`) and note the PR status in the report header.
- **Constitution not populated**: If `.trc/memory/constitution.md` contains only the placeholder text, the command warns and proceeds with profiles + custom prompt, matching `/trc.audit`'s fallback behavior.
- **Network failure mid-run**: A remote source fetch may fail after others succeeded. The command must continue with the sources that did load and clearly label which ones were skipped.
- **Profile file missing or malformed**: If a bundled profile file is missing or fails to parse, the command skips that profile with a warning and continues with the rest.
- **Cache corruption**: If a cached remote source file is empty or unreadable, the command treats it as a cache miss and refetches.
- **Duplicate findings across sources**: The same issue may be flagged by multiple profiles. The report lists each finding under its own source section; deduplication is not required for the first version.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The command MUST accept a pull request reference as a positional argument in any of three forms: bare number (`42`), hash-prefixed number (`#42`), or full GitHub PR URL.
- **FR-002**: The command MUST fail fast with a clear error message if the PR cannot be fetched (network error, permission denied, PR does not exist, or the underlying PR tooling is unavailable).
- **FR-003**: The command MUST operate on the PR's diff lines, not whole files — findings must be scoped to lines touched by the PR.
- **FR-004**: The command MUST evaluate the diff against four bundled review profiles: quality, style, security, complexity. Each profile is a standalone markdown system-prompt file.
- **FR-005**: Users MUST be able to restrict the evaluation to a subset of profiles via `--profile <name>[,<name>...]`. Passing `all` or omitting the flag evaluates all bundled profiles.
- **FR-006**: The command MUST load the project constitution from the configured path and evaluate the diff against its rules when the constitution is populated.
- **FR-007**: When the constitution contains only placeholder text, the command MUST warn the user and proceed with profiles + custom prompt without failing.
- **FR-008**: Users MUST be able to supply ad-hoc review criteria via `--prompt "<text>"`; the criteria are evaluated against the diff and findings appear in a dedicated Custom Prompt section.
- **FR-009**: The command MUST support user-configurable remote rule sources declared in `tricycle.config.yml` under a new `review.sources[]` list, each with a `name` and a `url`.
- **FR-010**: Remote rule sources MUST be cached locally under `.trc/cache/review-sources/` keyed by a hash of the URL; subsequent runs MUST use the cache when present.
- **FR-011**: When a remote rule source cannot be fetched and is not in the cache, the command MUST emit a warning and continue with the sources that did load.
- **FR-012**: Users MUST be able to scope a single run to a single configured remote source via `--source <name>`; when this flag is used, bundled profiles are skipped.
- **FR-013**: The command MUST tag each finding with a severity level: `critical`, `warning`, or `info`.
- **FR-014**: Each finding MUST include: source label, file path and line number, an evidence snippet (the quoted diff lines that triggered it), and a specific recommendation.
- **FR-015**: The command MUST write a markdown report to `docs/reviews/review-YYYY-MM-DD-PR<N>.md` containing: a PR header block (number, title, author, base branch, head branch, additions, deletions, status), a "Sources Used" list, one findings section per source, a "Skipped Files" section for binaries, and a summary table with one row per source and columns for each severity level.
- **FR-016**: The report directory path MUST be configurable via `review.report_dir` in `tricycle.config.yml`, defaulting to `docs/reviews`.
- **FR-017**: The command MUST support a `--post` flag that, after writing the local report, posts a condensed version (critical and warning findings only, no info) as a top-level PR comment.
- **FR-018**: When `--post` is used, the command MUST prompt the user for confirmation before posting the comment and MUST NOT post if the user declines.
- **FR-019**: After the report is written, the command MUST read `workflow.blocks.review.skills` from the config and invoke each listed skill that is installed, passing the report path as context. Skills that are not installed MUST be skipped silently.
- **FR-020**: The command MUST skip binary files in the diff (images, compiled assets, fonts, archives) and list them in a "Skipped Files" section of the report.
- **FR-021**: The command MUST handle empty diffs (no reviewable changes) gracefully by writing a minimal report with an explicit "No reviewable changes" note.
- **FR-022**: All bundled profile content MUST carry attribution in the profile file's frontmatter when adapted from an external source, including source name, URL, and license.
- **FR-023**: The command MUST be runnable without network access when no remote sources are configured and all required bundled profiles are present.
- **FR-024**: Command execution MUST NOT modify any files outside of the configured report directory, the remote-source cache directory, and temporary files; in particular it MUST NOT modify the repository's source tree or commit history.

### Key Entities

- **Pull Request reference**: A normalized pointer to a specific PR on the repository's remote host. Attributes: number, title, author, head branch, base branch, additions count, deletions count, status.
- **Review profile**: A standalone system-prompt file bundled with the command that defines one category of review rules. Attributes: name, source attribution, license, evaluation rules. The four built-in profiles are quality, style, security, complexity.
- **Remote source**: A user-configured URL pointing to an external markdown or text document containing review rules, declared in `tricycle.config.yml`. Attributes: name, URL, cached filepath.
- **Finding**: A single observation about a line in the PR diff. Attributes: source label (profile name, constitution rule, custom prompt, or remote source name), severity, file path, line number, evidence snippet, recommendation.
- **Review report**: The markdown artifact produced by the command. Contains PR header, sources used, findings grouped by source, skipped files, and a summary table. Written to a configurable directory.
- **Config block**: A new `review:` section in `tricycle.config.yml` plus a `workflow.blocks.review` entry for output-skill hand-off. Attributes: default profiles list, remote sources list, report directory, default value for `--post`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can run `/trc.review <pr-number>` against any open PR in their repository and receive a complete markdown report in under 60 seconds for a typical PR (under 500 changed lines), without providing any flags or editing any configuration.
- **SC-002**: At least 90% of findings in the report include a concrete file:line reference and an actionable recommendation (not just a generic warning).
- **SC-003**: A repeat run on the same PR with the same config completes at least 30% faster than the first run when remote sources are configured, demonstrating that caching is effective.
- **SC-004**: When a remote rule source URL becomes unreachable, the command still produces a complete report using all other available sources and clearly labels in the report which sources were skipped.
- **SC-005**: A user can add a new review rule set to the command in under 5 minutes by editing a single bundled profile file or adding one entry to `review.sources` in the config — no code changes required.
- **SC-006**: The command never posts to a PR unless the user explicitly passes `--post` and confirms the posting prompt; zero accidental posts in any usage pattern.
- **SC-007**: All four built-in profiles produce at least one recognizable finding when run against a small synthetic PR that intentionally violates each category (e.g. includes a hardcoded secret, an overly long function, an unclear variable name, and a missing error handler).

## Assumptions

- The user has the GitHub CLI (`gh`) installed and authenticated. The command will rely on `gh pr view` / `gh pr diff` for PR access and `gh pr comment` for optional posting. No alternative Git hosting platforms are supported in this ticket.
- Bundled profile content will be adapted from permissively licensed sources (MIT, Apache 2.0, CC-BY) with attribution preserved; copyleft sources will not be used.
- The command runs in the same shell environment as other `/trc.*` commands and may reuse existing helper libraries from `bin/lib/` and `core/scripts/bash/`.
- Report review is a human-facing activity; the command does not attempt to auto-resolve, auto-fix, or auto-approve findings.
- The command is diff-aware but not semantically aware of the surrounding codebase beyond what the diff exposes; full-repo context is out of scope for this ticket.
- Remote source documents are assumed to fit comfortably in memory (on the order of a few hundred KB at most). Pagination and streaming are out of scope.
- The default report directory is a tracked path (`docs/reviews/`) but the cache directory (`.trc/cache/`) is gitignored.
