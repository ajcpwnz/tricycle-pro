# Feature Specification: Auto Worktree Cleanup

**Feature Branch**: `TRI-22-auto-worktree-cleanup`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Worktree cleanup needs to happen automatically. Modify shipped files so that after a confirmed PR merge, the worktree is removed, stale references are pruned, and the feature branch is deleted — no manual commands required."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Cleanup After Merge (Priority: P1)

A user completes the implement workflow in a worktree. The PR is created, approved, and merged. After the merge is confirmed, the system automatically removes the worktree directory, prunes stale worktree references, and deletes the local feature branch. The user is returned to the main checkout with a clean state — no manual cleanup commands needed.

**Why this priority**: This is the entire feature. The current block only prints a reminder, forcing users to manually run 3 commands every time.

**Independent Test**: Complete a workflow in a worktree, merge the PR, and verify the worktree directory is gone, the branch is deleted, and the user's working directory is the main checkout.

**Acceptance Scenarios**:

1. **Given** the user is in a worktree and the PR has been merged, **When** the cleanup block executes, **Then** the worktree directory is removed, stale references are pruned, and the local feature branch is deleted.
2. **Given** the user is in a worktree and the PR has been merged, **When** cleanup completes, **Then** the user's working context is switched back to the main checkout.
3. **Given** the user is in the main checkout (not a worktree), **When** the cleanup block runs, **Then** it skips silently — no action taken.

---

### User Story 2 - Graceful Failure on Cleanup Errors (Priority: P2)

If worktree removal fails (e.g., open files, permission issues, branch checked out elsewhere), the system reports the error clearly and falls back to the manual-reminder behavior. It does not crash or leave the workflow in a broken state.

**Why this priority**: Cleanup failures shouldn't block the user or cause data loss.

**Independent Test**: Simulate a locked worktree (e.g., a process holding a file lock) and verify the block reports the error and prints manual cleanup instructions as a fallback.

**Acceptance Scenarios**:

1. **Given** worktree removal fails, **When** the cleanup block catches the error, **Then** it prints the manual cleanup commands as a fallback and continues without crashing.
2. **Given** branch deletion fails (e.g., branch has unmerged commits on another worktree), **When** the cleanup block catches the error, **Then** it reports the issue and skips branch deletion without affecting the worktree removal that already succeeded.

---

### Edge Cases

- What happens if the user has uncommitted changes in the worktree at cleanup time? The cleanup should only run after a confirmed merge, at which point all work should be committed and pushed. If uncommitted changes exist, warn and skip cleanup.
- What happens if the worktree directory was already manually removed? `git worktree prune` handles this gracefully — no error.
- What happens if the main checkout has the feature branch checked out? `git branch -d` would fail. The block should switch to the base branch first.
- What happens on a non-worktree run (`.git` is a directory)? Skip silently — this block only applies to worktree contexts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: After a confirmed PR merge, the system MUST automatically remove the worktree directory.
- **FR-002**: After worktree removal, the system MUST prune stale worktree references.
- **FR-003**: After pruning, the system MUST delete the local feature branch.
- **FR-004**: After cleanup, the system MUST return the user's working context to the main checkout directory.
- **FR-005**: If the current context is not a worktree, the system MUST skip cleanup silently.
- **FR-006**: If any cleanup step fails, the system MUST report the error and fall back to printing manual cleanup instructions.
- **FR-007**: The system MUST NOT attempt cleanup if the PR has not been confirmed as merged.
- **FR-008**: The system MUST NOT attempt cleanup if there are uncommitted changes in the worktree.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a merged PR, zero manual commands are required for worktree cleanup when the block is enabled.
- **SC-002**: Cleanup completes within 5 seconds of merge confirmation.
- **SC-003**: Failed cleanup attempts still provide actionable manual instructions — users are never left without a path forward.
- **SC-004**: No data loss — uncommitted changes are never silently discarded.

## Assumptions

- The worktree-cleanup block is an optional implement block, enabled via `workflow.blocks.implement.enable: [worktree-cleanup]` in `tricycle.config.yml`.
- The push-deploy block (which handles PR creation and merge) runs before the worktree-cleanup block (order 70 ensures this).
- The PR merge status is determinable from the push-deploy block's output or by querying `gh pr view`.
- The main checkout path can be derived from `git worktree list` or from the worktree's `.git` file.
