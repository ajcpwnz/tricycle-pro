---
name: input-validation
step: specify
description: Validate user prompt detail level based on configured chain length
required: true
default_enabled: true
order: 30
---

## Input Detail Validation

After reading the chain configuration, validate that the user's feature description provides sufficient detail for the configured chain length. Shorter chains require more detailed input because fewer planning phases are available to flesh out the details.

### Validation Rules by Chain Length

**Full chain `[specify, plan, tasks, implement]`**:
- Accept any non-empty feature description.
- Planning and task generation phases will flesh out the details.
- No minimum detail requirement beyond a basic description.

**Three-step chain `[specify, plan, implement]`**:
- The feature description should describe at least:
  - **Scope**: What the feature does and doesn't include
  - **Expected outcomes**: What success looks like
- If the description is very brief (roughly 1-2 sentences with no specifics), output:
  ```
  Your feature description may be too brief for a shortened workflow chain.
  Since the tasks step is omitted, the plan step will also generate tasks.
  Consider adding: scope boundaries and expected outcomes.
  ```
  Then ask the user if they want to proceed or provide more detail.

**Two-step chain `[specify, implement]`**:
- The feature description MUST describe at least:
  - **Scope**: What the feature does and its boundaries
  - **Expected behavior**: How it should work from a user perspective
  - **Technical constraints**: Key limitations or requirements
  - **Acceptance criteria**: How to verify the feature works
- If the description lacks these elements (roughly under 3-4 sentences with no technical detail), STOP and output:
  ```
  Error: Feature description is too brief for a specify-implement chain.

  Since plan and tasks steps are omitted, the specify step must also handle
  technical planning and task generation. Please provide more detail:

  - Scope: What does this feature include/exclude?
  - Expected behavior: How should it work?
  - Technical constraints: Any limitations or requirements?
  - Acceptance criteria: How do we verify it works?

  Provide an expanded description or switch to a longer chain in tricycle.config.yml.
  ```
  Wait for the user to provide a more detailed description before proceeding.

### Notes

- This validation uses AI judgment, not rigid character counts. A concise but information-dense description may pass even if short.
- If the user has provided enough semantic content (clear scope, outcomes, constraints) the description should be accepted regardless of length.
- A highly detailed prompt always passes regardless of chain length.
