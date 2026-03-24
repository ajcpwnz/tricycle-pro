# Research: Headless Mode

## Decision 1: Command implementation approach

**Decision**: Implement as a single markdown command file
(`core/commands/trc.headless.md`) that instructs Claude to invoke
each phase skill sequentially via the Skill tool.

**Rationale**: All existing trc commands are markdown prompt files
with YAML frontmatter. The command system works by Claude reading
the markdown instructions and executing them. The headless command
is an orchestrator — its markdown body tells Claude to:

1. Invoke `/trc.specify` with the user's prompt
2. When specify completes, invoke `/trc.plan`
3. When plan completes, invoke `/trc.tasks`
4. When tasks completes, invoke `/trc.implement`

This matches the existing handoff mechanism (where `send: true`
causes automatic chaining) but collapses the entire chain into a
single command's instructions rather than relying on per-command
handoffs.

**Alternatives considered**:

- **Node.js orchestrator script**: Would require a new runtime
  execution path separate from Claude Code's slash command system.
  Rejected because it would bypass Claude's judgment and couldn't
  handle the nuanced pause-point logic that requires AI reasoning.

- **Modified handoff flags**: Adding a `headless: true` flag to
  each existing command's frontmatter. Rejected because it spreads
  headless logic across 4+ files and makes the behavior harder to
  understand and maintain.

- **Shell script wrapper**: A bash script that invokes Claude Code
  multiple times. Rejected because each invocation would lose
  conversation context, making pause/resume impossible.

## Decision 2: Pause point implementation

**Decision**: The headless command's markdown instructions define
explicit pause conditions. Claude evaluates each condition using
its judgment and pauses when criteria are met.

**Rationale**: The pause points are:

1. **Critical clarifications**: When the specify phase generates
   `[NEEDS CLARIFICATION]` markers that cannot be safely defaulted.
   The headless command instructs Claude to auto-resolve where
   possible and only pause for genuinely ambiguous scope decisions.

2. **Destructive actions**: Defined as operations that cannot be
   undone — branch resets, file deletions outside the feature
   directory, database migrations. The command instructs Claude to
   check before these operations.

3. **Push approval**: Always pauses. Constitution Principle III is
   non-negotiable and the command explicitly states this.

**Alternatives considered**:

- **Structured pause-point config file**: A YAML file listing
  exact conditions. Rejected because the conditions require
  contextual judgment (e.g., "is this clarification critical?")
  that can't be expressed in static config.

- **No pause points**: Run everything without stopping. Rejected
  because it violates constitution Principle III and could cause
  irreversible damage.

## Decision 3: Progress reporting

**Decision**: Inline status messages between phases, with a
structured completion summary at the end.

**Rationale**: The command instructs Claude to output brief
status lines like:

```
--- Phase 1/4: Specify --- complete (spec.md created)
--- Phase 2/4: Plan --- starting...
```

And a final summary table listing all artifacts and their paths.

This is implemented purely through the command's markdown
instructions — no special tooling needed. Claude naturally outputs
text between tool calls.

**Alternatives considered**:

- **Progress file on disk**: Writing status to a file. Rejected
  because the user is watching the terminal output in real time;
  a file adds complexity without value.

- **No progress output**: Rely on Claude's natural verbosity.
  Rejected because headless runs can take several minutes and
  silence would feel broken.

## Decision 4: Feature branch creation

**Decision**: The headless command delegates branch creation to
the specify phase, which already calls `create-new-feature.sh`.

**Rationale**: The specify phase handles branch creation, spec
directory setup, and feature numbering. The headless command
simply passes the user's prompt through to specify and lets the
existing script handle the rest. No duplication of branch logic.

## Decision 5: Existing hook compatibility

**Decision**: All existing hooks (post-implement-lint,
block-spec-in-main, block-branch-in-main) remain active during
headless execution.

**Rationale**: Hooks are enforced by Claude Code's hook system,
not by the command file. The headless command executes within
the same Claude Code session, so all configured hooks fire
normally. The post-implement-lint hook fires after `/trc.implement`
completes, which is exactly the right behavior for headless mode.

No special handling needed. The hook system is orthogonal to the
command system.
