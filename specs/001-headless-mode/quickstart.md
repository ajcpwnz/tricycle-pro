# Quickstart: Headless Mode

## Verification Scenarios

### Scenario 1: Basic end-to-end execution

**Setup**: A project with Tricycle Pro initialized (tricycle.config.yml,
.specify/, .claude/commands/ all present).

**Steps**:
1. Run `/trc.headless "add a greeting command that prints hello world"`
2. Observe phase transition messages in the terminal
3. Wait for the chain to complete

**Expected**:
- Feature branch created (e.g., `002-greeting-command`)
- `specs/002-greeting-command/spec.md` exists and is populated
- `specs/002-greeting-command/plan.md` exists and is populated
- `specs/002-greeting-command/tasks.md` exists with checkbox items
- Implementation code exists at the paths specified in tasks.md
- Lint passes
- Tests pass
- Completion summary is displayed
- No push was performed (push gating respected)

### Scenario 2: Headless with pause point

**Setup**: Same as Scenario 1.

**Steps**:
1. Run `/trc.headless "add authentication"` (deliberately vague —
   could mean API keys, OAuth, session-based, etc.)
2. Observe the specify phase pausing for clarification
3. Respond with a choice (e.g., "API key authentication")
4. Observe the chain resuming automatically

**Expected**:
- System pauses with a clarification question about auth method
- After user responds, chain resumes from where it paused
- All phases complete successfully
- Final spec.md reflects the user's clarification choice

### Scenario 3: Empty prompt rejection

**Steps**:
1. Run `/trc.headless` (no prompt)

**Expected**:
- Immediate error: "No feature description provided."
- No files created, no branch created

### Scenario 4: Command file installation

**Steps**:
1. Run `npx tricycle-pro update --dry-run`

**Expected**:
- `trc.headless.md` appears in the update list
- After actual update, `.claude/commands/trc.headless.md` exists
