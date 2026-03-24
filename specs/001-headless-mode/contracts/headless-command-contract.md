# Contract: /trc.headless Command

## Invocation

```
/trc.headless <feature-description>
```

**Input**: A natural language feature description (string, required,
non-empty).

**Output**: All artifacts produced by the specify → plan → tasks →
implement chain, plus inline progress messages and a completion
summary.

## Command File Format

```yaml
---
description: >-
  Run the full specify → plan → tasks → implement chain
  automatically from a single prompt. Pauses only for critical
  clarifications, destructive actions, or push approval.
---
```

No `handoffs` field — the headless command is self-contained.

## Behavior Contract

### Phase Execution

The command MUST execute these phases in strict order:

1. **Specify**: Invoke `/trc.specify` with the user's prompt.
   Auto-resolve non-critical clarifications with informed guesses.
2. **Plan**: Invoke `/trc.plan` using the generated spec.
3. **Tasks**: Invoke `/trc.tasks` using the generated plan.
4. **Implement**: Invoke `/trc.implement` using the generated tasks.

Each phase MUST complete before the next begins.

### Pause Conditions

The command MUST pause and request user input when:

| Condition | Category | Resume behavior |
|-----------|----------|-----------------|
| Critical spec ambiguity (no safe default) | Clarification | Update spec, continue chain |
| Destructive file operation | Destructive action | User approves, continue |
| Push or PR creation | Push approval | User approves, push and continue |
| Lint/test failure after 3 retries | Error | User decides next step |

The command MUST NOT pause for:
- Phase transitions (specify → plan → tasks → implement)
- Non-critical clarifications (auto-resolve with defaults)
- Checklist validation (auto-proceed if all pass)
- Normal file creation/modification within the feature

### Progress Output

Between phases:
```
--- Phase N/4: [Phase Name] --- [status]
```

On completion:
```
--- Headless Run Complete ---

Branch: 001-feature-name
Artifacts:
  - specs/001-feature-name/spec.md
  - specs/001-feature-name/plan.md
  - specs/001-feature-name/research.md
  - specs/001-feature-name/data-model.md
  - specs/001-feature-name/tasks.md
  - [implementation files...]

Lint: PASS
Tests: PASS

Next: Push approval required. Say "push" when ready.
```

On failure:
```
--- Headless Run Failed ---

Failed at: Phase N ([Phase Name])
Error: [description]
Completed artifacts: [list]
Suggested next steps: [actions]
```

### Error Handling

| Error | Behavior |
|-------|----------|
| Empty prompt | Fail immediately: "No feature description provided." |
| Missing tricycle.config.yml | Fail immediately: "Tricycle Pro not initialized." |
| Missing .specify/ directory | Fail immediately: "Tricycle Pro not initialized." |
| Phase script failure | Report error, suggest manual intervention |
| Lint/test failure | Attempt fix (up to 3 retries), then pause |
