---
name: Never write migration files manually
description: Always use the project's migration tool/script — never hand-write SQL migration files
type: feedback
---

NEVER write migration files manually by editing SQL files directly. Always use the project's
designated migration tool or non-interactive wrapper script.

**Why:** Hand-written migrations bypass the ORM's migration tracking, can cause drift between
the schema and migration history, and miss edge cases the tool handles (timestamps, checksums,
rollback support). Interactive migration commands (like `prisma migrate dev`) fail in
non-interactive terminals — use wrapper scripts instead.

**How to apply:** After editing the schema, use the project's migration script (check CLAUDE.md
for the exact command). If the migration tool requires interactive prompts, check if a
non-interactive wrapper exists in `scripts/`.
