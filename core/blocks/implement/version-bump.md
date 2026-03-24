---
name: version-bump
step: implement
description: Bump VERSION file after all tasks pass
required: false
default_enabled: true
order: 60
---

10. **Version bump**: After all tasks pass and before reporting completion:
    - Read the current version from the `VERSION` file in the repo root
    - Bump the patch version (e.g., `0.2.0` → `0.2.1`; if this is a new feature, bump minor: `0.2.0` → `0.3.0`)
    - Write the new version to `VERSION`
    - Include the version bump in the final commit (do NOT create a separate commit for it)

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/trc.tasks` first to regenerate the task list.
