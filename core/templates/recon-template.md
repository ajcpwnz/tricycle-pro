# Epic Recon: [PARENT TITLE]

**Parent Issue**: `[PREFIX-NNN]`
**Run**: `[run-id]`
**Created**: [DATE]
**Integration Branch**: `band/[PREFIX-NNN]`
**Status**: Draft — awaiting user approval

## Epic Overview *(mandatory)*

<!--
  The high-level spec for the whole epic: what the parent issue is trying to
  achieve, distilled from the parent body + the project description. Workers
  read this section to understand the epic context their sub-issue serves.
-->

**Goal**: [What the epic delivers when every sub-issue ships]

**Scope**: [What is in scope across all sub-issues]

**Non-Goals**: [What this epic explicitly does not cover]

## Sub-Issues *(mandatory)*

<!-- One row per sub-issue fetched from the parent. Complexity drives model
     assignment; wave assignment comes from the Dependency Roadmap below. -->

| ID | Title | One-line scope | Complexity | Model | Wave |
|----|-------|----------------|------------|-------|------|
| [PREFIX-NNN] | [title] | [scope] | low/medium/high | [worker model] | [N] |

## Codebase Recon *(mandatory)*

<!-- Targeted findings, not a full audit: which areas each sub-issue touches,
     which patterns already exist and must be followed, what the constitution
     constrains. -->

### Affected Areas

- **[PREFIX-NNN]**: [modules/files this sub-issue will touch]

### Shared-Surface Matrix

<!-- Sub-issues touching the same module must NOT share a wave. This matrix
     justifies the wave split. -->

| | [ID-1] | [ID-2] |
|---|---|---|
| **[area/module]** | x | |

### Existing Patterns to Follow

- [pattern, with file path]

### Constitution Constraints

- [constraint relevant to this epic, or "None"]

## Dependency Roadmap *(mandatory)*

### Dependency Graph

<!-- One line per edge, with the reason. Sources: Linear blocks/blocked-by
     relations, issue bodies, file-overlap analysis. -->

- `[PREFIX-AAA]` -> `[PREFIX-BBB]` — [why BBB needs AAA first]

### Waves

<!-- Issues inside one wave run in parallel (bounded by band.max_parallel).
     A wave starts only when every earlier wave has fully drained. -->

- **Wave 1**: [IDs] — parallel-safe because [no shared surface / no deps]
- **Wave 2**: [IDs] — requires [what wave 1 delivers]

### Complexity & Model Assignment

<!-- Rate each sub-issue low/medium/high (scope of files, novelty,
     cross-cutting risk, test surface) and assign the worker model from the
     trc.band model matrix. -->

- **[PREFIX-NNN]**: [low/medium/high] — [one-line justification] → [model]

## Verification Strategy *(mandatory)*

<!-- Per the trc.band batching heuristics: full suite per sub-issue when high
     complexity, sole wave member, or shared-infrastructure touching;
     otherwise scoped checks per issue + full suite per wave in the
     integration worktree. Name the decision per issue. -->

- **[PREFIX-NNN]**: [per-issue full suite | scoped checks, verified with wave N batch]
- **Wave [N] batch verification**: [what runs after the wave merges]
- **Final verification**: full lint + test suite in the integration worktree before the push gate

## Integration Plan *(mandatory)*

- **Merge order**: [IDs in roadmap order]
- **Expected conflict hotspots**: [files/modules, or "None expected"]
- **Rebase policy**: on conflict the affected worker rebases onto `band/[PREFIX-NNN]` and re-verifies; capped at 2 rounds per sub-issue, then the band pauses for the user

## Risks & Open Questions

<!-- [NEEDS CLARIFICATION: ...] markers here pause the band at the recon
     approval gate until the user answers. -->

- [risk or open question, or "None"]

## Epic Checklist *(mandatory)*

<!-- Ticked by the ORCHESTRATOR ONLY as the run progresses. Workers never
     edit this file. -->

- [ ] Recon approved by user
- [ ] [PREFIX-NNN] — committed and merged into integration branch
- [ ] Wave [N] batch verification passed
- [ ] Final full-suite verification passed in integration worktree
- [ ] User approved the epic push
- [ ] Integration branch pushed, PR opened
