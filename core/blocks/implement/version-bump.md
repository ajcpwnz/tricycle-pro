---
name: version-bump
step: implement
description: Bump the VERSION file once the checklist is done and tests pass
required: false
default_enabled: true
order: 60
---

## Version bump

After every checklist item is done and tests pass, before reporting completion:
    - Read the current version from the `VERSION` file in the repo root
    - Bump the patch version, for example `0.2.0` → `0.2.1`. For a new feature, bump the minor version: `0.2.0` → `0.3.0`.
    - Write the new version to `VERSION`
    - Include the version bump in the final commit (do NOT create a separate commit for it)
