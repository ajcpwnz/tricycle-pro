# Implementation Plan: Auto Worktree Cleanup

**Branch**: `TRI-22-auto-worktree-cleanup` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-22-auto-worktree-cleanup/spec.md`
**Version**: 0.11.0 → 0.11.1 (patch bump — improvement to existing block)

## Summary

Replace the reminder-only `worktree-cleanup.md` implement block with one that automatically removes the worktree, prunes stale references, and deletes the feature branch after a confirmed PR merge. Falls back to manual instructions on failure. Single file change.

## Technical Context

**Language/Version**: Markdown (prompt block — instructs the AI agent)
**Primary Dependencies**: git (worktree, branch commands), gh (PR status)
**Testing**: `bash tests/run-tests.sh`, `node --test tests/test-*.js`
**Target Platform**: macOS, Linux
**Project Type**: CLI tool (block is agent prompt text, not executable code)

## Constitution Check

Constitution is a placeholder — no gates. Passes by default.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-22-auto-worktree-cleanup/
├── plan.md
├── spec.md
├── research.md
├── quickstart.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
core/blocks/optional/implement/
└── worktree-cleanup.md    # MODIFY: replace reminder with auto-cleanup instructions
```

**Structure Decision**: Single file change. The block is prompt text that tells the AI agent what to do during `/trc.implement`. No new files, no new scripts.

## Design

### Current Block (reminder only)

```markdown
## Worktree Cleanup Reminder
...
**Do NOT clean up automatically.**
Instead, after the push is approved and PR is created, remind the user:
[manual commands]
```

### New Block (auto cleanup)

The rewritten block will instruct the agent to:

1. **Detect worktree**: Check if `.git` is a file. If not, skip silently.
2. **Check merge status**: Only proceed if the PR has been confirmed merged (by the push-deploy block before it).
3. **Check for uncommitted changes**: Run `git status --porcelain`. If output is non-empty, warn and skip cleanup.
4. **Determine paths**:
   - Worktree path: current working directory (`$PWD`)
   - Branch name: `git rev-parse --abbrev-ref HEAD`
   - Main checkout: parse `.git` file → follow `gitdir:` path → walk up to repo root. Or use `git worktree list` first entry.
5. **Execute cleanup** (in try/catch style — if any step fails, print manual instructions):
   - Change working directory to the main checkout
   - `git worktree remove <worktree-path>`
   - `git worktree prune`
   - `git branch -d <branch-name>`
6. **Report**: Confirm cleanup succeeded, or print fallback commands if it failed.

### Key Constraint

The block is **prompt text** read by the AI agent, not a shell script. The agent interprets the instructions and runs the commands itself. So the block must be written as clear, imperative instructions — not bash code.

### What Does NOT Change

- `push-deploy.md` (order 65) — still handles PR creation, merge, and spec artifact cleanup
- Block frontmatter — name, step, order (70), required (false), default_enabled (false) all stay the same
- No changes to `bin/tricycle`, `assemble-commands.sh`, or any other file

## Testing Strategy

No new test file needed — this is a prompt block change. Validation:
1. Verify block frontmatter is preserved (existing tests check this)
2. Manual validation: run `/trc.implement` in a worktree with auto_merge enabled, confirm cleanup happens
3. Existing `bash tests/run-tests.sh` should still pass (no code changes)

## Complexity Tracking

No constitution violations. Single file change to a prompt block.
