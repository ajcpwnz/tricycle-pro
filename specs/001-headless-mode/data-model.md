# Data Model: Headless Mode

This feature does not introduce new persistent data entities.
The headless command produces the same artifacts as the individual
commands it orchestrates:

## Artifacts Produced (by delegation)

| Artifact | Produced By | Format |
|----------|-------------|--------|
| spec.md | /trc.specify | Markdown |
| plan.md | /trc.plan | Markdown |
| research.md | /trc.plan | Markdown |
| data-model.md | /trc.plan | Markdown |
| contracts/ | /trc.plan | Markdown files |
| quickstart.md | /trc.plan | Markdown |
| tasks.md | /trc.tasks | Markdown with checkboxes |
| Implementation code | /trc.implement | Source files |
| checklists/ | /trc.specify | Markdown with checkboxes |

## New File

| File | Format | Purpose |
|------|--------|---------|
| core/commands/trc.headless.md | Markdown with YAML frontmatter | Command definition |

### trc.headless.md structure

- **Frontmatter**: `description` field (string), no `handoffs`
  (the headless command is a terminal command — it doesn't hand
  off to another command because it runs the full chain itself)
- **Body**: Markdown instructions for Claude, structured as:
  1. Input validation (empty prompt check)
  2. Prerequisites check (tricycle.config.yml exists)
  3. Phase execution loop (specify → plan → tasks → implement)
  4. Pause point rules
  5. Progress reporting format
  6. Completion summary format
