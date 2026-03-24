---
name: quality-validation
step: specify
description: Validate spec quality via checklist and handle NEEDS CLARIFICATION markers
required: false
default_enabled: true
order: 50
---

## Specification Quality Validation

After writing the initial spec, validate it against quality criteria:

### a. Create Spec Quality Checklist

Generate a checklist file at `FEATURE_DIR/checklists/requirements.md` using the checklist template structure with these validation items:

```markdown
# Specification Quality Checklist: [FEATURE NAME]

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: [DATE]
**Feature**: [Link to spec.md]

## Content Quality

- [ ] No implementation details (languages, frameworks, APIs)
- [ ] Focused on user value and business needs
- [ ] Written for non-technical stakeholders
- [ ] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
- [ ] Requirements are testable and unambiguous
- [ ] Success criteria are measurable
- [ ] Success criteria are technology-agnostic (no implementation details)
- [ ] All acceptance scenarios are defined
- [ ] Edge cases are identified
- [ ] Scope is clearly bounded
- [ ] Dependencies and assumptions identified

## Feature Readiness

- [ ] All functional requirements have clear acceptance criteria
- [ ] User scenarios cover primary flows
- [ ] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/trc.clarify` or `/trc.plan`
```

### b. Run Validation Check

Review the spec against each checklist item:
- For each item, determine if it passes or fails
- Document specific issues found (quote relevant spec sections)

### c. Handle Validation Results

- **If all items pass**: Mark checklist complete and proceed to reporting completion

- **If items fail (excluding [NEEDS CLARIFICATION])**:
  1. List the failing items and specific issues
  2. Update the spec to address each issue
  3. Re-run validation until all items pass (max 3 iterations)
  4. If still failing after 3 iterations, document remaining issues in checklist notes and warn user

- **If [NEEDS CLARIFICATION] markers remain**:
  1. Extract all [NEEDS CLARIFICATION: ...] markers from the spec
  2. **LIMIT CHECK**: If more than 3 markers exist, keep only the 3 most critical (by scope/security/UX impact) and make informed guesses for the rest
  3. For each clarification needed (max 3), present options to user in this format:

     ```markdown
     ## Question [N]: [Topic]

     **Context**: [Quote relevant spec section]

     **What we need to know**: [Specific question from NEEDS CLARIFICATION marker]

     **Suggested Answers**:

     | Option | Answer | Implications |
     |--------|--------|--------------|
     | A      | [First suggested answer] | [What this means for the feature] |
     | B      | [Second suggested answer] | [What this means for the feature] |
     | C      | [Third suggested answer] | [What this means for the feature] |
     | Custom | Provide your own answer | [Explain how to provide custom input] |

     **Your choice**: _[Wait for user response]_
     ```

  4. **CRITICAL - Table Formatting**: Ensure markdown tables are properly formatted:
     - Use consistent spacing with pipes aligned
     - Each cell should have spaces around content: `| Content |` not `|Content|`
     - Header separator must have at least 3 dashes: `|--------|`
     - Test that the table renders correctly in markdown preview
  5. Number questions sequentially (Q1, Q2, Q3 - max 3 total)
  6. Present all questions together before waiting for responses
  7. Wait for user to respond with their choices for all questions (e.g., "Q1: A, Q2: Custom - [details], Q3: B")
  8. Update the spec by replacing each [NEEDS CLARIFICATION] marker with the user's selected or provided answer
  9. Re-run validation after all clarifications are resolved

### d. Update Checklist

After each validation iteration, update the checklist file with current pass/fail status.

## Report Completion

Report completion with branch name, spec file path, checklist results, and readiness for the next phase (`/trc.clarify` or `/trc.plan`).
